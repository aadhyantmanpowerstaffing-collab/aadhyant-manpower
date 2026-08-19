-- PRE-R14 C1: remove tenant access to Admin-only requirement and assignment columns.
-- Admin base-table policies remain unchanged; tenant reads move to explicit projections.

begin;

do $$
declare
  missing_columns text[];
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.requirement_contractors') is null
     or to_regclass('public.company_users') is null
     or to_regclass('public.contractor_users') is null then
    raise exception 'C1 prerequisite tables are missing';
  end if;

  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('private.current_active_company_id()') is null
     or to_regprocedure('private.current_active_contractor_id()') is null then
    raise exception 'C1 prerequisite authorization helpers are missing';
  end if;

  select array_agg(required.column_name order by required.column_name)
  into missing_columns
  from (values
    ('employer_requirements', 'internal_notes'),
    ('requirement_contractors', 'internal_notes')
  ) as required(table_name, column_name)
  where not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = required.table_name
      and c.column_name = required.column_name
  );
  if missing_columns is not null then
    raise exception 'C1 sensitive columns are missing: %', array_to_string(missing_columns, ', ');
  end if;

  if not has_table_privilege('authenticated', 'public.employer_requirements', 'select')
     or not has_table_privilege('authenticated', 'public.requirement_contractors', 'select') then
    raise exception 'C1 expected authenticated base-table grants are missing; inspect database state';
  end if;

  if not exists (
       select 1 from pg_policies
       where schemaname = 'public' and tablename = 'employer_requirements'
         and policyname = 'M8B active company reads own requirements'
     )
     or not exists (
       select 1 from pg_policies
       where schemaname = 'public' and tablename = 'employer_requirements'
         and policyname = 'M8C active contractor reads assigned requirements'
     )
     or not exists (
       select 1 from pg_policies
       where schemaname = 'public' and tablename = 'requirement_contractors'
         and policyname = 'M8C active contractor reads own assignments'
     ) then
    raise exception 'C1 expected tenant read policies are missing; inspect database state';
  end if;

  if not exists (
       select 1 from pg_policies
       where schemaname = 'public' and tablename = 'employer_requirements'
         and policyname in ('Admins can read employer requirements', 'M7 admins read requirements')
     )
     or not exists (
       select 1 from pg_policies
       where schemaname = 'public' and tablename = 'requirement_contractors'
         and policyname = 'M7 admins read requirement assignments'
     ) then
    raise exception 'C1 expected Admin read policies are missing';
  end if;

  if to_regprocedure('public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') is null
     or to_regprocedure('public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') is null
     or to_regprocedure('public.close_company_requirement(uuid)') is null
     or to_regprocedure('public.respond_requirement_assignment(uuid,text,text)') is null then
    raise exception 'C1 prerequisite tenant mutation functions are missing';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'get_company_requirements',
        'manage_company_requirement',
        'get_staffing_partner_assignments',
        'staffing_partner_respond_requirement_assignment'
      )
  ) then
    raise exception 'C1 tenant projection function already exists; inspect database state instead of re-running';
  end if;
end;
$$;

create function public.get_company_requirements()
returns table (
  id uuid,
  requirement_code text,
  department text,
  job_role text,
  job_location text,
  required_headcount integer,
  filled_positions integer,
  qualification text,
  experience_requirement text,
  gender_preference text,
  age_min integer,
  age_max integer,
  salary_min numeric,
  salary_max numeric,
  shift_details text,
  working_hours text,
  overtime_details text,
  canteen text,
  transport text,
  accommodation text,
  interview_location text,
  interview_date timestamptz,
  additional_notes text,
  requirement_stage text,
  requirement_visibility text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  company_id_value uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authenticated Company access is required';
  end if;
  company_id_value := (select private.current_active_company_id());
  if company_id_value is null then
    raise exception 'Active Company access is required';
  end if;

  return query
  select
    r.id,
    r.requirement_code,
    r.department,
    r.job_role,
    r.job_location,
    r.required_headcount,
    r.filled_positions,
    r.qualification,
    r.experience_requirement,
    r.gender_preference,
    r.age_min,
    r.age_max,
    r.salary_min,
    r.salary_max,
    r.shift_details,
    r.working_hours,
    r.overtime_details,
    r.canteen,
    r.transport,
    r.accommodation,
    r.interview_location,
    r.interview_date,
    r.additional_notes,
    r.requirement_stage,
    r.requirement_visibility,
    r.created_at,
    r.updated_at
  from public.employer_requirements r
  where r.company_id = company_id_value
  order by r.created_at desc, r.requirement_code desc;
end;
$$;

create function public.get_staffing_partner_assignments()
returns table (
  id uuid,
  assigned_headcount integer,
  assignment_status text,
  assigned_at timestamptz,
  accepted_at timestamptz,
  declined_at timestamptz,
  requirement_code text,
  company_name text,
  department text,
  job_role text,
  job_location text,
  company_location text,
  required_headcount integer,
  salary_min numeric,
  salary_max numeric,
  qualification text,
  experience_requirement text,
  shift_details text,
  canteen text,
  transport text,
  accommodation text,
  interview_location text,
  interview_date timestamptz,
  requirement_stage text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  contractor_id_value uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authenticated Staffing Partner access is required';
  end if;
  contractor_id_value := (select private.current_active_contractor_id());
  if contractor_id_value is null then
    raise exception 'Active Staffing Partner access is required';
  end if;

  return query
  select
    rc.id,
    rc.assigned_headcount,
    rc.assignment_status,
    rc.assigned_at,
    rc.accepted_at,
    rc.declined_at,
    r.requirement_code,
    r.company_name,
    r.department,
    r.job_role,
    r.job_location,
    r.company_location,
    r.required_headcount,
    r.salary_min,
    r.salary_max,
    r.qualification,
    r.experience_requirement,
    r.shift_details,
    r.canteen,
    r.transport,
    r.accommodation,
    r.interview_location,
    r.interview_date,
    r.requirement_stage
  from public.requirement_contractors rc
  join public.employer_requirements r on r.id = rc.requirement_id
  where rc.contractor_id = contractor_id_value
  order by rc.assigned_at desc, rc.id;
end;
$$;

create function public.manage_company_requirement(
  p_action text,
  p_requirement_id uuid default null,
  p_department text default null,
  p_job_role text default null,
  p_job_location text default null,
  p_required_headcount integer default null,
  p_qualification text default null,
  p_experience_requirement text default 'Both',
  p_gender_preference text default 'Any',
  p_age_min integer default null,
  p_age_max integer default null,
  p_salary_min numeric default null,
  p_salary_max numeric default null,
  p_shift_details text default null,
  p_working_hours text default null,
  p_overtime_details text default null,
  p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',
  p_accommodation text default 'Not Applicable',
  p_interview_location text default null,
  p_interview_date timestamptz default null,
  p_additional_notes text default null
)
returns table (
  id uuid,
  requirement_code text,
  requirement_stage text,
  requirement_visibility text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  company_id_value uuid;
  requirement_record public.employer_requirements%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Authenticated Company access is required';
  end if;
  company_id_value := (select private.current_active_company_id());
  if company_id_value is null then
    raise exception 'Active Company access is required';
  end if;
  if p_action not in ('create', 'update', 'close') then
    raise exception 'Unsupported Company requirement action';
  end if;

  if p_action = 'create' then
    requirement_record := public.create_company_requirement(
      p_department, p_job_role, p_job_location, p_required_headcount,
      p_qualification, p_experience_requirement, p_gender_preference,
      p_age_min, p_age_max, p_salary_min, p_salary_max, p_shift_details,
      p_working_hours, p_overtime_details, p_canteen, p_transport,
      p_accommodation, p_interview_location, p_interview_date,
      p_additional_notes
    );
  elsif p_action = 'update' then
    if p_requirement_id is null then raise exception 'Requirement identifier is required'; end if;
    requirement_record := public.update_company_requirement(
      p_requirement_id, p_department, p_job_role, p_job_location,
      p_required_headcount, p_qualification, p_experience_requirement,
      p_gender_preference, p_age_min, p_age_max, p_salary_min, p_salary_max,
      p_shift_details, p_working_hours, p_overtime_details, p_canteen,
      p_transport, p_accommodation, p_interview_location, p_interview_date,
      p_additional_notes
    );
  else
    if p_requirement_id is null then raise exception 'Requirement identifier is required'; end if;
    requirement_record := public.close_company_requirement(p_requirement_id);
  end if;

  if requirement_record.company_id <> company_id_value then
    raise exception 'Company requirement ownership verification failed';
  end if;
  return query select
    requirement_record.id,
    requirement_record.requirement_code,
    requirement_record.requirement_stage,
    requirement_record.requirement_visibility,
    requirement_record.updated_at;
end;
$$;

create function public.staffing_partner_respond_requirement_assignment(
  p_assignment_id uuid,
  p_response text,
  p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  contractor_id_value uuid;
  assignment_record public.requirement_contractors%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Authenticated Staffing Partner access is required';
  end if;
  contractor_id_value := (select private.current_active_contractor_id());
  if contractor_id_value is null then
    raise exception 'Active Staffing Partner access is required';
  end if;
  assignment_record := public.respond_requirement_assignment(p_assignment_id, p_response, p_reason);
  if assignment_record.contractor_id <> contractor_id_value then
    raise exception 'Staffing Partner assignment ownership verification failed';
  end if;
  return true;
end;
$$;

revoke all on function public.get_company_requirements() from public, anon;
revoke all on function public.get_staffing_partner_assignments() from public, anon;
revoke all on function public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) from public, anon;
revoke all on function public.staffing_partner_respond_requirement_assignment(uuid,text,text) from public, anon;
revoke execute on function public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) from authenticated;
revoke execute on function public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) from authenticated;
revoke execute on function public.close_company_requirement(uuid) from authenticated;
revoke execute on function public.respond_requirement_assignment(uuid,text,text) from authenticated;
grant execute on function public.get_company_requirements() to authenticated;
grant execute on function public.get_staffing_partner_assignments() to authenticated;
grant execute on function public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) to authenticated;
grant execute on function public.staffing_partner_respond_requirement_assignment(uuid,text,text) to authenticated;

drop policy "M8B active company reads own requirements" on public.employer_requirements;
drop policy "M8C active contractor reads assigned requirements" on public.employer_requirements;
drop policy "M8C active contractor reads own assignments" on public.requirement_contractors;

-- The authenticated table grants remain for approved Admin browser queries.
-- With tenant read policies removed, RLS returns no base rows to Company/Partner sessions.

commit;
