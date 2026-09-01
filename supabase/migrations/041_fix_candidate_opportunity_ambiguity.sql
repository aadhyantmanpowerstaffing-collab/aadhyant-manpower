-- Batch 2 corrective migration: preserve the Migration 039 Candidate opportunity
-- eligibility boundary while removing an ambiguous Candidate identifier.
begin;

do $$
declare
  function_definition text;
  function_is_secure boolean;
  function_config text;
  contractor_definition text;
begin
  if to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is null
     or to_regprocedure('private.current_candidate_portal_id()') is null
     or to_regprocedure('private.vacancy_is_application_eligible(uuid)') is null
     or to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)') is null then
    raise exception 'Migration 039/040 Candidate opportunity prerequisites are missing';
  end if;
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict function_definition,function_is_secure,function_config
  from pg_proc p
  where p.oid='public.list_candidate_job_opportunities(text,integer,integer)'::regprocedure;
  if not function_is_secure or function_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.list_candidate_job_opportunities(text,integer,integer)','execute')
     or has_function_privilege('anon','public.list_candidate_job_opportunities(text,integer,integer)','execute') then
    raise exception 'Migration 039 Candidate opportunity security baseline drifted';
  end if;
  if position('a.candidate_id=candidate_id' in function_definition)=0
     or position('v_candidate_id' in function_definition)>0 then
    raise exception 'Migration 041 expected pre-correction Candidate opportunity function is not installed';
  end if;
  select pg_get_functiondef(p.oid) into strict contractor_definition
  from pg_proc p
  where p.oid='public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)'::regprocedure;
  if position('rc.contractor_id=v_contractor_id' in contractor_definition)=0 then
    raise exception 'Migration 040 Contractor correction prerequisite is not installed';
  end if;
end;
$$;

create or replace function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,department text,job_location text,open_positions integer,
  qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,
  shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,
  interview_location text,expected_joining_date date,safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path='' as $$
declare
  v_candidate_id uuid:=(select private.current_candidate_portal_id());
  v_term text:=nullif(btrim(p_search),'');
begin
  if v_candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query
  select r.requirement_code,r.job_role,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,
    r.qualification,r.iti_trade,r.experience_requirement,r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,r.shift_details,r.working_hours,
    r.overtime_details,r.canteen,r.transport,r.accommodation,r.interview_location,r.expected_joining_date,r.additional_notes,
    exists(select 1 from public.candidate_applications a where a.candidate_id=v_candidate_id and a.requirement_id=r.id)
  from public.employer_requirements r
  where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null
    and (v_term is null or r.requirement_code ilike '%'||v_term||'%' or r.job_role ilike '%'||v_term||'%' or coalesce(r.job_location,'') ilike '%'||v_term||'%')
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

revoke all on function public.list_candidate_job_opportunities(text,integer,integer) from public,anon;
grant execute on function public.list_candidate_job_opportunities(text,integer,integer) to authenticated;

do $$
declare
  function_definition text;
  function_is_secure boolean;
  function_config text;
begin
  select pg_get_functiondef(p.oid),p.prosecdef,coalesce(array_to_string(p.proconfig,','),'')
    into strict function_definition,function_is_secure,function_config
  from pg_proc p
  where p.oid='public.list_candidate_job_opportunities(text,integer,integer)'::regprocedure;
  if position('a.candidate_id=v_candidate_id' in function_definition)=0
     or position('a.candidate_id=candidate_id' in function_definition)>0
     or not function_is_secure or function_config not like '%search_path=%'
     or not has_function_privilege('authenticated','public.list_candidate_job_opportunities(text,integer,integer)','execute')
     or has_function_privilege('anon','public.list_candidate_job_opportunities(text,integer,integer)','execute') then
    raise exception 'Migration 041 Candidate opportunity post-install assertion failed';
  end if;
end;
$$;

commit;
