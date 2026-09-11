\set ON_ERROR_STOP on
-- Checkpoint 025 constructs Candidate identities, approved/open/public and hidden
-- vacancies, candidate-specific applications, capacity conditions, and rolls all
-- fixtures back. Reuse that canonical fixture rather than duplicate its graph.
\ir 025_candidate_portal_foundation_test.sql

do $$
begin
  if to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is null then
    raise exception 'M047 Candidate opportunity projection signature missing';
  end if;
  if has_function_privilege('anon','public.list_candidate_job_opportunities(text,integer,integer)','execute')
     or not has_function_privilege('authenticated','public.list_candidate_job_opportunities(text,integer,integer)','execute') then
    raise exception 'M047 Candidate opportunity projection execution boundary failed';
  end if;
end;
$$;

\echo CHECKPOINT_047_CANDIDATE_OPPORTUNITY_PROJECTION_AMBIGUITY_PASS
