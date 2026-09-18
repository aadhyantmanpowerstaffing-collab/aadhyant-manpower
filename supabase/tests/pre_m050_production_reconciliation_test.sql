-- Disposable contract checkpoint for the manual pre-M050 reconciler.
-- Execute only against a disposable baseline matching the documented drift;
-- it is never a production fixture.  The reconciler commits its one manual
-- transaction; this checkpoint rolls back only its own assertions/fixtures.
set app.pre_m050_reconciliation_approved = 'yes';
\ir ../production/pre_m050_production_reconciliation.sql
begin;

do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_joinings') is null then
    raise exception 'CHECKPOINT_PRE_M050_BASELINE_REQUIRED';
  end if;
  if to_regclass('private.contractor_vacancy_submission_requests') is not null
     or to_regclass('private.vacancy_candidate_benefits') is not null then
    raise exception 'CHECKPOINT_PRE_M050_M049_OR_M050_MUST_BE_ABSENT';
  end if;
end;
$$;

-- The runnable harness supplies the artifact in the same disposable session
-- with app.pre_m050_reconciliation_approved=yes.  The following postflight
-- assertions intentionally contain no business records or identifiers.
do $$
begin
  if (select count(*) from public.employer_requirements where status='in_progress' and requirement_stage='open' and requirement_visibility='public' and review_status='approved' and published_at is not null) <> 1
     or (select count(*) from public.employer_requirements where status='new' and requirement_stage='draft' and requirement_visibility='private' and review_status='draft' and published_at is null) <> 1 then
    raise exception 'CHECKPOINT_PRE_M050_LIFECYCLE_MAPPING';
  end if;
  if to_regprocedure('private.validate_candidate_joining_dates()') is null
     or not exists(select 1 from pg_trigger where tgrelid='public.candidate_joinings'::regclass and tgname='candidate_joinings_validate_dates') then
    raise exception 'CHECKPOINT_PRE_M050_M037';
  end if;
  if has_table_privilege('authenticated','public.candidate_applications','insert,update')
     or has_table_privilege('authenticated','public.candidate_joinings','insert,update') then
    raise exception 'CHECKPOINT_PRE_M050_M038_DIRECT_WRITE';
  end if;
  if to_regprocedure('private.vacancy_is_application_eligible(uuid)') is null
     or to_regprocedure('private.current_candidate_portal_id()') is null
     or to_regprocedure('public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)') is null
     or to_regprocedure('private.vacancy_compensation_projection(public.employer_requirements)') is null
     or to_regprocedure('public.list_company_portal_requirements(text,text,integer,integer)') is null then
    raise exception 'CHECKPOINT_PRE_M050_REVIEW_COMPANY_OR_PROJECTION';
  end if;
  if has_function_privilege('anon','private.current_candidate_portal_id()','execute')
     or has_function_privilege('authenticated','private.current_candidate_portal_id()','execute')
     or pg_get_function_result('public.list_contractor_portal_vacancies(text,text,integer,integer)'::regprocedure) !~ 'payable_days integer'
     or pg_get_function_result('public.list_contractor_portal_vacancies(text,text,integer,integer)'::regprocedure) !~ 'accommodation_charge_basis text' then
    raise exception 'CHECKPOINT_PRE_M050_CANDIDATE_IDENTITY_OR_CONTRACTOR_LIST_UPGRADE';
  end if;
  if to_regprocedure('public.admin_approve_and_publish_vacancy(uuid,timestamp with time zone)') is null
     or to_regprocedure('public.admin_list_vacancy_reviews(text,text,integer,integer)') is null
     or to_regprocedure('public.admin_get_vacancy_review_detail(uuid)') is null
     or to_regprocedure('public.list_company_portal_vacancy_reviews(text,text,integer,integer)') is null
     or to_regprocedure('public.review_contractor_vacancy(uuid,text,text)') is null
     or to_regprocedure('public.delete_company_portal_draft_vacancy(uuid)') is null
     or to_regprocedure('public.close_contractor_portal_open_vacancy(uuid)') is null
     or to_regprocedure('public.get_company_portal_requirement(uuid)') is null
     or to_regprocedure('public.get_contractor_portal_vacancy(uuid)') is null
     or to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is null then
    raise exception 'CHECKPOINT_PRE_M050_M039_TO_M048';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='private' and p.proname in ('vacancy_compensation_projection','vacancy_accommodation_projection')
              and (not p.prosecdef or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%')) then
    raise exception 'CHECKPOINT_PRE_M050_PRIVATE_SECURITY';
  end if;
  if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)') is null
     or to_regclass('private.contractor_vacancy_submission_requests') is not null
     or to_regclass('private.vacancy_candidate_benefits') is not null then
    raise exception 'CHECKPOINT_PRE_M050_M049_PRECONDITION';
  end if;
end;
$$;

-- The M037 trigger must reject an actual date before a Joining reaches its
-- terminal Joined/Left state. The complete fixture transaction is rolled back.
do $$
declare v_candidate uuid:=gen_random_uuid(); v_application uuid:=gen_random_uuid();
begin
  insert into public.candidates(id) values(v_candidate);
  insert into public.candidate_applications(id,requirement_id,candidate_id,application_status)
    select v_application,id,v_candidate,'applied' from public.employer_requirements where requirement_code='HIST-OPEN';
  begin
    insert into public.candidate_joinings(application_id,joining_status,actual_joining_date)
    values(v_application,'pending',current_date);
    raise exception 'CHECKPOINT_PRE_M050_M037_ACCEPTED_INVALID_DATE';
  exception when raise_exception then
    if sqlerrm <> 'Actual joining date requires Joined or Left status' then raise; end if;
  end;
end;
$$;

-- M045 must record the lifecycle action atomically. This isolated synthetic
-- owner fixture is rolled back with the checkpoint and never models live data.
insert into auth.users(id) values ('10000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name) values ('10000000-0000-0000-0000-000000000001','company','Synthetic owner');
insert into public.companies(id,legal_name) values ('20000000-0000-0000-0000-000000000001','Synthetic company');
insert into public.company_users(company_id,user_id,status,role) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','active','owner');
insert into public.employer_requirements(requirement_code,company_id,company_name,job_role,job_location,required_headcount,source_type,status,requirement_stage,requirement_visibility,review_status,published_at)
values ('SYNTH-AUDIT','20000000-0000-0000-0000-000000000001','Synthetic company','Synthetic role','Synthetic location',1,'employer_portal','in_progress','open','public','approved',clock_timestamp());
select set_config('test.auth_uid','10000000-0000-0000-0000-000000000001',true);
select public.close_company_portal_open_vacancy(id) from public.employer_requirements where requirement_code='SYNTH-AUDIT';
do $$
begin
  if not exists(select 1 from public.audit_logs where action='company_vacancy_closed' and entity_type='employer_requirement' and source='company') then
    raise exception 'CHECKPOINT_PRE_M050_M045_AUDIT';
  end if;
end;
$$;

-- Exercise the final M039 reviewer detail/list contract through a synthetic
-- pending Company vacancy. It proves the approve transition and its audit are
-- atomic without relying on historical rows.
insert into public.employer_requirements(requirement_code,company_id,company_name,job_role,job_location,required_headcount,source_type,status,requirement_stage,requirement_visibility,review_status,submitted_at)
values ('SYNTH-REVIEW','20000000-0000-0000-0000-000000000001','Synthetic company','Synthetic reviewer role','Synthetic location',1,'employer_portal','new','draft','private','pending_review',clock_timestamp());
do $$
declare v_id uuid; v_detail jsonb;
begin
  select id into v_id from public.employer_requirements where requirement_code='SYNTH-REVIEW';
  v_detail:=public.admin_approve_and_publish_vacancy(v_id,null);
  if v_detail #>> '{lifecycle,requirement_stage}' <> 'open'
     or v_detail #>> '{lifecycle,requirement_visibility}' <> 'public'
     or (select count(*) from public.admin_list_vacancy_reviews('approved','employer_portal',25,0) where requirement_id=v_id) <> 1
     or (select count(*) from public.list_company_portal_vacancy_reviews(null,'approved',25,0) where requirement_id=v_id) <> 1
     or public.get_company_portal_requirement(v_id) is null
     or not exists(select 1 from public.audit_logs where action='vacancy_review_approved_published' and entity_id=v_id) then
    raise exception 'CHECKPOINT_PRE_M050_M039_REVIEW_SURFACES';
  end if;
end;
$$;

rollback;
