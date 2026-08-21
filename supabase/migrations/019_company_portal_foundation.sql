-- W4: Company / Employer Portal over canonical recruitment data.
-- Migration 015 tenant isolation and W3 internal operations remain authoritative.

begin;

do $$
begin
  if to_regprocedure('private.current_active_company_id()') is null
     or to_regprocedure('public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.interviews') is null
     or to_regclass('public.candidate_joinings') is null then
    raise exception 'W4 prerequisite company and recruitment contracts are missing';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('private','public') and p.proname like '%company_portal%'
  ) then
    raise exception 'W4 company portal objects already exist; inspect database state';
  end if;
end;
$$;

create function private.current_company_portal_id(p_require_active boolean default true)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare resolved uuid; membership_count integer;
begin
  if (select auth.uid()) is null then return null; end if;
  select min(cu.company_id::text)::uuid,count(*)::integer into resolved,membership_count
  from public.company_users cu
  join public.platform_users pu on pu.user_id=cu.user_id
  join public.companies c on c.id=cu.company_id
  where cu.user_id=(select auth.uid()) and pu.account_type='company'
    and (not p_require_active or (pu.account_status='active' and cu.status='active' and c.account_status='active'));
  if membership_count=0 then return null; end if;
  if membership_count<>1 then raise exception 'Exactly one company membership is required'; end if;
  return resolved;
end;
$$;

create function private.can_manage_company_portal()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.company_users cu
    where cu.user_id=(select auth.uid()) and cu.company_id=(select private.current_company_portal_id(true))
      and cu.status='active' and cu.role in ('owner','hr_admin','recruiter')
  );
$$;

create function private.can_administer_company_profile()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.company_users cu
    where cu.user_id=(select auth.uid()) and cu.company_id=(select private.current_company_portal_id(true))
      and cu.status='active' and cu.role in ('owner','hr_admin')
  );
$$;

create function public.get_company_portal_context()
returns table(company_id uuid,company_name text,member_role text,membership_status text,
  platform_status text,company_status text,verification_status text,can_manage_requirements boolean,can_update_profile boolean)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid;
begin
  if (select auth.uid()) is null then raise exception 'Authenticated Company access is required'; end if;
  cid:=(select private.current_company_portal_id(false));
  if cid is null then raise exception 'Company Portal access is required'; end if;
  return query select c.id,c.legal_name,cu.role,cu.status,pu.account_status,c.account_status,c.verification_status,
    (pu.account_status='active' and c.account_status='active' and cu.status='active' and cu.role in ('owner','hr_admin','recruiter')),
    (pu.account_status='active' and c.account_status='active' and cu.status='active' and cu.role in ('owner','hr_admin'))
  from public.companies c join public.company_users cu on cu.company_id=c.id
    join public.platform_users pu on pu.user_id=cu.user_id
  where c.id=cid and cu.user_id=(select auth.uid());
end;
$$;

create function public.get_company_dashboard_metrics()
returns table(active_requirements bigint,total_openings bigint,applications bigint,screening bigint,
  shortlisted bigint,interviews bigint,selected bigint,joining_pending bigint,joined bigint)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid;
begin
  cid:=(select private.current_company_portal_id(true));
  if cid is null then raise exception 'Active Company access is required'; end if;
  return query
  with requirement_metrics as (
    select count(*) filter(where r.requirement_stage in ('open','on_hold'))::bigint active_requirements,
      coalesce(sum(greatest(r.required_headcount-r.filled_positions,0))
        filter(where r.requirement_stage in ('open','on_hold')),0)::bigint total_openings
    from public.employer_requirements r where r.company_id=cid
  ), application_metrics as (
    select count(*)::bigint applications,
      count(*) filter(where a.application_status='screening')::bigint screening,
      count(*) filter(where a.application_status='shortlisted')::bigint shortlisted,
      count(*) filter(where a.application_status='interview')::bigint interviews,
      count(*) filter(where a.application_status='selected')::bigint selected,
      count(*) filter(where a.application_status='joining_pending')::bigint joining_pending,
      count(*) filter(where a.application_status='joined')::bigint joined
    from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id
    where r.company_id=cid
  )
  select r.active_requirements,r.total_openings,a.applications,a.screening,a.shortlisted,a.interviews,
    a.selected,a.joining_pending,a.joined from requirement_metrics r cross join application_metrics a;
end;
$$;

create function public.get_company_profile()
returns table(legal_name text,trade_name text,industry text,website text,main_phone text,main_email text,
  address text,city text,district text,state text,pincode text,contact_person text,workforce_size text,
  verification_status text,account_status text,can_update boolean)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid;
begin
  cid:=(select private.current_company_portal_id(false));
  if cid is null then raise exception 'Company Portal access is required'; end if;
  return query select c.legal_name,c.trade_name,c.industry,c.website,c.main_phone,c.main_email,c.address,c.city,
    c.district,c.state,c.pincode,c.contact_person,c.workforce_size,c.verification_status,c.account_status,
    (select private.can_administer_company_profile()) from public.companies c where c.id=cid;
end;
$$;

create function public.update_company_profile(p_trade_name text,p_industry text,p_website text,p_main_phone text,
  p_address text,p_city text,p_district text,p_state text,p_pincode text,p_contact_person text,p_workforce_size text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare cid uuid; phone text:=nullif(btrim(p_main_phone),''); pin text:=nullif(btrim(p_pincode),'');
begin
  cid:=(select private.current_company_portal_id(true));
  if cid is null or not (select private.can_administer_company_profile()) then raise exception 'Company profile management access is required'; end if;
  if phone is not null and phone !~ '^[6-9][0-9]{9}$' then raise exception 'A valid Indian mobile number is required'; end if;
  if pin is not null and pin !~ '^[0-9]{6}$' then raise exception 'A valid pincode is required'; end if;
  if length(coalesce(nullif(btrim(p_contact_person),''),''))>160 or length(coalesce(nullif(btrim(p_trade_name),''),''))>240
     or length(coalesce(nullif(btrim(p_industry),''),''))>160 or length(coalesce(nullif(btrim(p_website),''),''))>500
     or length(coalesce(nullif(btrim(p_address),''),''))>1000 or length(coalesce(nullif(btrim(p_city),''),''))>160
     or length(coalesce(nullif(btrim(p_district),''),''))>160 or length(coalesce(nullif(btrim(p_state),''),''))>160 then
    raise exception 'One or more company profile fields are too long';
  end if;
  if nullif(btrim(p_workforce_size),'') is not null and btrim(p_workforce_size) not in ('1-10','11-50','51-200','201-500','501-1000','1000+') then
    raise exception 'Workforce size is invalid';
  end if;
  update public.companies set trade_name=nullif(btrim(p_trade_name),''),industry=nullif(btrim(p_industry),''),
    website=nullif(btrim(p_website),''),main_phone=phone,address=nullif(btrim(p_address),''),city=nullif(btrim(p_city),''),
    district=nullif(btrim(p_district),''),state=nullif(btrim(p_state),''),pincode=pin,
    contact_person=nullif(btrim(p_contact_person),''),workforce_size=nullif(btrim(p_workforce_size),'') where id=cid;
  return found;
end;
$$;

create function public.list_company_portal_requirements(p_search text default null,p_stage text default null,
  p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,department text,job_role text,job_location text,required_headcount integer,
  filled_positions integer,qualification text,experience_requirement text,gender_preference text,age_min integer,age_max integer,
  salary_min numeric,salary_max numeric,shift_details text,working_hours text,overtime_details text,canteen text,transport text,
  accommodation text,interview_location text,interview_date timestamptz,additional_notes text,requirement_stage text,
  requirement_visibility text,application_count bigint,interview_count bigint,selected_count bigint,joined_count bigint,
  created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid; needle text:=nullif(btrim(p_search),''); stage text:=nullif(lower(btrim(p_stage)),'');
begin
  cid:=(select private.current_company_portal_id(true)); if cid is null then raise exception 'Active Company access is required'; end if;
  if stage is not null and stage not in ('draft','open','on_hold','filled','closed','cancelled') then raise exception 'Unsupported requirement stage'; end if;
  return query select r.id,r.requirement_code,r.department,r.job_role,r.job_location,r.required_headcount,r.filled_positions,
    r.qualification,r.experience_requirement,r.gender_preference,r.age_min,r.age_max,r.salary_min,r.salary_max,r.shift_details,
    r.working_hours,r.overtime_details,r.canteen,r.transport,r.accommodation,r.interview_location,r.interview_date,r.additional_notes,
    r.requirement_stage,r.requirement_visibility,count(distinct a.id),count(distinct i.id),
    count(distinct a.id) filter(where a.application_status='selected'),count(distinct a.id) filter(where a.application_status='joined'),
    r.created_at,r.updated_at
  from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id
    left join public.interviews i on i.application_id=a.id
  where r.company_id=cid and (stage is null or r.requirement_stage=stage)
    and (needle is null or r.requirement_code ilike '%'||needle||'%' or r.job_role ilike '%'||needle||'%' or r.job_location ilike '%'||needle||'%')
  group by r.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create function public.get_company_portal_requirement(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare cid uuid; result jsonb;
begin
  cid:=(select private.current_company_portal_id(true)); if cid is null then raise exception 'Active Company access is required'; end if;
  select jsonb_build_object('requirement_code',r.requirement_code,'department',r.department,'job_role',r.job_role,
    'job_location',r.job_location,'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,
    'qualification',r.qualification,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,
    'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,
    'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,
    'accommodation',r.accommodation,'interview_location',r.interview_location,'interview_date',r.interview_date,
    'additional_notes',r.additional_notes,'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,
    'created_at',r.created_at,'updated_at',r.updated_at,'pipeline',jsonb_build_object(
      'applications',count(distinct a.id),'screening',count(distinct a.id)filter(where a.application_status='screening'),
      'shortlisted',count(distinct a.id)filter(where a.application_status='shortlisted'),
      'interviews',count(distinct a.id)filter(where a.application_status='interview'),
      'selected',count(distinct a.id)filter(where a.application_status='selected'),
      'joining_pending',count(distinct a.id)filter(where a.application_status='joining_pending'),
      'joined',count(distinct a.id)filter(where a.application_status='joined'))) into result
  from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id
  where r.id=p_requirement_id and r.company_id=cid group by r.id;
  if result is null then raise exception 'Company requirement was not found'; end if; return result;
end;
$$;

create function public.manage_company_portal_requirement(p_action text,p_requirement_id uuid default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_interview_date timestamptz default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare cid uuid; requirement_record public.employer_requirements%rowtype;
begin
  if not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  if p_action in ('create','update') then
    if length(coalesce(btrim(p_qualification),''))>200
       or length(coalesce(btrim(p_shift_details),''))>200
       or length(coalesce(btrim(p_working_hours),''))>200
       or length(coalesce(btrim(p_overtime_details),''))>500
       or length(coalesce(btrim(p_interview_location),''))>240
       or length(coalesce(btrim(p_additional_notes),''))>2000 then
      raise exception 'One or more requirement fields are too long';
    end if;
    if (p_age_min is not null and (p_age_min<16 or p_age_min>75))
       or (p_age_max is not null and (p_age_max<16 or p_age_max>75)) then
      raise exception 'Age criteria must be between 16 and 75';
    end if;
    if coalesce(p_salary_min,0)<0 or coalesce(p_salary_max,0)<0 then
      raise exception 'Salary values cannot be negative';
    end if;
  end if;
  cid:=(select private.current_company_portal_id(true));
  if p_action='create' then
    requirement_record:=public.create_company_requirement(p_department,p_job_role,p_job_location,p_required_headcount,
      p_qualification,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,
      p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,
      p_interview_date,p_additional_notes);
  elsif p_action='update' then
    if p_requirement_id is null then raise exception 'Requirement identifier is required'; end if;
    requirement_record:=public.update_company_requirement(p_requirement_id,p_department,p_job_role,p_job_location,
      p_required_headcount,p_qualification,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,
      p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,
      p_interview_location,p_interview_date,p_additional_notes);
  elsif p_action='close' then
    if p_requirement_id is null then raise exception 'Requirement identifier is required'; end if;
    requirement_record:=public.close_company_requirement(p_requirement_id);
  else
    raise exception 'Unsupported Company requirement action';
  end if;
  if requirement_record.company_id<>cid then raise exception 'Company requirement ownership verification failed'; end if;
  return query select requirement_record.id,requirement_record.requirement_code,requirement_record.requirement_stage,
    requirement_record.requirement_visibility,requirement_record.updated_at;
end;
$$;

-- Retain the migration-015 signature for compatible clients, but route every
-- mutation through the W4 role-aware boundary so a Company viewer cannot bypass it.
create or replace function public.manage_company_requirement(
  p_action text,p_requirement_id uuid default null,p_department text default null,p_job_role text default null,
  p_job_location text default null,p_required_headcount integer default null,p_qualification text default null,
  p_experience_requirement text default 'Both',p_gender_preference text default 'Any',p_age_min integer default null,
  p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,
  p_canteen text default 'Not Applicable',p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',
  p_interview_location text default null,p_interview_date timestamptz default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language sql security definer set search_path = '' as $$
  select * from public.manage_company_portal_requirement(p_action,p_requirement_id,p_department,p_job_role,p_job_location,
    p_required_headcount,p_qualification,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,
    p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_interview_date,p_additional_notes);
$$;

create function public.list_company_portal_applications(p_requirement_id uuid default null,p_stage text default null,
  p_limit integer default 25,p_offset integer default 0)
returns table(application_id uuid,requirement_code text,job_role text,candidate_name text,qualification text,specialization text,
  experience_summary text,current_location text,district text,state text,application_stage text,interview_status text,
  joining_status text,applied_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid; stage text:=nullif(lower(btrim(p_stage)),'');
begin
  cid:=(select private.current_company_portal_id(true)); if cid is null then raise exception 'Active Company access is required'; end if;
  if p_requirement_id is not null and not exists(select 1 from public.employer_requirements r where r.id=p_requirement_id and r.company_id=cid) then raise exception 'Company requirement was not found'; end if;
  if stage is not null and not exists(select 1 from public.application_stages s where s.stage=stage) then raise exception 'Unsupported application stage'; end if;
  return query select a.id,r.requirement_code,r.job_role,c.full_name,c.highest_qualification,c.specialization,
    coalesce(c.total_experience,c.previous_job_role),c.current_location,c.district,c.state,a.application_status,
    (select i.status from public.interviews i where i.application_id=a.id order by i.created_at desc,i.id desc limit 1),
    (select j.joining_status from public.candidate_joinings j where j.application_id=a.id),a.applied_at,a.updated_at
  from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id
    join public.candidates c on c.id=a.candidate_id
  where r.company_id=cid and (p_requirement_id is null or r.id=p_requirement_id) and (stage is null or a.application_status=stage)
  order by a.updated_at desc,a.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create function public.get_company_portal_application(p_application_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare cid uuid; result jsonb;
begin
  cid:=(select private.current_company_portal_id(true)); if cid is null then raise exception 'Active Company access is required'; end if;
  select jsonb_build_object('candidate_name',c.full_name,'qualification',c.highest_qualification,'specialization',c.specialization,
    'experience_summary',coalesce(c.total_experience,c.previous_job_role),'current_location',c.current_location,'district',c.district,
    'state',c.state,'requirement_code',r.requirement_code,'job_role',r.job_role,'application_stage',a.application_status,
    'applied_at',a.applied_at,'updated_at',a.updated_at,'stage_history',(select coalesce(jsonb_agg(jsonb_build_object(
      'from_stage',h.from_stage,'to_stage',h.to_stage,'created_at',h.created_at)order by h.created_at),'[]'::jsonb)
      from public.application_stage_history h where h.application_id=a.id),'interviews',(select coalesce(jsonb_agg(jsonb_build_object(
      'round',i.interview_round,'scheduled_at',i.scheduled_at,'mode',i.mode,'status',i.status,'result',i.result)order by i.created_at),'[]'::jsonb)
      from public.interviews i where i.application_id=a.id),'joining',(select jsonb_build_object('expected_joining_date',j.expected_joining_date,
      'actual_joining_date',j.actual_joining_date,'joining_status',j.joining_status)from public.candidate_joinings j where j.application_id=a.id)) into result
  from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id
    join public.candidates c on c.id=a.candidate_id where a.id=p_application_id and r.company_id=cid;
  if result is null then raise exception 'Company application was not found'; end if; return result;
end;
$$;

create function public.list_company_portal_interviews(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,candidate_name text,interview_round smallint,scheduled_at timestamptz,
  mode text,location text,status text,result text)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid;
begin
  cid:=(select private.current_company_portal_id(true));if cid is null then raise exception 'Active Company access is required';end if;
  return query select r.requirement_code,r.job_role,c.full_name,i.interview_round,i.scheduled_at,i.mode,i.location,i.status,i.result
  from public.interviews i join public.candidate_applications a on a.id=i.application_id
    join public.employer_requirements r on r.id=a.requirement_id join public.candidates c on c.id=a.candidate_id
  where r.company_id=cid order by i.scheduled_at desc nulls last,i.id
  limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create function public.list_company_portal_joinings(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,candidate_name text,expected_joining_date date,actual_joining_date date,
  joining_status text,employee_code text)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid;
begin
  cid:=(select private.current_company_portal_id(true));if cid is null then raise exception 'Active Company access is required';end if;
  return query select r.requirement_code,r.job_role,c.full_name,j.expected_joining_date,j.actual_joining_date,j.joining_status,j.employee_code
  from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id
    join public.employer_requirements r on r.id=a.requirement_id join public.candidates c on c.id=a.candidate_id
  where r.company_id=cid order by j.updated_at desc,j.id
  limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create index employer_requirements_company_stage_created_w4_idx
  on public.employer_requirements(company_id,requirement_stage,created_at desc) where company_id is not null;

revoke all on function private.current_company_portal_id(boolean) from public,anon,authenticated;
revoke all on function private.can_manage_company_portal() from public,anon,authenticated;
revoke all on function private.can_administer_company_profile() from public,anon,authenticated;

revoke all on function public.get_company_portal_context() from public,anon;
revoke all on function public.get_company_dashboard_metrics() from public,anon;
revoke all on function public.get_company_profile() from public,anon;
revoke all on function public.update_company_profile(text,text,text,text,text,text,text,text,text,text,text) from public,anon;
revoke all on function public.list_company_portal_requirements(text,text,integer,integer) from public,anon;
revoke all on function public.get_company_portal_requirement(uuid) from public,anon;
revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) from public,anon;
revoke all on function public.list_company_portal_applications(uuid,text,integer,integer) from public,anon;
revoke all on function public.get_company_portal_application(uuid) from public,anon;
revoke all on function public.list_company_portal_interviews(integer,integer) from public,anon;
revoke all on function public.list_company_portal_joinings(integer,integer) from public,anon;

grant execute on function public.get_company_portal_context() to authenticated;
grant execute on function public.get_company_dashboard_metrics() to authenticated;
grant execute on function public.get_company_profile() to authenticated;
grant execute on function public.update_company_profile(text,text,text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.list_company_portal_requirements(text,text,integer,integer) to authenticated;
grant execute on function public.get_company_portal_requirement(uuid) to authenticated;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) to authenticated;
grant execute on function public.list_company_portal_applications(uuid,text,integer,integer) to authenticated;
grant execute on function public.get_company_portal_application(uuid) to authenticated;
grant execute on function public.list_company_portal_interviews(integer,integer) to authenticated;
grant execute on function public.list_company_portal_joinings(integer,integer) to authenticated;

-- Migration-015 projections and signatures remain compatible. The legacy mutation
-- signature now delegates to the W4 role-aware wrapper above.

-- No table grant or browser RLS policy is added. W3 internal RPC grants are unchanged.
commit;
