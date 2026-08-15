-- MILESTONE 7: additive multi-role platform architecture
-- MANUAL REVIEW REQUIRED. Do not run against Supabase until approved and backed up.
-- This migration preserves employer_requirements, candidates, admin_users, and their policies.

begin;

do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidates') is null
     or to_regclass('public.admin_users') is null then
    raise exception 'Milestone 5/6 prerequisite tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('private.set_updated_at()') is null then
    raise exception 'Milestone 5/6 private authorization or timestamp function is missing';
  end if;
  if to_regclass('public.platform_users') is not null
     or to_regclass('public.companies') is not null
     or to_regclass('public.company_users') is not null
     or to_regclass('public.contractors') is not null
     or to_regclass('public.contractor_users') is not null
     or to_regclass('public.requirement_contractors') is not null
     or to_regclass('public.candidate_applications') is not null
     or to_regclass('public.interviews') is not null
     or to_regclass('public.candidate_joinings') is not null
     or to_regclass('public.requirement_code_seq') is not null
     or to_regprocedure('private.assign_requirement_code()') is not null then
    raise exception 'Milestone 7 objects already exist; inspect partial/manual changes instead of re-running';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and ((table_name = 'candidates' and column_name = any (array[
          'user_id', 'profile_status', 'profile_completion_status',
          'current_employment_status', 'availability_status', 'verified_at'
        ]))
        or (table_name = 'employer_requirements' and column_name = any (array[
          'requirement_code', 'company_id', 'created_by_user_id', 'department',
          'job_location', 'age_min', 'age_max', 'filled_positions', 'salary_min',
          'salary_max', 'overtime_details', 'interview_location', 'interview_date',
          'requirement_visibility', 'requirement_stage', 'published_at', 'closed_at'
        ])))
  ) then
    raise exception 'Milestone 7 extension columns already exist; inspect database state before proceeding';
  end if;
  if exists (select 1 from pg_trigger where tgname = 'employer_requirements_assign_code') then
    raise exception 'Milestone 7 requirement-code trigger already exists; inspect database state before proceeding';
  end if;
end;
$$;

create table if not exists public.platform_users (
  user_id uuid primary key references auth.users(id) on delete restrict,
  account_type text not null check (account_type in ('company', 'contractor', 'candidate')),
  display_name text not null check (length(btrim(display_name)) between 1 and 160),
  mobile text check (mobile is null or mobile ~ '^[6-9][0-9]{9}$'),
  email text,
  account_status text not null default 'pending'
    check (account_status in ('pending', 'active', 'suspended', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null check (length(btrim(legal_name)) between 1 and 240),
  trade_name text,
  industry text,
  gstin text,
  cin text,
  website text,
  main_phone text,
  main_email text,
  address text,
  city text,
  district text,
  state text,
  pincode text check (pincode is null or pincode ~ '^[0-9]{6}$'),
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected')),
  account_status text not null default 'pending'
    check (account_status in ('pending', 'active', 'suspended', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_users (
  company_id uuid not null references public.companies(id) on delete restrict,
  user_id uuid not null references public.platform_users(user_id) on delete restrict,
  role text not null default 'recruiter'
    check (role in ('owner', 'hr_admin', 'recruiter', 'viewer')),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id, user_id)
);

create table if not exists public.contractors (
  id uuid primary key default gen_random_uuid(),
  agency_name text not null check (length(btrim(agency_name)) between 1 and 240),
  owner_name text,
  gstin text,
  esic_code text,
  epfo_code text,
  labour_license_number text,
  main_phone text,
  main_email text,
  address text,
  city text,
  district text,
  state text,
  operating_locations text[],
  workforce_capacity integer check (workforce_capacity is null or workforce_capacity >= 0),
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected')),
  account_status text not null default 'pending'
    check (account_status in ('pending', 'active', 'suspended', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.contractor_users (
  contractor_id uuid not null references public.contractors(id) on delete restrict,
  user_id uuid not null references public.platform_users(user_id) on delete restrict,
  role text not null default 'recruiter'
    check (role in ('owner', 'manager', 'recruiter', 'coordinator')),
  status text not null default 'pending'
    check (status in ('pending', 'active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (contractor_id, user_id)
);

-- Existing candidate registrations remain valid. Account linking is nullable and manual.
alter table public.candidates add column if not exists user_id uuid;
alter table public.candidates add column if not exists profile_status text not null default 'registered';
alter table public.candidates add column if not exists profile_completion_status text not null default 'incomplete';
alter table public.candidates add column if not exists current_employment_status text not null default 'unknown';
alter table public.candidates add column if not exists availability_status text not null default 'unknown';
alter table public.candidates add column if not exists verified_at timestamptz;

-- Existing public requirements remain valid. required_headcount remains the source of openings.
alter table public.employer_requirements add column if not exists requirement_code text;
alter table public.employer_requirements add column if not exists company_id uuid;
alter table public.employer_requirements add column if not exists created_by_user_id uuid;
alter table public.employer_requirements add column if not exists department text;
alter table public.employer_requirements add column if not exists job_location text;
alter table public.employer_requirements add column if not exists age_min integer;
alter table public.employer_requirements add column if not exists age_max integer;
alter table public.employer_requirements add column if not exists filled_positions integer not null default 0;
alter table public.employer_requirements add column if not exists salary_min numeric(12,2);
alter table public.employer_requirements add column if not exists salary_max numeric(12,2);
alter table public.employer_requirements add column if not exists overtime_details text;
alter table public.employer_requirements add column if not exists interview_location text;
alter table public.employer_requirements add column if not exists interview_date timestamptz;
alter table public.employer_requirements add column if not exists requirement_visibility text not null default 'private';
alter table public.employer_requirements add column if not exists requirement_stage text not null default 'draft';
alter table public.employer_requirements add column if not exists published_at timestamptz;
alter table public.employer_requirements add column if not exists closed_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'candidates_user_id_fkey') then
    alter table public.candidates add constraint candidates_user_id_fkey
      foreign key (user_id) references public.platform_users(user_id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'candidates_user_id_key') then
    alter table public.candidates add constraint candidates_user_id_key unique (user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'candidates_profile_status_check') then
    alter table public.candidates add constraint candidates_profile_status_check
      check (profile_status in ('registered', 'active', 'inactive', 'archived'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'candidates_profile_completion_status_check') then
    alter table public.candidates add constraint candidates_profile_completion_status_check
      check (profile_completion_status in ('incomplete', 'complete', 'review_required'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'candidates_current_employment_status_check') then
    alter table public.candidates add constraint candidates_current_employment_status_check
      check (current_employment_status in ('unemployed', 'employed', 'notice_period', 'unknown'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'candidates_availability_status_check') then
    alter table public.candidates add constraint candidates_availability_status_check
      check (availability_status in ('available', 'not_available', 'open_to_opportunities', 'unknown'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_requirement_code_key') then
    alter table public.employer_requirements add constraint employer_requirements_requirement_code_key unique (requirement_code);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_company_id_fkey') then
    alter table public.employer_requirements add constraint employer_requirements_company_id_fkey
      foreign key (company_id) references public.companies(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_created_by_user_id_fkey') then
    alter table public.employer_requirements add constraint employer_requirements_created_by_user_id_fkey
      foreign key (created_by_user_id) references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_age_range_check') then
    alter table public.employer_requirements add constraint employer_requirements_age_range_check
      check ((age_min is null or age_min between 16 and 75)
        and (age_max is null or age_max between 16 and 75)
        and (age_min is null or age_max is null or age_min <= age_max));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_filled_positions_check') then
    alter table public.employer_requirements add constraint employer_requirements_filled_positions_check
      check (filled_positions >= 0 and filled_positions <= required_headcount);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_salary_range_check') then
    alter table public.employer_requirements add constraint employer_requirements_salary_range_check
      check ((salary_min is null or salary_min >= 0)
        and (salary_max is null or salary_max >= 0)
        and (salary_min is null or salary_max is null or salary_min <= salary_max));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_visibility_check') then
    alter table public.employer_requirements add constraint employer_requirements_visibility_check
      check (requirement_visibility in ('private', 'assigned', 'public'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'employer_requirements_stage_check') then
    alter table public.employer_requirements add constraint employer_requirements_stage_check
      check (requirement_stage in ('draft', 'open', 'on_hold', 'filled', 'closed', 'cancelled'));
  end if;
end;
$$;

create sequence if not exists public.requirement_code_seq as bigint start with 1 increment by 1;
revoke all on sequence public.requirement_code_seq from anon, authenticated;

create or replace function private.assign_requirement_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.requirement_code is null then
    new.requirement_code := 'AAD-' || to_char(current_date, 'YYYY') || '-'
      || lpad(nextval('public.requirement_code_seq'::regclass)::text, 6, '0');
  end if;
  return new;
end;
$$;
revoke all on function private.assign_requirement_code() from public;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'employer_requirements_assign_code') then
    create trigger employer_requirements_assign_code
      before insert on public.employer_requirements
      for each row execute function private.assign_requirement_code();
  end if;
end;
$$;

create table if not exists public.requirement_contractors (
  id uuid primary key default gen_random_uuid(),
  requirement_id uuid not null references public.employer_requirements(id) on delete restrict,
  contractor_id uuid not null references public.contractors(id) on delete restrict,
  assigned_headcount integer not null check (assigned_headcount > 0),
  assignment_status text not null default 'assigned'
    check (assignment_status in ('assigned', 'accepted', 'declined', 'active', 'completed', 'cancelled')),
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  accepted_at timestamptz,
  closed_at timestamptz,
  internal_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (requirement_id, contractor_id),
  constraint requirement_contractors_id_requirement_key unique (id, requirement_id)
);

create table if not exists public.candidate_applications (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidates(id) on delete restrict,
  requirement_id uuid not null references public.employer_requirements(id) on delete restrict,
  requirement_contractor_id uuid,
  source_type text not null default 'direct'
    check (source_type in ('direct', 'contractor', 'admin', 'whatsapp', 'campus', 'referral')),
  application_status text not null default 'applied'
    check (application_status in ('interested', 'applied', 'screening', 'shortlisted', 'interview', 'selected', 'rejected', 'joining_pending', 'joined', 'left', 'cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (candidate_id, requirement_id),
  constraint candidate_applications_assignment_requirement_fkey
    foreign key (requirement_contractor_id, requirement_id)
    references public.requirement_contractors(id, requirement_id) on delete restrict,
  check (source_type <> 'contractor' or requirement_contractor_id is not null)
);

create table if not exists public.interviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.candidate_applications(id) on delete restrict,
  scheduled_at timestamptz,
  location text,
  mode text check (mode is null or mode in ('onsite', 'phone', 'video', 'other')),
  status text not null default 'scheduled'
    check (status in ('scheduled', 'attended', 'absent', 'rescheduled', 'completed', 'cancelled')),
  result text check (result is null or result in ('pending', 'selected', 'rejected', 'on_hold')),
  remarks text,
  internal_notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.candidate_joinings (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.candidate_applications(id) on delete restrict,
  expected_joining_date date,
  actual_joining_date date,
  joining_status text not null default 'pending'
    check (joining_status in ('pending', 'confirmed', 'joined', 'no_show', 'deferred', 'left', 'cancelled')),
  employee_code text,
  remarks text,
  internal_notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Reuse the existing timestamp function without replacing current triggers.
do $$
declare
  table_name text;
  trigger_name text;
begin
  foreach table_name in array array[
    'platform_users', 'companies', 'company_users', 'contractors', 'contractor_users',
    'requirement_contractors', 'candidate_applications', 'interviews', 'candidate_joinings'
  ] loop
    trigger_name := table_name || '_set_updated_at';
    if not exists (select 1 from pg_trigger where tgname = trigger_name) then
      execute format(
        'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
        trigger_name, table_name
      );
    end if;
  end loop;
end;
$$;

create index if not exists platform_users_account_type_status_idx on public.platform_users (account_type, account_status);
create index if not exists companies_account_status_idx on public.companies (account_status);
create index if not exists company_users_user_id_idx on public.company_users (user_id);
create index if not exists contractors_account_status_idx on public.contractors (account_status);
create index if not exists contractor_users_user_id_idx on public.contractor_users (user_id);
create index if not exists candidates_user_id_idx on public.candidates (user_id) where user_id is not null;
create index if not exists employer_requirements_company_id_idx on public.employer_requirements (company_id) where company_id is not null;
create index if not exists employer_requirements_stage_created_idx on public.employer_requirements (requirement_stage, created_at desc);
create index if not exists requirement_contractors_requirement_idx on public.requirement_contractors (requirement_id, assignment_status);
create index if not exists requirement_contractors_contractor_idx on public.requirement_contractors (contractor_id, assignment_status);
create index if not exists candidate_applications_candidate_idx on public.candidate_applications (candidate_id, created_at desc);
create index if not exists candidate_applications_requirement_idx on public.candidate_applications (requirement_id, application_status);
create index if not exists candidate_applications_status_created_idx on public.candidate_applications (application_status, created_at desc);
create index if not exists candidate_applications_assignment_idx on public.candidate_applications (requirement_contractor_id) where requirement_contractor_id is not null;
create index if not exists interviews_application_idx on public.interviews (application_id, scheduled_at desc);
create index if not exists candidate_joinings_status_idx on public.candidate_joinings (joining_status, created_at desc);

alter table public.platform_users enable row level security;
alter table public.companies enable row level security;
alter table public.company_users enable row level security;
alter table public.contractors enable row level security;
alter table public.contractor_users enable row level security;
alter table public.requirement_contractors enable row level security;
alter table public.candidate_applications enable row level security;
alter table public.interviews enable row level security;
alter table public.candidate_joinings enable row level security;

revoke all on public.platform_users from anon, authenticated;
revoke all on public.companies from anon, authenticated;
revoke all on public.company_users from anon, authenticated;
revoke all on public.contractors from anon, authenticated;
revoke all on public.contractor_users from anon, authenticated;
revoke all on public.requirement_contractors from anon, authenticated;
revoke all on public.candidate_applications from anon, authenticated;
revoke all on public.interviews from anon, authenticated;
revoke all on public.candidate_joinings from anon, authenticated;

grant select, insert, update on public.platform_users to authenticated;
grant select, insert, update on public.companies to authenticated;
grant select, insert, update on public.company_users to authenticated;
grant select, insert, update on public.contractors to authenticated;
grant select, insert, update on public.contractor_users to authenticated;
grant select, insert, update on public.requirement_contractors to authenticated;
grant select, insert, update on public.candidate_applications to authenticated;
grant select, insert, update on public.interviews to authenticated;
grant select, insert, update on public.candidate_joinings to authenticated;

-- Existing public INSERT grants are not changed. These new columns remain admin-managed.
grant update (user_id, profile_status, profile_completion_status, current_employment_status, availability_status, verified_at)
  on public.candidates to authenticated;
grant update (requirement_code, company_id, created_by_user_id, department, job_location, age_min, age_max,
  filled_positions, salary_min, salary_max, overtime_details, interview_location, interview_date,
  requirement_visibility, requirement_stage, published_at, closed_at)
  on public.employer_requirements to authenticated;

-- Only existing allowlisted Aadhyant admins receive access in Milestone 7.
create policy "M7 admins read platform users" on public.platform_users for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create platform users" on public.platform_users for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update platform users" on public.platform_users for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read companies" on public.companies for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create companies" on public.companies for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update companies" on public.companies for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read company users" on public.company_users for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create company users" on public.company_users for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update company users" on public.company_users for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read contractors" on public.contractors for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create contractors" on public.contractors for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update contractors" on public.contractors for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read contractor users" on public.contractor_users for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create contractor users" on public.contractor_users for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update contractor users" on public.contractor_users for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read requirement assignments" on public.requirement_contractors for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create requirement assignments" on public.requirement_contractors for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update requirement assignments" on public.requirement_contractors for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read applications" on public.candidate_applications for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create applications" on public.candidate_applications for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update applications" on public.candidate_applications for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read interviews" on public.interviews for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create interviews" on public.interviews for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update interviews" on public.interviews for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "M7 admins read joinings" on public.candidate_joinings for select to authenticated using ((select private.is_admin()));
create policy "M7 admins create joinings" on public.candidate_joinings for insert to authenticated with check ((select private.is_admin()));
create policy "M7 admins update joinings" on public.candidate_joinings for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

-- Intentionally absent in Milestone 7:
-- * anon SELECT/UPDATE/DELETE grants or policies
-- * company, contractor, or candidate policies
-- * public SELECT on employer_requirements or candidates
-- * DELETE grants or policies
-- Their login/onboarding milestones must add narrowly scoped ownership policies after testing.

commit;
