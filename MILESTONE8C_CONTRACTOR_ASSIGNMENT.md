# Milestone 8C — Contractor Onboarding and Requirement Assignment

## Scope

Milestone 8C adds staffing-partner registration, approval, portal access, and controlled assignment of existing Company requirements. It does not add candidate submission, interviews, joining, payroll, attendance, compliance processing, or billing.

## Account lifecycle

Supabase Auth signup metadata is processed by `private.handle_contractor_signup()`. The transaction creates exactly one `platform_users` row (`account_type = contractor`), one `contractors` row, and one owner `contractor_users` membership. All three begin as `pending`.

An approved Aadhyant Admin calls `public.set_contractor_account_status()`. The guarded RPC synchronizes the platform account, contractor account, and owner memberships. Supported account states remain `pending`, `active`, `suspended`, and `rejected`; membership uses the existing `pending`, `active`, and `suspended` values. Only an active platform account, contractor, and membership can enter the assignment workspace.

## Assignment lifecycle

The existing `requirement_contractors` table is reused. The lifecycle is:

`assigned` → contractor `accepted` → admin `active` (shown as **In Progress**) → admin `completed`

An `assigned` row may instead become `declined`. Admin may cancel `assigned`, `accepted`, or `active` work. Assignment rows are never deleted. `accepted_at`, `declined_at`, and `closed_at` preserve response and closure history.

## Headcount allocation rule

Allocatable headcount is:

`required_headcount - filled_positions - SUM(targets in assigned/accepted/active)`

Declined, cancelled, and completed assignments do not reserve sourcing capacity. The admin assignment RPC requires a positive target, locks per requirement with a transaction advisory lock, locks the requirement row, and recalculates the allocation in the database. This prevents concurrent requests from exceeding the open balance.

## Access control and privacy

- Anonymous, Candidate, Company, pending Contractor, suspended Contractor, and rejected Contractor sessions cannot read contractor or assignment workspace data.
- An active Contractor can read only its own contractor profile, membership, assignment rows, and requirements reachable through an explicit assignment.
- `requirement_visibility = public` does not grant Contractor operational access.
- Contractor response is RPC-only. Contractors cannot change the requirement, contractor, target, assigning admin, internal note, ownership, filled positions, or timestamps.
- Company users receive no Contractor profile or assignment access in this milestone.
- Approved Admin users retain the existing M7 administration policy and use guarded RPCs for account and assignment operations.
- Every new `SECURITY DEFINER` function uses `search_path = ''`, schema-qualified objects, `auth.uid()` checks, lifecycle validation, and restricted grants.

## User workflows

### Contractor

1. Register through `/contractor/register.html` and confirm email when Auth requires it.
2. Log in and see the pending, suspended, or rejected gate until active.
3. Once active, open `/contractor/assignments.html`.
4. Review only explicitly assigned requirements and accept or decline a new assignment.
5. Track Assigned, Accepted, In Progress, Completed, Declined, or Cancelled state.

### Admin

1. Review the **Staffing Partners** tab and activate, suspend, or reject an account.
2. Open a Company Requirement and choose **Assign Staffing Partner**.
3. Select an active partner, enter a target within the displayed remaining allocation, and optionally add an internal note.
4. Review responses, cancel eligible work, or move Accepted work to In Progress and then Completed.

## Local validation

The migration was applied after `schema.sql` and migrations 007–009 to the disposable Docker-backed stack at `127.0.0.1:54321` (database port `54322`). Fake local identities covered Admin, two active Companies, two active Contractors, pending and suspended Contractors, and a Candidate.

Validated behavior includes atomic onboarding, account gates, admin activation, assignment eligibility, positive targets, closed-requirement denial, allocation limits, concurrent over-allocation prevention, system-owned fields, cross-contractor isolation, unassigned-requirement denial, accept/decline timestamps, lifecycle guards, no Contractor delete, admin-only operations, Company 8A/8B database regressions, and anonymous Employer/Candidate insert regressions.

Authenticated Chrome validation exercised registration, pending gating, Admin activation, assignment creation, Contractor login/profile, assignment detail and acceptance, refresh persistence, Contractor B isolation, suspended gating, Admin review, and transition to In Progress. Company Requirements and Admin views were checked at 360, 390, 768, 1024, and 1440 pixels with no page-level overflow or unexplained console, runtime, network, asset, CSP, or CORS errors.

## Production read-only preflight SQL

Run this in the Production Supabase SQL Editor before migration 010. Stop if any M8C function, policy, column, or trigger already exists, or if the prerequisite tables are missing.

```sql
select
  to_regclass('public.contractors') as contractors,
  to_regclass('public.contractor_users') as contractor_users,
  to_regclass('public.requirement_contractors') as requirement_contractors,
  to_regclass('public.employer_requirements') as employer_requirements;

select
  to_regprocedure('private.handle_contractor_signup()') as handle_contractor_signup,
  to_regprocedure('private.current_active_contractor_id()') as current_active_contractor_id,
  to_regprocedure('public.set_contractor_account_status(uuid,text)') as set_contractor_account_status,
  to_regprocedure('public.assign_requirement_contractor(uuid,uuid,integer,text)') as assign_requirement_contractor,
  to_regprocedure('public.respond_requirement_assignment(uuid,text,text)') as respond_requirement_assignment,
  to_regprocedure('public.set_requirement_assignment_status(uuid,text)') as set_requirement_assignment_status;

select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'contractors' and column_name in
      ('website','pincode','manpower_categories','onboarding_notes','onboarding_consent_at'))
    or
    (table_name = 'requirement_contractors' and column_name in
      ('declined_at','response_notes'))
  )
order by table_name, column_name;

select event_object_schema, event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_name = 'on_auth_user_created_contractor_onboarding';

select schemaname, tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public' and policyname like 'M8C%'
order by tablename, policyname;
```

Expected preflight: all four tables are present; every function result is `NULL`; the column, trigger, and policy queries return zero rows.

## Manual production migration procedure

1. Confirm the checked-out file is `supabase/migrations/010_contractor_assignment_rls.sql` and verify its documented SHA-256 immediately before use.
2. Run the read-only preflight above in the Production SQL Editor and save the results.
3. Stop if the result differs from the expected clean preflight. Do not rerun migration 007, 008, or 009.
4. Open migration 010 locally, copy its complete contents from the first comment through the final `commit;`, and paste it into a new Production SQL Editor query.
5. Review the target project name, then run the entire script once. Do not select or run a fragment.
6. If any statement errors, stop. The transaction must roll back; capture the complete error before investigating.
7. Run the post-migration verification below. Do not register a production test Contractor as part of migration verification.

## Post-migration verification SQL

```sql
select
  to_regprocedure('private.handle_contractor_signup()') as handle_contractor_signup,
  to_regprocedure('private.current_active_contractor_id()') as current_active_contractor_id,
  to_regprocedure('public.set_contractor_account_status(uuid,text)') as set_contractor_account_status,
  to_regprocedure('public.assign_requirement_contractor(uuid,uuid,integer,text)') as assign_requirement_contractor,
  to_regprocedure('public.respond_requirement_assignment(uuid,text,text)') as respond_requirement_assignment,
  to_regprocedure('public.set_requirement_assignment_status(uuid,text)') as set_requirement_assignment_status;

select event_object_schema, event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_name = 'on_auth_user_created_contractor_onboarding';

select tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public' and policyname like 'M8C%'
order by tablename, policyname;

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'contractors' and column_name in
      ('website','pincode','manpower_categories','onboarding_notes','onboarding_consent_at'))
    or
    (table_name = 'requirement_contractors' and column_name in
      ('declined_at','response_notes'))
  )
order by table_name, column_name;

select
  (select count(*) from public.employer_requirements) as requirements,
  (select count(*) from public.contractors) as contractors,
  (select count(*) from public.contractor_users) as contractor_memberships,
  (select count(*) from public.requirement_contractors) as assignments;
```

Expected verification: six functions, one enabled Auth trigger, five M8C policies, all seven additive columns, and unchanged application-row counts.

## Recovery notes

Migration 010 is transactional and rejects an accidental second run before changing data. If execution errors before `commit`, do not attempt partial repairs; confirm the new objects are absent and diagnose the exact error. After a successful production commit, do not improvise a destructive rollback: disable the unreleased frontend if necessary, preserve contractor and assignment history, and prepare a separately reviewed forward recovery migration.

## Frontend deployment checklist

1. Apply and verify migration 010 manually before exposing the Contractor routes.
2. Review explicit changed files, browser-safe `config.js`, CNAME, and staged secret scan.
3. Commit and push only through the separately authorized release process.
4. Verify `/contractor/register.html`, `/contractor/login.html`, `/contractor/`, `/contractor/assignments.html`, `/admin/login.html`, and `/admin/` over HTTPS.
5. Confirm live code uses the production publishable/anon configuration and no localhost or privileged key.
6. Run the production Contractor signup/approval/assignment smoke test only under a separate explicit instruction.
