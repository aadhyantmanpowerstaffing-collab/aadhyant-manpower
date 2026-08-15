-- Aadhyant Manpower & Staffing
-- Supabase schema, constraints, grants, and Row Level Security policies.
-- Run this file in a new Supabase project's SQL Editor as a trusted project owner.

create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.employer_requirements (
  id uuid primary key default gen_random_uuid(),
  company_name text not null check (length(btrim(company_name)) between 1 and 200),
  contact_person text not null check (length(btrim(contact_person)) between 1 and 160),
  mobile text not null check (mobile ~ '^[6-9][0-9]{9}$'),
  email text,
  company_location text not null check (length(btrim(company_location)) between 1 and 300),
  job_role text not null check (length(btrim(job_role)) between 1 and 200),
  required_headcount integer not null check (required_headcount > 0),
  qualification text,
  iti_trade text,
  experience_requirement text check (experience_requirement is null or experience_requirement in ('Fresher', 'Experienced', 'Both')),
  gender_preference text check (gender_preference is null or gender_preference in ('Any', 'Male', 'Female')),
  salary_wage text,
  shift_details text,
  working_hours text,
  expected_joining_date date,
  accommodation text check (accommodation is null or accommodation in ('Yes', 'No', 'Not Applicable')),
  canteen text check (canteen is null or canteen in ('Yes', 'No', 'Not Applicable')),
  transport text check (transport is null or transport in ('Yes', 'No', 'Not Applicable')),
  additional_notes text,
  internal_notes text,
  consent boolean not null check (consent = true),
  status text not null default 'new' check (status in ('new', 'contacted', 'in_progress', 'fulfilled', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.candidates (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(btrim(full_name)) between 1 and 160),
  age integer not null check (age between 16 and 75),
  gender text not null check (gender in ('Male', 'Female', 'Other / Prefer not to say')),
  mobile text not null check (mobile ~ '^[6-9][0-9]{9}$'),
  whatsapp_number text check (whatsapp_number is null or whatsapp_number ~ '^[6-9][0-9]{9}$'),
  current_location text not null check (length(btrim(current_location)) between 1 and 200),
  district text not null check (length(btrim(district)) between 1 and 160),
  state text not null check (length(btrim(state)) between 1 and 160),
  highest_qualification text not null check (highest_qualification in ('Below 10th', '10th', '12th', 'ITI', 'Diploma', 'Graduate', 'Post Graduate', 'Other')),
  specialization text,
  candidate_type text not null check (candidate_type in ('Fresher', 'Experienced')),
  total_experience text,
  previous_job_role text,
  interview_available text not null check (interview_available in ('Yes', 'No')),
  preferred_job_location text,
  additional_information text,
  internal_notes text,
  consent boolean not null check (consent = true),
  status text not null default 'new' check (status in ('new', 'contacted', 'shortlisted', 'interview', 'selected', 'joined', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists employer_requirements_created_at_idx on public.employer_requirements (created_at desc);
create index if not exists employer_requirements_status_idx on public.employer_requirements (status);
create index if not exists candidates_created_at_idx on public.candidates (created_at desc);
create index if not exists candidates_status_idx on public.candidates (status);
create index if not exists candidates_mobile_idx on public.candidates (mobile);

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = (select auth.uid())
  );
$$;

revoke all on function private.is_admin() from public;
grant usage on schema private to authenticated;
grant execute on function private.is_admin() to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public;

drop trigger if exists employer_requirements_set_updated_at on public.employer_requirements;
create trigger employer_requirements_set_updated_at
before update on public.employer_requirements
for each row execute function private.set_updated_at();

drop trigger if exists candidates_set_updated_at on public.candidates;
create trigger candidates_set_updated_at
before update on public.candidates
for each row execute function private.set_updated_at();

alter table public.admin_users enable row level security;
alter table public.employer_requirements enable row level security;
alter table public.candidates enable row level security;

revoke all on public.admin_users from anon, authenticated;
revoke all on public.employer_requirements from anon, authenticated;
revoke all on public.candidates from anon, authenticated;

grant select on public.admin_users to authenticated;

grant insert (
  company_name, contact_person, mobile, email, company_location, job_role,
  required_headcount, qualification, iti_trade, experience_requirement,
  gender_preference, salary_wage, shift_details, working_hours,
  expected_joining_date, accommodation, canteen, transport,
  additional_notes, consent
) on public.employer_requirements to anon;

grant insert (
  full_name, age, gender, mobile, whatsapp_number, current_location,
  district, state, highest_qualification, specialization, candidate_type,
  total_experience, previous_job_role, interview_available,
  preferred_job_location, additional_information, consent
) on public.candidates to anon;

grant select on public.employer_requirements to authenticated;
grant select on public.candidates to authenticated;
grant update (status, internal_notes) on public.employer_requirements to authenticated;
grant update (status, internal_notes) on public.candidates to authenticated;

drop policy if exists "Admin can verify own membership" on public.admin_users;
create policy "Admin can verify own membership"
on public.admin_users for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Public can submit employer requirements" on public.employer_requirements;
create policy "Public can submit employer requirements"
on public.employer_requirements for insert
to anon
with check (consent = true and status = 'new');

drop policy if exists "Admins can read employer requirements" on public.employer_requirements;
create policy "Admins can read employer requirements"
on public.employer_requirements for select
to authenticated
using ((select private.is_admin()));

drop policy if exists "Admins can update employer workflow" on public.employer_requirements;
create policy "Admins can update employer workflow"
on public.employer_requirements for update
to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

drop policy if exists "Public can submit candidate registrations" on public.candidates;
create policy "Public can submit candidate registrations"
on public.candidates for insert
to anon
with check (consent = true and status = 'new');

drop policy if exists "Admins can read candidate registrations" on public.candidates;
create policy "Admins can read candidate registrations"
on public.candidates for select
to authenticated
using ((select private.is_admin()));

drop policy if exists "Admins can update candidate workflow" on public.candidates;
create policy "Admins can update candidate workflow"
on public.candidates for update
to authenticated
using ((select private.is_admin()))
with check ((select private.is_admin()));

-- No INSERT policy exists for admin_users. Add the first approved admin manually:
-- insert into public.admin_users (user_id) values ('AUTH-USER-UUID-HERE');
-- No DELETE policies or DELETE grants are created in this milestone.
