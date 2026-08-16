-- MILESTONE 8B: company-owned manpower requirements and controlled lifecycle
-- Apply only after 007 and 008 have completed successfully.

begin;

do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.platform_users') is null
     or to_regclass('public.companies') is null
     or to_regclass('public.company_users') is null then
    raise exception 'Milestone 7/8A prerequisite tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('public.set_company_account_status(uuid,text)') is null then
    raise exception 'Milestone 7/8A prerequisite functions are missing';
  end if;
  if to_regprocedure('public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,timestamp with time zone,text)') is not null
     or to_regprocedure('public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,timestamp with time zone,text)') is not null
     or to_regprocedure('public.close_company_requirement(uuid)') is not null
     or to_regprocedure('public.set_company_requirement_stage(uuid,text,text)') is not null
     or exists (select 1 from pg_policies where schemaname = 'public' and policyname like 'M8B %') then
    raise exception 'Milestone 8B objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

create or replace function private.current_active_company_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  resolved_company_id uuid;
  membership_count integer;
begin
  if (select auth.uid()) is null then
    return null;
  end if;

  select min(cu.company_id::text)::uuid, count(*)::integer
  into resolved_company_id, membership_count
  from public.company_users cu
  join public.platform_users pu on pu.user_id = cu.user_id
  join public.companies c on c.id = cu.company_id
  where cu.user_id = (select auth.uid())
    and pu.account_type = 'company'
    and pu.account_status = 'active'
    and cu.status = 'active'
    and c.account_status = 'active';

  if membership_count = 0 then
    return null;
  end if;
  if membership_count <> 1 then
    raise exception 'Exactly one active company membership is required';
  end if;
  return resolved_company_id;
end;
$$;

revoke all on function private.current_active_company_id() from public, anon;
grant execute on function private.current_active_company_id() to authenticated;

create or replace function public.create_company_requirement(
  p_department text,
  p_job_role text,
  p_job_location text,
  p_required_headcount integer,
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
returns public.employer_requirements
language plpgsql
security definer
set search_path = ''
as $$
declare
  company_id_value uuid;
  company_record public.companies%rowtype;
  user_record public.platform_users%rowtype;
  created_requirement public.employer_requirements%rowtype;
begin
  company_id_value := private.current_active_company_id();
  if company_id_value is null then
    raise exception 'An active company account and membership are required';
  end if;
  if btrim(coalesce(p_department, '')) = '' or length(btrim(p_department)) > 160 then
    raise exception 'A valid department is required';
  end if;
  if btrim(coalesce(p_job_role, '')) = '' or length(btrim(p_job_role)) > 200 then
    raise exception 'A valid job role is required';
  end if;
  if btrim(coalesce(p_job_location, '')) = '' or length(btrim(p_job_location)) > 240 then
    raise exception 'A valid job location is required';
  end if;
  if p_required_headcount is null or p_required_headcount < 1 or p_required_headcount > 100000 then
    raise exception 'Required headcount must be between 1 and 100000';
  end if;
  if p_age_min is not null and p_age_max is not null and p_age_min > p_age_max then
    raise exception 'Minimum age cannot exceed maximum age';
  end if;
  if p_salary_min is not null and p_salary_max is not null and p_salary_min > p_salary_max then
    raise exception 'Minimum salary cannot exceed maximum salary';
  end if;
  if p_experience_requirement not in ('Fresher', 'Experienced', 'Both')
     or p_gender_preference not in ('Any', 'Male', 'Female')
     or p_canteen not in ('Yes', 'No', 'Not Applicable')
     or p_transport not in ('Yes', 'No', 'Not Applicable')
     or p_accommodation not in ('Yes', 'No', 'Not Applicable') then
    raise exception 'One or more controlled values are invalid';
  end if;

  select * into strict company_record from public.companies where id = company_id_value;
  select * into strict user_record from public.platform_users where user_id = (select auth.uid());

  insert into public.employer_requirements (
    company_name, contact_person, mobile, email, company_location,
    job_role, required_headcount, qualification, experience_requirement,
    gender_preference, salary_wage, shift_details, working_hours,
    accommodation, canteen, transport, additional_notes, consent, status,
    company_id, created_by_user_id, department, job_location, age_min,
    age_max, filled_positions, salary_min, salary_max, overtime_details,
    interview_location, interview_date, requirement_visibility, requirement_stage
  ) values (
    company_record.legal_name, coalesce(company_record.contact_person, user_record.display_name),
    coalesce(company_record.main_phone, user_record.mobile),
    coalesce(company_record.main_email, user_record.email),
    concat_ws(', ', nullif(company_record.city, ''), nullif(company_record.state, '')),
    btrim(p_job_role), p_required_headcount, nullif(btrim(coalesce(p_qualification, '')), ''),
    p_experience_requirement, p_gender_preference,
    case when p_salary_min is null and p_salary_max is null then null
         else concat_ws(' - ', p_salary_min::text, p_salary_max::text) end,
    nullif(btrim(coalesce(p_shift_details, '')), ''),
    nullif(btrim(coalesce(p_working_hours, '')), ''),
    p_accommodation, p_canteen, p_transport,
    nullif(btrim(coalesce(p_additional_notes, '')), ''), true, 'new',
    company_id_value, (select auth.uid()), btrim(p_department), btrim(p_job_location),
    p_age_min, p_age_max, 0, p_salary_min, p_salary_max,
    nullif(btrim(coalesce(p_overtime_details, '')), ''),
    nullif(btrim(coalesce(p_interview_location, '')), ''), p_interview_date,
    'private', 'draft'
  ) returning * into created_requirement;

  return created_requirement;
end;
$$;

create or replace function public.update_company_requirement(
  p_requirement_id uuid,
  p_department text,
  p_job_role text,
  p_job_location text,
  p_required_headcount integer,
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
returns public.employer_requirements
language plpgsql
security definer
set search_path = ''
as $$
declare
  company_id_value uuid;
  updated_requirement public.employer_requirements%rowtype;
begin
  company_id_value := private.current_active_company_id();
  if company_id_value is null then raise exception 'An active company account and membership are required'; end if;
  if btrim(coalesce(p_department, '')) = '' or length(btrim(p_department)) > 160
     or btrim(coalesce(p_job_role, '')) = '' or length(btrim(p_job_role)) > 200
     or btrim(coalesce(p_job_location, '')) = '' or length(btrim(p_job_location)) > 240 then
    raise exception 'Department, job role, and location are required';
  end if;
  if p_required_headcount is null or p_required_headcount < 1 or p_required_headcount > 100000 then raise exception 'Required headcount is invalid'; end if;
  if p_age_min is not null and p_age_max is not null and p_age_min > p_age_max then raise exception 'Minimum age cannot exceed maximum age'; end if;
  if p_salary_min is not null and p_salary_max is not null and p_salary_min > p_salary_max then raise exception 'Minimum salary cannot exceed maximum salary'; end if;
  if p_experience_requirement not in ('Fresher', 'Experienced', 'Both')
     or p_gender_preference not in ('Any', 'Male', 'Female')
     or p_canteen not in ('Yes', 'No', 'Not Applicable')
     or p_transport not in ('Yes', 'No', 'Not Applicable')
     or p_accommodation not in ('Yes', 'No', 'Not Applicable') then raise exception 'One or more controlled values are invalid'; end if;

  update public.employer_requirements
  set department = btrim(p_department), job_role = btrim(p_job_role), job_location = btrim(p_job_location),
      required_headcount = p_required_headcount, qualification = nullif(btrim(coalesce(p_qualification, '')), ''),
      experience_requirement = p_experience_requirement, gender_preference = p_gender_preference,
      age_min = p_age_min, age_max = p_age_max, salary_min = p_salary_min, salary_max = p_salary_max,
      salary_wage = case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ', p_salary_min::text, p_salary_max::text) end,
      shift_details = nullif(btrim(coalesce(p_shift_details, '')), ''), working_hours = nullif(btrim(coalesce(p_working_hours, '')), ''),
      overtime_details = nullif(btrim(coalesce(p_overtime_details, '')), ''), canteen = p_canteen,
      transport = p_transport, accommodation = p_accommodation,
      interview_location = nullif(btrim(coalesce(p_interview_location, '')), ''), interview_date = p_interview_date,
      additional_notes = nullif(btrim(coalesce(p_additional_notes, '')), '')
  where id = p_requirement_id and company_id = company_id_value and requirement_stage = 'draft'
  returning * into updated_requirement;
  if updated_requirement.id is null then raise exception 'Requirement was not found or is not editable'; end if;
  return updated_requirement;
end;
$$;

create or replace function public.close_company_requirement(p_requirement_id uuid)
returns public.employer_requirements
language plpgsql
security definer
set search_path = ''
as $$
declare
  company_id_value uuid;
  closed_requirement public.employer_requirements%rowtype;
begin
  company_id_value := private.current_active_company_id();
  if company_id_value is null then raise exception 'An active company account and membership are required'; end if;
  update public.employer_requirements
  set requirement_stage = case when requirement_stage = 'draft' then 'cancelled' else 'closed' end,
      requirement_visibility = 'private', closed_at = now(), status = 'closed'
  where id = p_requirement_id and company_id = company_id_value
    and requirement_stage in ('draft', 'open', 'on_hold')
  returning * into closed_requirement;
  if closed_requirement.id is null then raise exception 'Requirement was not found or cannot be closed'; end if;
  return closed_requirement;
end;
$$;

create or replace function public.set_company_requirement_stage(
  p_requirement_id uuid,
  p_requirement_stage text,
  p_requirement_visibility text
)
returns public.employer_requirements
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_requirement public.employer_requirements%rowtype;
begin
  if (select auth.uid()) is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_requirement_stage not in ('draft', 'open', 'on_hold', 'filled', 'closed', 'cancelled')
     or p_requirement_visibility not in ('private', 'assigned', 'public') then raise exception 'Invalid lifecycle value'; end if;
  update public.employer_requirements
  set requirement_stage = p_requirement_stage,
      requirement_visibility = p_requirement_visibility,
      published_at = case when p_requirement_stage = 'open' then coalesce(published_at, now()) else published_at end,
      closed_at = case when p_requirement_stage in ('filled', 'closed', 'cancelled') then coalesce(closed_at, now()) else null end,
      status = case when p_requirement_stage = 'filled' then 'fulfilled'
                    when p_requirement_stage in ('closed', 'cancelled') then 'closed'
                    when p_requirement_stage = 'open' then 'in_progress'
                    else status end
  where id = p_requirement_id and company_id is not null
  returning * into updated_requirement;
  if updated_requirement.id is null then raise exception 'Company requirement was not found'; end if;
  return updated_requirement;
end;
$$;

revoke all on function public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) from public, anon;
revoke all on function public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) from public, anon;
revoke all on function public.close_company_requirement(uuid) from public, anon;
revoke all on function public.set_company_requirement_stage(uuid,text,text) from public, anon;
grant execute on function public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) to authenticated;
grant execute on function public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamptz,text) to authenticated;
grant execute on function public.close_company_requirement(uuid) to authenticated;
grant execute on function public.set_company_requirement_stage(uuid,text,text) to authenticated;

create policy "M8B active company reads own requirements"
on public.employer_requirements for select to authenticated
using (
  company_id is not null
  and company_id = (select private.current_active_company_id())
);

-- Company writes are intentionally RPC-only. Existing M7 admin policies and the
-- narrow anonymous public INSERT policy remain unchanged. No DELETE policy exists.

commit;
