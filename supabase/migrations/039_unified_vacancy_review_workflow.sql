-- Batch 2: canonical Company/Contractor vacancy review, publication, and eligibility boundary.
begin;

do $$
declare
  retained_total integer;
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.requirement_contractors') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.audit_logs') is null then
    raise exception 'Migration 039 prerequisite tables are missing';
  end if;
  if to_regprocedure('public.create_recruitment_joining(uuid,date,text,text,uuid)') is null
     or to_regprocedure('public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)') is null
     or to_regprocedure('public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') is null
     or to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)') is null
     or to_regprocedure('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)') is null
     or to_regprocedure('public.admin_get_job_lead_detail(uuid)') is null
     or to_regprocedure('public.apply_candidate_job(text)') is null
     or to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null
     or to_regprocedure('public.process_whatsapp_interested_response(uuid)') is null then
    raise exception 'Migration 037/038 or vacancy workflow RPC prerequisites are missing';
  end if;
  if has_table_privilege('authenticated','public.candidate_applications','insert,update,delete')
     or has_table_privilege('authenticated','public.candidate_joinings','insert,update,delete')
     or exists(
       select 1 from pg_policy
       where polrelid in ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass)
         and polcmd in ('a','w','d','*')
     ) then
    raise exception 'Migration 038 direct-write hardening baseline is not installed';
  end if;
  if exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='employer_requirements'
      and column_name in ('review_status','review_feedback','submitted_at','reviewed_at','reviewed_by')
  ) or to_regprocedure('private.normalized_vacancy_review_status(uuid)') is not null
    or to_regprocedure('public.admin_list_vacancy_reviews(text,text,integer,integer)') is not null then
    raise exception 'Migration 039 appears partially installed';
  end if;
  if not exists(
       select 1 from information_schema.columns
       where table_schema='public' and table_name='requirement_contractors' and column_name='submission_status'
     ) or not exists(
       select 1 from information_schema.columns
       where table_schema='public' and table_name='requirement_contractors' and column_name='review_feedback'
     ) then
    raise exception 'Contractor review columns are missing';
  end if;
  if exists(
    select 1 from public.requirement_contractors
    where origin_type='contractor_submission'
    group by requirement_id having count(*)<>1
  ) then
    raise exception 'Contractor submission multiplicity conflict requires review';
  end if;
  if exists(
    select 1 from public.employer_requirements
    where filled_positions>required_headcount
       or (filled_positions=required_headcount and
          (requirement_stage<>'filled' or requirement_visibility<>'private' or status<>'fulfilled'))
       or (requirement_stage='filled' and filled_positions<>required_headcount)
  ) then
    raise exception 'Requirement fulfillment state is incompatible with Migration 039';
  end if;

  select count(*) into retained_total from public.employer_requirements;
  if retained_total<>0 then
    if retained_total<>5 or (select count(*) from public.employer_requirements where id in (
      '89800000-0000-0000-0001-000000000001'::uuid,
      '33d8c291-850c-4533-96c1-f2a97543813e'::uuid,
      '81fa702d-0b02-4417-bc3d-4307ee719858'::uuid,
      '69e6b28e-3815-47a6-9c0f-ab17868139af'::uuid,
      '82a877fd-86aa-4853-9b2c-ac1fde9dc98a'::uuid
    ))<>5 then
      raise exception 'Retained requirement inventory changed after Migration 039 reconciliation';
    end if;
    if not exists(
      select 1 from public.employer_requirements r
      where r.id='33d8c291-850c-4533-96c1-f2a97543813e' and r.requirement_code='AAD-2026-000150'
        and r.source_type='admin_manual' and r.requirement_stage='open' and r.requirement_visibility='public'
        and r.status='in_progress' and r.required_headcount=10 and r.filled_positions=1
        and (select count(*) from public.company_users cu where cu.company_id=r.company_id
             and cu.user_id=r.created_by_user_id and cu.status='active')=1
        and (select count(*) from public.candidate_applications a where a.requirement_id=r.id)=1
        and (select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id
             where a.requirement_id=r.id and j.joining_status='joined')=1
    ) then raise exception 'AAD-2026-000150 no longer matches its reviewed retained state'; end if;
    if not exists(
      select 1 from public.employer_requirements r
      where r.id='89800000-0000-0000-0001-000000000001' and r.requirement_code='REQ-W7C-EDGE-V5'
        and r.source_type='admin_manual' and r.requirement_stage='open' and r.requirement_visibility='private'
        and r.status='in_progress' and r.required_headcount=1 and r.filled_positions=0
        and r.company_id is null and r.created_by_user_id is null
        and (select count(*) from public.candidate_applications a where a.requirement_id=r.id)=1
        and not exists(select 1 from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=r.id)
    ) then raise exception 'REQ-W7C-EDGE-V5 no longer matches its reviewed retained state'; end if;
    if (select count(*) from public.employer_requirements r
        where (r.id='81fa702d-0b02-4417-bc3d-4307ee719858' and r.requirement_code='AAD-2026-000193' and r.required_headcount=20)
           or (r.id='69e6b28e-3815-47a6-9c0f-ab17868139af' and r.requirement_code='AAD-2026-000194' and r.required_headcount=400))<>2
       or (select count(*) from public.requirement_contractors rc
           where rc.requirement_id in ('81fa702d-0b02-4417-bc3d-4307ee719858','69e6b28e-3815-47a6-9c0f-ab17868139af')
             and rc.origin_type='contractor_submission' and rc.submission_status='closed'
             and rc.reviewed_by is not null and rc.submitted_at is not null and rc.reviewed_at is not null)<>2
       or (select count(*) from public.audit_logs l
           where l.entity_type='employer_requirement'
             and l.entity_id in ('81fa702d-0b02-4417-bc3d-4307ee719858','69e6b28e-3815-47a6-9c0f-ab17868139af')
             and l.action='contractor_vacancy_review_approve')<>2 then
      raise exception 'Retained Contractor review history changed after reconciliation';
    end if;
    if not exists(
      select 1 from public.employer_requirements r
      where r.id='82a877fd-86aa-4853-9b2c-ac1fde9dc98a' and r.requirement_code='AAD-2026-000195'
        and r.source_type='admin_manual' and r.requirement_stage='open' and r.requirement_visibility='public'
        and r.required_headcount=10 and r.filled_positions=0
        and (select count(*) from public.company_users cu where cu.company_id=r.company_id
             and cu.user_id=r.created_by_user_id and cu.status='active')=1
        and exists(select 1 from public.audit_logs l where l.entity_type='employer_requirement' and l.entity_id=r.id
          and l.action='recruitment.requirement_lifecycle_changed' and l.actor_type='staff' and l.actor_user_id is not null)
    ) then raise exception 'AAD-2026-000195 no longer matches its reviewed retained state'; end if;
  end if;
end;
$$;

alter table public.employer_requirements
  add column review_status text,
  add column review_feedback text,
  add column submitted_at timestamptz,
  add column reviewed_at timestamptz,
  add column reviewed_by uuid references auth.users(id) on delete set null;

alter table public.employer_requirements
  add constraint employer_requirements_review_status_check
    check (review_status is null or review_status in
      ('draft','pending_review','correction_required','approved','rejected','closed')),
  add constraint employer_requirements_review_feedback_check
    check (review_feedback is null or length(btrim(review_feedback)) between 1 and 2000),
  add constraint employer_requirements_review_reason_check
    check (review_status not in ('correction_required','rejected') or review_feedback is not null);

create index employer_requirements_review_queue_idx
  on public.employer_requirements(review_status,submitted_at desc,id)
  where review_status in ('pending_review','correction_required');

do $$
declare
  changed integer;
  historical_reviewer uuid;
  historical_reviewed_at timestamptz;
  closed_time timestamptz:=clock_timestamp();
begin
  if exists(select 1 from public.employer_requirements) then
    update public.employer_requirements
    set source_type='employer_portal',review_status='approved',review_feedback=null,
        submitted_at=coalesce(submitted_at,created_at),reviewed_at=coalesce(reviewed_at,published_at)
    where id='33d8c291-850c-4533-96c1-f2a97543813e' and requirement_code='AAD-2026-000150'
      and source_type='admin_manual' and requirement_stage='open' and requirement_visibility='public';
    get diagnostics changed=row_count;
    if changed<>1 then raise exception 'AAD-2026-000150 normalization did not affect exactly one row'; end if;

    update public.employer_requirements set source_type='contractor_portal'
    where id='81fa702d-0b02-4417-bc3d-4307ee719858' and requirement_code='AAD-2026-000193' and source_type='admin_manual';
    get diagnostics changed=row_count;
    if changed<>1 then raise exception 'AAD-2026-000193 normalization did not affect exactly one row'; end if;
    update public.employer_requirements set source_type='contractor_portal'
    where id='69e6b28e-3815-47a6-9c0f-ab17868139af' and requirement_code='AAD-2026-000194' and source_type='admin_manual';
    get diagnostics changed=row_count;
    if changed<>1 then raise exception 'AAD-2026-000194 normalization did not affect exactly one row'; end if;

    select l.actor_user_id,l.created_at into strict historical_reviewer,historical_reviewed_at
    from public.audit_logs l
    where l.entity_type='employer_requirement' and l.entity_id='82a877fd-86aa-4853-9b2c-ac1fde9dc98a'
      and l.action='recruitment.requirement_lifecycle_changed' and l.actor_type='staff' and l.actor_user_id is not null
    order by l.created_at desc,l.id desc limit 1;
    update public.employer_requirements
    set source_type='employer_portal',review_status='approved',review_feedback=null,
        submitted_at=coalesce(submitted_at,created_at),reviewed_at=historical_reviewed_at,reviewed_by=historical_reviewer
    where id='82a877fd-86aa-4853-9b2c-ac1fde9dc98a' and requirement_code='AAD-2026-000195'
      and source_type='admin_manual' and requirement_stage='open' and requirement_visibility='public';
    get diagnostics changed=row_count;
    if changed<>1 then raise exception 'AAD-2026-000195 normalization did not affect exactly one row'; end if;

    update public.employer_requirements
    set review_status='closed',review_feedback='Retained synthetic W7C validation fixture; not a candidate-public approved vacancy.',
        reviewed_at=closed_time,requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=closed_time
    where id='89800000-0000-0000-0001-000000000001' and requirement_code='REQ-W7C-EDGE-V5'
      and source_type='admin_manual' and requirement_stage='open' and requirement_visibility='private';
    get diagnostics changed=row_count;
    if changed<>1 then raise exception 'REQ-W7C-EDGE-V5 normalization did not affect exactly one row'; end if;

    insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,metadata)
    select 'migration','migration039.retained_requirement_normalized','employer_requirement',r.id,'migration',
      jsonb_build_object('requirement_code',r.requirement_code,'source_type',r.source_type,'review_status',r.review_status,
        'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'human_decision_approved',true)
    from public.employer_requirements r
    where r.id in ('89800000-0000-0000-0001-000000000001','33d8c291-850c-4533-96c1-f2a97543813e',
      '81fa702d-0b02-4417-bc3d-4307ee719858','69e6b28e-3815-47a6-9c0f-ab17868139af','82a877fd-86aa-4853-9b2c-ac1fde9dc98a');
    get diagnostics changed=row_count;
    if changed<>5 then raise exception 'Retained normalization audit count is inconsistent'; end if;
  end if;
end;
$$;

create function private.normalized_vacancy_review_status(p_requirement_id uuid)
returns text language sql stable security definer set search_path='' as $$
  select case
    when count(rc.id) filter(where rc.origin_type='contractor_submission')>1 then null
    when count(rc.id) filter(where rc.origin_type='contractor_submission')=1 then
      max(case rc.submission_status
        when 'draft' then 'draft'
        when 'submitted' then 'pending_review'
        when 'under_review' then 'pending_review'
        when 'correction_required' then 'correction_required'
        when 'approved' then 'approved'
        when 'rejected' then 'rejected'
        when 'closed' then 'closed'
        when 'cancelled' then 'closed' end)
    else max(r.review_status)
  end
  from public.employer_requirements r
  left join public.requirement_contractors rc on rc.requirement_id=r.id and rc.origin_type='contractor_submission'
  where r.id=p_requirement_id
  group by r.id;
$$;

create function private.vacancy_is_application_eligible(p_requirement_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.employer_requirements r
    where r.id=p_requirement_id
      and private.normalized_vacancy_review_status(r.id)='approved'
      and r.requirement_stage='open' and r.requirement_visibility='public'
      and r.filled_positions<r.required_headcount
  );
$$;

create function private.can_review_vacancies()
returns boolean language sql stable security definer set search_path='' as $$
  select (select private.is_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'));
$$;

revoke all on function private.normalized_vacancy_review_status(uuid) from public,anon,authenticated;
revoke all on function private.vacancy_is_application_eligible(uuid) from public,anon,authenticated;
revoke all on function private.can_review_vacancies() from public,anon,authenticated;

create function public.manage_company_portal_vacancy(
  p_action text,p_requirement_id uuid default null,p_department text default null,p_job_role text default null,
  p_job_location text default null,p_required_headcount integer default null,p_qualification text default null,
  p_iti_trade text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,
  p_canteen text default 'Not Applicable',p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',
  p_interview_location text default null,p_interview_date timestamptz default null,p_expected_joining_date date default null,
  p_additional_notes text default null
)
returns table(id uuid,requirement_code text,review_status text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=(select auth.uid()); cid uuid; action text:=lower(btrim(coalesce(p_action,'')));
  company_record public.companies%rowtype; user_record public.platform_users%rowtype;
  req public.employer_requirements%rowtype; previous_feedback text; previous_review text;
begin
  if not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  cid:=(select private.current_company_portal_id(true));
  if cid is null then raise exception 'Active Company access is required'; end if;
  if action in ('create','create_draft','create_and_submit','update','update_draft') then
    if length(btrim(coalesce(p_department,''))) not between 1 and 160
       or length(btrim(coalesce(p_job_role,''))) not between 1 and 200
       or length(btrim(coalesce(p_job_location,''))) not between 1 and 240
       or p_required_headcount is null or p_required_headcount not between 1 and 100000 then
      raise exception 'Department, role, location, and valid openings are required';
    end if;
    if p_experience_requirement not in ('Fresher','Experienced','Both')
       or p_gender_preference not in ('Any','Male','Female')
       or p_canteen not in ('Yes','No','Not Applicable')
       or p_transport not in ('Yes','No','Not Applicable')
       or p_accommodation not in ('Yes','No','Not Applicable')
       or (p_age_min is not null and p_age_min not between 16 and 75)
       or (p_age_max is not null and p_age_max not between 16 and 75)
       or (p_age_min is not null and p_age_max is not null and p_age_min>p_age_max)
       or coalesce(p_salary_min,0)<0 or coalesce(p_salary_max,0)<0
       or (p_salary_min is not null and p_salary_max is not null and p_salary_min>p_salary_max) then
      raise exception 'Vacancy criteria are invalid';
    end if;
    if length(coalesce(btrim(p_qualification),''))>200 or length(coalesce(btrim(p_iti_trade),''))>200
       or length(coalesce(btrim(p_shift_details),''))>200 or length(coalesce(btrim(p_working_hours),''))>200
       or length(coalesce(btrim(p_overtime_details),''))>500 or length(coalesce(btrim(p_interview_location),''))>240
       or length(coalesce(btrim(p_additional_notes),''))>2000 then raise exception 'One or more vacancy fields are too long'; end if;
  end if;
  if action in ('create','create_draft','create_and_submit') then
    select c.* into strict company_record from public.companies c where c.id=cid;
    select * into strict user_record from public.platform_users where user_id=actor;
    insert into public.employer_requirements(company_name,contact_person,mobile,email,company_location,job_role,required_headcount,
      qualification,iti_trade,experience_requirement,gender_preference,salary_wage,shift_details,working_hours,expected_joining_date,
      accommodation,canteen,transport,additional_notes,consent,status,company_id,created_by_user_id,department,job_location,
      age_min,age_max,filled_positions,salary_min,salary_max,overtime_details,interview_location,interview_date,
      requirement_visibility,requirement_stage,source_type,review_status,submitted_at)
    values(company_record.legal_name,user_record.display_name,
      coalesce(company_record.main_phone,user_record.mobile),coalesce(company_record.main_email,user_record.email),
      concat_ws(', ',nullif(company_record.city,''),nullif(company_record.state,'')),btrim(p_job_role),p_required_headcount,
      nullif(btrim(p_qualification),''),nullif(btrim(p_iti_trade),''),p_experience_requirement,p_gender_preference,
      case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
      nullif(btrim(p_shift_details),''),nullif(btrim(p_working_hours),''),p_expected_joining_date,p_accommodation,p_canteen,p_transport,
      nullif(btrim(p_additional_notes),''),true,'new',cid,actor,btrim(p_department),btrim(p_job_location),p_age_min,p_age_max,0,
      p_salary_min,p_salary_max,nullif(btrim(p_overtime_details),''),nullif(btrim(p_interview_location),''),p_interview_date,
      'private','draft','employer_portal',case when action='create_and_submit' then 'pending_review' else 'draft' end,
      case when action='create_and_submit' then clock_timestamp() end) returning * into req;
  else
    select r.* into req from public.employer_requirements r
    where r.id=p_requirement_id and r.company_id=cid and r.source_type='employer_portal' for update;
    if not found then raise exception 'Company vacancy was not found'; end if;
    previous_feedback:=req.review_feedback; previous_review:=req.review_status;
    if action in ('update','update_draft') then
      if req.review_status not in ('draft','correction_required') or req.requirement_stage<>'draft' then
        raise exception 'Only draft or correction-required vacancies can be edited'; end if;
      update public.employer_requirements set department=btrim(p_department),job_role=btrim(p_job_role),job_location=btrim(p_job_location),
        company_location=btrim(p_job_location),required_headcount=p_required_headcount,qualification=nullif(btrim(p_qualification),''),
        iti_trade=nullif(btrim(p_iti_trade),''),experience_requirement=p_experience_requirement,gender_preference=p_gender_preference,
        age_min=p_age_min,age_max=p_age_max,salary_min=p_salary_min,salary_max=p_salary_max,
        salary_wage=case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
        shift_details=nullif(btrim(p_shift_details),''),working_hours=nullif(btrim(p_working_hours),''),
        overtime_details=nullif(btrim(p_overtime_details),''),canteen=p_canteen,transport=p_transport,accommodation=p_accommodation,
        interview_location=nullif(btrim(p_interview_location),''),interview_date=p_interview_date,
        expected_joining_date=p_expected_joining_date,additional_notes=nullif(btrim(p_additional_notes),'')
      where employer_requirements.id=req.id returning * into req;
    elsif action='submit' then
      if req.review_status<>'draft' then raise exception 'Only a draft vacancy can be submitted'; end if;
      update public.employer_requirements set review_status='pending_review',submitted_at=clock_timestamp(),
        reviewed_at=null,reviewed_by=null,review_feedback=null,requirement_stage='draft',requirement_visibility='private'
      where employer_requirements.id=req.id returning * into req;
    elsif action='resubmit' then
      if req.review_status<>'correction_required' then raise exception 'Only a correction-required vacancy can be resubmitted'; end if;
      update public.employer_requirements set review_status='pending_review',submitted_at=clock_timestamp(),
        reviewed_at=null,reviewed_by=null,review_feedback=null,requirement_stage='draft',requirement_visibility='private'
      where employer_requirements.id=req.id returning * into req;
    elsif action='close' then
      if req.review_status not in ('draft','pending_review','correction_required','approved')
         or req.requirement_stage in ('filled','closed','cancelled') then raise exception 'This vacancy cannot be closed'; end if;
      update public.employer_requirements set review_status='closed',requirement_stage='closed',requirement_visibility='private',
        status='closed',closed_at=clock_timestamp() where employer_requirements.id=req.id returning * into req;
    else raise exception 'Unsupported Company vacancy action'; end if;
  end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'company','company_vacancy_'||action,'employer_requirement',req.id,'company',
    jsonb_strip_nulls(jsonb_build_object('source_type',req.source_type,'old_review_status',previous_review,
      'new_review_status',req.review_status,'prior_feedback',previous_feedback)));
  return query select req.id,req.requirement_code,req.review_status,req.requirement_stage,req.requirement_visibility,req.updated_at;
end;
$$;

revoke all on function public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,date,text) from public,anon;
grant execute on function public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,date,text) to authenticated;

create or replace function public.manage_company_portal_requirement(p_action text,p_requirement_id uuid default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_interview_date timestamptz default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language sql security definer set search_path='' as $$
  select v.id,v.requirement_code,v.requirement_stage,v.requirement_visibility,v.updated_at
  from public.manage_company_portal_vacancy(p_action,p_requirement_id,p_department,p_job_role,p_job_location,
    p_required_headcount,p_qualification,null,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,
    p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,
    p_interview_location,p_interview_date,null,p_additional_notes) v;
$$;

revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text) from public,anon;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text) to authenticated;

-- Contractor submissions retain their canonical link/history, while source and review
-- state now participate in the same vacancy-review contract as Company submissions.
create or replace function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid default null,p_client_name text default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_iti_trade text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_expected_joining_date date default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); contractor_id uuid; contractor public.contractors%rowtype;
  req public.employer_requirements%rowtype; link public.requirement_contractors%rowtype;
  action text:=lower(btrim(coalesce(p_action,''))); prior_status text;
begin
  if actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  contractor_id:=(select private.current_contractor_portal_id(true));
  select c.* into contractor from public.contractors c where c.id=contractor_id;
  if contractor.id is null or contractor.main_phone is null or contractor.main_phone !~ '^[6-9][0-9]{9}$' then
    raise exception 'A valid contractor contact phone is required before submitting vacancies'; end if;
  if action in ('create','create_draft','create_and_submit','update','update_draft','resubmit') then
    if length(btrim(coalesce(p_client_name,''))) not between 1 and 200 or length(btrim(coalesce(p_job_role,''))) not between 1 and 200
       or length(btrim(coalesce(p_job_location,''))) not between 1 and 300 or coalesce(p_required_headcount,0) not between 1 and 100000 then
      raise exception 'Client, role, location, and valid openings are required'; end if;
    if p_experience_requirement not in ('Fresher','Experienced','Both') or p_gender_preference not in ('Any','Male','Female')
       or (p_age_min is not null and p_age_min not between 16 and 75) or (p_age_max is not null and p_age_max not between 16 and 75)
       or (p_age_min is not null and p_age_max is not null and p_age_min>p_age_max)
       or coalesce(p_salary_min,0)<0 or coalesce(p_salary_max,0)<0 or (p_salary_min is not null and p_salary_max is not null and p_salary_min>p_salary_max) then
      raise exception 'Vacancy criteria are invalid'; end if;
  end if;
  if action in ('create','create_draft','create_and_submit') then
    insert into public.employer_requirements(company_name,contact_person,mobile,email,company_location,job_role,required_headcount,
      qualification,iti_trade,experience_requirement,gender_preference,salary_wage,shift_details,working_hours,expected_joining_date,
      accommodation,canteen,transport,additional_notes,consent,status,created_by_user_id,department,job_location,age_min,age_max,
      salary_min,salary_max,overtime_details,interview_location,requirement_visibility,requirement_stage,source_type)
    values(btrim(p_client_name),coalesce(nullif(btrim(contractor.owner_name),''),contractor.agency_name),btrim(contractor.main_phone),contractor.main_email,
      btrim(p_job_location),btrim(p_job_role),p_required_headcount,nullif(btrim(p_qualification),''),nullif(btrim(p_iti_trade),''),p_experience_requirement,
      p_gender_preference,case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
      nullif(btrim(p_shift_details),''),nullif(btrim(p_working_hours),''),p_expected_joining_date,p_accommodation,p_canteen,p_transport,
      nullif(btrim(p_additional_notes),''),true,'new',actor,nullif(btrim(p_department),''),btrim(p_job_location),p_age_min,p_age_max,p_salary_min,p_salary_max,
      nullif(btrim(p_overtime_details),''),nullif(btrim(p_interview_location),''),'private','draft','contractor_portal') returning * into req;
    insert into public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,assignment_status,origin_type,submission_status,submitted_at)
    values(req.id,contractor_id,p_required_headcount,'assigned','contractor_submission',case when action='create_and_submit' then 'submitted' else 'draft' end,
      case when action='create_and_submit' then clock_timestamp() else null end) returning * into link;
  else
    select r.* into req from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
    if req.id is null then raise exception 'Contractor vacancy was not found'; end if;
    select rc.* into link from public.requirement_contractors rc where rc.requirement_id=req.id and rc.contractor_id=contractor_id and rc.origin_type='contractor_submission' for update;
    if link.id is null then raise exception 'Contractor vacancy was not found'; end if;
    prior_status:=link.submission_status;
    if action in ('update','update_draft') then
      if link.submission_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be edited'; end if;
      update public.employer_requirements set company_name=btrim(p_client_name),department=nullif(btrim(p_department),''),job_role=btrim(p_job_role),
        company_location=btrim(p_job_location),job_location=btrim(p_job_location),required_headcount=p_required_headcount,qualification=nullif(btrim(p_qualification),''),
        iti_trade=nullif(btrim(p_iti_trade),''),experience_requirement=p_experience_requirement,gender_preference=p_gender_preference,age_min=p_age_min,age_max=p_age_max,
        salary_min=p_salary_min,salary_max=p_salary_max,salary_wage=case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
        shift_details=nullif(btrim(p_shift_details),''),working_hours=nullif(btrim(p_working_hours),''),overtime_details=nullif(btrim(p_overtime_details),''),
        canteen=p_canteen,transport=p_transport,accommodation=p_accommodation,interview_location=nullif(btrim(p_interview_location),''),
        expected_joining_date=p_expected_joining_date,additional_notes=nullif(btrim(p_additional_notes),''),requirement_stage='draft',requirement_visibility='private'
      where employer_requirements.id=req.id returning * into req;
    elsif action in ('submit','resubmit') then
      if (action='submit' and link.submission_status<>'draft') or (action='resubmit' and link.submission_status<>'correction_required') then
        raise exception 'Vacancy is not in an allowed submission state'; end if;
      update public.requirement_contractors set submission_status='submitted',submitted_at=clock_timestamp(),review_feedback=null,reviewed_at=null,reviewed_by=null
      where requirement_contractors.id=link.id returning * into link;
      update public.employer_requirements set requirement_stage='draft',requirement_visibility='private' where employer_requirements.id=req.id returning * into req;
    elsif action='cancel' then
      if link.submission_status not in ('draft','submitted','under_review','correction_required') then raise exception 'This vacancy cannot be cancelled'; end if;
      update public.requirement_contractors set submission_status='cancelled',closed_at=clock_timestamp() where requirement_contractors.id=link.id returning * into link;
      update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where employer_requirements.id=req.id returning * into req;
    else raise exception 'Unsupported Contractor vacancy action'; end if;
  end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'contractor','contractor_vacancy_'||action,'employer_requirement',req.id,'contractor',
    jsonb_build_object('old_submission_status',prior_status,'new_submission_status',link.submission_status,'source_type',req.source_type));
  return query select req.id,req.requirement_code,link.submission_status,req.requirement_stage,req.updated_at;
end;
$$;

revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) from public,anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) to authenticated;

create function public.admin_list_vacancy_reviews(p_review_status text default 'pending_review',p_source_type text default null,p_limit integer default 50,p_offset integer default 0)
returns table(requirement_id uuid,requirement_code text,source_type text,normalized_review_status text,contractor_submission_status text,
  submitted_at timestamptz,company_name text,contractor_name text,job_role text,department text,job_location text,required_headcount integer,
  filled_positions integer,remaining_positions integer,review_feedback text,requirement_stage text,requirement_visibility text)
language sql stable security definer set search_path='' as $$
  with authz as (select private.can_review_vacancies() allowed), rows as (
    select r.id,r.requirement_code,r.source_type,private.normalized_vacancy_review_status(r.id) normalized_review_status,
      rc.submission_status,coalesce(rc.submitted_at,r.submitted_at) submitted_at,r.company_name,coalesce(c.agency_name,c.owner_name) contractor_name,
      r.job_role,r.department,coalesce(r.job_location,r.company_location) job_location,r.required_headcount,r.filled_positions,
      r.required_headcount-r.filled_positions remaining_positions,coalesce(rc.review_feedback,r.review_feedback) review_feedback,
      r.requirement_stage,r.requirement_visibility
    from public.employer_requirements r
    left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
    left join public.contractors c on c.id=rc.contractor_id)
  select rows.id,rows.requirement_code,rows.source_type,rows.normalized_review_status,rows.submission_status,rows.submitted_at,rows.company_name,
    rows.contractor_name,rows.job_role,rows.department,rows.job_location,rows.required_headcount,rows.filled_positions,rows.remaining_positions,
    rows.review_feedback,rows.requirement_stage,rows.requirement_visibility
  from rows cross join authz where authz.allowed and (p_review_status is null or rows.normalized_review_status=lower(btrim(p_review_status)))
    and (p_source_type is null or rows.source_type=lower(btrim(p_source_type))) order by rows.submitted_at nulls last,rows.requirement_code
  limit greatest(1,least(coalesce(p_limit,50),200)) offset greatest(0,coalesce(p_offset,0));
$$;

create function public.admin_get_vacancy_review_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not (select private.can_review_vacancies()) then raise exception 'Approved administrator access is required'; end if;
  select jsonb_build_object(
    'source',jsonb_strip_nulls(jsonb_build_object('source_type',r.source_type,'submitted_by',u.display_name,'company',r.company_name,
      'contractor',coalesce(c.agency_name,c.owner_name))),
    'vacancy',jsonb_strip_nulls(jsonb_build_object('requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,
      'department',r.department,'location',coalesce(r.job_location,r.company_location),'openings',r.required_headcount,
      'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,
      'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,
      'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,
      'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes)),
    'review',jsonb_strip_nulls(jsonb_build_object('normalized_status',private.normalized_vacancy_review_status(r.id),'contractor_submission_status',rc.submission_status,
      'feedback',coalesce(rc.review_feedback,r.review_feedback),'submitted_at',coalesce(rc.submitted_at,r.submitted_at),'reviewed_at',coalesce(rc.reviewed_at,r.reviewed_at),
      'reviewer',reviewer.display_name)),
    'lifecycle',jsonb_build_object('requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'published_at',r.published_at,
      'closed_at',r.closed_at,'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,'remaining_positions',r.required_headcount-r.filled_positions),
    'progress',jsonb_build_object('applications',(select count(*) from public.candidate_applications a where a.requirement_id=r.id),
      'interviews',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id),
      'selected',(select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status='selected'),
      'joined',(select count(*) from public.candidate_joinings j
                  join public.candidate_applications a on a.id=j.application_id
                  where a.requirement_id=r.id and j.joining_status='joined')))
  into result
  from public.employer_requirements r
  left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
  left join public.contractors c on c.id=rc.contractor_id
  left join public.platform_users u on u.user_id=r.created_by_user_id
  left join public.platform_users reviewer on reviewer.user_id=coalesce(rc.reviewed_by,r.reviewed_by)
  where r.id=p_requirement_id;
  if result is null then raise exception 'Vacancy was not found'; end if;
  return result;
end;
$$;

create function private.lock_vacancy_review(p_requirement_id uuid)
returns public.employer_requirements language plpgsql security definer set search_path='' as $$
declare r public.employer_requirements%rowtype;
begin
  select * into r from public.employer_requirements where id=p_requirement_id for update;
  if r.id is null then raise exception 'Vacancy was not found'; end if;
  return r;
end;
$$;

create function public.admin_approve_and_publish_vacancy(p_requirement_id uuid,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); r public.employer_requirements%rowtype; rc public.requirement_contractors%rowtype; now_at timestamptz:=clock_timestamp();
begin
  if actor is null or not (select private.can_review_vacancies()) then raise exception 'Approved administrator access is required'; end if;
  r:=private.lock_vacancy_review(p_requirement_id);
  if p_expected_updated_at is not null and r.updated_at is distinct from p_expected_updated_at then raise exception 'Vacancy changed; refresh before reviewing'; end if;
  if not (r.required_headcount>r.filled_positions) then raise exception 'A full vacancy cannot be published'; end if;
  if r.source_type='contractor_portal' then
    select * into rc from public.requirement_contractors where requirement_id=r.id and origin_type='contractor_submission' for update;
    if rc.id is null or rc.submission_status not in ('submitted','under_review') then raise exception 'Only a pending Contractor vacancy can be approved'; end if;
    update public.requirement_contractors set submission_status='approved',assignment_status='active',reviewed_at=now_at,reviewed_by=actor where id=rc.id;
  elsif r.source_type='employer_portal' then
    if r.review_status<>'pending_review' then raise exception 'Only a pending Company vacancy can be approved'; end if;
    update public.employer_requirements set review_status='approved',reviewed_at=now_at,reviewed_by=actor,review_feedback=null where id=r.id;
  else raise exception 'Only portal-submitted vacancies can be approved'; end if;
  update public.employer_requirements set requirement_stage='open',requirement_visibility='public',status='in_progress',published_at=coalesce(published_at,now_at),closed_at=null where id=r.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','vacancy_review_approved_published','employer_requirement',r.id,'admin',jsonb_build_object('source_type',r.source_type,'old_stage',r.requirement_stage,'old_visibility',r.requirement_visibility));
  return public.admin_get_vacancy_review_detail(r.id);
end;
$$;

create function public.admin_request_vacancy_correction(p_requirement_id uuid,p_reason text,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); r public.employer_requirements%rowtype; rc public.requirement_contractors%rowtype; reason text:=nullif(btrim(p_reason),''); now_at timestamptz:=clock_timestamp();
begin
  if actor is null or not (select private.can_review_vacancies()) then raise exception 'Approved administrator access is required'; end if;
  if reason is null or length(reason)>2000 then raise exception 'A correction reason of at most 2000 characters is required'; end if;
  r:=private.lock_vacancy_review(p_requirement_id);
  if p_expected_updated_at is not null and r.updated_at is distinct from p_expected_updated_at then raise exception 'Vacancy changed; refresh before reviewing'; end if;
  if r.source_type='contractor_portal' then
    select * into rc from public.requirement_contractors where requirement_id=r.id and origin_type='contractor_submission' for update;
    if rc.id is null or rc.submission_status not in ('submitted','under_review') then raise exception 'Only a pending Contractor vacancy can require correction'; end if;
    update public.requirement_contractors set submission_status='correction_required',review_feedback=reason,reviewed_at=now_at,reviewed_by=actor where id=rc.id;
  elsif r.source_type='employer_portal' then
    if r.review_status<>'pending_review' then raise exception 'Only a pending Company vacancy can require correction'; end if;
    update public.employer_requirements set review_status='correction_required',review_feedback=reason,reviewed_at=now_at,reviewed_by=actor where id=r.id;
  else raise exception 'Only portal-submitted vacancies can require correction'; end if;
  update public.employer_requirements set requirement_stage='draft',requirement_visibility='private',published_at=null,closed_at=null where id=r.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','vacancy_review_correction_requested','employer_requirement',r.id,'admin',jsonb_build_object('source_type',r.source_type,'reason',reason));
  return public.admin_get_vacancy_review_detail(r.id);
end;
$$;

create function public.admin_reject_vacancy(p_requirement_id uuid,p_reason text,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); r public.employer_requirements%rowtype; rc public.requirement_contractors%rowtype; reason text:=nullif(btrim(p_reason),''); now_at timestamptz:=clock_timestamp();
begin
  if actor is null or not (select private.can_review_vacancies()) then raise exception 'Approved administrator access is required'; end if;
  if reason is null or length(reason)>2000 then raise exception 'A rejection reason of at most 2000 characters is required'; end if;
  r:=private.lock_vacancy_review(p_requirement_id);
  if p_expected_updated_at is not null and r.updated_at is distinct from p_expected_updated_at then raise exception 'Vacancy changed; refresh before reviewing'; end if;
  if r.source_type='contractor_portal' then
    select * into rc from public.requirement_contractors where requirement_id=r.id and origin_type='contractor_submission' for update;
    if rc.id is null or rc.submission_status not in ('submitted','under_review') then raise exception 'Only a pending Contractor vacancy can be rejected'; end if;
    update public.requirement_contractors set submission_status='rejected',assignment_status='cancelled',review_feedback=reason,reviewed_at=now_at,reviewed_by=actor,closed_at=now_at where id=rc.id;
  elsif r.source_type='employer_portal' then
    if r.review_status<>'pending_review' then raise exception 'Only a pending Company vacancy can be rejected'; end if;
    update public.employer_requirements set review_status='rejected',review_feedback=reason,reviewed_at=now_at,reviewed_by=actor where id=r.id;
  else raise exception 'Only portal-submitted vacancies can be rejected'; end if;
  update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=now_at where id=r.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','vacancy_review_rejected','employer_requirement',r.id,'admin',jsonb_build_object('source_type',r.source_type,'reason',reason));
  return public.admin_get_vacancy_review_detail(r.id);
end;
$$;

-- Application eligibility is enforced in each canonical mutation RPC and at the
-- API-role table boundary.  Owner-only checkpoint fixtures have no API role GUC;
-- browser/service API sessions do, so a future canonical writer cannot omit it.
create function private.enforce_candidate_application_vacancy_gate()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if current_setting('request.jwt.claim.role',true) is not null
     and not (select private.vacancy_is_application_eligible(new.requirement_id)) then
    raise exception using errcode='42501',message='Applications are allowed only for approved public vacancies with capacity';
  end if;
  return new;
end;
$$;

create trigger candidate_applications_require_approved_public_vacancy
before insert on public.candidate_applications
for each row execute function private.enforce_candidate_application_vacancy_gate();

create or replace function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,department text,job_location text,open_positions integer,
  qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,
  shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,
  interview_location text,expected_joining_date date,safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path='' as $$
declare candidate_id uuid:=(select private.current_candidate_portal_id()); term text:=nullif(btrim(p_search),'');
begin
  if candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,
    r.qualification,r.iti_trade,r.experience_requirement,r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,r.shift_details,r.working_hours,
    r.overtime_details,r.canteen,r.transport,r.accommodation,r.interview_location,r.expected_joining_date,r.additional_notes,
    exists(select 1 from public.candidate_applications a where a.candidate_id=candidate_id and a.requirement_id=r.id)
  from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null
    and (term is null or r.requirement_code ilike '%'||term||'%' or r.job_role ilike '%'||term||'%' or coalesce(r.job_location,'') ilike '%'||term||'%')
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create or replace function public.apply_candidate_job(p_requirement_code text)
returns uuid language plpgsql security definer set search_path='' as $$
declare candidate_id uuid:=(select private.current_candidate_portal_id()); req public.employer_requirements%rowtype; application_id uuid;
begin
  if candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  if not exists(select 1 from public.candidates c where c.id=candidate_id and c.mobile~'^[6-9][0-9]{9}$' and c.aadhaar_last4 is not null and c.profile_completion_status='complete')
     or not exists(select 1 from public.candidate_documents d where d.candidate_id=candidate_id and d.document_type='resume' and d.active) then
    raise exception 'Complete the required Candidate profile and Resume before applying'; end if;
  select r.* into req from public.employer_requirements r where r.requirement_code=upper(btrim(p_requirement_code)) and private.vacancy_is_application_eligible(r.id) for share;
  if req.id is null then raise exception 'Opportunity is not available'; end if;
  insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,created_by,source_reference)
  values(candidate_id,req.id,'direct','applied',(select auth.uid()),'candidate_portal') returning id into application_id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values((select auth.uid()),'candidate','candidate.application_created','candidate_application',application_id,'candidate',jsonb_build_object('requirement_id',req.id));
  return application_id;
exception when unique_violation then raise exception 'You already have an application for this opportunity';
end;
$$;

create or replace function public.create_recruitment_application(p_candidate_id uuid,p_requirement_id uuid,p_source_reference text default null,p_correlation_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); new_id uuid;
begin
  if actor is null or not (select private.can_manage_applications()) then raise exception 'Application management access is required'; end if;
  if not exists(select 1 from public.candidates where id=p_candidate_id and status<>'inactive') then raise exception 'Active candidate was not found'; end if;
  if not (select private.vacancy_is_application_eligible(p_requirement_id)) then raise exception 'Approved public vacancy with capacity was not found'; end if;
  insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,created_by,source_reference,correlation_id)
  values(p_candidate_id,p_requirement_id,'admin','applied',actor,nullif(btrim(p_source_reference),''),p_correlation_id) returning id into new_id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff','recruitment.application_created','candidate_application',new_id,'admin',p_correlation_id,jsonb_build_object('candidate_id',p_candidate_id,'requirement_id',p_requirement_id));
  return new_id;
exception when unique_violation then raise exception 'Candidate already has an application for this requirement';
end;
$$;

-- Replace the Job Lead detail projection at its canonical source rather than
-- maintaining a second vacancy-detail representation.  job_role is selected
-- directly from employer_requirements, removing the historical "—" fallback.
create or replace function public.admin_get_job_lead_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not (select private.can_manage_recruitment_operations()) then raise exception 'Recruitment access is required'; end if;
  select jsonb_build_object(
    'requirement',jsonb_strip_nulls(jsonb_build_object('requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,
      'department',r.department,'location',coalesce(r.job_location,r.company_location),'company',r.company_name,'contractor',coalesce(c.agency_name,c.owner_name),
      'submitted_by',submitter.display_name,'source_type',r.source_type,
      'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,
      'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,
      'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,
      'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,
      'additional_notes',r.additional_notes,'normalized_review_status',private.normalized_vacancy_review_status(r.id),
      'review_feedback',coalesce(rc.review_feedback,r.review_feedback),'submitted_at',coalesce(rc.submitted_at,r.submitted_at),
      'reviewed_at',coalesce(rc.reviewed_at,r.reviewed_at),'reviewed_by',reviewer.display_name,'contractor_submission_status',rc.submission_status,
      'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'published_at',r.published_at,'closed_at',r.closed_at,
      'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,'remaining_positions',r.required_headcount-r.filled_positions,
      'application_count',(select count(*) from public.candidate_applications a where a.requirement_id=r.id),
      'interview_count',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id),
      'selected_count',(select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status='selected'),
      'joined_count',(select count(*) from public.candidate_joinings j
                       join public.candidate_applications a on a.id=j.application_id
                       where a.requirement_id=r.id and j.joining_status='joined'))),
    'history',coalesce((select jsonb_agg(jsonb_build_object('action',h.action,'actor_type',h.actor_type,'created_at',h.created_at,'summary','Operational activity') order by h.created_at desc,h.id desc)
      from (select l.id,l.action,l.actor_type,l.created_at from public.audit_logs l where l.entity_id=r.id and l.entity_type='employer_requirement' order by l.created_at desc,l.id desc limit 50) h),'[]'::jsonb))
  into result from public.employer_requirements r
  left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
  left join public.contractors c on c.id=rc.contractor_id
  left join public.platform_users submitter on submitter.user_id=r.created_by_user_id
  left join public.platform_users reviewer on reviewer.user_id=coalesce(rc.reviewed_by,r.reviewed_by)
  where r.id=p_requirement_id;
  if result is null then raise exception 'Job Lead was not found'; end if;
  return result;
end;
$$;

create or replace function public.get_public_job_requirements(p_limit integer default 20,p_offset integer default 0)
returns table(requirement_code text,job_role text,department text,job_location text,open_positions integer,salary_min numeric,salary_max numeric,
  salary_text text,qualification text,iti_trade text,experience_requirement text,shift_details text,working_hours text,overtime_details text,
  canteen text,transport text,accommodation text,interview_date timestamptz,interview_location text,expected_joining_date date,published_at timestamptz)
language sql stable security definer set search_path='' as $$
  select r.requirement_code,r.job_role,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,
    r.salary_min,r.salary_max,r.salary_wage,r.qualification,r.iti_trade,r.experience_requirement,r.shift_details,r.working_hours,
    r.overtime_details,r.canteen,r.transport,r.accommodation,r.interview_date,r.interview_location,r.expected_joining_date,
    coalesce(r.published_at,r.created_at)
  from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,20),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
$$;

create or replace function public.get_company_portal_requirement(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid:=(select private.current_company_portal_id(true)); result jsonb;
begin
  if v_company_id is null then raise exception 'Active Company access is required'; end if;
  select jsonb_build_object('requirement_code',r.requirement_code,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,
    'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,'qualification',r.qualification,'iti_trade',r.iti_trade,
    'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,
    'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,
    'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'interview_location',r.interview_location,'interview_date',r.interview_date,
    'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,'review_status',r.review_status,'review_feedback',r.review_feedback,
    'submitted_at',r.submitted_at,'reviewed_at',r.reviewed_at,'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,
    'created_at',r.created_at,'updated_at',r.updated_at,'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),
      'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct a.id) filter(where a.application_status='interview'),
      'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct a.id) filter(where a.application_status='joined')))
  into result from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id
  where r.id=p_requirement_id and r.company_id=v_company_id group by r.id;
  if result is null then raise exception 'Company requirement was not found'; end if;
  return result;
end;
$$;

create function public.list_company_portal_vacancy_reviews(p_search text default null,p_review_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_id uuid,requirement_code text,job_role text,department text,job_location text,required_headcount integer,filled_positions integer,
  remaining_positions integer,review_status text,review_feedback text,requirement_stage text,requirement_visibility text,application_count bigint,
  interview_count bigint,selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid:=(select private.current_company_portal_id(true)); term text:=nullif(btrim(p_search),''); status_filter text:=nullif(lower(btrim(p_review_status)), '');
begin
  if v_company_id is null then raise exception 'Active Company access is required'; end if;
  if status_filter is not null and status_filter not in ('draft','pending_review','correction_required','approved','rejected','closed') then
    raise exception 'Unsupported review status'; end if;
  return query select r.id,r.requirement_code,r.job_role,r.department,r.job_location,r.required_headcount,r.filled_positions,
    r.required_headcount-r.filled_positions,r.review_status,r.review_feedback,r.requirement_stage,r.requirement_visibility,
    count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where r.company_id=v_company_id and r.source_type='employer_portal' and (status_filter is null or r.review_status=status_filter)
    and (term is null or r.requirement_code ilike '%'||term||'%' or r.job_role ilike '%'||term||'%' or r.job_location ilike '%'||term||'%')
  group by r.id order by r.updated_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create or replace function public.get_contractor_portal_vacancy(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_contractor_id uuid:=(select private.current_contractor_portal_id(true)); result jsonb;
begin
  if v_contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  select jsonb_build_object('requirement_code',r.requirement_code,'client_name',r.company_name,'department',r.department,'job_role',r.job_role,
    'job_location',r.job_location,'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,
    'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,
    'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,
    'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'interview_location',r.interview_location,'expected_joining_date',r.expected_joining_date,
    'additional_notes',r.additional_notes,'submission_status',rc.submission_status,'normalized_review_status',private.normalized_vacancy_review_status(r.id),
    'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'review_feedback',rc.review_feedback,'submitted_at',rc.submitted_at,
    'reviewed_at',rc.reviewed_at,'created_at',r.created_at,'updated_at',r.updated_at,'pipeline',jsonb_build_object('applications',count(distinct a.id),
      'screening',count(distinct a.id) filter(where a.application_status='screening'),'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),
      'interviews',count(distinct i.id),'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct a.id) filter(where a.application_status='joined')))
  into result from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where r.id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' group by r.id,rc.id;
  if result is null then raise exception 'Contractor vacancy was not found'; end if;
  return result;
end;
$$;

-- Legacy Contractor review entry point remains callable for controlled internal
-- compatibility, but delegates publish/correction/rejection to the unified
-- review boundary.  Opening a record no longer creates a required UI step.
create or replace function public.review_contractor_vacancy(p_requirement_id uuid,p_action text,p_feedback text default null)
returns table(requirement_id uuid,requirement_code text,submission_status text,requirement_stage text,requirement_visibility text)
language plpgsql security definer set search_path='' as $$
declare r public.employer_requirements%rowtype; rc public.requirement_contractors%rowtype; action text:=lower(btrim(coalesce(p_action,'')));
begin
  if not (select private.can_review_vacancies()) then raise exception 'Contractor vacancy review access is required'; end if;
  if length(coalesce(p_feedback,''))>2000 then raise exception 'Review feedback is too long'; end if;
  r:=private.lock_vacancy_review(p_requirement_id);
  if r.source_type<>'contractor_portal' then raise exception 'Contractor vacancy was not found'; end if;
  select * into rc from public.requirement_contractors where requirement_id=r.id and origin_type='contractor_submission' for update;
  if rc.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if action='start_review' then
    if rc.submission_status<>'submitted' then raise exception 'Only a submitted vacancy can be opened for review'; end if;
    update public.requirement_contractors set submission_status='under_review',reviewed_at=clock_timestamp(),reviewed_by=(select auth.uid()) where id=rc.id returning * into rc;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','contractor_vacancy_review_opened','employer_requirement',r.id,'admin','{}');
  elsif action='approve' then
    perform public.admin_approve_and_publish_vacancy(r.id,null);
    select * into rc from public.requirement_contractors where id=rc.id;
    select * into r from public.employer_requirements where id=r.id;
  elsif action='request_correction' then
    perform public.admin_request_vacancy_correction(r.id,p_feedback,null);
    select * into rc from public.requirement_contractors where id=rc.id;
    select * into r from public.employer_requirements where id=r.id;
  elsif action='reject' then
    perform public.admin_reject_vacancy(r.id,p_feedback,null);
    select * into rc from public.requirement_contractors where id=rc.id;
    select * into r from public.employer_requirements where id=r.id;
  elsif action='close' then
    if rc.submission_status<>'approved' then raise exception 'Only an approved vacancy can be closed'; end if;
    update public.requirement_contractors set submission_status='closed',assignment_status='completed',reviewed_at=clock_timestamp(),reviewed_by=(select auth.uid()),closed_at=clock_timestamp() where id=rc.id returning * into rc;
    update public.employer_requirements set requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=r.id returning * into r;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','contractor_vacancy_review_closed','employer_requirement',r.id,'admin','{}');
  else raise exception 'Invalid Contractor vacancy review action'; end if;
  return query select r.id,r.requirement_code,rc.submission_status,r.requirement_stage,r.requirement_visibility;
end;
$$;

-- The older lifecycle RPC remains usable for non-public operational transitions,
-- but it cannot bypass the new Admin review contract into open/public.
create or replace function public.set_company_requirement_stage(p_requirement_id uuid,p_requirement_stage text,p_requirement_visibility text)
returns public.employer_requirements language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); current_requirement public.employer_requirements%rowtype; updated_requirement public.employer_requirements%rowtype; operation_id uuid:=gen_random_uuid();
begin
  if actor is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_requirement_stage not in ('draft','open','on_hold','filled','closed','cancelled') or p_requirement_visibility not in ('private','assigned','public') then raise exception 'Invalid lifecycle value'; end if;
  select * into current_requirement from public.employer_requirements where id=p_requirement_id and company_id is not null for update;
  if current_requirement.id is null then raise exception 'Company requirement was not found'; end if;
  if p_requirement_stage='open' and p_requirement_visibility='public' and current_requirement.review_status is distinct from 'approved' then
    raise exception 'Only an approved vacancy can be published'; end if;
  if p_requirement_stage='open' and current_requirement.filled_positions>=current_requirement.required_headcount then raise exception 'Requirement has no remaining capacity and cannot be opened'; end if;
  if p_requirement_stage='filled' and current_requirement.filled_positions<>current_requirement.required_headcount then raise exception 'Requirement can be Filled only at full headcount'; end if;
  if p_requirement_stage='filled' and p_requirement_visibility<>'private' then raise exception 'Filled requirement must be private'; end if;
  if p_requirement_stage in ('closed','cancelled') and p_requirement_visibility='public' then raise exception 'Closed or Cancelled requirement cannot be public'; end if;
  update public.employer_requirements set requirement_stage=p_requirement_stage,requirement_visibility=p_requirement_visibility,
    published_at=case when p_requirement_stage='open' then coalesce(published_at,clock_timestamp()) else published_at end,
    closed_at=case when p_requirement_stage in ('filled','closed','cancelled') then coalesce(closed_at,clock_timestamp()) else null end,
    status=case when p_requirement_stage='filled' then 'fulfilled' when p_requirement_stage in ('closed','cancelled') then 'closed' when p_requirement_stage='open' then 'in_progress' else status end
  where id=current_requirement.id returning * into updated_requirement;
  if current_requirement.requirement_stage is distinct from updated_requirement.requirement_stage or current_requirement.requirement_visibility is distinct from updated_requirement.requirement_visibility then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.requirement_lifecycle_changed','employer_requirement',updated_requirement.id,'admin',operation_id,
      jsonb_build_object('old',jsonb_build_object('requirement_stage',current_requirement.requirement_stage,'requirement_visibility',current_requirement.requirement_visibility),
        'new',jsonb_build_object('requirement_stage',updated_requirement.requirement_stage,'requirement_visibility',updated_requirement.requirement_visibility)));
  end if;
  return updated_requirement;
end;
$$;

-- Campaign audience status is a matching surface too.  API-role sessions must
-- retain the same approved/open/public/capacity predicate through queueing.
create function private.enforce_whatsapp_campaign_vacancy_gate()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if current_setting('request.jwt.claim.role',true) is not null and new.campaign_status in ('audience_ready','approved','queued')
     and not (select private.vacancy_is_application_eligible(new.requirement_id)) then
    raise exception using errcode='42501',message='Campaigns require an approved public vacancy with capacity';
  end if;
  return new;
end;
$$;

create trigger whatsapp_campaigns_require_approved_public_vacancy
before insert or update of requirement_id,campaign_status on public.whatsapp_campaigns
for each row execute function private.enforce_whatsapp_campaign_vacancy_gate();

-- Migration 032 already removed broad authenticated UPDATE; retain that posture
-- and remove the two inherited legacy column grants which are not used by any
-- canonical portal or Admin mutation RPC.
revoke update(status,internal_notes) on public.employer_requirements from authenticated;
-- Direct legacy Company requirement writers would retain the pre-039 default
-- source_type.  Portal compatibility routes through manage_company_portal_requirement,
-- so browser execution of these lower-level writers is intentionally retired.
revoke execute on function public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text) from public,anon,authenticated;
revoke execute on function public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text) from public,anon,authenticated;
revoke execute on function public.close_company_requirement(uuid) from public,anon,authenticated;

revoke all on function private.normalized_vacancy_review_status(uuid),private.vacancy_is_application_eligible(uuid),
  private.can_review_vacancies(),private.lock_vacancy_review(uuid),private.enforce_candidate_application_vacancy_gate(),
  private.enforce_whatsapp_campaign_vacancy_gate() from public,anon,authenticated;
revoke all on function public.admin_list_vacancy_reviews(text,text,integer,integer),public.admin_get_vacancy_review_detail(uuid),
  public.admin_approve_and_publish_vacancy(uuid,timestamp with time zone),public.admin_request_vacancy_correction(uuid,text,timestamp with time zone),
  public.admin_reject_vacancy(uuid,text,timestamp with time zone),public.review_contractor_vacancy(uuid,text,text),
  public.list_company_portal_vacancy_reviews(text,text,integer,integer) from public,anon;
grant execute on function public.admin_list_vacancy_reviews(text,text,integer,integer),public.admin_get_vacancy_review_detail(uuid),
  public.admin_approve_and_publish_vacancy(uuid,timestamp with time zone),public.admin_request_vacancy_correction(uuid,text,timestamp with time zone),
  public.admin_reject_vacancy(uuid,text,timestamp with time zone),public.review_contractor_vacancy(uuid,text,text),
  public.list_company_portal_vacancy_reviews(text,text,integer,integer) to authenticated;

do $$
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='employer_requirements' and column_name='review_status')
     or not exists(select 1 from pg_constraint where conname='employer_requirements_review_status_check')
     or not exists(select 1 from pg_trigger where tgname='candidate_applications_require_approved_public_vacancy' and not tgisinternal)
     or not exists(select 1 from pg_trigger where tgname='whatsapp_campaigns_require_approved_public_vacancy' and not tgisinternal) then
    raise exception 'Migration 039 post-install catalog assertion failed';
  end if;
  if has_table_privilege('authenticated','public.employer_requirements','update')
     or has_function_privilege('anon','public.admin_approve_and_publish_vacancy(uuid,timestamp with time zone)','execute')
     or has_function_privilege('authenticated','private.vacancy_is_application_eligible(uuid)','execute')
     or has_function_privilege('authenticated','public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)','execute')
     or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       where p.oid='public.admin_approve_and_publish_vacancy(uuid,timestamp with time zone)'::regprocedure
         and acl.grantee=0 and acl.privilege_type='EXECUTE') then
    raise exception 'Migration 039 privilege assertion failed';
  end if;
end;
$$;

commit;
