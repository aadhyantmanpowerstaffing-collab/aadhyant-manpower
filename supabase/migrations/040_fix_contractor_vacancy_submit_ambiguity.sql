-- Batch 2 corrective migration: preserve the Migration 039 Contractor vacancy
-- contract while removing an ambiguous local/table identifier in submit paths.
begin;

do $$
declare
  function_definition text;
  function_is_secure boolean;
  function_config text;
  review_definition text;
  review_is_secure boolean;
  review_config text;
begin
  if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)') is null
     or to_regprocedure('private.normalized_vacancy_review_status(uuid)') is null
     or to_regprocedure('private.current_contractor_portal_id(boolean)') is null
     or to_regprocedure('public.review_contractor_vacancy(uuid,text,text)') is null then
    raise exception 'Migration 039 Contractor vacancy prerequisites are missing';
  end if;
  if exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='employer_requirements'
      and not exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='source_type' and not a.attisdropped)
  ) then
    raise exception 'Migration 039 source-type prerequisite is missing';
  end if;
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict function_definition,function_is_secure,function_config
  from pg_proc p
  where p.oid='public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)'::regprocedure;
  if not function_is_secure or function_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)','execute')
     or has_function_privilege('anon','public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)','execute') then
    raise exception 'Migration 039 Contractor vacancy security baseline drifted';
  end if;
  if position('rc.contractor_id=contractor_id' in function_definition)=0
     or position('v_contractor_id' in function_definition)>0 then
    raise exception 'Migration 040 expected pre-correction Contractor function is not installed';
  end if;
  if position('if action in (''create'',''create_draft'',''create_and_submit'',''update'',''update_draft'',''resubmit'') then' in lower(function_definition))=0 then
    raise exception 'Migration 039 Contractor resubmit validation baseline drifted';
  end if;
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict review_definition,review_is_secure,review_config
  from pg_proc p
  where p.oid='public.review_contractor_vacancy(uuid,text,text)'::regprocedure;
  if not review_is_secure or review_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.review_contractor_vacancy(uuid,text,text)','execute')
     or has_function_privilege('anon','public.review_contractor_vacancy(uuid,text,text)','execute') then
    raise exception 'Migration 039 Contractor review security baseline drifted';
  end if;
  if position('where requirement_id=r.id and origin_type=''contractor_submission'' for update' in review_definition)=0
     or position('v_requirement' in review_definition)>0 then
    raise exception 'Migration 040 expected pre-correction Contractor review function is not installed';
  end if;
end;
$$;

create or replace function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid default null,p_client_name text default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_iti_trade text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_expected_joining_date date default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=(select auth.uid());
  v_contractor_id uuid;
  v_contractor public.contractors%rowtype;
  v_requirement public.employer_requirements%rowtype;
  v_link public.requirement_contractors%rowtype;
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_prior_status text;
begin
  if v_actor is null or not (select private.can_manage_contractor_vacancies()) then
    raise exception 'Contractor vacancy management access is required';
  end if;
  v_contractor_id:=(select private.current_contractor_portal_id(true));
  select c.* into v_contractor from public.contractors c where c.id=v_contractor_id;
  if v_contractor.id is null or v_contractor.main_phone is null or v_contractor.main_phone !~ '^[6-9][0-9]{9}$' then
    raise exception 'A valid contractor contact phone is required before submitting vacancies';
  end if;
  if v_action in ('create','create_draft','create_and_submit','update','update_draft') then
    if length(btrim(coalesce(p_client_name,''))) not between 1 and 200 or length(btrim(coalesce(p_job_role,''))) not between 1 and 200
       or length(btrim(coalesce(p_job_location,''))) not between 1 and 300 or coalesce(p_required_headcount,0) not between 1 and 100000 then
      raise exception 'Client, role, location, and valid openings are required';
    end if;
    if p_experience_requirement not in ('Fresher','Experienced','Both') or p_gender_preference not in ('Any','Male','Female')
       or (p_age_min is not null and p_age_min not between 16 and 75) or (p_age_max is not null and p_age_max not between 16 and 75)
       or (p_age_min is not null and p_age_max is not null and p_age_min>p_age_max)
       or coalesce(p_salary_min,0)<0 or coalesce(p_salary_max,0)<0 or (p_salary_min is not null and p_salary_max is not null and p_salary_min>p_salary_max) then
      raise exception 'Vacancy criteria are invalid';
    end if;
  end if;
  if v_action in ('create','create_draft','create_and_submit') then
    insert into public.employer_requirements(company_name,contact_person,mobile,email,company_location,job_role,required_headcount,
      qualification,iti_trade,experience_requirement,gender_preference,salary_wage,shift_details,working_hours,expected_joining_date,
      accommodation,canteen,transport,additional_notes,consent,status,created_by_user_id,department,job_location,age_min,age_max,
      salary_min,salary_max,overtime_details,interview_location,requirement_visibility,requirement_stage,source_type)
    values(btrim(p_client_name),coalesce(nullif(btrim(v_contractor.owner_name),''),v_contractor.agency_name),btrim(v_contractor.main_phone),v_contractor.main_email,
      btrim(p_job_location),btrim(p_job_role),p_required_headcount,nullif(btrim(p_qualification),''),nullif(btrim(p_iti_trade),''),p_experience_requirement,
      p_gender_preference,case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
      nullif(btrim(p_shift_details),''),nullif(btrim(p_working_hours),''),p_expected_joining_date,p_accommodation,p_canteen,p_transport,
      nullif(btrim(p_additional_notes),''),true,'new',v_actor,nullif(btrim(p_department),''),btrim(p_job_location),p_age_min,p_age_max,p_salary_min,p_salary_max,
      nullif(btrim(p_overtime_details),''),nullif(btrim(p_interview_location),''),'private','draft','contractor_portal') returning * into v_requirement;
    insert into public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,assignment_status,origin_type,submission_status,submitted_at)
    values(v_requirement.id,v_contractor_id,p_required_headcount,'assigned','contractor_submission',case when v_action='create_and_submit' then 'submitted' else 'draft' end,
      case when v_action='create_and_submit' then clock_timestamp() else null end) returning * into v_link;
  else
    select r.* into v_requirement from public.employer_requirements r
    where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
    if v_requirement.id is null then raise exception 'Contractor vacancy was not found'; end if;
    select rc.* into v_link from public.requirement_contractors rc
    where rc.requirement_id=v_requirement.id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' for update;
    if v_link.id is null then raise exception 'Contractor vacancy was not found'; end if;
    v_prior_status:=v_link.submission_status;
    if v_action in ('update','update_draft') then
      if v_link.submission_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be edited'; end if;
      update public.employer_requirements as r set company_name=btrim(p_client_name),department=nullif(btrim(p_department),''),job_role=btrim(p_job_role),
        company_location=btrim(p_job_location),job_location=btrim(p_job_location),required_headcount=p_required_headcount,qualification=nullif(btrim(p_qualification),''),
        iti_trade=nullif(btrim(p_iti_trade),''),experience_requirement=p_experience_requirement,gender_preference=p_gender_preference,age_min=p_age_min,age_max=p_age_max,
        salary_min=p_salary_min,salary_max=p_salary_max,salary_wage=case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
        shift_details=nullif(btrim(p_shift_details),''),working_hours=nullif(btrim(p_working_hours),''),overtime_details=nullif(btrim(p_overtime_details),''),
        canteen=p_canteen,transport=p_transport,accommodation=p_accommodation,interview_location=nullif(btrim(p_interview_location),''),
        expected_joining_date=p_expected_joining_date,additional_notes=nullif(btrim(p_additional_notes),''),requirement_stage='draft',requirement_visibility='private'
      where r.id=v_requirement.id returning r.* into v_requirement;
    elsif v_action in ('submit','resubmit') then
      if (v_action='submit' and v_link.submission_status<>'draft') or (v_action='resubmit' and v_link.submission_status<>'correction_required') then
        raise exception 'Vacancy is not in an allowed submission state'; end if;
      update public.requirement_contractors as rc set submission_status='submitted',submitted_at=clock_timestamp(),review_feedback=null,reviewed_at=null,reviewed_by=null
      where rc.id=v_link.id returning rc.* into v_link;
      update public.employer_requirements as r set requirement_stage='draft',requirement_visibility='private' where r.id=v_requirement.id returning r.* into v_requirement;
    elsif v_action='cancel' then
      if v_link.submission_status not in ('draft','submitted','under_review','correction_required') then raise exception 'This vacancy cannot be cancelled'; end if;
      update public.requirement_contractors as rc set submission_status='cancelled',closed_at=clock_timestamp() where rc.id=v_link.id returning rc.* into v_link;
      update public.employer_requirements as r set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp()
      where r.id=v_requirement.id returning r.* into v_requirement;
    else
      raise exception 'Unsupported Contractor vacancy action';
    end if;
  end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(v_actor,'contractor','contractor_vacancy_'||v_action,'employer_requirement',v_requirement.id,'contractor',
    jsonb_build_object('old_submission_status',v_prior_status,'new_submission_status',v_link.submission_status,'source_type',v_requirement.source_type));
  return query select v_requirement.id,v_requirement.requirement_code,v_link.submission_status,v_requirement.requirement_stage,v_requirement.updated_at;
end;
$$;

revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) from public,anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) to authenticated;

create or replace function public.review_contractor_vacancy(p_requirement_id uuid,p_action text,p_feedback text default null)
returns table(requirement_id uuid,requirement_code text,submission_status text,requirement_stage text,requirement_visibility text)
language plpgsql security definer set search_path='' as $$
declare
  v_requirement public.employer_requirements%rowtype;
  v_link public.requirement_contractors%rowtype;
  v_action text:=lower(btrim(coalesce(p_action,'')));
begin
  if not (select private.can_review_vacancies()) then raise exception 'Contractor vacancy review access is required'; end if;
  if length(coalesce(p_feedback,''))>2000 then raise exception 'Review feedback is too long'; end if;
  v_requirement:=private.lock_vacancy_review(p_requirement_id);
  if v_requirement.source_type<>'contractor_portal' then raise exception 'Contractor vacancy was not found'; end if;
  select rc.* into v_link from public.requirement_contractors rc
  where rc.requirement_id=v_requirement.id and rc.origin_type='contractor_submission' for update;
  if v_link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if v_action='start_review' then
    if v_link.submission_status<>'submitted' then raise exception 'Only a submitted vacancy can be opened for review'; end if;
    update public.requirement_contractors as rc set submission_status='under_review',reviewed_at=clock_timestamp(),reviewed_by=(select auth.uid())
    where rc.id=v_link.id returning rc.* into v_link;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','contractor_vacancy_review_opened','employer_requirement',v_requirement.id,'admin','{}');
  elsif v_action='approve' then
    perform public.admin_approve_and_publish_vacancy(v_requirement.id,null);
    select rc.* into v_link from public.requirement_contractors rc where rc.id=v_link.id;
    select r.* into v_requirement from public.employer_requirements r where r.id=v_requirement.id;
  elsif v_action='request_correction' then
    perform public.admin_request_vacancy_correction(v_requirement.id,p_feedback,null);
    select rc.* into v_link from public.requirement_contractors rc where rc.id=v_link.id;
    select r.* into v_requirement from public.employer_requirements r where r.id=v_requirement.id;
  elsif v_action='reject' then
    perform public.admin_reject_vacancy(v_requirement.id,p_feedback,null);
    select rc.* into v_link from public.requirement_contractors rc where rc.id=v_link.id;
    select r.* into v_requirement from public.employer_requirements r where r.id=v_requirement.id;
  elsif v_action='close' then
    if v_link.submission_status<>'approved' then raise exception 'Only an approved vacancy can be closed'; end if;
    update public.requirement_contractors as rc set submission_status='closed',assignment_status='completed',reviewed_at=clock_timestamp(),reviewed_by=(select auth.uid()),closed_at=clock_timestamp()
    where rc.id=v_link.id returning rc.* into v_link;
    update public.employer_requirements as r set requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp()
    where r.id=v_requirement.id returning r.* into v_requirement;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','contractor_vacancy_review_closed','employer_requirement',v_requirement.id,'admin','{}');
  else
    raise exception 'Invalid Contractor vacancy review action';
  end if;
  return query select v_requirement.id,v_requirement.requirement_code,v_link.submission_status,v_requirement.requirement_stage,v_requirement.requirement_visibility;
end;
$$;

revoke all on function public.review_contractor_vacancy(uuid,text,text) from public,anon;
grant execute on function public.review_contractor_vacancy(uuid,text,text) to authenticated;

do $$
declare
  function_definition text;
  function_is_secure boolean;
  function_config text;
  review_definition text;
  review_is_secure boolean;
  review_config text;
begin
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict function_definition,function_is_secure,function_config
  from pg_proc p
  where p.oid='public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)'::regprocedure;
  if position('rc.contractor_id=v_contractor_id' in function_definition)=0
     or position('rc.contractor_id=contractor_id' in function_definition)>0
     or position('if v_action in (''create'',''create_draft'',''create_and_submit'',''update'',''update_draft'',''resubmit'') then' in lower(function_definition))>0
     or not function_is_secure or function_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)','execute')
     or has_function_privilege('anon','public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)','execute') then
    raise exception 'Migration 040 Contractor vacancy post-install assertion failed';
  end if;
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict review_definition,review_is_secure,review_config
  from pg_proc p
  where p.oid='public.review_contractor_vacancy(uuid,text,text)'::regprocedure;
  if position('rc.requirement_id=v_requirement.id' in review_definition)=0
     or position('where requirement_id=r.id' in review_definition)>0
     or not review_is_secure or review_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.review_contractor_vacancy(uuid,text,text)','execute')
     or has_function_privilege('anon','public.review_contractor_vacancy(uuid,text,text)','execute') then
    raise exception 'Migration 040 Contractor review post-install assertion failed';
  end if;
end;
$$;

commit;
