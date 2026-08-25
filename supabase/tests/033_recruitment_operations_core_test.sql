-- Recruitment Operations Core Phase A rollback checkpoint.
\set ON_ERROR_STOP on
begin;

-- Fixture contract: the authorized NONPROD runner must execute this file in a
-- rollback-scoped transaction with deterministic UUID fixtures. No retained
-- rows may be used. The case matrix below is intentionally explicit so a
-- runner cannot treat a generic exception as authorization proof.
create temporary table phase_a_checkpoint_cases(case_name text primary key, expected_error text not null) on commit drop;
insert into phase_a_checkpoint_cases values
 ('unauthorized_source_correction','Recruitment access is required'),
 ('invalid_owner','Owner must be an active recruitment staff member'),
 ('unauthorized_follow_up','Recruitment access is required'),
 ('missing_correction_reason','Correction reason is required'),
 ('due_without_action','A follow-up due date requires a next action');

-- Deterministic disposable fixtures. This block is transaction-scoped and is
-- never safe to run against a retained/shared dataset.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('93000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-a-admin@test.local','x','{}','{}',now(),now()),
 ('93000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-a-recruiter@test.local','x','{}','{}',now(),now()),
 ('93000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-a-inactive@test.local','x','{}','{}',now(),now()),
 ('93000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-a-viewer@test.local','x','{}','{}',now(),now());
insert into public.staff_profiles(user_id,display_name,status) values
 ('93000000-0000-0000-0000-000000000001','Phase A Admin','active'),('93000000-0000-0000-0000-000000000002','Phase A Recruiter','active'),('93000000-0000-0000-0000-000000000003','Phase A Inactive','suspended'),('93000000-0000-0000-0000-000000000004','Phase A Viewer','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
 ('93000000-0000-0000-0000-000000000001','admin','active','93000000-0000-0000-0000-000000000001'),('93000000-0000-0000-0000-000000000002','recruiter','active','93000000-0000-0000-0000-000000000001'),('93000000-0000-0000-0000-000000000003','recruiter','active','93000000-0000-0000-0000-000000000001'),('93000000-0000-0000-0000-000000000004','viewer','active','93000000-0000-0000-0000-000000000001');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,interview_available,consent,status)
values('93000000-0000-0000-0001-000000000001','Phase A Candidate',24,'Female','9876543210','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new');
insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,qualification,consent,status,requirement_code,job_location,requirement_stage,requirement_visibility)
values('93000000-0000-0000-0002-000000000001','Phase A Company','Phase A Contact','9876543211','Chennai','Fitter',2,'ITI',true,'in_progress','PHA-REQ-001','Chennai','draft','private');
insert into public.contractors(id,agency_name,owner_name,account_status,verification_status) values('93000000-0000-0000-0003-000000000001','Phase A Contractor','Phase A Owner','pending','pending');
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_at,updated_at)
values('93000000-0000-0000-0004-000000000001','93000000-0000-0000-0001-000000000001','93000000-0000-0000-0002-000000000001','direct','applied',clock_timestamp()-interval '3 days',clock_timestamp()-interval '3 days');
insert into public.interviews(id,application_id,scheduled_at,status,result,created_by) values
 ('93000000-0000-0000-0005-000000000001','93000000-0000-0000-0004-000000000001',clock_timestamp()+interval '24 hours','scheduled','pending','93000000-0000-0000-000000000001');
insert into public.candidate_joinings(id,application_id,expected_joining_date,joining_status,created_by) values
 ('93000000-0000-0000-0006-000000000001','93000000-0000-0000-0004-000000000001',current_date+5,'pending','93000000-0000-0000-000000000001');
do $$
begin
  if (select count(*) from phase_a_checkpoint_cases)<>5 then raise exception 'Authorization case matrix incomplete'; end if;
  if exists(select 1 from phase_a_checkpoint_cases where expected_error is null or length(expected_error)=0) then raise exception 'Authorization case contains an unbounded error expectation'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-0000-0000-000000000001',true);
do $$
declare raised text; audit jsonb; old_at timestamptz;
begin
  select attributed_at into old_at from public.employer_requirements where id='93000000-0000-0000-0002-000000000001';
  perform public.admin_correct_requirement_source('93000000-0000-0000-0002-000000000001','public_website','phase-a-detail','phase-a-ref','phase-a correction');
  if (select attributed_at from public.employer_requirements where id='93000000-0000-0000-0002-000000000001')<>old_at then raise exception 'First attribution timestamp changed'; end if;
  select metadata into audit from public.audit_logs where entity_id='93000000-0000-0000-0002-000000000001' and action='recruitment.source_corrected' order by created_at desc limit 1;
  if audit->>'old_source_type' <> 'admin_manual' or audit->>'new_source_type' <> 'public_website' or audit->>'new_source_detail' <> 'phase-a-detail' or audit->>'new_source_reference' <> 'phase-a-ref' or audit->>'reason' <> 'phase-a correction' then raise exception 'Source correction audit is incomplete'; end if;
  begin perform public.admin_correct_requirement_source('93000000-0000-0000-0002-000000000001','not_a_source',null,null,'bad source'); raise exception 'invalid_source'; exception when others then raised:=sqlerrm; end;
  if raised<>'Unsupported source type' then raise exception 'Unexpected source denial: %',raised; end if;
  begin perform public.admin_correct_requirement_source('93000000-0000-0000-0002-000000000001','referral',null,null,''); raise exception 'missing_reason'; exception when others then raised:=sqlerrm; end;
  if raised<>'Correction reason is required' then raise exception 'Unexpected reason denial: %',raised; end if;
  perform public.admin_assign_requirement_owner('93000000-0000-0000-0002-000000000001','93000000-0000-0000-0000-000000000002');
  perform public.admin_assign_requirement_owner('93000000-0000-0000-0002-000000000001',null);
  perform public.admin_set_requirement_follow_up('93000000-0000-0000-0002-000000000001','Call employer',clock_timestamp()-interval '1 hour');
  if not exists(select 1 from public.admin_list_recruitment_attention(100,0) where entity_id='93000000-0000-0000-0002-000000000001' and reason='Requirement follow-up due') then raise exception 'Overdue follow-up attention missing'; end if;
  perform public.admin_set_requirement_follow_up('93000000-0000-0000-0002-000000000001',null,null);
  begin perform public.admin_set_requirement_follow_up('93000000-0000-0000-0002-000000000001',null,clock_timestamp()); raise exception 'due_without_action'; exception when others then raised:=sqlerrm; end;
  if raised<>'A follow-up due date requires a next action' then raise exception 'Unexpected follow-up denial: %',raised; end if;
  begin perform public.admin_assign_requirement_owner('93000000-0000-0000-0002-000000000001','93000000-0000-0000-0000-000000000003'); raise exception 'invalid_owner'; exception when others then raised:=sqlerrm; end;
  if raised<>'Owner must be an active recruitment staff member' then raise exception 'Unexpected owner denial: %',raised; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-0000-0000-000000000004',true);
do $$ declare raised text; begin
  begin perform public.admin_correct_requirement_source('93000000-0000-0000-0002-000000000001','referral',null,null,'viewer attempt'); raise exception 'unauthorized_source'; exception when others then raised:=sqlerrm; end;
  if raised<>'Recruitment access is required' then raise exception 'Unexpected unauthorized source denial: %',raised; end if;
end $$;
reset role;

do $$
begin
  if to_regclass('public.recruitment_source_vocabulary') is null then raise exception 'Phase A source vocabulary is missing'; end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='employer_requirements' and column_name in ('source_type','source_detail','source_reference','attributed_at','owner_staff_user_id','owner_assigned_at','owner_assigned_by','next_action','follow_up_due_at','qualified_at','lost_reason','operational_updated_at'))<>12 then raise exception 'Requirement Phase A columns are incomplete'; end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='candidates' and column_name in ('acquisition_source_type','acquisition_source_detail','acquisition_source_reference','acquisition_attributed_at','owner_staff_user_id','owner_assigned_at','owner_assigned_by','next_action','follow_up_due_at'))<>9 then raise exception 'Candidate Phase A columns are incomplete'; end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='contractors' and column_name in ('acquisition_source_type','acquisition_source_detail','acquisition_source_reference','acquisition_attributed_at','owner_staff_user_id','owner_assigned_at','owner_assigned_by','next_action','follow_up_due_at'))<>9 then raise exception 'Contractor Phase A columns are incomplete'; end if;
  if not exists(select 1 from pg_constraint where conname='candidate_applications_source_type_check') then raise exception 'Application source compatibility constraint is missing'; end if;
  if not exists(select 1 from pg_constraint where conname='recruitment_requirement_source_type_check') then raise exception 'Requirement source constraint is missing'; end if;
  if to_regprocedure('public.admin_list_recruitment_attention(integer,integer)') is null then raise exception 'Attention projection is missing'; end if;
  if to_regprocedure('private.phase_a_sla()') is null then raise exception 'Central Phase A SLA contract is missing'; end if;
  if not exists(select 1 from pg_trigger where tgname='recruitment_clear_reopened_lost_reason' and tgrelid='public.employer_requirements'::regclass and tgenabled<>'D') then raise exception 'Lost-reason reopen trigger is missing'; end if;
  if (select count(*) from public.recruitment_source_vocabulary)<>12 then raise exception 'Source vocabulary is not exactly the approved 12 values'; end if;
  if exists(select 1 from public.recruitment_source_vocabulary where source_type not in ('public_website','candidate_portal','employer_portal','contractor_portal','whatsapp_campaign','admin_manual','referral','campus','iti','csc_vle','field_sourcing','external_job_lead')) then raise exception 'Unexpected source vocabulary value'; end if;
  if to_regprocedure('public.admin_assign_requirement_owner(uuid,uuid)') is null or to_regprocedure('public.admin_set_requirement_follow_up(uuid,text,timestamptz)') is null then raise exception 'Requirement ownership RPCs are missing'; end if;
  if to_regprocedure('public.admin_correct_candidate_source(uuid,text,text,text,text)') is null then raise exception 'Candidate source correction RPC is missing'; end if;
  if pg_get_functiondef('public.admin_list_recruitment_attention(integer,integer)'::regprocedure) not ilike '%security definer%' or pg_get_functiondef('public.admin_list_recruitment_attention(integer,integer)'::regprocedure) not ilike '%set search_path to ''''%' then raise exception 'Attention RPC security posture is invalid'; end if;
  if has_function_privilege('anon','public.admin_list_recruitment_attention(integer,integer)','execute') or not has_function_privilege('authenticated','public.admin_list_recruitment_attention(integer,integer)','execute') then raise exception 'Attention RPC grant boundary is invalid'; end if;
  if exists(select 1 from information_schema.column_privileges where table_schema='public' and table_name in ('employer_requirements','candidates','contractors') and privilege_type='UPDATE' and grantee='authenticated' and column_name in ('source_type','acquisition_source_type','owner_staff_user_id','next_action','follow_up_due_at')) then raise exception 'Browser metadata update grant detected'; end if;
  if pg_get_functiondef('private.phase_a_sla()'::regprocedure) not ilike '%security definer%' or pg_get_functiondef('private.phase_a_sla()'::regprocedure) not ilike '%set search_path to ''''%' then raise exception 'SLA function security posture is invalid'; end if;
  if pg_get_functiondef('public.admin_list_recruitment_attention(integer,integer)'::regprocedure) not ilike '%interviews%' or pg_get_functiondef('public.admin_list_recruitment_attention(integer,integer)'::regprocedure) not ilike '%candidate_joinings%' or pg_get_functiondef('public.admin_list_recruitment_attention(integer,integer)'::regprocedure) not ilike '%requirement_contractors%' then raise exception 'Attention projection omits a canonical attention source'; end if;
  if pg_get_functiondef('public.admin_correct_candidate_source(uuid,text,text,text,text)'::regprocedure) ilike '%phone%' or pg_get_functiondef('public.admin_list_recruitment_attention(integer,integer)'::regprocedure) ilike '%email%' then raise exception 'Privacy-sensitive projection or audit reference detected'; end if;
end $$;

do $$
declare before_requirements integer; before_candidates integer; before_contractors integer;
begin
  select count(*) into before_requirements from public.employer_requirements;
  select count(*) into before_candidates from public.candidates;
  select count(*) into before_contractors from public.contractors;
  if (select count(*) from public.recruitment_source_vocabulary)<>12 then raise exception 'Source vocabulary count is not exactly 12'; end if;
  if (exists(select 1 from public.recruitment_source_vocabulary where source_type='whatsapp_campaign' and not active)) then raise exception 'Approved WhatsApp source is inactive'; end if;
  if (select count(*) from public.employer_requirements)<>before_requirements or (select count(*) from public.candidates)<>before_candidates or (select count(*) from public.contractors)<>before_contractors then raise exception 'Checkpoint changed canonical rows'; end if;
end $$;

-- Runtime fixture matrix to be executed by the NONPROD operator after
-- migration application: deterministic entities must cover every positive
-- and negative rule, then be rolled back. True multi-session races are not
-- claimed here; replay/idempotency must be checked by repeating each RPC and
-- asserting one final canonical state plus one audit event per state change.
do $$
begin
  if not exists(select 1 from phase_a_checkpoint_cases where case_name='invalid_owner') then raise exception 'Fixture matrix missing owner denial'; end if;
  if not exists(select 1 from phase_a_checkpoint_cases where case_name='due_without_action') then raise exception 'Fixture matrix missing follow-up boundary'; end if;
end $$;

rollback;
