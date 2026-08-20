-- W3: least-privilege internal recruitment operations over canonical entities.

begin;

do $$
begin
  if to_regclass('public.candidates') is null
     or to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.interviews') is null
     or to_regclass('public.candidate_joinings') is null
     or to_regclass('public.application_stages') is null
     or to_regclass('public.application_stage_history') is null
     or to_regclass('public.audit_logs') is null then
    raise exception 'W3 prerequisite recruitment tables are missing';
  end if;
  if to_regprocedure('private.current_staff_profile_id()') is null
     or to_regprocedure('private.has_staff_role(text)') is null
     or to_regprocedure('public.get_current_staff_session()') is null
     or to_regprocedure('public.get_company_requirements()') is null
     or to_regprocedure('public.get_staffing_partner_assignments()') is null then
    raise exception 'W3 prerequisite W2 or migration 015 contracts are missing';
  end if;
  if to_regprocedure('public.get_recruitment_permissions()') is not null then
    raise exception 'W3 objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

create function private.is_bootstrap_recruitment_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select private.is_admin())
    and (select auth.uid()) is not null
    and not exists (select 1 from public.platform_users where user_id = (select auth.uid()));
$$;

create function private.can_view_recruitment()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select private.is_bootstrap_recruitment_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'))
    or (select private.has_staff_role('recruiter'))
    or (select private.has_staff_role('operations'))
    or (select private.has_staff_role('viewer'));
$$;

create function private.can_manage_candidates()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select private.is_bootstrap_recruitment_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'))
    or (select private.has_staff_role('recruiter'));
$$;

create function private.can_manage_applications()
returns boolean language sql stable security definer set search_path = '' as $$ select private.can_manage_candidates(); $$;

create function private.can_manage_interviews()
returns boolean language sql stable security definer set search_path = '' as $$ select private.can_manage_candidates(); $$;

create function private.can_manage_joinings()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select private.is_bootstrap_recruitment_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'))
    or (select private.has_staff_role('operations'));
$$;

revoke all on function private.is_bootstrap_recruitment_admin() from public, anon, authenticated;
revoke all on function private.can_view_recruitment() from public, anon, authenticated;
revoke all on function private.can_manage_candidates() from public, anon, authenticated;
revoke all on function private.can_manage_applications() from public, anon, authenticated;
revoke all on function private.can_manage_interviews() from public, anon, authenticated;
revoke all on function private.can_manage_joinings() from public, anon, authenticated;

create function public.get_recruitment_permissions()
returns table(view_access boolean, candidate_mutation boolean, application_mutation boolean,
  interview_mutation boolean, joining_mutation boolean, pii_detail_access boolean)
language sql stable security definer set search_path = '' as $$
  select private.can_view_recruitment(), private.can_manage_candidates(),
    private.can_manage_applications(), private.can_manage_interviews(),
    private.can_manage_joinings(), private.can_manage_candidates();
$$;

create function public.get_recruitment_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  return jsonb_build_object(
    'active_requirements', (select count(*) from public.employer_requirements where requirement_stage = 'open'),
    'new_candidates', (select count(*) from public.candidates where status = 'new'),
    'applications', (select count(*) from public.candidate_applications),
    'upcoming_interviews', (select count(*) from public.interviews where status = 'scheduled' and scheduled_at >= now()),
    'selected', (select count(*) from public.candidate_applications where application_status = 'selected'),
    'joining_pending', (select count(*) from public.candidate_joinings where joining_status in ('pending','confirmed','deferred')),
    'joined', (select count(*) from public.candidate_joinings where joining_status = 'joined')
  );
end;
$$;

create function public.list_recruitment_candidates(
  p_search text default null, p_state text default null, p_district text default null,
  p_qualification text default null, p_candidate_type text default null,
  p_status text default null, p_limit integer default 25, p_offset integer default 0)
returns table(id uuid, full_name text, current_location text, district text, state text,
  highest_qualification text, specialization text, candidate_type text,
  total_experience text, interview_available text, status text, created_at timestamptz,
  application_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare term text := nullif(btrim(p_search), ''); capped integer := least(greatest(coalesce(p_limit,25),1),100);
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if coalesce(p_offset,0) < 0 then raise exception 'Offset must not be negative'; end if;
  return query select c.id,c.full_name,c.current_location,c.district,c.state,c.highest_qualification,
    c.specialization,c.candidate_type,c.total_experience,c.interview_available,c.status,c.created_at,
    (select count(*) from public.candidate_applications a where a.candidate_id=c.id)
  from public.candidates c
  where (term is null or c.full_name ilike '%'||term||'%' or c.current_location ilike '%'||term||'%')
    and (nullif(btrim(p_state),'') is null or lower(c.state)=lower(btrim(p_state)))
    and (nullif(btrim(p_district),'') is null or lower(c.district)=lower(btrim(p_district)))
    and (nullif(btrim(p_qualification),'') is null or c.highest_qualification=btrim(p_qualification))
    and (nullif(btrim(p_candidate_type),'') is null or c.candidate_type=btrim(p_candidate_type))
    and (nullif(btrim(p_status),'') is null or c.status=lower(btrim(p_status)))
    and ((select private.can_manage_candidates()) or not (select private.has_staff_role('operations')) or exists(
      select 1 from public.candidate_applications a where a.candidate_id=c.id
        and a.application_status in ('selected','joining_pending','joined','left')))
  order by c.created_at desc,c.id limit capped offset coalesce(p_offset,0);
end;
$$;

create function public.get_recruitment_candidate(p_candidate_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb; expose_pii boolean := (select private.can_manage_candidates());
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if (select private.has_staff_role('operations')) and not expose_pii and not exists(
    select 1 from public.candidate_applications where candidate_id=p_candidate_id
      and application_status in ('selected','joining_pending','joined','left')) then
    raise exception 'Selected-candidate context is required';
  end if;
  select jsonb_build_object('id',c.id,'full_name',c.full_name,'age',c.age,'gender',c.gender,
    'mobile',case when expose_pii then c.mobile else null end,
    'whatsapp_number',case when expose_pii then c.whatsapp_number else null end,
    'current_location',c.current_location,'district',c.district,'state',c.state,
    'highest_qualification',c.highest_qualification,'specialization',c.specialization,
    'candidate_type',c.candidate_type,'total_experience',c.total_experience,
    'previous_job_role',c.previous_job_role,'interview_available',c.interview_available,
    'preferred_job_location',c.preferred_job_location,'status',c.status,
    'internal_notes',case when expose_pii then c.internal_notes else null end,
    'created_at',c.created_at,'updated_at',c.updated_at,
    'applications',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'requirement_id',a.requirement_id,
      'requirement_code',r.requirement_code,'job_role',r.job_role,'company_name',r.company_name,
      'status',a.application_status,'applied_at',a.applied_at) order by a.applied_at desc),'[]'::jsonb)
      from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id where a.candidate_id=c.id),
    'interviews',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'application_id',i.application_id,
      'scheduled_at',i.scheduled_at,'mode',i.mode,'status',i.status,'result',i.result) order by i.created_at desc),'[]'::jsonb)
      from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.candidate_id=c.id))
  into result from public.candidates c where c.id=p_candidate_id;
  if result is null then raise exception 'Candidate was not found'; end if;
  return result;
end;
$$;

create function public.update_recruitment_candidate(p_candidate_id uuid,p_status text,p_interview_available text,
  p_internal_notes text default null,p_correlation_id uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); normalized_status text:=lower(btrim(coalesce(p_status,'')));
  normalized_availability text:=btrim(coalesce(p_interview_available,'')); notes text:=nullif(btrim(p_internal_notes),'');
begin
  if actor is null or not (select private.can_manage_candidates()) then raise exception 'Candidate management access is required'; end if;
  if normalized_status not in ('new','contacted','shortlisted','interview','selected','joined','inactive')
     or normalized_availability not in ('Yes','No') then raise exception 'Unsupported candidate workflow value'; end if;
  if length(coalesce(notes,''))>4000 then raise exception 'Candidate note is too long'; end if;
  update public.candidates set status=normalized_status,interview_available=normalized_availability,internal_notes=notes where id=p_candidate_id;
  if not found then raise exception 'Candidate was not found'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.candidate_updated','candidate',p_candidate_id,'admin',p_correlation_id,
      jsonb_build_object('status',normalized_status,'interview_available',normalized_availability));
  return true;
end;
$$;

create function public.list_recruitment_requirements(p_search text default null,p_stage text default null,
  p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,company_name text,job_role text,job_location text,
  required_headcount integer,filled_positions integer,qualification text,iti_trade text,
  experience_requirement text,gender_preference text,age_min integer,age_max integer,
  salary_min numeric,salary_max numeric,shift_details text,working_hours text,
  accommodation text,canteen text,transport text,requirement_stage text,created_at timestamptz,
  application_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare term text:=nullif(btrim(p_search),''); capped integer:=least(greatest(coalesce(p_limit,25),1),100);
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  return query select r.id,r.requirement_code,r.company_name,r.job_role,coalesce(r.job_location,r.company_location),
    r.required_headcount,r.filled_positions,r.qualification,r.iti_trade,r.experience_requirement,r.gender_preference,
    r.age_min,r.age_max,r.salary_min,r.salary_max,r.shift_details,r.working_hours,r.accommodation,r.canteen,r.transport,
    r.requirement_stage,r.created_at,(select count(*) from public.candidate_applications a where a.requirement_id=r.id)
  from public.employer_requirements r where (term is null or r.company_name ilike '%'||term||'%' or r.job_role ilike '%'||term||'%'
    or r.requirement_code ilike '%'||term||'%' or coalesce(r.job_location,r.company_location) ilike '%'||term||'%')
    and (nullif(btrim(p_stage),'') is null or r.requirement_stage=lower(btrim(p_stage)))
  order by r.created_at desc,r.id limit capped offset greatest(coalesce(p_offset,0),0);
end;
$$;

create function public.create_recruitment_application(p_candidate_id uuid,p_requirement_id uuid,
  p_source_reference text default null,p_correlation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); new_id uuid;
begin
  if actor is null or not (select private.can_manage_applications()) then raise exception 'Application management access is required'; end if;
  if not exists(select 1 from public.candidates where id=p_candidate_id and status<>'inactive') then raise exception 'Active candidate was not found'; end if;
  if not exists(select 1 from public.employer_requirements where id=p_requirement_id and requirement_stage='open') then raise exception 'Open requirement was not found'; end if;
  insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,created_by,source_reference,correlation_id)
    values(p_candidate_id,p_requirement_id,'admin','applied',actor,nullif(btrim(p_source_reference),''),p_correlation_id) returning id into new_id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.application_created','candidate_application',new_id,'admin',p_correlation_id,
      jsonb_build_object('candidate_id',p_candidate_id,'requirement_id',p_requirement_id));
  return new_id;
exception when unique_violation then raise exception 'Candidate already has an application for this requirement';
end;
$$;

create function public.list_recruitment_applications(p_stage text default null,p_search text default null,
  p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,candidate_id uuid,candidate_name text,requirement_id uuid,requirement_code text,
  company_name text,job_role text,application_status text,source_type text,applied_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare term text:=nullif(btrim(p_search),''); capped integer:=least(greatest(coalesce(p_limit,25),1),100);
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  return query select a.id,a.candidate_id,c.full_name,a.requirement_id,r.requirement_code,r.company_name,r.job_role,
    a.application_status,a.source_type,a.applied_at,a.updated_at
  from public.candidate_applications a join public.candidates c on c.id=a.candidate_id
    join public.employer_requirements r on r.id=a.requirement_id
  where (nullif(btrim(p_stage),'') is null or a.application_status=lower(btrim(p_stage)))
    and (term is null or c.full_name ilike '%'||term||'%' or r.requirement_code ilike '%'||term||'%'
      or r.company_name ilike '%'||term||'%' or r.job_role ilike '%'||term||'%')
    and (not (select private.has_staff_role('operations')) or (select private.can_manage_applications())
      or a.application_status in ('selected','joining_pending','joined','left'))
  order by a.updated_at desc,a.id limit capped offset greatest(coalesce(p_offset,0),0);
end;
$$;

create function public.get_recruitment_application(p_application_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  select jsonb_build_object('id',a.id,'candidate_id',a.candidate_id,'candidate_name',c.full_name,
    'requirement_id',a.requirement_id,'requirement_code',r.requirement_code,'company_name',r.company_name,
    'job_role',r.job_role,'application_status',a.application_status,'source_type',a.source_type,
    'admin_notes',case when (select private.can_manage_applications()) then a.admin_notes else null end,
    'applied_at',a.applied_at,'updated_at',a.updated_at,
    'stage_history',(select coalesce(jsonb_agg(jsonb_build_object('from_stage',h.from_stage,'to_stage',h.to_stage,
      'reason',h.reason,'created_at',h.created_at) order by h.created_at desc),'[]'::jsonb) from public.application_stage_history h where h.application_id=a.id),
    'interviews',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'interview_round',i.interview_round,
      'scheduled_at',i.scheduled_at,'mode',i.mode,'status',i.status,'result',i.result) order by i.created_at desc),'[]'::jsonb)
      from public.interviews i where i.application_id=a.id)) into result
  from public.candidate_applications a join public.candidates c on c.id=a.candidate_id
    join public.employer_requirements r on r.id=a.requirement_id where a.id=p_application_id;
  if result is null then raise exception 'Application was not found'; end if;
  return result;
end;
$$;

create function public.transition_recruitment_application(p_application_id uuid,p_to_stage text,
  p_reason text default null,p_internal_notes text default null,p_correlation_id uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); prior_stage text; target text:=lower(btrim(coalesce(p_to_stage,'')));
  allowed boolean:=false; normalized_reason text:=nullif(btrim(p_reason),''); notes text:=nullif(btrim(p_internal_notes),'');
begin
  if actor is null or not (select private.can_manage_applications()) then raise exception 'Application management access is required'; end if;
  select application_status into prior_stage from public.candidate_applications where id=p_application_id for update;
  if prior_stage is null then raise exception 'Application was not found'; end if;
  allowed := (prior_stage,target) in (('interested','applied'),('applied','screening'),('screening','shortlisted'),
    ('shortlisted','interview'),('interview','selected'),('interview','rejected'),('selected','rejected'));
  if not allowed then raise exception 'Unsupported application stage transition'; end if;
  if length(coalesce(normalized_reason,''))>2000 or length(coalesce(notes,''))>4000 then raise exception 'Application note is too long'; end if;
  update public.candidate_applications set application_status=target,admin_notes=notes,correlation_id=p_correlation_id where id=p_application_id;
  update public.application_stage_history as h set reason=normalized_reason
    where h.application_id=p_application_id and h.from_stage=prior_stage and h.to_stage=target
      and h.actor_user_id=actor and h.correlation_id is not distinct from p_correlation_id
      and h.id=(select latest.id from public.application_stage_history latest where latest.application_id=p_application_id order by latest.created_at desc,latest.id desc limit 1);
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.application_transitioned','candidate_application',p_application_id,'admin',p_correlation_id,
      jsonb_build_object('from_stage',prior_stage,'to_stage',target));
  return true;
end;
$$;

create function public.list_recruitment_interviews(p_upcoming_only boolean default false,p_limit integer default 50)
returns table(id uuid,application_id uuid,candidate_name text,requirement_code text,interview_round smallint,
  scheduled_at timestamptz,mode text,status text,result text,updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  return query select i.id,i.application_id,c.full_name,r.requirement_code,i.interview_round,i.scheduled_at,i.mode,i.status,i.result,i.updated_at
  from public.interviews i join public.candidate_applications a on a.id=i.application_id
    join public.candidates c on c.id=a.candidate_id join public.employer_requirements r on r.id=a.requirement_id
  where (not coalesce(p_upcoming_only,false) or (i.status='scheduled' and i.scheduled_at>=now()))
    and (not (select private.has_staff_role('operations')) or (select private.can_manage_interviews())
      or a.application_status in ('selected','joining_pending','joined','left'))
  order by i.scheduled_at desc nulls last,i.id limit least(greatest(coalesce(p_limit,50),1),100);
end;
$$;

create function public.schedule_recruitment_interview(p_application_id uuid,p_scheduled_at timestamptz,p_mode text,
  p_location text default null,p_instructions text default null,p_correlation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); new_id uuid; next_round smallint; stage text; normalized_mode text:=lower(btrim(coalesce(p_mode,'')));
begin
  if actor is null or not (select private.can_manage_interviews()) then raise exception 'Interview management access is required'; end if;
  if p_scheduled_at is null or p_scheduled_at<=now() or normalized_mode not in ('onsite','phone','video','other') then raise exception 'Valid future interview details are required'; end if;
  select application_status into stage from public.candidate_applications where id=p_application_id for update;
  if stage not in ('interested','applied','screening','shortlisted','interview') then raise exception 'Application is not eligible for interview'; end if;
  if exists(select 1 from public.interviews where application_id=p_application_id and status='scheduled') then raise exception 'A current interview is already scheduled'; end if;
  select (coalesce(max(interview_round),0)+1)::smallint into next_round from public.interviews where application_id=p_application_id;
  insert into public.interviews(application_id,interview_round,scheduled_at,mode,location,instructions,status,created_by)
    values(p_application_id,next_round,p_scheduled_at,normalized_mode,nullif(btrim(p_location),''),nullif(btrim(p_instructions),''),'scheduled',actor) returning id into new_id;
  if stage in ('interested','applied','screening','shortlisted') then update public.candidate_applications set application_status='interview',correlation_id=p_correlation_id where id=p_application_id; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.interview_scheduled','interview',new_id,'admin',p_correlation_id,jsonb_build_object('application_id',p_application_id));
  return new_id;
exception when unique_violation then raise exception 'A current interview is already scheduled';
end;
$$;

create function public.update_recruitment_interview(p_interview_id uuid,p_status text,p_result text default null,
  p_result_notes text default null,p_correlation_id uuid default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); normalized_status text:=lower(btrim(coalesce(p_status,'')));
  normalized_result text:=nullif(lower(btrim(p_result)),''); app_id uuid; previous_status text;
begin
  if actor is null or not (select private.can_manage_interviews()) then raise exception 'Interview management access is required'; end if;
  if normalized_status not in ('attended','absent','completed','cancelled')
     or (normalized_result is not null and normalized_result not in ('pending','selected','rejected','on_hold')) then raise exception 'Unsupported interview outcome'; end if;
  if normalized_status in ('absent','cancelled') and normalized_result is not null then raise exception 'Absent or cancelled interviews cannot have a result'; end if;
  if normalized_status='completed' and normalized_result is null then raise exception 'Completed interview requires a result'; end if;
  if length(coalesce(nullif(btrim(p_result_notes),''),''))>4000 then raise exception 'Interview result note is too long'; end if;
  select i.status,i.application_id into previous_status,app_id from public.interviews i where i.id=p_interview_id for update;
  if app_id is null then raise exception 'Interview was not found'; end if;
  if previous_status not in ('scheduled','attended') then raise exception 'Interview outcome is already final'; end if;
  update public.interviews set status=normalized_status,result=normalized_result,result_notes=nullif(btrim(p_result_notes),'') where id=p_interview_id;
  if normalized_result='selected' then update public.candidate_applications set application_status='selected',correlation_id=p_correlation_id where id=app_id and application_status='interview';
  elsif normalized_result='rejected' then update public.candidate_applications set application_status='rejected',correlation_id=p_correlation_id where id=app_id and application_status='interview'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.interview_updated','interview',p_interview_id,'admin',p_correlation_id,jsonb_build_object('status',normalized_status,'result',normalized_result));
  return true;
end;
$$;

create function public.reschedule_recruitment_interview(p_interview_id uuid,p_scheduled_at timestamptz,p_mode text,
  p_location text default null,p_instructions text default null,p_correlation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); previous_id uuid; previous_application_id uuid;
  previous_round smallint; previous_status text; replacement uuid;
  normalized_mode text:=lower(btrim(coalesce(p_mode,'')));
begin
  if actor is null or not (select private.can_manage_interviews()) then raise exception 'Interview management access is required'; end if;
  if p_scheduled_at is null or p_scheduled_at<=now() or normalized_mode not in ('onsite','phone','video','other') then raise exception 'Valid future interview details are required'; end if;
  select i.id,i.application_id,i.interview_round,i.status
    into previous_id,previous_application_id,previous_round,previous_status
    from public.interviews i where i.id=p_interview_id for update;
  if previous_id is null or previous_status<>'scheduled' then raise exception 'A scheduled interview was not found'; end if;
  update public.interviews set status='rescheduled' where id=previous_id;
  insert into public.interviews(application_id,interview_round,supersedes_interview_id,scheduled_at,mode,location,instructions,status,created_by)
    values(previous_application_id,previous_round,previous_id,p_scheduled_at,normalized_mode,
      nullif(btrim(p_location),''),nullif(btrim(p_instructions),''),'scheduled',actor) returning id into replacement;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.interview_rescheduled','interview',replacement,'admin',p_correlation_id,jsonb_build_object('supersedes_interview_id',previous_id));
  return replacement;
end;
$$;

create function public.list_recruitment_joinings(p_status text default null,p_limit integer default 50)
returns table(id uuid,application_id uuid,candidate_name text,requirement_code text,company_name text,
  expected_joining_date date,actual_joining_date date,joining_status text,employee_code text,remarks text,updated_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_view_recruitment()) then raise exception 'Recruitment access is required'; end if;
  return query select j.id,j.application_id,c.full_name,r.requirement_code,r.company_name,j.expected_joining_date,
    j.actual_joining_date,j.joining_status,j.employee_code,j.remarks,j.updated_at
  from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id
    join public.candidates c on c.id=a.candidate_id join public.employer_requirements r on r.id=a.requirement_id
  where nullif(btrim(p_status),'') is null or j.joining_status=lower(btrim(p_status))
  order by j.updated_at desc,j.id limit least(greatest(coalesce(p_limit,50),1),100);
end;
$$;

create function public.upsert_recruitment_joining(p_application_id uuid,p_expected_date date,p_actual_date date,
  p_joining_status text,p_employee_code text default null,p_remarks text default null,p_correlation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); normalized text:=lower(btrim(coalesce(p_joining_status,'')));
  joining_id uuid; app_stage text; previous_joining_status text;
begin
  if actor is null or not (select private.can_manage_joinings()) then raise exception 'Joining management access is required'; end if;
  if normalized not in ('pending','confirmed','joined','no_show','deferred','left','cancelled') then raise exception 'Unsupported joining status'; end if;
  if normalized='joined' and p_actual_date is null then raise exception 'Joined status requires actual joining date'; end if;
  if p_actual_date is not null and normalized not in ('joined','left') then raise exception 'Actual joining date requires joined or left status'; end if;
  if normalized in ('pending','confirmed','deferred') and p_expected_date is null then raise exception 'Active joining workflow requires expected joining date'; end if;
  if length(coalesce(nullif(btrim(p_employee_code),''),''))>200 or length(coalesce(nullif(btrim(p_remarks),''),''))>4000 then raise exception 'Joining details are too long'; end if;
  select application_status into app_stage from public.candidate_applications where id=p_application_id for update;
  if app_stage not in ('selected','joining_pending','joined','left','cancelled') then raise exception 'Selected application context is required'; end if;
  select j.joining_status into previous_joining_status from public.candidate_joinings j where j.application_id=p_application_id for update;
  if previous_joining_status is null and app_stage<>'selected' then raise exception 'A new joining requires a selected application'; end if;
  if previous_joining_status='joined' and normalized not in ('joined','left') then raise exception 'Joined placement can only remain joined or move to left'; end if;
  if previous_joining_status in ('left','no_show','cancelled') and normalized<>previous_joining_status then raise exception 'Terminal joining status cannot transition'; end if;
  insert into public.candidate_joinings(application_id,expected_joining_date,actual_joining_date,joining_status,employee_code,remarks,created_by)
    values(p_application_id,p_expected_date,p_actual_date,normalized,nullif(btrim(p_employee_code),''),nullif(btrim(p_remarks),''),actor)
  on conflict(application_id) do update set expected_joining_date=excluded.expected_joining_date,
    actual_joining_date=case when excluded.joining_status='left' then coalesce(excluded.actual_joining_date,candidate_joinings.actual_joining_date) else excluded.actual_joining_date end,
    joining_status=excluded.joining_status,employee_code=excluded.employee_code,remarks=excluded.remarks returning id into joining_id;
  update public.candidate_applications set application_status=case
      when normalized='joined' then 'joined' when normalized='left' then 'left'
      when normalized in ('no_show','cancelled') then 'cancelled' else 'joining_pending' end,
    correlation_id=p_correlation_id where id=p_application_id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.joining_upserted','candidate_joining',joining_id,'admin',p_correlation_id,jsonb_build_object('status',normalized));
  return joining_id;
end;
$$;

create index candidate_applications_updated_stage_idx on public.candidate_applications(application_status,updated_at desc);
create index interviews_upcoming_idx on public.interviews(scheduled_at) where status='scheduled';
create index candidate_joinings_expected_idx on public.candidate_joinings(expected_joining_date) where joining_status in ('pending','confirmed','deferred');

revoke all on function public.get_recruitment_permissions() from public,anon;
revoke all on function public.get_recruitment_dashboard() from public,anon;
revoke all on function public.list_recruitment_candidates(text,text,text,text,text,text,integer,integer) from public,anon;
revoke all on function public.get_recruitment_candidate(uuid) from public,anon;
revoke all on function public.update_recruitment_candidate(uuid,text,text,text,uuid) from public,anon;
revoke all on function public.list_recruitment_requirements(text,text,integer,integer) from public,anon;
revoke all on function public.create_recruitment_application(uuid,uuid,text,uuid) from public,anon;
revoke all on function public.list_recruitment_applications(text,text,integer,integer) from public,anon;
revoke all on function public.get_recruitment_application(uuid) from public,anon;
revoke all on function public.transition_recruitment_application(uuid,text,text,text,uuid) from public,anon;
revoke all on function public.list_recruitment_interviews(boolean,integer) from public,anon;
revoke all on function public.schedule_recruitment_interview(uuid,timestamp with time zone,text,text,text,uuid) from public,anon;
revoke all on function public.update_recruitment_interview(uuid,text,text,text,uuid) from public,anon;
revoke all on function public.reschedule_recruitment_interview(uuid,timestamp with time zone,text,text,text,uuid) from public,anon;
revoke all on function public.list_recruitment_joinings(text,integer) from public,anon;
revoke all on function public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid) from public,anon;

grant execute on function public.get_recruitment_permissions() to authenticated;
grant execute on function public.get_recruitment_dashboard() to authenticated;
grant execute on function public.list_recruitment_candidates(text,text,text,text,text,text,integer,integer) to authenticated;
grant execute on function public.get_recruitment_candidate(uuid) to authenticated;
grant execute on function public.update_recruitment_candidate(uuid,text,text,text,uuid) to authenticated;
grant execute on function public.list_recruitment_requirements(text,text,integer,integer) to authenticated;
grant execute on function public.create_recruitment_application(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.list_recruitment_applications(text,text,integer,integer) to authenticated;
grant execute on function public.get_recruitment_application(uuid) to authenticated;
grant execute on function public.transition_recruitment_application(uuid,text,text,text,uuid) to authenticated;
grant execute on function public.list_recruitment_interviews(boolean,integer) to authenticated;
grant execute on function public.schedule_recruitment_interview(uuid,timestamp with time zone,text,text,text,uuid) to authenticated;
grant execute on function public.update_recruitment_interview(uuid,text,text,text,uuid) to authenticated;
grant execute on function public.reschedule_recruitment_interview(uuid,timestamp with time zone,text,text,text,uuid) to authenticated;
grant execute on function public.list_recruitment_joinings(text,integer) to authenticated;
grant execute on function public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid) to authenticated;

-- No direct table grants or policies are added. Migration 015 tenant projections
-- and W2 staff-management authorization remain unchanged.

commit;
