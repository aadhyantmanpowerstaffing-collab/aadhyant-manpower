-- Recruitment Operations Core Phase A rollback checkpoint.
\set ON_ERROR_STOP on
begin;

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

rollback;
