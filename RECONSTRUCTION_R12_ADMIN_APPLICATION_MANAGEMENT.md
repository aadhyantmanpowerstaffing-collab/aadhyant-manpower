# Reconstruction R12 — Admin Candidate Application Management

## 1. Existing application model

`public.candidate_applications` is the Milestone 7 Candidate↔Requirement relation. It references `public.candidates` and `public.employer_requirements` with `ON DELETE RESTRICT`, retains `applied_at`, `created_at`, and trigger-managed `updated_at`, and enforces `UNIQUE(candidate_id, requirement_id)`. R11 creates direct `interested` rows through its narrow anonymous RPC.

## 2. Existing statuses and source types

The existing status constraint is preserved unchanged:

`interested`, `applied`, `screening`, `shortlisted`, `interview`, `selected`, `rejected`, `joining_pending`, `joined`, `left`, `cancelled`.

Existing sources remain `direct`, `contractor`, `admin`, `whatsapp`, `campus`, and `referral`. R12 does not reinterpret historical values or add a state machine.

## 3. Existing Admin policies and timestamp behavior

M7 already grants authenticated table operations but gates Candidate application SELECT/INSERT/UPDATE through `private.is_admin()`. Anonymous, Company, and Staffing Partner users have no qualifying policies. The existing `candidate_applications_set_updated_at` trigger calls `private.set_updated_at()`, so R12 status/note updates preserve `applied_at` and advance `updated_at`.

## 4. Admin list, filters, and pagination

The existing Candidate Interests tab remains server-paginated at 25 rows. Its single relational query fetches the Candidate, application, and requirement context without N+1 requests. Columns cover interest date, requirement, role, Candidate, mobile, location, qualification, specialization, type/experience, status, and a **View / Manage** action.

Server-side filters cover requirement code, job role, Candidate name/mobile, location, qualification, status, and interested-since date. Empty and filtered-empty states remain distinct.

## 5. Application detail view

An Admin-only modal separates Opportunity/Requirement and Candidate Profile data. It uses only existing columns, contains no Candidate or requirement editing controls, closes through Escape/native dialog, backdrop, Cancel, or close button, and restores focus to the triggering action.

## 6. Status management and internal notes

The status dropdown contains only the existing constraint values. Migration 013 adds optional `admin_notes text` with a 4,000-character check. Notes are fetched only through the Admin-authorized application query and are absent from R10, R11, public, Company, and Staffing Partner surfaces.

## 7. Admin update RPC

`public.admin_update_candidate_application(uuid,text,text)` updates exactly one application. It is `SECURITY DEFINER`, uses `search_path = ''`, verifies `auth.uid()` and `private.is_admin()`, allowlists every supported status, bounds notes, rejects missing/unknown IDs, contains no dynamic SQL, and returns only boolean success. `PUBLIC` and `anon` execution are revoked; `authenticated` execution is granted, with Admin authorization enforced inside the function.

Existing generic table grants/policies are not broadened. Candidate and requirement records are immutable in this workflow.

## 8. RLS and privacy boundaries

- **Anonymous:** no Candidate/application SELECT and no R12 execute.
- **Authenticated non-admin:** table RLS returns no application/Candidate rows; R12 RPC rejects the caller.
- **Company:** no Candidate/application visibility or management.
- **Staffing Partner:** no Candidate/application visibility or management.
- **Public:** R10/R11 signatures and projections are unchanged; Admin notes and application status are not exposed.
- **Admin:** existing M7 policies permit review; R12 RPC permits only status/note updates.

No `USING (true)`, tenant Candidate policy, public projection, Candidate edit, requirement edit, interview/joining action, WhatsApp action, or delete is introduced.

## 9. Performance and indexes

Existing indexes already cover Candidate, requirement/status, status/created date, and assignment. Migration 013 adds only `candidate_applications_applied_at_idx (applied_at desc)` for the Admin list’s deterministic newest-first pagination. No existing index is duplicated.

## 10. Accessibility and responsive behavior

The table has headers and contained horizontal scrolling. Filters, status, and notes are labelled. Save/error messages use a live region. Dialog sections have semantic headings; controls remain keyboard/touch accessible and stack on small screens. Validate at 360, 390, 768, 1024, and 1440px with no page-level overflow.

## 11. SQL tests

Run `supabase/tests/013_admin_candidate_application_management_test.sql` only in disposable local Supabase after schema and migrations 007–013. It verifies Admin read/update, updated timestamp, bounded notes, invalid status/ID rejection, anon/non-admin/Company/Partner denial, Candidate and requirement immutability, unique constraint preservation, R10/R11 preservation, grant boundaries, and transactional rollback.

## 12. Production preflight — SELECT only

Run separately in Production SQL Editor and review every result before migration 013.

```sql
-- R12 STEP A: READ-ONLY PRODUCTION PREFLIGHT

select to_regclass('public.candidate_applications') as candidate_applications,
       to_regclass('public.candidates') as candidates,
       to_regclass('public.employer_requirements') as employer_requirements;

select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='candidate_applications'
order by ordinal_position;

select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.candidate_applications'::regclass
order by conname;

select indexname, indexdef
from pg_indexes
where schemaname='public' and tablename='candidate_applications'
order by indexname;

select application_status, count(*) as application_count
from public.candidate_applications
group by application_status
order by application_status;

select to_regprocedure('private.is_admin()') as admin_helper,
       to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_jobs_function,
       to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') as r11_interest_function,
       to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') as existing_r12_function;

select column_name
from information_schema.columns
where table_schema='public' and table_name='candidate_applications' and column_name='admin_notes';

select c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname='candidate_applications';

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename in ('candidate_applications','candidates','employer_requirements')
order by tablename, policyname;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name in ('candidate_applications','candidates','employer_requirements')
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema='public'
  and routine_name in ('get_public_job_requirements','register_candidate_requirement_interest','admin_update_candidate_application')
order by routine_name, grantee;
```

**EXPECTED RESULT:** all prerequisite tables exist; the application status/source/unique/FK constraints and timestamp columns match M7; RLS is enabled; M7 Admin read/create/update policies exist; no anon or tenant application/Candidate SELECT policy exists; R10, R11, and `private.is_admin()` exist; `existing_r12_function` is null; `admin_notes` returns zero rows; no applied-at index with the R12 name exists; current statuses all satisfy the existing constraint.

**STOP CONDITIONS:** stop if any prerequisite, constraint, policy, helper, R10/R11 function, or expected grant differs; RLS is disabled; anon/Company/Partner Candidate access exists; `admin_notes`, the R12 function, or a conflicting applied-at index already exists; unsupported status data or partial R12 objects are present.

## 13. Manual application boundary

1. Run and review the SELECT-only preflight.
2. Verify migration 013 fingerprint and normal backup/change record.
3. Manually execute only `supabase/migrations/013_admin_candidate_application_management.sql`.
4. Stop on any error; do not work around partial state blindly.
5. Run the read-only postflight.

R12 development never links to or modifies production.

## 14. Production postflight — read only

```sql
-- R12 STEP D: READ-ONLY PRODUCTION POSTFLIGHT

select to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') as r12_function,
       to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_jobs_function,
       to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') as r11_interest_function;

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema='public' and table_name='candidate_applications' and column_name='admin_notes';

select p.prosecdef as security_definer, p.proconfig as function_config,
       pg_get_function_result(p.oid) as return_type
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.oid='public.admin_update_candidate_application(uuid,text,text)'::regprocedure;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema='public' and routine_name='admin_update_candidate_application'
order by grantee;

select c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname='candidate_applications';

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename in ('candidate_applications','candidates','employer_requirements')
order by tablename, policyname;

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.candidate_applications'::regclass
order by conname;

select indexname, indexdef
from pg_indexes
where schemaname='public' and tablename='candidate_applications'
order by indexname;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name in ('candidate_applications','candidates')
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;
```

Expected: R12/R10/R11 functions exist; R12 is security-definer with empty search path and boolean result; only authenticated has execute and internal Admin authorization remains in function source; `admin_notes` and its length check exist; RLS/Admin policies and original status/unique constraints remain; the applied-date index exists; no anon or tenant Candidate/application access appears.

## 15. Rollback — manual only

Prefer a non-destructive rollback that removes the callable R12 surface and index but retains `admin_notes` data for audit/recovery:

```sql
begin;
revoke execute on function public.admin_update_candidate_application(uuid,text,text) from authenticated;
drop function public.admin_update_candidate_application(uuid,text,text);
drop index public.candidate_applications_applied_at_idx;
commit;
```

The nullable `admin_notes` column and its data intentionally remain. Dropping it would destroy Admin notes and requires a separate reviewed data-retention decision. Do not alter Candidate/application rows, original constraints/policies, R10, or R11.

## 16. Regression and limitations

R12 preserves Admin login and every existing tab/workflow; Company and Staffing Partner source files remain unchanged; all public routes and R10/R11 behavior must pass locally. Expected unexplained console errors, failed requests, and asset 404s are zero.

Known limitations: no status history table, no Candidate corrections, no Candidate Auth, no interview/joining workflow, no Company/Partner sharing, no messaging automation, and no bulk actions. The Admin note is current-state text rather than an append-only audit log.

Recommended next: a separately approved interview scheduling/audit-history milestone, retaining Admin coordination and explicit Candidate-sharing privacy boundaries.

## 17. Completed local validation

Migration 013 fingerprint: SHA-256 `2f6498de49836e8d35b33d9163bf0525eeb4ef47ac496f4a1485e5e2646b3745`, 3,080 bytes, 83 lines, from `begin;` through `commit;`.

Schema and migrations 007–013 executed in disposable local Supabase CLI 2.114.0 with Docker Engine 29.7.2. The final transactional SQL suite passed and rolled back every fixture. Authenticated Chrome/Selenium validation passed list loading, Candidate/requirement/status/location/qualification filters, filtered empty state, detail separation, exact status allowlist, 4,000-character note bound, focus restoration, safe deliberate network-failure feedback, successful RPC save, and persistence. Responsive checks passed at 360, 390, 768, 1024, and 1440px with contained tables/dialog and no page overflow. Unexplained console errors and failed HTTP requests were zero.

Final read-only local verification confirmed the saved `shortlisted` status/note, unchanged Candidate and requirement records, enabled application RLS, zero anon Candidate/application SELECT, zero anon R12 execute, zero non-Admin tenant application policies, preserved Candidate/requirement uniqueness, and functioning R10/R11/R12 functions. Every required public, Company, Staffing Partner, and Admin route returned HTTP 200. No production endpoint or data was used.

## 18. Operator-reported production status

Manual production verification reported by the operator: migration 013 was applied outside Codex after its SHA-256 was verified as `2f6498de49836e8d35b33d9163bf0525eeb4ef47ac496f4a1485e5e2646b3745`. The operator reported that production postflight confirmed `public.admin_update_candidate_application(uuid,text,text)`, `candidate_applications.admin_notes`, and `candidate_applications_applied_at_idx` exist; anon execute on the R12 RPC is false; authenticated execute is true. Codex did not access production or execute production SQL.
