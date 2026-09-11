\set ON_ERROR_STOP on
-- The canonical Company and Contractor foundation checkpoints construct isolated
-- owner identities, tenant-scoped vacancies, cross-tenant denial checks, and
-- rollback every fixture. Running them here verifies the four M046 projections
-- against the same runtime contracts rather than duplicating their fixtures.
\ir 019_company_portal_foundation_test.sql
\ir 022_contractor_portal_foundation_test.sql

do $$
begin
  if to_regprocedure('public.list_company_portal_requirements(text,text,integer,integer)') is null
     or to_regprocedure('public.get_company_portal_requirement(uuid)') is null
     or to_regprocedure('public.list_contractor_portal_vacancies(text,text,integer,integer)') is null
     or to_regprocedure('public.get_contractor_portal_vacancy(uuid)') is null then
    raise exception 'M046 owner vacancy projection signature missing';
  end if;
  if has_function_privilege('anon','public.list_company_portal_requirements(text,text,integer,integer)','execute')
     or has_function_privilege('anon','public.get_company_portal_requirement(uuid)','execute')
     or has_function_privilege('anon','public.list_contractor_portal_vacancies(text,text,integer,integer)','execute')
     or has_function_privilege('anon','public.get_contractor_portal_vacancy(uuid)','execute') then
    raise exception 'M046 owner vacancy projection anon execution granted';
  end if;
end;
$$;

\echo CHECKPOINT_046_OWNER_VACANCY_PROJECTION_AMBIGUITY_PASS
