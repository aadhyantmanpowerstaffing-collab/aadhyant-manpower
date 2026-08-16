-- R10: narrowly scoped anonymous public Jobs projection.
-- Base employer_requirements SELECT grants and RLS policies are intentionally unchanged.

begin;

do $$
declare
  required_columns text[] := array[
    'requirement_code', 'job_role', 'department', 'job_location',
    'required_headcount', 'filled_positions', 'salary_min', 'salary_max',
    'salary_wage', 'qualification', 'iti_trade', 'experience_requirement',
    'shift_details', 'working_hours', 'overtime_details', 'canteen',
    'transport', 'accommodation', 'interview_date', 'interview_location',
    'expected_joining_date', 'published_at', 'created_at',
    'requirement_stage', 'requirement_visibility'
  ];
  missing_columns text[];
begin
  if to_regclass('public.employer_requirements') is null then
    raise exception 'R10 prerequisite public.employer_requirements is missing';
  end if;

  select array_agg(required_column order by required_column)
  into missing_columns
  from unnest(required_columns) required_column
  where not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'employer_requirements'
      and c.column_name = required_column
  );

  if missing_columns is not null then
    raise exception 'R10 prerequisite columns are missing: %', array_to_string(missing_columns, ', ');
  end if;

  if to_regprocedure('public.get_public_job_requirements(integer,integer)') is not null then
    raise exception 'R10 public Jobs function already exists; inspect state instead of re-running';
  end if;
end;
$$;

create function public.get_public_job_requirements(
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  requirement_code text,
  job_role text,
  department text,
  job_location text,
  open_positions integer,
  salary_min numeric,
  salary_max numeric,
  salary_text text,
  qualification text,
  iti_trade text,
  experience_requirement text,
  shift_details text,
  working_hours text,
  overtime_details text,
  canteen text,
  transport text,
  accommodation text,
  interview_date timestamptz,
  interview_location text,
  expected_joining_date date,
  published_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    r.requirement_code,
    r.job_role,
    r.department,
    r.job_location,
    greatest(r.required_headcount - r.filled_positions, 0)::integer as open_positions,
    r.salary_min,
    r.salary_max,
    r.salary_wage as salary_text,
    r.qualification,
    r.iti_trade,
    r.experience_requirement,
    r.shift_details,
    r.working_hours,
    r.overtime_details,
    r.canteen,
    r.transport,
    r.accommodation,
    r.interview_date,
    r.interview_location,
    r.expected_joining_date,
    coalesce(r.published_at, r.created_at) as published_at
  from public.employer_requirements r
  where r.requirement_stage = 'open'
    and r.requirement_visibility = 'public'
    and r.requirement_code is not null
    and r.required_headcount > r.filled_positions
  order by coalesce(r.published_at, r.created_at) desc, r.requirement_code desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 5000);
$$;

revoke all on function public.get_public_job_requirements(integer, integer) from public;
grant execute on function public.get_public_job_requirements(integer, integer) to anon, authenticated;

commit;
