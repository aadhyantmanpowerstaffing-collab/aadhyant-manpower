-- Batch 2 corrective migration: preserve the Migration 039 Candidate Apply
-- contract while removing the remaining ambiguous Candidate identifier.
begin;

do $$
declare
  function_definition text;
  function_is_secure boolean;
  function_config text;
  opportunity_definition text;
begin
  if to_regprocedure('public.apply_candidate_job(text)') is null
     or to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is null
     or to_regprocedure('private.current_candidate_portal_id()') is null
     or to_regprocedure('private.vacancy_is_application_eligible(uuid)') is null then
    raise exception 'Migration 039/041 Candidate Apply prerequisites are missing';
  end if;

  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict function_definition,function_is_secure,function_config
  from pg_proc p
  where p.oid='public.apply_candidate_job(text)'::regprocedure;
  if not function_is_secure or function_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.apply_candidate_job(text)','execute')
     or has_function_privilege('anon','public.apply_candidate_job(text)','execute') then
    raise exception 'Migration 039 Candidate Apply security baseline drifted';
  end if;
  if position('d.candidate_id=candidate_id' in function_definition)=0
     or position('v_candidate_id' in function_definition)>0 then
    raise exception 'Migration 042 expected pre-correction Candidate Apply function is not installed';
  end if;

  select pg_get_functiondef(p.oid) into strict opportunity_definition
  from pg_proc p
  where p.oid='public.list_candidate_job_opportunities(text,integer,integer)'::regprocedure;
  if position('a.candidate_id=v_candidate_id' in opportunity_definition)=0 then
    raise exception 'Migration 041 Candidate opportunity correction prerequisite is not installed';
  end if;
end;
$$;

create or replace function public.apply_candidate_job(p_requirement_code text)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_candidate_id uuid:=(select private.current_candidate_portal_id());
  v_requirement public.employer_requirements%rowtype;
  v_application_id uuid;
begin
  if v_candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  if not exists(
       select 1 from public.candidates c
       where c.id=v_candidate_id
         and c.mobile~'^[6-9][0-9]{9}$'
         and c.aadhaar_last4 is not null
         and c.profile_completion_status='complete'
     )
     or not exists(
       select 1 from public.candidate_documents d
       where d.candidate_id=v_candidate_id
         and d.document_type='resume'
         and d.active
     ) then
    raise exception 'Complete the required Candidate profile and Resume before applying';
  end if;

  select r.* into v_requirement
  from public.employer_requirements r
  where r.requirement_code=upper(btrim(p_requirement_code))
    and private.vacancy_is_application_eligible(r.id)
  for share;
  if v_requirement.id is null then raise exception 'Opportunity is not available'; end if;

  insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,created_by,source_reference)
  values(v_candidate_id,v_requirement.id,'direct','applied',(select auth.uid()),'candidate_portal')
  returning id into v_application_id;

  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values((select auth.uid()),'candidate','candidate.application_created','candidate_application',v_application_id,'candidate',
    jsonb_build_object('requirement_id',v_requirement.id));
  return v_application_id;
exception when unique_violation then
  raise exception 'You already have an application for this opportunity';
end;
$$;

revoke all on function public.apply_candidate_job(text) from public,anon;
grant execute on function public.apply_candidate_job(text) to authenticated;

do $$
declare
  function_definition text;
  function_is_secure boolean;
  function_config text;
begin
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict function_definition,function_is_secure,function_config
  from pg_proc p
  where p.oid='public.apply_candidate_job(text)'::regprocedure;
  if position('d.candidate_id=v_candidate_id' in function_definition)=0
     or position('d.candidate_id=candidate_id' in function_definition)>0
     or position('private.vacancy_is_application_eligible(r.id)' in function_definition)=0
     or not function_is_secure or function_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.apply_candidate_job(text)','execute')
     or has_function_privilege('anon','public.apply_candidate_job(text)','execute') then
    raise exception 'Migration 042 Candidate Apply post-install assertion failed';
  end if;
end;
$$;

commit;
