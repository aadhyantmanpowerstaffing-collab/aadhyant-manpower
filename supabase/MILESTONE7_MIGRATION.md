# Milestone 7 Migration Review and Recovery Guide

## Status

**Do not run this migration against the live Supabase project until the architecture and SQL have been manually reviewed and approved.** Codex has not executed it remotely.

Milestone 7A validation status: **static-only**. Supabase CLI, Docker, local PostgreSQL, and a PostgreSQL SQL parser were not available in the workspace. Baseline execution, migration execution, fixtures, foreign-key failure tests, trigger execution, and live RLS role simulation therefore remain unverified. Production application is not recommended until the complete file and RLS matrix pass in a disposable Supabase environment.

Migration file:

```text
supabase/migrations/007_platform_roles_architecture.sql
```

The file is a one-time migration wrapped in an explicit `BEGIN` / `COMMIT` transaction. A SQL error should roll back the whole migration. Its preflight block deliberately stops if Milestone 7 tables, key extension columns, the sequence, or the code function already exist; do not treat that failure as permission to bypass the check.

## Prerequisites

Before applying in a later approved milestone:

1. Confirm `supabase/schema.sql` has already been applied successfully.
2. Confirm `admin_users`, `employer_requirements`, and `candidates` exist.
3. Confirm `private.is_admin()` and `private.set_updated_at()` exist.
4. Confirm current employer/candidate public inserts and admin dashboard access work.
5. Confirm no object from this migration already exists from a partial/manual experiment. The migration will fail clearly if representative Milestone 7 objects are detected.
6. Review every new table, constraint, grant, function, trigger, and policy.
7. Take a verified Supabase database backup before execution.
8. Schedule a maintenance window and retain the exact pre-migration schema snapshot.

## Additive changes

The migration creates:

- `platform_users`
- `companies`
- `company_users`
- `contractors`
- `contractor_users`
- `requirement_contractors`
- `candidate_applications`
- `interviews`
- `candidate_joinings`
- `requirement_code_seq`
- `private.assign_requirement_code()` and an INSERT trigger
- indexes, updated-at triggers, RLS, and admin-only policies

It extends, without renaming or removing fields:

- `candidates`: nullable Auth link and profile lifecycle fields
- `employer_requirements`: nullable company/job fields, requirement lifecycle fields, and future-safe structured values

Existing rows are not deleted, renamed, or automatically linked. Existing requirement codes remain null. Existing public form column grants and policies are not replaced.

Contractor-sourced applications use a composite foreign key so `requirement_contractor_id` and `requirement_id` must refer to the same assignment/requirement pair.

## Manual preflight queries

Run read-only checks before any approved execution:

```sql
select to_regclass('public.admin_users'),
       to_regclass('public.employer_requirements'),
       to_regclass('public.candidates');

select to_regprocedure('private.is_admin()'),
       to_regprocedure('private.set_updated_at()');

select schemaname, tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('admin_users', 'employer_requirements', 'candidates')
order by tablename, policyname;
```

Record baseline counts without exporting personal data:

```sql
select count(*) as employer_requirement_count from public.employer_requirements;
select count(*) as candidate_count from public.candidates;
```

## Expected post-migration validation

After an explicitly approved future application, validate:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'platform_users', 'companies', 'company_users', 'contractors', 'contractor_users',
    'requirement_contractors', 'candidate_applications', 'interviews', 'candidate_joinings'
  )
order by table_name;

select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in (
    'platform_users', 'companies', 'company_users', 'contractors', 'contractor_users',
    'requirement_contractors', 'candidate_applications', 'interviews', 'candidate_joinings'
  )
order by tablename;

select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public' and policyname like 'M7 %'
order by tablename, policyname;
```

Expected security properties:

- Anonymous users have no privileges on new tables.
- Authenticated non-admin users have grants but no matching RLS policy, so access is denied.
- Existing allowlisted admins can SELECT/INSERT/UPDATE new tables.
- No browser role can DELETE new operational data.
- Existing anonymous employer/candidate INSERTs still succeed.
- Existing anonymous SELECT/UPDATE/DELETE attempts still fail.
- Existing Admin Dashboard still reads and updates its original fields.

Re-run baseline counts and confirm they are unchanged by the migration itself.

Confirm assignment/application integrity in a disposable environment: a contractor assignment for requirement A must not be accepted by an application for requirement B.

## Requirement-code validation

Do not create a live test requirement merely to inspect the trigger. In a disposable/local Supabase environment, verify concurrent inserts produce distinct codes matching:

```text
AAD-YYYY-NNNNNN
```

The UUID remains the primary key. The sequence is globally increasing and does not reset each year. Existing rows remain null unless a later reviewed backfill is approved.

## Public-form regression checklist

After a future approved migration in a safe environment:

1. Submit one authorized employer test requirement through the public flow.
2. Submit one authorized candidate registration through the public flow.
3. Confirm both arrive in the existing Admin Dashboard.
4. Confirm public SELECT, UPDATE, and DELETE remain denied.
5. Confirm the new requirement receives a code while no new platform fields are required from the old form.

## Recovery and rollback considerations

This migration is intentionally additive. Recovery should not begin by dropping objects.

If a problem appears:

1. Stop any new platform feature rollout.
2. Keep the existing public forms and Admin Dashboard on their current columns.
3. If the SQL Editor reports an error before `COMMIT`, confirm the transaction rolled back and inspect the first error.
4. Do not rerun blindly. Inventory tables, columns, functions, triggers, policies, and sequence state first.
5. Revoke access to new tables or disable new policies if a committed migration later proves unsafe.
6. Diagnose and correct the forward migration with a reviewed follow-up migration.
7. Restore from the verified backup only if existing data integrity was affected.

Do not run a blanket rollback script. New objects may contain operational history by the time a rollback is considered. Removing a table, column, constraint, trigger, policy, or sequence requires a separate inventory confirming that it is unused and contains no required data. Any eventual removal must be explicitly reviewed, backed up, and executed manually.

## Re-run behavior

This migration is intended to run exactly once. `IF NOT EXISTS` is used for additive object/column syntax, but the preflight guard and uniquely named policies intentionally make a completed or partially manual re-run stop rather than silently accepting an unknown schema. Because the reviewed file runs in one transaction, ordinary statement failure should leave no partial committed objects. If the client disconnects or an operator manually executes fragments outside the transaction, inspect state and prepare a reviewed corrective migration instead of rerunning the complete file.

## Approval gate

The migration should be applied only after:

- architecture approval;
- SQL review by someone responsible for the Supabase project;
- backup verification;
- disposable-environment testing;
- RLS tests for anonymous, non-admin authenticated, and admin sessions;
- explicit authorization to modify the live project.
