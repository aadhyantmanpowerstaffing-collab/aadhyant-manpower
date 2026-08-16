# Milestone 8B — Company Manpower Requirements

## Scope

Milestone 8B adds Company-owned manpower requirement creation, listing, detail, draft editing, and non-destructive close/cancel behavior to the Company Portal. It also adds an Admin Company Requirements view and controlled operational lifecycle updates. Contractor assignment, candidate applications, interviews, and joining remain intentionally deferred.

The implementation reuses `public.employer_requirements`. Existing public/legacy rows keep nullable `company_id` and `created_by_user_id`; no production row is backfilled or rewritten.

## Ownership and write design

Migration `supabase/migrations/009_company_requirements_rls.sql` uses guarded `SECURITY DEFINER` RPCs rather than broad browser INSERT/UPDATE rights:

- `create_company_requirement(...)` resolves exactly one active Company membership internally, sets `company_id` and `created_by_user_id` from the authenticated context, fixes `filled_positions = 0`, `requirement_stage = draft`, and `requirement_visibility = private`, and lets the existing M7 trigger assign `requirement_code`.
- `update_company_requirement(...)` updates only explicitly listed business fields and only while the caller's own requirement is `draft`.
- `close_company_requirement(uuid)` changes a draft to `cancelled` or an open/on-hold requirement to `closed`; it never deletes.
- `set_company_requirement_stage(uuid,text,text)` is admin-guarded and controls exact M7 stage/visibility literals and lifecycle timestamps.

All functions set an empty `search_path` and schema-qualify objects. The browser cannot supply IDs, ownership, codes, filled counts, publication timestamps, close timestamps, or internal notes. Company direct INSERT/UPDATE/DELETE is not introduced.

## Lifecycle

| Actor | Allowed transition/action |
| --- | --- |
| Active Company | Create private draft; edit own draft; cancel own draft; close own open/on-hold requirement |
| Pending/suspended/rejected Company | No requirement workspace read or write |
| Approved Admin | View all requirements; set `draft`, `open`, `on_hold`, `filled`, `closed`, or `cancelled` with `private`, `assigned`, or `public` visibility |
| Anonymous | Existing narrow public form INSERT only; no SELECT/UPDATE/DELETE |

Opening sets `published_at` once. Terminal stages set `closed_at`. Reopening clears `closed_at`. Company requirements remain in history.

## Local validation

The baseline schema and migrations 007, 008, and 009 were executed in order against a disposable Docker Supabase stack bound to `127.0.0.1`. `supabase/tests/009_company_requirements_test.sql` uses fake local identities and rolls back its fixtures.

Validated: active Company creation and automatic ownership/code/defaults; Company A/B isolation; pending, suspended, and non-company denial; protected-column direct update denial; no DELETE privilege; draft-only edit; non-destructive close; approved-admin all-row read and lifecycle update; non-admin admin-RPC denial; legacy anonymous Employer insert; Candidate insert; anonymous read denial; headcount/age/salary/open-balance constraints; canonical code uniqueness; M8A access compatibility; clean second-run rejection; safe `SECURITY DEFINER` configuration; and transaction rollback after an intentional partial failure.

## Production read-only preflight

Run this in the intended Production Supabase SQL Editor. Stop if prerequisites are null, any M8B object already exists, or the policy query returns rows.

```sql
select
  to_regclass('public.employer_requirements') as employer_requirements,
  to_regclass('public.platform_users') as platform_users,
  to_regclass('public.companies') as companies,
  to_regclass('public.company_users') as company_users,
  to_regprocedure('private.is_admin()') as is_admin,
  to_regprocedure('public.set_company_account_status(uuid,text)') as company_status_rpc,
  to_regprocedure('private.assign_requirement_code()') as requirement_code_trigger_function;

select
  to_regprocedure('private.current_active_company_id()') as active_company_helper,
  to_regprocedure('public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') as create_rpc,
  to_regprocedure('public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)') as update_rpc,
  to_regprocedure('public.close_company_requirement(uuid)') as close_rpc,
  to_regprocedure('public.set_company_requirement_stage(uuid,text,text)') as admin_stage_rpc;

select policyname from pg_policies
where schemaname = 'public' and policyname like 'M8B %';

select
  count(*) as total_requirements,
  count(*) filter (where company_id is null) as public_or_legacy_requirements,
  count(*) filter (where company_id is not null) as company_owned_requirements
from public.employer_requirements;
```

## Manual production migration

1. Confirm a current verified production backup and record the preflight counts.
2. Verify the local migration fingerprint reported with the release.
3. Open `supabase/migrations/009_company_requirements_rls.sql` locally and copy the complete file, including `begin;` and `commit;`.
4. Paste it into a new Production SQL Editor query and execute the complete file exactly once.
5. Stop on the first error. Do not execute fragments or rerun blindly.
6. Run the post-migration verification below before deploying the frontend.

```sql
select n.nspname, p.proname, p.prosecdef, p.proconfig
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where p.proname in (
  'current_active_company_id','create_company_requirement',
  'update_company_requirement','close_company_requirement',
  'set_company_requirement_stage'
)
order by p.proname;

select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public' and policyname like 'M8B %';

select
  has_table_privilege('anon','public.employer_requirements','select') as anon_select,
  has_table_privilege('anon','public.employer_requirements','delete') as anon_delete,
  has_table_privilege('authenticated','public.employer_requirements','delete') as authenticated_delete;

select
  count(*) as total_requirements,
  count(*) filter (where company_id is null) as public_or_legacy_requirements,
  count(*) filter (where company_id is not null) as company_owned_requirements
from public.employer_requirements;
```

Expected: five `SECURITY DEFINER` functions with `search_path=""`; exactly one M8B SELECT policy; all three broad privilege checks false; and unchanged counts immediately after migration.

## Manual frontend deployment

After the migration and verification are approved: review the explicit changed-file manifest, run secret and regression scans, commit on `v2-development`, push that branch, compare it with the confirmed GitHub Pages deployment branch, merge normally, and verify `/`, `/company/`, `/company/requirements.html`, `/admin/login.html`, and `/admin/` over HTTPS. Do not create production smoke-test records during route verification.

## Recovery

Migration 009 is additive and transactional. A failure before `commit` rolls back the migration; preserve the exact first error. After a successful production commit, disable the new frontend route first if a problem appears and prepare a reviewed forward-fix migration. Do not drop functions/policies blindly and do not delete requirements. Existing public forms remain independent.
