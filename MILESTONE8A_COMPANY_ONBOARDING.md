# Milestone 8A — Company Registration, Login, and Approval

## Scope

Milestone 8A adds Company account onboarding and approval only. Contractor login, Candidate login, and Company requirement CRUD remain intentionally unavailable.

The existing anonymous Employer Requirement and Candidate Registration forms continue to use their original tables and policies.

## Data and authorization design

Company identity continues to use the Milestone 7 model:

```text
auth.users
  -> platform_users (account_type = company, account_status = pending)
  -> company_users (role = owner, status = pending)
  -> companies (account_status = pending)
```

Migration `supabase/migrations/008_company_onboarding_rls.sql` adds four nullable onboarding fields to `companies`: `contact_person`, `workforce_size`, `onboarding_notes`, and `onboarding_consent_at`.

Company signup uses the `private.handle_company_signup()` Auth trigger. The browser supplies company details as signup metadata but never supplies a target user ID, role, or account status. The `SECURITY DEFINER` trigger:

- runs only when `onboarding_type` is exactly `company`;
- uses the newly inserted `auth.users.id` and email;
- validates required fields, consent, mobile, GSTIN, and workforce size;
- creates all three public rows atomically with pending status;
- creates one owner membership; and
- rejects a conflicting/duplicate account instead of creating another company.

This trigger-based design supports both immediate sessions and email-confirmation-required projects because onboarding occurs in the Auth user creation transaction. No company table receives a broad Company INSERT policy.

Admin approval uses `public.set_company_account_status(uuid, text)`. It verifies `auth.uid()` through `private.is_admin()` and synchronizes:

- `platform_users.account_status`;
- `companies.account_status` and verification status where applicable; and
- `company_users.status`.

Company users can read only their own `platform_users` row and owner membership. A company profile is readable only when the linked platform account and membership are both active. Company users receive no Company UPDATE, INSERT, DELETE, self-approval, or role-change policy.

## Account states

- `pending`: registration exists; approval message only; company profile is not exposed.
- `active`: company dashboard shell and own company profile are available.
- `suspended`: active content/profile access is denied; suspension message is shown.
- `rejected`: active content/profile access is denied; rejection message is shown.

No rejected or suspended record is deleted.

## Local validation

Milestone 8A was executed only against a disposable Docker-backed Supabase stack on loopback ports. Fake Auth identities and records were used.

Validated behavior includes:

- Auth signup and atomic pending company/profile/owner creation;
- duplicate and invalid onboarding rejection without partial Auth records;
- email-confirmation and immediate-session UI branches;
- anonymous denial and non-admin approval denial;
- self-activation, role-change, arbitrary user, and arbitrary membership denial;
- pending, active, suspended, and rejected access boundaries;
- Company A / Company B profile and membership isolation;
- approved-admin company reads and controlled state transitions;
- existing Admin login/read/update behavior;
- current public Employer and Candidate REST submissions;
- unauthenticated dashboard redirects and logout code paths;
- responsive widths at 360, 390, 768, 1024, and 1440 pixels; and
- browser runtime, console, and horizontal-overflow checks.

## Manual production procedure

Do not use `supabase link`, `db push`, or a remote CLI migration command for this milestone.

1. Confirm the Supabase SQL Editor is open on the intended production project.
2. Confirm migration 007 is present and production backups are current and verified.
3. Record baseline counts for `platform_users`, `companies`, and `company_users`.
4. Run the read-only preflight below. Stop if any result differs from the expectation.
5. Open `supabase/migrations/008_company_onboarding_rls.sql` locally.
6. Copy the entire file, including its single `BEGIN;` and final `COMMIT;`.
7. Paste it into a new Production SQL Editor query and execute the complete file once.
8. Stop on the first error. Do not rerun or execute fragments.
9. Run the post-migration verification queries below.
10. Perform an explicitly authorized fake Company signup and admin approval smoke test manually.

### Production preflight

```sql
select
  to_regclass('public.platform_users') as platform_users,
  to_regclass('public.companies') as companies,
  to_regclass('public.company_users') as company_users,
  to_regclass('public.admin_users') as admin_users,
  to_regprocedure('private.is_admin()') as is_admin;

select
  to_regprocedure('private.handle_company_signup()') as company_signup_function,
  to_regprocedure('public.set_company_account_status(uuid,text)') as company_status_function;

select tgname
from pg_trigger
where tgname = 'on_auth_user_created_company_onboarding';

select policyname
from pg_policies
where schemaname = 'public' and policyname like 'M8A %';

select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'companies'
  and column_name in (
    'contact_person', 'workforce_size', 'onboarding_notes', 'onboarding_consent_at'
  );

select
  (select count(*) from public.platform_users) as platform_user_count,
  (select count(*) from public.companies) as company_count,
  (select count(*) from public.company_users) as company_membership_count;
```

Expected: all Milestone 7 prerequisites are non-null; both Milestone 8A functions are null; the trigger, policy, and new-column queries return zero rows.

### Post-migration verification

```sql
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'companies'
  and column_name in (
    'contact_person', 'workforce_size', 'onboarding_notes', 'onboarding_consent_at'
  )
order by column_name;

select n.nspname, p.proname, p.prosecdef, p.proconfig
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where (n.nspname, p.proname) in (
  ('private', 'handle_company_signup'),
  ('public', 'set_company_account_status')
)
order by n.nspname, p.proname;

select tgname, tgenabled
from pg_trigger
where tgname = 'on_auth_user_created_company_onboarding';

select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public' and policyname like 'M8A %'
order by tablename, policyname;

select
  has_function_privilege('anon', 'public.set_company_account_status(uuid,text)', 'execute') as anon_can_change_status,
  has_function_privilege('authenticated', 'public.set_company_account_status(uuid,text)', 'execute') as authenticated_can_call_guarded_rpc;

select
  (select count(*) from public.platform_users) as platform_user_count,
  (select count(*) from public.companies) as company_count,
  (select count(*) from public.company_users) as company_membership_count;
```

Expected: four columns, two `SECURITY DEFINER` functions with an empty safe search path, one enabled trigger, exactly three M8A policies, no anonymous RPC execution, and unchanged baseline counts immediately after migration.

## Recovery notes

Migration 008 is additive and wrapped in one transaction. If execution fails before `COMMIT`, confirm rollback and preserve the first error. Do not rerun blindly.

After a successful production commit, do not drop onboarding objects or columns as an immediate rollback. Disable Company Portal rollout first. The existing public forms and Admin submission workflows are independent and can remain available. Inventory any new Auth users, platform users, companies, and memberships before preparing a reviewed forward-fix migration. Restore from backup only through the approved production recovery process if data integrity was affected.
