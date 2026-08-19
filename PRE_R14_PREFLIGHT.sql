-- Migration 015 preflight (SELECT-only)

-- Do not run migration 015 until an operator runs and reviews this block in the
-- target environment's Supabase SQL Editor.

select current_database() as database_name, current_user as executing_role;

select c.table_name, c.column_name, c.data_type, c.is_nullable
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in ('employer_requirements','requirement_contractors','company_users','contractor_users')
order by c.table_name, c.ordinal_position;

select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('employer_requirements','requirement_contractors');

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('employer_requirements','requirement_contractors','company_users','contractor_users')
order by tablename, policyname;

select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('employer_requirements','requirement_contractors')
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;

select p.oid::regprocedure::text as function_signature,
       p.prosecdef as security_definer,
       p.proconfig as function_config,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public','private')
  and p.proname in (
    'is_admin','current_active_company_id','current_active_contractor_id',
    'create_company_requirement','update_company_requirement','close_company_requirement',
    'respond_requirement_assignment','get_public_job_requirements',
    'register_candidate_requirement_interest','admin_update_candidate_application',
    'admin_schedule_candidate_interview','admin_reschedule_candidate_interview',
    'admin_update_candidate_interview'
  )
order by p.oid::regprocedure::text;
