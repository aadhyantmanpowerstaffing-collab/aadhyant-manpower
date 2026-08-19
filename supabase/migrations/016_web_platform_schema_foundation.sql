-- W1: additive schema foundation for internal staff, candidate preferences,
-- application stage history, and future audited platform workflows.

begin;

do $$
begin
  if to_regclass('public.admin_users') is null
     or to_regclass('public.candidates') is null
     or to_regclass('public.candidate_applications') is null then
    raise exception 'W1 prerequisite tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('private.set_updated_at()') is null
     or to_regprocedure('public.get_company_requirements()') is null
     or to_regprocedure('public.get_staffing_partner_assignments()') is null then
    raise exception 'W1 prerequisite authorization or migration 015 functions are missing';
  end if;
  if to_regclass('public.staff_profiles') is not null
     or to_regclass('public.staff_roles') is not null
     or to_regclass('public.candidate_preferences') is not null
     or to_regclass('public.application_stages') is not null
     or to_regclass('public.application_stage_history') is not null
     or to_regclass('public.audit_logs') is not null
     or to_regprocedure('private.record_application_stage_history()') is not null then
    raise exception 'W1 objects already exist; inspect partial/manual changes instead of re-running';
  end if;
end;
$$;

create table public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) between 1 and 160),
  status text not null default 'active' check (status in ('active', 'suspended', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff_roles (
  user_id uuid not null references public.staff_profiles(user_id) on delete restrict,
  role text not null check (role in ('super_admin', 'admin', 'recruiter', 'operations', 'viewer')),
  status text not null default 'active' check (status in ('active', 'revoked')),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.candidate_preferences (
  candidate_id uuid primary key references public.candidates(id) on delete restrict,
  preferred_locations text[] not null default '{}',
  preferred_job_roles text[] not null default '{}',
  expected_salary_min numeric(12,2),
  expected_salary_max numeric(12,2),
  preferred_shift text,
  preferred_working_hours text,
  accommodation_required boolean,
  transport_required boolean,
  immediate_joining boolean,
  joining_availability_date date,
  source text not null default 'admin' check (source in ('admin', 'candidate', 'whatsapp', 'migration', 'system')),
  source_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidate_preferences_salary_range_check check (
    (expected_salary_min is null or expected_salary_min >= 0)
    and (expected_salary_max is null or expected_salary_max >= 0)
    and (expected_salary_min is null or expected_salary_max is null or expected_salary_min <= expected_salary_max)
  ),
  constraint candidate_preferences_joining_check check (
    immediate_joining is distinct from true or joining_availability_date is null
  ),
  constraint candidate_preferences_source_reference_length_check check (
    source_reference is null or length(source_reference) <= 500
  )
);

create table public.application_stages (
  stage text primary key,
  stage_order smallint not null unique check (stage_order > 0),
  category text not null check (category in ('active', 'success', 'exception', 'legacy')),
  is_terminal boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.application_stages(stage, stage_order, category, is_terminal) values
  ('new_lead', 10, 'active', false),
  ('registered', 20, 'active', false),
  ('interested', 30, 'active', false),
  ('applied', 40, 'active', false),
  ('screening', 50, 'active', false),
  ('interview_scheduled', 60, 'active', false),
  ('interview_attended', 70, 'active', false),
  ('selected', 80, 'active', false),
  ('joining_pending', 90, 'active', false),
  ('joined', 100, 'success', false),
  ('active', 110, 'success', false),
  ('rejected', 120, 'exception', true),
  ('no_show', 130, 'exception', true),
  ('withdrawn', 140, 'exception', true),
  ('left', 150, 'exception', true),
  -- Existing candidate_applications values remain recognized until W4 performs
  -- an explicitly reviewed status-contract migration.
  ('shortlisted', 160, 'legacy', false),
  ('interview', 170, 'legacy', false),
  ('cancelled', 180, 'legacy', true);

create table public.application_stage_history (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.candidate_applications(id) on delete restrict,
  from_stage text references public.application_stages(stage) on delete restrict,
  to_stage text not null references public.application_stages(stage) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  source text not null check (source in ('admin', 'company', 'contractor', 'candidate', 'whatsapp', 'automation', 'migration', 'system', 'database')),
  reason text,
  correlation_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  constraint application_stage_history_transition_check check (from_stage is null or from_stage <> to_stage),
  constraint application_stage_history_reason_length_check check (reason is null or length(reason) <= 2000)
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_type text not null check (actor_type in ('staff', 'company', 'contractor', 'candidate', 'anonymous', 'system', 'service', 'migration')),
  action text not null check (length(btrim(action)) between 1 and 160),
  entity_type text not null check (length(btrim(entity_type)) between 1 and 160),
  entity_id uuid,
  source text not null check (source in ('admin', 'company', 'contractor', 'candidate', 'public', 'whatsapp', 'automation', 'migration', 'system')),
  correlation_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

alter table public.candidate_applications
  add column source_reference text,
  add column correlation_id uuid;

alter table public.candidate_applications
  add constraint candidate_applications_source_reference_length_check
  check (source_reference is null or length(source_reference) <= 500);

create function private.record_application_stage_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.application_stage_history(
      application_id, from_stage, to_stage, actor_user_id, source, correlation_id
    ) values (
      new.id, null, new.application_status, (select auth.uid()), 'database', new.correlation_id
    );
  elsif new.application_status is distinct from old.application_status then
    insert into public.application_stage_history(
      application_id, from_stage, to_stage, actor_user_id, source, correlation_id
    ) values (
      new.id, old.application_status, new.application_status,
      (select auth.uid()), 'database', new.correlation_id
    );
  end if;
  return new;
end;
$$;

revoke all on function private.record_application_stage_history() from public, anon, authenticated;

create trigger candidate_applications_record_stage_history
  after insert or update of application_status on public.candidate_applications
  for each row execute function private.record_application_stage_history();

create trigger staff_profiles_set_updated_at before update on public.staff_profiles
  for each row execute function private.set_updated_at();
create trigger staff_roles_set_updated_at before update on public.staff_roles
  for each row execute function private.set_updated_at();
create trigger candidate_preferences_set_updated_at before update on public.candidate_preferences
  for each row execute function private.set_updated_at();

create index staff_profiles_status_idx on public.staff_profiles(status);
create index staff_roles_role_status_idx on public.staff_roles(role, status);
create index candidate_preferences_locations_gin_idx on public.candidate_preferences using gin(preferred_locations);
create index candidate_preferences_job_roles_gin_idx on public.candidate_preferences using gin(preferred_job_roles);
create index application_stage_history_application_created_idx
  on public.application_stage_history(application_id, created_at desc);
create index application_stage_history_correlation_idx
  on public.application_stage_history(correlation_id) where correlation_id is not null;
create index audit_logs_entity_created_idx on public.audit_logs(entity_type, entity_id, created_at desc);
create index audit_logs_actor_created_idx on public.audit_logs(actor_user_id, created_at desc)
  where actor_user_id is not null;
create index audit_logs_correlation_idx on public.audit_logs(correlation_id)
  where correlation_id is not null;
create index candidate_applications_correlation_idx on public.candidate_applications(correlation_id)
  where correlation_id is not null;

alter table public.staff_profiles enable row level security;
alter table public.staff_roles enable row level security;
alter table public.candidate_preferences enable row level security;
alter table public.application_stages enable row level security;
alter table public.application_stage_history enable row level security;
alter table public.audit_logs enable row level security;

revoke all on public.staff_profiles from anon, authenticated;
revoke all on public.staff_roles from anon, authenticated;
revoke all on public.candidate_preferences from anon, authenticated;
revoke all on public.application_stages from anon, authenticated;
revoke all on public.application_stage_history from anon, authenticated;
revoke all on public.audit_logs from anon, authenticated;

grant select, insert, update on public.staff_profiles to authenticated;
grant select, insert, update on public.staff_roles to authenticated;
grant select, insert, update on public.candidate_preferences to authenticated;
grant select on public.application_stages to authenticated;
grant select on public.application_stage_history to authenticated;
grant select on public.audit_logs to authenticated;
grant update(source_reference, correlation_id) on public.candidate_applications to authenticated;

create policy "W1 admins read staff profiles" on public.staff_profiles for select to authenticated
  using ((select private.is_admin()));
create policy "W1 admins create staff profiles" on public.staff_profiles for insert to authenticated
  with check ((select private.is_admin()));
create policy "W1 admins update staff profiles" on public.staff_profiles for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "W1 admins read staff roles" on public.staff_roles for select to authenticated
  using ((select private.is_admin()));
create policy "W1 admins create staff roles" on public.staff_roles for insert to authenticated
  with check ((select private.is_admin()));
create policy "W1 admins update staff roles" on public.staff_roles for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "W1 admins read candidate preferences" on public.candidate_preferences for select to authenticated
  using ((select private.is_admin()));
create policy "W1 admins create candidate preferences" on public.candidate_preferences for insert to authenticated
  with check ((select private.is_admin()));
create policy "W1 admins update candidate preferences" on public.candidate_preferences for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

create policy "W1 admins read application stages" on public.application_stages for select to authenticated
  using ((select private.is_admin()));
create policy "W1 admins read application stage history" on public.application_stage_history for select to authenticated
  using ((select private.is_admin()));
create policy "W1 admins read audit logs" on public.audit_logs for select to authenticated
  using ((select private.is_admin()));

-- No INSERT policy exists for history/audit tables. Stage history writes occur
-- only through the narrow trigger. Audit insertion is intentionally deferred to
-- future domain-specific server/RPC functions; browsers cannot forge entries.
-- No company, contractor, candidate, or anonymous policy is introduced.

commit;
