-- Batch 2 corrective migration: extend the Company compatibility RPC with
-- existing canonical iti_trade and expected_joining_date fields only.
begin;

do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='employer_requirements' and column_name='iti_trade' and data_type='text')
     or not exists (select 1 from information_schema.columns where table_schema='public' and table_name='employer_requirements' and column_name='expected_joining_date' and data_type='date') then
    raise exception 'Migration 043 requires canonical employer_requirements iti_trade and expected_joining_date columns';
  end if;
  if to_regprocedure('public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') is null
     or to_regprocedure('public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)') is null then
    raise exception 'Migration 043 Company vacancy RPC baseline is missing';
  end if;
  if to_regprocedure('public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)') is not null then
    raise exception 'Migration 043 extended Company vacancy RPC already exists';
  end if;
end;
$$;

-- This overload deliberately has no defaults.  The legacy wrapper below keeps
-- its historical optional-argument contract, while explicit 24-field callers
-- select this implementation without ambiguous named/default resolution.
create function public.manage_company_portal_requirement(p_action text,p_requirement_id uuid,
  p_department text,p_job_role text,p_job_location text,p_required_headcount integer,
  p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,
  p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,
  p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,
  p_transport text,p_accommodation text,p_interview_location text,
  p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language sql security definer set search_path='' as $$
  select v.id,v.requirement_code,v.requirement_stage,v.requirement_visibility,v.updated_at
  from public.manage_company_portal_vacancy(p_action,p_requirement_id,p_department,p_job_role,p_job_location,p_required_headcount,
    p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,
    p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,
    p_interview_date,p_expected_joining_date,p_additional_notes) v;
$$;

create or replace function public.manage_company_portal_requirement(p_action text,p_requirement_id uuid default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_interview_date timestamptz default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language sql security definer set search_path='' as $$
  select * from public.manage_company_portal_requirement(p_action,p_requirement_id,p_department,p_job_role,p_job_location,p_required_headcount,
    p_qualification,null,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,
    p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_interview_date,null,p_additional_notes);
$$;

revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text) from public,anon;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text) to authenticated;
revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text) from public,anon;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text) to authenticated;

do $$
begin
  if not has_function_privilege('authenticated','public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)','execute')
     or has_function_privilege('anon','public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)','execute') then
    raise exception 'Migration 043 Company vacancy RPC grant postcondition failed';
  end if;
  if not exists(
    select 1 from pg_proc p
    where p.oid='public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)'::regprocedure
      and p.prosecdef
      and array_to_string(p.proconfig, ',') like '%search_path=%'
  ) then
    raise exception 'Migration 043 Company vacancy RPC security postcondition failed';
  end if;
end;
$$;

commit;
