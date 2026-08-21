-- W5: Contractor Portal over canonical requirements and W3 recruitment data.
-- Contractor submissions remain private/draft until an authorized Aadhyant review approves the same record.

begin;

do $$ begin
  if to_regclass('public.contractors') is null or to_regclass('public.contractor_users') is null
     or to_regclass('public.requirement_contractors') is null or to_regclass('public.employer_requirements') is null
     or to_regprocedure('private.has_staff_role(text)') is null then
    raise exception 'W5 prerequisite contractor, requirement, and staff contracts are missing';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('private','public') and p.proname like '%contractor_portal%') then
    raise exception 'W5 Contractor Portal objects already exist; inspect database state';
  end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='requirement_contractors'
    and column_name in ('origin_type','submission_status','review_feedback','submitted_at','reviewed_at','reviewed_by')) then
    raise exception 'W5 requirement review columns already exist; inspect database state';
  end if;
end $$;

alter table public.requirement_contractors
  add column origin_type text not null default 'internal_assignment',
  add column submission_status text,
  add column review_feedback text,
  add column submitted_at timestamptz,
  add column reviewed_at timestamptz,
  add column reviewed_by uuid references auth.users(id) on delete set null,
  add constraint requirement_contractors_origin_type_check check(origin_type in ('internal_assignment','contractor_submission')),
  add constraint requirement_contractors_submission_status_check check(submission_status is null or submission_status in
    ('draft','submitted','under_review','correction_required','approved','rejected','closed','cancelled')),
  add constraint requirement_contractors_review_feedback_length_check check(review_feedback is null or length(review_feedback)<=2000),
  add constraint requirement_contractors_submission_shape_check check(
    (origin_type='internal_assignment' and submission_status is null)
    or (origin_type='contractor_submission' and submission_status is not null));

create function private.current_contractor_portal_id(p_require_active boolean default true)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare resolved uuid; membership_count integer;
begin
  if (select auth.uid()) is null then return null; end if;
  select min(cu.contractor_id::text)::uuid,count(*)::integer into resolved,membership_count
  from public.contractor_users cu join public.platform_users pu on pu.user_id=cu.user_id
    join public.contractors c on c.id=cu.contractor_id
  where cu.user_id=(select auth.uid()) and pu.account_type='contractor'
    and (not p_require_active or (pu.account_status='active' and cu.status='active' and c.account_status='active'));
  if membership_count=0 then return null; end if;
  if membership_count<>1 then raise exception 'Exactly one contractor membership is required'; end if;
  return resolved;
end $$;

create function private.can_manage_contractor_vacancies()
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.contractor_users cu
    where cu.user_id=(select auth.uid()) and cu.contractor_id=(select private.current_contractor_portal_id(true))
      and cu.status='active' and cu.role in ('owner','manager','recruiter'));
$$;

create function private.can_edit_contractor_profile()
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.contractor_users cu
    where cu.user_id=(select auth.uid()) and cu.contractor_id=(select private.current_contractor_portal_id(true))
      and cu.status='active' and cu.role in ('owner','manager'));
$$;

create function public.get_contractor_portal_context()
returns table(contractor_name text,member_role text,membership_status text,platform_status text,contractor_status text,
  verification_status text,can_manage_vacancies boolean,can_update_profile boolean)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
  if (select auth.uid()) is null then raise exception 'Authenticated Contractor access is required'; end if;
  cid:=(select private.current_contractor_portal_id(false));
  if cid is null then raise exception 'Contractor Portal access is required'; end if;
  return query select c.agency_name,cu.role,cu.status,pu.account_status,c.account_status,c.verification_status,
    (pu.account_status='active' and c.account_status='active' and cu.status='active' and cu.role in ('owner','manager','recruiter')),
    (pu.account_status='active' and c.account_status='active' and cu.status='active' and cu.role in ('owner','manager'))
  from public.contractors c join public.contractor_users cu on cu.contractor_id=c.id
    join public.platform_users pu on pu.user_id=cu.user_id where c.id=cid and cu.user_id=(select auth.uid());
end $$;

create function public.get_contractor_dashboard_metrics()
returns table(draft_vacancies bigint,under_review bigint,approved_active bigint,needs_action bigint,total_openings bigint,
  applications bigint,interviews bigint,selected bigint,joining_pending bigint,joined bigint)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
  cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  return query with vacancy as (
    select count(*) filter(where rc.submission_status='draft')::bigint drafts,
      count(*) filter(where rc.submission_status in ('submitted','under_review'))::bigint reviews,
      count(*) filter(where rc.submission_status='approved' and r.requirement_stage in ('open','on_hold'))::bigint approved,
      count(*) filter(where rc.submission_status in ('correction_required','rejected'))::bigint action,
      coalesce(sum(greatest(r.required_headcount-r.filled_positions,0)) filter(where rc.submission_status='approved' and r.requirement_stage in ('open','on_hold')),0)::bigint openings
    from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    where rc.contractor_id=cid and rc.origin_type='contractor_submission'), progress as (
    select count(distinct a.id)::bigint applications,count(distinct i.id)::bigint interviews,
      count(distinct a.id) filter(where a.application_status='selected')::bigint selected,
      count(distinct a.id) filter(where a.application_status='joining_pending')::bigint joining_pending,
      count(distinct a.id) filter(where a.application_status='joined')::bigint joined
    from public.requirement_contractors rc join public.candidate_applications a on a.requirement_id=rc.requirement_id
      left join public.interviews i on i.application_id=a.id
    where rc.contractor_id=cid and rc.origin_type='contractor_submission' and rc.submission_status='approved')
  select v.drafts,v.reviews,v.approved,v.action,v.openings,p.applications,p.interviews,p.selected,p.joining_pending,p.joined
  from vacancy v cross join progress p;
end $$;

create function public.get_contractor_portal_profile()
returns table(agency_name text,owner_name text,main_phone text,main_email text,website text,address text,city text,district text,
  state text,pincode text,operating_locations text[],workforce_capacity integer,manpower_categories text[],gstin text,
  esic_code text,epfo_code text,labour_license_number text,verification_status text,account_status text,can_update boolean)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
  cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  return query select c.agency_name,c.owner_name,c.main_phone,c.main_email,c.website,c.address,c.city,c.district,c.state,c.pincode,
    c.operating_locations,c.workforce_capacity,c.manpower_categories,c.gstin,c.esic_code,c.epfo_code,c.labour_license_number,
    c.verification_status,c.account_status,(select private.can_edit_contractor_profile()) from public.contractors c where c.id=cid;
end $$;

create function public.update_contractor_portal_profile(p_owner_name text,p_main_phone text,p_website text,p_address text,
  p_city text,p_district text,p_state text,p_pincode text,p_operating_locations text[],p_workforce_capacity integer,p_manpower_categories text[])
returns boolean language plpgsql security definer set search_path='' as $$
declare cid uuid; phone text:=nullif(btrim(p_main_phone),''); pin text:=nullif(btrim(p_pincode),'');
begin
  cid:=(select private.current_contractor_portal_id(true));
  if cid is null or not (select private.can_edit_contractor_profile()) then raise exception 'Contractor profile management access is required'; end if;
  if phone is not null and phone!~'^[6-9][0-9]{9}$' then raise exception 'A valid Indian mobile number is required'; end if;
  if pin is not null and pin!~'^[0-9]{6}$' then raise exception 'A valid pincode is required'; end if;
  if p_workforce_capacity is not null and (p_workforce_capacity<0 or p_workforce_capacity>1000000) then raise exception 'Workforce capacity is invalid'; end if;
  if length(coalesce(btrim(p_owner_name),''))>160 or length(coalesce(btrim(p_website),''))>500
     or length(coalesce(btrim(p_address),''))>1000 or length(coalesce(btrim(p_city),''))>160
     or length(coalesce(btrim(p_district),''))>160 or length(coalesce(btrim(p_state),''))>160
     or coalesce(array_length(p_operating_locations,1),0)>50 or coalesce(array_length(p_manpower_categories,1),0)>50 then
    raise exception 'One or more contractor profile fields are invalid';
  end if;
  update public.contractors set owner_name=nullif(btrim(p_owner_name),''),main_phone=phone,website=nullif(btrim(p_website),''),
    address=nullif(btrim(p_address),''),city=nullif(btrim(p_city),''),district=nullif(btrim(p_district),''),state=nullif(btrim(p_state),''),
    pincode=pin,operating_locations=coalesce(p_operating_locations,array[]::text[]),workforce_capacity=p_workforce_capacity,
    manpower_categories=coalesce(p_manpower_categories,array[]::text[]) where id=cid;
  return found;
end $$;

create function public.list_contractor_portal_vacancies(p_search text default null,p_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,client_name text,job_role text,job_location text,required_headcount integer,
  submission_status text,requirement_stage text,review_feedback text,application_count bigint,interview_count bigint,
  selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid; needle text:=nullif(btrim(p_search),''); filter_status text:=nullif(lower(btrim(p_status)),'');
begin
  cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  if filter_status is not null and filter_status not in ('draft','submitted','under_review','correction_required','approved','rejected','closed','cancelled') then raise exception 'Unsupported submission status'; end if;
  return query select r.id,r.requirement_code,r.company_name,r.job_role,r.job_location,r.required_headcount,rc.submission_status,
    r.requirement_stage,rc.review_feedback,count(distinct a.id),count(distinct i.id),
    count(distinct a.id)filter(where a.application_status='selected'),count(distinct a.id)filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where rc.contractor_id=cid and rc.origin_type='contractor_submission' and (filter_status is null or rc.submission_status=filter_status)
    and (needle is null or r.requirement_code ilike '%'||needle||'%' or r.job_role ilike '%'||needle||'%' or r.job_location ilike '%'||needle||'%')
  group by r.id,rc.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end $$;

create function public.get_contractor_portal_vacancy(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; result jsonb;
begin
  cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  select jsonb_build_object('requirement_code',r.requirement_code,'client_name',r.company_name,'department',r.department,'job_role',r.job_role,
    'job_location',r.job_location,'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,
    'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,
    'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,
    'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,
    'interview_location',r.interview_location,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,
    'submission_status',rc.submission_status,'requirement_stage',r.requirement_stage,'review_feedback',rc.review_feedback,
    'created_at',r.created_at,'updated_at',r.updated_at,'pipeline',jsonb_build_object('applications',count(distinct a.id),
      'screening',count(distinct a.id)filter(where a.application_status='screening'),'shortlisted',count(distinct a.id)filter(where a.application_status='shortlisted'),
      'interviews',count(distinct i.id),'selected',count(distinct a.id)filter(where a.application_status='selected'),
      'joining_pending',count(distinct a.id)filter(where a.application_status='joining_pending'),'joined',count(distinct a.id)filter(where a.application_status='joined'))) into result
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where r.id=p_requirement_id and rc.contractor_id=cid and rc.origin_type='contractor_submission' group by r.id,rc.id;
  if result is null then raise exception 'Contractor vacancy was not found'; end if; return result;
end $$;

create function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid default null,p_client_name text default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_iti_trade text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_expected_joining_date date default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare cid uuid; contractor_record public.contractors%rowtype; req public.employer_requirements%rowtype; rc public.requirement_contractors%rowtype;
begin
  if not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  cid:=(select private.current_contractor_portal_id(true)); select * into contractor_record from public.contractors where id=cid;
  if contractor_record.main_phone is null or contractor_record.main_phone!~'^[6-9][0-9]{9}$' then
    raise exception 'A valid contractor contact phone is required before submitting vacancies'; end if;
  if p_action in ('create','update') then
    if length(btrim(coalesce(p_client_name,''))) not between 1 and 200 or length(btrim(coalesce(p_job_role,''))) not between 1 and 200
       or length(btrim(coalesce(p_job_location,''))) not between 1 and 300 or p_required_headcount is null or p_required_headcount<1 or p_required_headcount>100000 then
      raise exception 'Client, role, location, and valid openings are required'; end if;
    if p_experience_requirement not in ('Fresher','Experienced','Both') or p_gender_preference not in ('Any','Male','Female')
       or (p_age_min is not null and p_age_min not between 16 and 75) or (p_age_max is not null and p_age_max not between 16 and 75)
       or (p_age_min is not null and p_age_max is not null and p_age_min>p_age_max)
       or coalesce(p_salary_min,0)<0 or coalesce(p_salary_max,0)<0 or (p_salary_min is not null and p_salary_max is not null and p_salary_min>p_salary_max) then
      raise exception 'Vacancy criteria are invalid'; end if;
    if length(coalesce(btrim(p_qualification),''))>200 or length(coalesce(btrim(p_iti_trade),''))>200
       or length(coalesce(btrim(p_shift_details),''))>200 or length(coalesce(btrim(p_working_hours),''))>200
       or length(coalesce(btrim(p_overtime_details),''))>500 or length(coalesce(btrim(p_interview_location),''))>240
       or length(coalesce(btrim(p_additional_notes),''))>2000 then raise exception 'One or more vacancy fields are too long'; end if;
  end if;
  if p_action='create' then
    insert into public.employer_requirements(company_name,contact_person,mobile,email,company_location,job_role,required_headcount,
      qualification,iti_trade,experience_requirement,gender_preference,salary_wage,shift_details,working_hours,expected_joining_date,
      accommodation,canteen,transport,additional_notes,consent,status,created_by_user_id,department,job_location,age_min,age_max,
      salary_min,salary_max,overtime_details,interview_location,requirement_visibility,requirement_stage)
    values(btrim(p_client_name),coalesce(nullif(btrim(contractor_record.owner_name),''),contractor_record.agency_name),
      btrim(contractor_record.main_phone),contractor_record.main_email,btrim(p_job_location),btrim(p_job_role),p_required_headcount,
      nullif(btrim(p_qualification),''),nullif(btrim(p_iti_trade),''),p_experience_requirement,p_gender_preference,
      case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
      nullif(btrim(p_shift_details),''),nullif(btrim(p_working_hours),''),p_expected_joining_date,p_accommodation,p_canteen,p_transport,
      nullif(btrim(p_additional_notes),''),true,'new',(select auth.uid()),nullif(btrim(p_department),''),btrim(p_job_location),p_age_min,p_age_max,
      p_salary_min,p_salary_max,nullif(btrim(p_overtime_details),''),nullif(btrim(p_interview_location),''),'private','draft') returning * into req;
    insert into public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,assignment_status,origin_type,submission_status)
      values(req.id,cid,p_required_headcount,'assigned','contractor_submission','draft') returning * into rc;
  else
    select r.* into req from public.employer_requirements r
      where r.id=p_requirement_id and exists(select 1 from public.requirement_contractors link
        where link.requirement_id=r.id and link.contractor_id=cid and link.origin_type='contractor_submission') for update;
    if not found then raise exception 'Contractor vacancy was not found'; end if;
    select link.* into rc from public.requirement_contractors link
      where link.requirement_id=req.id and link.contractor_id=cid and link.origin_type='contractor_submission' for update;
    if not found then raise exception 'Contractor vacancy was not found'; end if;
    if p_action='update' then
      if rc.submission_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be edited'; end if;
      update public.employer_requirements set company_name=btrim(p_client_name),department=nullif(btrim(p_department),''),job_role=btrim(p_job_role),
        company_location=btrim(p_job_location),job_location=btrim(p_job_location),required_headcount=p_required_headcount,qualification=nullif(btrim(p_qualification),''),
        iti_trade=nullif(btrim(p_iti_trade),''),experience_requirement=p_experience_requirement,gender_preference=p_gender_preference,age_min=p_age_min,age_max=p_age_max,
        salary_min=p_salary_min,salary_max=p_salary_max,salary_wage=case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
        shift_details=nullif(btrim(p_shift_details),''),working_hours=nullif(btrim(p_working_hours),''),overtime_details=nullif(btrim(p_overtime_details),''),
        canteen=p_canteen,transport=p_transport,accommodation=p_accommodation,interview_location=nullif(btrim(p_interview_location),''),
        expected_joining_date=p_expected_joining_date,additional_notes=nullif(btrim(p_additional_notes),''),requirement_stage='draft',requirement_visibility='private' where id=req.id returning * into req;
      update public.requirement_contractors set assigned_headcount=p_required_headcount,submission_status='draft',review_feedback=null where id=rc.id returning * into rc;
    elsif p_action='submit' then
      if rc.submission_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be submitted'; end if;
      update public.requirement_contractors set submission_status='submitted',submitted_at=now(),review_feedback=null where id=rc.id returning * into rc;
    elsif p_action='cancel' then
      if rc.submission_status not in ('draft','submitted','correction_required') then raise exception 'This vacancy cannot be cancelled'; end if;
      update public.requirement_contractors set submission_status='cancelled',closed_at=now() where id=rc.id returning * into rc;
      update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=now() where id=req.id returning * into req;
    else raise exception 'Unsupported Contractor vacancy action'; end if;
  end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'contractor','contractor_vacancy_'||p_action,'employer_requirement',req.id,'contractor',
      jsonb_build_object('submission_status',rc.submission_status));
  return query select req.id,req.requirement_code,rc.submission_status,req.requirement_stage,req.updated_at;
end $$;

create function public.list_contractor_portal_applications(p_requirement_id uuid default null,p_stage text default null,p_limit integer default 25,p_offset integer default 0)
returns table(application_id uuid,requirement_code text,job_role text,candidate_name text,qualification text,specialization text,
  experience_summary text,current_location text,district text,state text,application_stage text,interview_status text,joining_status text,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid; filter_stage text:=nullif(lower(btrim(p_stage)),'');
begin
  cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  if filter_stage is not null and not exists(select 1 from public.application_stages s where s.stage=filter_stage) then raise exception 'Unsupported application stage'; end if;
  return query select a.id,r.requirement_code,r.job_role,c.full_name,c.highest_qualification,c.specialization,
    coalesce(c.total_experience,c.previous_job_role),c.current_location,c.district,c.state,a.application_status,
    (select i.status from public.interviews i where i.application_id=a.id order by i.created_at desc,i.id desc limit 1),
    (select j.joining_status from public.candidate_joinings j where j.application_id=a.id),a.updated_at
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    join public.candidate_applications a on a.requirement_id=r.id join public.candidates c on c.id=a.candidate_id
  where rc.contractor_id=cid and rc.origin_type='contractor_submission' and rc.submission_status='approved'
    and (p_requirement_id is null or r.id=p_requirement_id) and (filter_stage is null or a.application_status=filter_stage)
  order by a.updated_at desc,a.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end $$;

create function public.get_contractor_portal_application(p_application_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid; result jsonb;
begin
  cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  select jsonb_build_object('candidate_name',c.full_name,'qualification',c.highest_qualification,'specialization',c.specialization,
    'experience_summary',coalesce(c.total_experience,c.previous_job_role),'current_location',c.current_location,'district',c.district,'state',c.state,
    'requirement_code',r.requirement_code,'job_role',r.job_role,'application_stage',a.application_status,'updated_at',a.updated_at,
    'interviews',(select coalesce(jsonb_agg(jsonb_build_object('round',i.interview_round,'scheduled_at',i.scheduled_at,'mode',i.mode,
      'location',i.location,'status',i.status,'result',i.result) order by i.created_at),'[]'::jsonb) from public.interviews i where i.application_id=a.id),
    'joining',(select jsonb_build_object('expected_joining_date',j.expected_joining_date,'actual_joining_date',j.actual_joining_date,'joining_status',j.joining_status)
      from public.candidate_joinings j where j.application_id=a.id)) into result
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    join public.candidate_applications a on a.requirement_id=r.id join public.candidates c on c.id=a.candidate_id
  where a.id=p_application_id and rc.contractor_id=cid and rc.origin_type='contractor_submission' and rc.submission_status='approved';
  if result is null then raise exception 'Contractor application was not found'; end if; return result;
end $$;

create function public.list_contractor_portal_interviews(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,candidate_name text,interview_round smallint,scheduled_at timestamptz,mode text,location text,status text,result text)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  return query select r.requirement_code,r.job_role,c.full_name,i.interview_round,i.scheduled_at,i.mode,i.location,i.status,i.result
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    join public.candidate_applications a on a.requirement_id=r.id join public.candidates c on c.id=a.candidate_id join public.interviews i on i.application_id=a.id
  where rc.contractor_id=cid and rc.origin_type='contractor_submission' and rc.submission_status='approved'
  order by i.scheduled_at desc nulls last,i.id limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0); end $$;

create function public.list_contractor_portal_joinings(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,candidate_name text,expected_joining_date date,actual_joining_date date,joining_status text)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin cid:=(select private.current_contractor_portal_id(true)); if cid is null then raise exception 'Active Contractor access is required'; end if;
  return query select r.requirement_code,r.job_role,c.full_name,j.expected_joining_date,j.actual_joining_date,j.joining_status
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    join public.candidate_applications a on a.requirement_id=r.id join public.candidates c on c.id=a.candidate_id join public.candidate_joinings j on j.application_id=a.id
  where rc.contractor_id=cid and rc.origin_type='contractor_submission' and rc.submission_status='approved'
  order by j.updated_at desc,j.id limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0); end $$;

create function public.list_contractor_vacancy_reviews(p_status text default null,p_limit integer default 50,p_offset integer default 0)
returns table(requirement_id uuid,requirement_code text,contractor_name text,client_name text,job_role text,job_location text,
  required_headcount integer,submission_status text,submitted_at timestamptz,review_feedback text)
language plpgsql stable security definer set search_path='' as $$
begin
  if not ((select private.is_admin()) or (select private.has_staff_role('super_admin')) or (select private.has_staff_role('admin'))) then
    raise exception 'Contractor vacancy review access is required'; end if;
  return query select r.id,r.requirement_code,c.agency_name,r.company_name,r.job_role,r.job_location,r.required_headcount,rc.submission_status,rc.submitted_at,rc.review_feedback
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id join public.contractors c on c.id=rc.contractor_id
  where rc.origin_type='contractor_submission' and (nullif(lower(btrim(p_status)),'') is null or rc.submission_status=lower(btrim(p_status)))
  order by coalesce(rc.submitted_at,r.created_at) desc,r.id limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
end $$;

create function public.review_contractor_vacancy(p_requirement_id uuid,p_action text,p_feedback text default null)
returns table(requirement_id uuid,requirement_code text,submission_status text,requirement_stage text,requirement_visibility text)
language plpgsql security definer set search_path='' as $$
declare req public.employer_requirements%rowtype; rc public.requirement_contractors%rowtype; action text:=lower(btrim(p_action)); feedback text:=nullif(btrim(p_feedback),'');
begin
  if not ((select private.is_admin()) or (select private.has_staff_role('super_admin')) or (select private.has_staff_role('admin'))) then
    raise exception 'Contractor vacancy review access is required'; end if;
  if length(coalesce(feedback,''))>2000 then raise exception 'Review feedback is too long'; end if;
  select r.* into req from public.employer_requirements r
    where r.id=p_requirement_id and exists(select 1 from public.requirement_contractors link
      where link.requirement_id=r.id and link.origin_type='contractor_submission') for update;
  if not found then raise exception 'Contractor vacancy was not found'; end if;
  select link.* into rc from public.requirement_contractors link
    where link.requirement_id=req.id and link.origin_type='contractor_submission' for update;
  if not found then raise exception 'Contractor vacancy was not found'; end if;
  if action='start_review' and rc.submission_status='submitted' then
    update public.requirement_contractors set submission_status='under_review',reviewed_by=(select auth.uid()),reviewed_at=now() where id=rc.id returning * into rc;
  elsif action='request_correction' and rc.submission_status in ('submitted','under_review') then
    if feedback is null then raise exception 'A correction reason is required'; end if;
    update public.requirement_contractors set submission_status='correction_required',review_feedback=feedback,reviewed_by=(select auth.uid()),reviewed_at=now() where id=rc.id returning * into rc;
  elsif action='approve' and rc.submission_status in ('submitted','under_review') then
    update public.requirement_contractors set submission_status='approved',assignment_status='active',review_feedback=feedback,reviewed_by=(select auth.uid()),reviewed_at=now(),accepted_at=now() where id=rc.id returning * into rc;
    update public.employer_requirements set requirement_stage='open',requirement_visibility='assigned',status='in_progress',published_at=now(),closed_at=null where id=req.id returning * into req;
  elsif action='reject' and rc.submission_status in ('submitted','under_review') then
    if feedback is null then raise exception 'A rejection reason is required'; end if;
    update public.requirement_contractors set submission_status='rejected',assignment_status='cancelled',review_feedback=feedback,reviewed_by=(select auth.uid()),reviewed_at=now(),closed_at=now() where id=rc.id returning * into rc;
    update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=now() where id=req.id returning * into req;
  elsif action='close' and rc.submission_status='approved' then
    update public.requirement_contractors set submission_status='closed',assignment_status='completed',review_feedback=feedback,reviewed_by=(select auth.uid()),reviewed_at=now(),closed_at=now() where id=rc.id returning * into rc;
    update public.employer_requirements set requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=now() where id=req.id returning * into req;
  else raise exception 'Invalid contractor vacancy review transition'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','contractor_vacancy_review_'||action,'employer_requirement',req.id,'admin',
      jsonb_build_object('submission_status',rc.submission_status));
  return query select req.id,req.requirement_code,rc.submission_status,req.requirement_stage,req.requirement_visibility;
end $$;

create index requirement_contractors_portal_status_idx on public.requirement_contractors(contractor_id,submission_status,created_at desc)
  where origin_type='contractor_submission';

revoke all on function private.current_contractor_portal_id(boolean) from public,anon,authenticated;
revoke all on function private.can_manage_contractor_vacancies() from public,anon,authenticated;
revoke all on function private.can_edit_contractor_profile() from public,anon,authenticated;

revoke all on function public.get_contractor_portal_context() from public,anon;
revoke all on function public.get_contractor_dashboard_metrics() from public,anon;
revoke all on function public.get_contractor_portal_profile() from public,anon;
revoke all on function public.update_contractor_portal_profile(text,text,text,text,text,text,text,text,text[],integer,text[]) from public,anon;
revoke all on function public.list_contractor_portal_vacancies(text,text,integer,integer) from public,anon;
revoke all on function public.get_contractor_portal_vacancy(uuid) from public,anon;
revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) from public,anon;
revoke all on function public.list_contractor_portal_applications(uuid,text,integer,integer) from public,anon;
revoke all on function public.get_contractor_portal_application(uuid) from public,anon;
revoke all on function public.list_contractor_portal_interviews(integer,integer) from public,anon;
revoke all on function public.list_contractor_portal_joinings(integer,integer) from public,anon;
revoke all on function public.list_contractor_vacancy_reviews(text,integer,integer) from public,anon;
revoke all on function public.review_contractor_vacancy(uuid,text,text) from public,anon;

grant execute on function public.get_contractor_portal_context() to authenticated;
grant execute on function public.get_contractor_dashboard_metrics() to authenticated;
grant execute on function public.get_contractor_portal_profile() to authenticated;
grant execute on function public.update_contractor_portal_profile(text,text,text,text,text,text,text,text,text[],integer,text[]) to authenticated;
grant execute on function public.list_contractor_portal_vacancies(text,text,integer,integer) to authenticated;
grant execute on function public.get_contractor_portal_vacancy(uuid) to authenticated;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) to authenticated;
grant execute on function public.list_contractor_portal_applications(uuid,text,integer,integer) to authenticated;
grant execute on function public.get_contractor_portal_application(uuid) to authenticated;
grant execute on function public.list_contractor_portal_interviews(integer,integer) to authenticated;
grant execute on function public.list_contractor_portal_joinings(integer,integer) to authenticated;
grant execute on function public.list_contractor_vacancy_reviews(text,integer,integer) to authenticated;
grant execute on function public.review_contractor_vacancy(uuid,text,text) to authenticated;

commit;
