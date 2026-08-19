# Pre-R14 Cleanup C1 — Tenant Requirement Security Boundary

## 1. Original leak path

`authenticated` had table-level `SELECT` on `public.employer_requirements` and `public.requirement_contractors`. Tenant RLS correctly limited rows, but the policies still allowed every column in an allowed row. Consequently, a Company could explicitly request `employer_requirements.internal_notes`; an approved Staffing Partner could request both that column for an assigned requirement and `requirement_contractors.internal_notes` for its assignment. Frontend omission was not a database boundary.

This was reproduced only in a disposable local database. Before migration 015, authenticated tenant fixtures successfully read the seeded values `LEAKED REQUIREMENT ADMIN NOTE` and `LEAKED ASSIGNMENT ADMIN NOTE` by naming the columns directly.

The audit also found that the existing tenant mutation RPCs returned full table rows. Even after read policies were removed, their return values could disclose internal columns. C1 therefore replaces tenant execution of those functions with minimal-return wrappers as well as safe read projections.

## 2. Sensitive columns

- `public.employer_requirements.internal_notes` — Admin operational note.
- `public.requirement_contractors.internal_notes` — Admin assignment/coordination note.
- Full-row mutation returns also contained unrelated private/internal columns such as Company contact and ownership metadata.

`additional_notes` remains in the Company projection because it is Company-supplied requirement content displayed and edited by the existing Company form; it is not the Admin-only `internal_notes` field. Partner output intentionally excludes response notes and all Candidate, application, and interview data.

## 3. Company access model

`public.get_company_requirements()` derives the caller's Company through `private.current_active_company_id()` and returns only explicit portal fields for that Company's rows. `public.manage_company_requirement(...)` retains create/update/close behavior by invoking the pre-existing validated functions internally but returns only requirement ID, code, stage, visibility, and update time. The browser no longer reads the base requirement table or executes a full-row-returning mutation function.

## 4. Staffing Partner access model

`public.get_staffing_partner_assignments()` derives the approved Partner through `private.current_active_contractor_id()`, joins only assignments for that Partner, and returns an explicit flattened operational allowlist. `public.staffing_partner_respond_requirement_assignment(...)` preserves accept/decline behavior and returns only a Boolean after verifying assignment ownership. No Partner-supplied tenant UUID is trusted.

## 5. Base-table grants before and after

Before C1, `authenticated` table grants plus three tenant SELECT policies made full allowed rows retrievable. Migration 015 removes:

- `M8B active company reads own requirements`
- `M8C active contractor reads assigned requirements`
- `M8C active contractor reads own assignments`

The authenticated table grants remain because the Admin browser uses direct table reads. Without tenant policies, tenant sessions receive no base rows; existing Admin policies remain authoritative. Execute on the four legacy full-row tenant mutation RPCs is revoked from `authenticated`; execute on the four C1 safe functions is granted only to `authenticated`.

## 6. RLS

RLS remains enabled and is not weakened. No `USING (true)` or `WITH CHECK (true)` policy is introduced. Company ownership and Partner assignment isolation are enforced inside fixed-search-path SECURITY DEFINER projections using canonical membership helpers. Admin policies are unchanged.

## 7. Projection/RPC design

All C1 functions use `SECURITY DEFINER`, `SET search_path = ''`, schema-qualified objects, explicit return columns, no dynamic SQL, no `SELECT *`, and internal identity derivation. PUBLIC and anon execute are revoked. A non-member authenticated caller is rejected before data access.

## 8. Frontend changes

- `company/company.js` reads through `get_company_requirements` and creates, updates, or closes through `manage_company_requirement`.
- `contractor/contractor.js` reads dashboard counts/details through `get_staffing_partner_assignments` and responds through `staffing_partner_respond_requirement_assignment`.

Visible workflows and field presentation are preserved. The nested `employer_requirements(*)` assignment read and tenant base-table requirement read are removed.

## 9. Admin preservation

Admin policies and Admin frontend queries are unchanged. The local C1 test proves Admin can still retrieve both internal-note columns and execute assignment management. Admin Candidate/Application/Interview logic is untouched.

## 10. Public preservation

Migration 015 does not alter `public.get_public_job_requirements(integer,integer)`, `public.register_candidate_requirement_interest(text,jsonb)`, `public.admin_update_candidate_application(uuid,text,text)`, or the R13 interview RPCs. Public Jobs behavior and anonymous grants are unchanged.

## 11. Tests

`supabase/tests/015_tenant_requirement_security_boundary_test.sql` is transactional and rolls back all fixtures. On a clean disposable PostgreSQL/Supabase database with schema plus migrations 007–015 it passed:

- own/assigned safe reads and cross-tenant isolation;
- direct base-table reads returning no tenant rows;
- explicit sensitive-column retrieval returning no tenant rows;
- safe Company create and Partner response behavior;
- denial for anon and authenticated non-members;
- Admin internal-note access;
- removal of legacy full-row execute grants and presence of safe grants;
- preservation of R10–R13 function objects.

R13's historical SQL suite also passed. The historical R10 suite contains an assertion requiring the three tenant policies C1 intentionally removes, so it is superseded for that assertion. Historical R11/R12 local fixtures reference an `auth.users.email_confirmed_at` column absent from the repository's current disposable baseline image; they did not reach feature assertions. C1 does not modify their functions, and their presence is checked by the C1 suite.

JavaScript syntax validation and `git diff --check` pass.

## 12. Production preflight (SELECT-only)

Do not run migration 015 until an operator runs and reviews this block in Production Supabase SQL Editor.

```sql
select current_database() as database_name, current_user as executing_role;

select c.table_name, c.column_name, c.data_type, c.is_nullable
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in ('employer_requirements','requirement_contractors','company_users','contractor_users')
order by c.table_name, c.ordinal_position;

select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('employer_requirements','requirement_contractors');

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('employer_requirements','requirement_contractors','company_users','contractor_users')
order by tablename, policyname;

select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('employer_requirements','requirement_contractors')
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;

select p.oid::regprocedure::text as function_signature,
       p.prosecdef as security_definer,
       p.proconfig as function_config,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public','private')
  and p.proname in (
    'is_admin','current_active_company_id','current_active_contractor_id',
    'create_company_requirement','update_company_requirement','close_company_requirement',
    'respond_requirement_assignment','get_public_job_requirements',
    'register_candidate_requirement_interest','admin_update_candidate_application',
    'admin_schedule_candidate_interview','admin_reschedule_candidate_interview',
    'admin_update_candidate_interview'
  )
order by p.oid::regprocedure::text;

select p.oid::regprocedure::text as collision
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'get_company_requirements','manage_company_requirement',
    'get_staffing_partner_assignments','staffing_partner_respond_requirement_assignment'
  );
```

**EXPECTED RESULT:** Both base tables and both `internal_notes` columns exist; RLS is enabled; all three named tenant read policies and the documented Admin read policies exist; authenticated currently has base SELECT and legacy tenant mutation execute; canonical membership helpers and R10–R13 functions exist; the collision query returns zero rows.

**STOP CONDITIONS:** Stop if any table, sensitive column, helper, legacy function, or Admin policy is missing; RLS is disabled; policy names/semantics differ; authenticated lacks the expected baseline grants; a C1 function collision exists; or any result differs enough that migration prerequisites or preserved Admin/public behavior cannot be confirmed.

## 13. Migration fingerprint

- File: `supabase/migrations/015_tenant_requirement_security_boundary.sql`
- SHA-256: `eee0d5c6f3f96a32d8b50a172db22957a160402809dec37c7842e1a858af03f9`
- Size: 13,893 bytes
- Line count: 392
- First executable statement: `begin;`
- Last executable statement: `commit;`

Recompute the fingerprint after any review edit and before manual production application.

## 14. Production postflight (SELECT-only)

```sql
select p.oid::regprocedure::text as function_signature,
       pg_get_function_result(p.oid) as return_signature,
       p.prosecdef as security_definer,
       p.proconfig as function_config,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'get_company_requirements','manage_company_requirement',
    'get_staffing_partner_assignments','staffing_partner_respond_requirement_assignment'
  )
order by p.oid::regprocedure::text;

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('employer_requirements','requirement_contractors')
order by tablename, policyname;

select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('employer_requirements','requirement_contractors');

select p.oid::regprocedure::text as function_signature,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'create_company_requirement','update_company_requirement','close_company_requirement',
    'respond_requirement_assignment','get_public_job_requirements',
    'register_candidate_requirement_interest','admin_update_candidate_application',
    'admin_schedule_candidate_interview','admin_reschedule_candidate_interview',
    'admin_update_candidate_interview'
  )
order by p.oid::regprocedure::text;
```

Expected: four C1 functions exist, are SECURITY DEFINER with empty search path, deny anon, allow authenticated, and their return signatures contain no internal-note fields. The three tenant base-read policies are absent while Admin policies remain. RLS is enabled. Legacy tenant mutation functions deny authenticated; R10–R13 grants remain as previously approved. Tenant-specific row behavior must then be checked with approved test accounts through the deployed portals, not by exposing production secrets in SQL.

## 15. Rollback

Rollback is non-destructive to data but restores the known privacy exposure and is therefore emergency-only. After human review, it would revoke/drop the four C1 functions, recreate the three prior tenant SELECT policies with their exact migration 009/010 predicates, and re-grant authenticated execute on the four legacy tenant mutation functions. It must not alter requirement, assignment, Candidate, application, or interview records. Frontends would also have to be reverted atomically to the legacy calls. Do not roll back only the database or only the frontend.

## 16. Known limitations

- Tenant safe lists remain unpaginated, matching the current portal behavior; pagination is a separate scalability improvement.
- Table-level authenticated SELECT remains for the existing Admin browser. Security depends on the retained Admin RLS policies and removal of tenant read policies; a future Admin-only RPC migration could remove this shared table grant entirely.
- Production migration and tenant-account verification were not performed by Codex.

## 17. Recommended next cleanup item

After operator preflight, migration review, manual application, postflight, and tenant portal smoke tests, continue the Pre-R14 audit cleanup sequence. A later narrowly scoped phase may add bounded tenant pagination and modernize historical SQL fixture compatibility without mixing those concerns into this security fix.
