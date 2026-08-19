-- Run only against an isolated disposable Supabase with migrations through 016.
\set ON_ERROR_STOP on
begin;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'staff_profiles', 'staff_roles', 'candidate_preferences',
    'application_stages', 'application_stage_history', 'audit_logs'
  ] loop
    if to_regclass('public.' || table_name) is null then
      raise exception 'W1 table is missing: %', table_name;
    end if;
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=table_name and c.relrowsecurity
    ) then raise exception 'RLS is not enabled on W1 table: %', table_name; end if;
    if has_table_privilege('anon', 'public.' || table_name, 'SELECT')
       or has_table_privilege('anon', 'public.' || table_name, 'INSERT')
       or has_table_privilege('anon', 'public.' || table_name, 'UPDATE')
       or has_table_privilege('anon', 'public.' || table_name, 'DELETE') then
      raise exception 'Anonymous has W1 table privilege: %', table_name;
    end if;
  end loop;

  if to_regclass('public.candidate_master') is not null
     or to_regclass('public.vacancies') is not null
     or to_regclass('public.joining_records') is not null then
    raise exception 'W1 introduced a duplicate core entity';
  end if;
end;
$$;

do $$
declare
  expected_stages text[] := array[
    'new_lead','registered','interested','applied','screening',
    'interview_scheduled','interview_attended','selected','joining_pending',
    'joined','active','rejected','no_show','withdrawn','left'
  ];
  missing_stage text;
begin
  select min(stage) into missing_stage
  from unnest(expected_stages) stage
  where not exists(select 1 from public.application_stages s where s.stage=stage);
  if missing_stage is not null then raise exception 'Required stage is missing: %', missing_stage; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='candidate_applications' and column_name='source_reference'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='candidate_applications' and column_name='correlation_id'
  ) then raise exception 'Candidate application correlation/source columns are missing'; end if;
end;
$$;

do $$
begin
  if to_regprocedure('private.record_application_stage_history()') is null then
    raise exception 'Stage-history trigger function is missing';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname='record_application_stage_history'
      and p.prosecdef
      and exists (
        select 1 from unnest(p.proconfig) config
        where split_part(config, '=', 1)='search_path'
          and btrim(split_part(config, '=', 2), '"')=''
      )
  ) then raise exception 'Stage-history trigger function security configuration is invalid'; end if;
  if has_function_privilege('anon','private.record_application_stage_history()','EXECUTE')
     or has_function_privilege('authenticated','private.record_application_stage_history()','EXECUTE') then
    raise exception 'Browser role can execute the private history trigger function';
  end if;
  if not exists(select 1 from pg_trigger where tgname='candidate_applications_record_stage_history' and not tgisinternal) then
    raise exception 'Stage-history trigger is missing';
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('authenticated','public.application_stage_history','INSERT')
     or has_table_privilege('authenticated','public.application_stage_history','UPDATE')
     or has_table_privilege('authenticated','public.application_stage_history','DELETE')
     or has_table_privilege('authenticated','public.audit_logs','INSERT')
     or has_table_privilege('authenticated','public.audit_logs','UPDATE')
     or has_table_privilege('authenticated','public.audit_logs','DELETE') then
    raise exception 'Authenticated has append-only table mutation privilege';
  end if;
  if exists (
    select 1 from pg_policies where schemaname='public'
      and tablename in ('application_stage_history','audit_logs')
      and cmd in ('INSERT','UPDATE','DELETE','ALL')
  ) then raise exception 'Append-only tables have a browser mutation policy'; end if;

  if to_regprocedure('public.get_company_requirements()') is null
     or to_regprocedure('public.get_staffing_partner_assignments()') is null
     or to_regprocedure('public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') is null
     or to_regprocedure('public.staffing_partner_respond_requirement_assignment(uuid,text,text)') is null then
    raise exception 'Migration 015 compatibility function is missing';
  end if;
  if has_function_privilege('anon','public.get_company_requirements()','EXECUTE')
     or not has_function_privilege('authenticated','public.get_company_requirements()','EXECUTE') then
    raise exception 'Migration 015 grant compatibility changed';
  end if;
end;
$$;

rollback;
\echo 'W1 SCHEMA FOUNDATION TESTS PASSED'
