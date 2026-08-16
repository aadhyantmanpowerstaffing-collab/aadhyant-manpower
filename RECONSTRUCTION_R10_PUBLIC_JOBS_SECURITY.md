# Reconstruction R10 — Secure Public Jobs Projection

## 1. Existing RLS finding

`public.employer_requirements` has RLS enabled. Anonymous users have a narrow INSERT grant/policy for the public Employer form but no base-table SELECT grant or SELECT policy. Authenticated reads are independently controlled for approved Admins, active Company ownership and active Staffing Partners with explicit assignments.

The exact lifecycle columns are `requirement_stage text` with `draft`, `open`, `on_hold`, `filled`, `closed`, `cancelled`, and `requirement_visibility text` with `private`, `assigned`, `public`. R10 eligibility is exactly `requirement_stage = 'open'` and `requirement_visibility = 'public'`, with a non-null canonical requirement code and positive open balance.

## 2. Chosen projection design

R10 uses a read-only `SECURITY DEFINER` SQL RPC rather than an anonymous base-table policy or view. The function has an empty fixed search path, schema-qualified table reference, no dynamic SQL and no caller-controlled identifiers. It is `STABLE` and contains one SELECT statement.

## 3. Public field allowlist

The projection returns only:

- `requirement_code text`
- `job_role text`
- `department text`
- `job_location text`
- `open_positions integer` (computed from required minus filled)
- `salary_min numeric`
- `salary_max numeric`
- `salary_text text`
- `qualification text`
- `iti_trade text`
- `experience_requirement text`
- `shift_details text`
- `working_hours text`
- `overtime_details text`
- `canteen text`
- `transport text`
- `accommodation text`
- `interview_date timestamptz`
- `interview_location text`
- `expected_joining_date date`
- `published_at timestamptz` (published date, falling back to created date)

Age and gender preference are omitted under data minimisation even though base columns exist.

## 4. Sensitive-field denylist

The signature excludes requirement UUIDs, Company UUIDs, creator/auth IDs, Company name, contact person, phone, email, Company location, internal notes, additional notes, consent/status internals, Contractor identities, assignment IDs/targets/notes, Candidate data and audit metadata not deliberately public.

## 5. Company identity decision

Company legal/trade names are omitted. The current schema does not define a separate reviewed public Company display identity, so R10 publishes the opportunity rather than the Employer identity.

## 6. Function signature

```sql
public.get_public_job_requirements(
  p_limit integer default 20,
  p_offset integer default 0
)
```

The complete return table is the explicit allowlist above. No filter text or SQL fragments are accepted.

Validated migration fingerprint:

- File: `supabase/migrations/011_public_jobs_projection.sql`
- SHA-256: `8ac216facd54acc0c7d24f93cfe121e2bd7c7cd85b44b980c2f386c13bfb6eed`
- Size: 3,416 bytes
- Lines: 111

## 7. Grants

The migration first revokes function execution from `PUBLIC`, then grants only EXECUTE to `anon` and `authenticated`. It grants no table permission and creates no RLS policy.

## 8. Pagination and ordering

The default page size is 20 and the maximum is 50. Values below 1 are clamped to 1. Offset is clamped between 0 and 5000. Results order deterministically by public/published date descending and requirement code descending. Unlimited reads and arbitrary sorting are unavailable.

## 9. RLS preservation

R10 does not alter, drop or recreate any base-table grant or policy. Existing Admin, Company and assigned Staffing Partner access remains independent. Anonymous direct SELECT remains denied.

## 10. Frontend integration

`/jobs/` uses the existing browser-safe Supabase client to call only `get_public_job_requirements`. It never queries `employer_requirements`. Cards are created with DOM text nodes rather than HTML interpolation and receive only projection fields.

## 11. Jobs filters

Keyword/role, location, qualification and experience filtering runs client-side over the bounded 20-row page. No dynamic SQL or incomplete location dataset is involved.

## 12. Empty and error states

Loading is announced with `role=status` and the result list uses `aria-busy`. Zero rows shows “No public openings are available right now.” RPC/configuration failure shows “Job listings are temporarily unavailable.” Neither state exposes PostgREST, SQL, table, policy or stack details.

## 13. Security tests

The transactional SQL suite verifies:

- Anonymous base `employer_requirements`, `candidates` and `requirement_contractors` reads are denied.
- Exactly the open/public fixture is projected.
- Private/open, public/draft and public/closed fixtures are excluded.
- Open positions are computed correctly.
- Requirement code is present.
- Sensitive fields are absent from the OUT signature.
- Maximum page size is 50.
- Anonymous and authenticated EXECUTE grants exist.
- No anonymous base-table SELECT policy exists.
- Existing Admin, Company and Staffing Partner policies remain present.

The suite runs inside a transaction and rolls back fixtures. A local anonymous REST call and actual Jobs UI test also passed against the disposable Docker-backed stack.

## 14. Portal regression

Company registration/login/dashboard/requirements, Staffing Partner registration/login/dashboard/assignments and Admin login/dashboard returned HTTP 200 locally. No portal source file changed.

## 15. Read-only production preflight SQL

Run this block separately in the Production SQL Editor. It contains SELECT statements only.

```sql
-- R10 STEP A: READ-ONLY PRODUCTION PREFLIGHT

select to_regclass('public.employer_requirements') as employer_requirements;

select column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'employer_requirements'
  and column_name = any (array[
    'requirement_code', 'job_role', 'department', 'job_location',
    'required_headcount', 'filled_positions', 'salary_min', 'salary_max',
    'salary_wage', 'qualification', 'iti_trade', 'experience_requirement',
    'shift_details', 'working_hours', 'overtime_details', 'canteen',
    'transport', 'accommodation', 'interview_date', 'interview_location',
    'expected_joining_date', 'published_at', 'created_at',
    'requirement_stage', 'requirement_visibility'
  ])
order by column_name;

select requirement_stage, requirement_visibility, count(*) as row_count
from public.employer_requirements
group by requirement_stage, requirement_visibility
order by requirement_stage, requirement_visibility;

select to_regprocedure('public.get_public_job_requirements(integer,integer)') as existing_r10_function;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'employer_requirements'
order by policyname;

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'employer_requirements'
  and grantee in ('anon', 'authenticated')
order by grantee, privilege_type;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema = 'public'
  and routine_name = 'get_public_job_requirements'
order by grantee;
```

Expected: the table and every required column exist; lifecycle values conform to current constraints; `existing_r10_function` is null; there is no anonymous SELECT policy/grant; existing Admin, M8B Company and M8C Contractor policies are present. Stop if results differ or an R10 function already exists.

## 16. Manual migration application procedure

1. Complete and review the read-only preflight above.
2. Confirm the migration file fingerprint against this document/final R10 report.
3. Open `supabase/migrations/011_public_jobs_projection.sql` locally and review the complete file.
4. In a new Production SQL Editor query, paste exactly that file from `begin;` through `commit;`.
5. Confirm the selected production project manually.
6. Run once. Stop on any error; do not edit around prerequisite or collision failures.
7. Run the postflight below separately.
8. Do not run prior migrations, `supabase link`, `db push`, or any remote CLI command.

## 17. Read-only production postflight SQL

```sql
-- R10 STEP D: READ-ONLY PRODUCTION POSTFLIGHT

select
  to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_function,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  p.proconfig as function_settings,
  pg_get_function_result(p.oid) as return_signature
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_public_job_requirements'
  and pg_get_function_identity_arguments(p.oid) = 'p_limit integer, p_offset integer';

select parameter_name, data_type, udt_name, parameter_mode, ordinal_position
from information_schema.parameters
where specific_schema = 'public'
  and specific_name like 'get_public_job_requirements_%'
order by ordinal_position;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema = 'public'
  and routine_name = 'get_public_job_requirements'
order by grantee;

select c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'employer_requirements';

select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'employer_requirements'
order by policyname;

select * from public.get_public_job_requirements(20, 0);

select count(*) as ineligible_rows_leaked
from public.get_public_job_requirements(50, 0) j
join public.employer_requirements r using (requirement_code)
where r.requirement_stage <> 'open'
   or r.requirement_visibility <> 'public';

select count(*) as sensitive_signature_columns
from information_schema.parameters
where specific_schema = 'public'
  and specific_name like 'get_public_job_requirements_%'
  and parameter_mode = 'OUT'
  and parameter_name = any(array[
    'id', 'company_id', 'created_by_user_id', 'company_name',
    'contact_person', 'mobile', 'email', 'internal_notes', 'additional_notes'
  ]);
```

Expected: one SECURITY DEFINER/STABLE function with `search_path=""`; only anon/authenticated EXECUTE grants plus owner visibility as reported by the catalog; RLS remains enabled; no anonymous SELECT policy was added; `ineligible_rows_leaked = 0`; `sensitive_signature_columns = 0`.

## 18. Rollback procedure

Rollback removes only the R10 function and grants. Run manually only after human review:

```sql
begin;
revoke execute on function public.get_public_job_requirements(integer, integer) from anon, authenticated;
drop function public.get_public_job_requirements(integer, integer);
commit;
```

This does not modify tables, policies or data. After rollback, deploy/revert the Jobs frontend to the pre-R10 empty-state implementation so it no longer calls a missing RPC.

## 19. Privacy and Terms consistency

R9 already describes controlled public/private sharing. R10 exposes only deliberately public requirement information, no Employer identity/contact data and no Candidate data, so legal text requires no change.

## 20. Abuse considerations and limitations

Page size and offset are bounded; ordering is fixed; dynamic SQL and arbitrary sort/filter identifiers do not exist; fields are minimised. If traffic requires it, rate limiting or caching may later be added at an edge/API layer. R10 does not add JobPosting JSON-LD because completeness and freshness governance are not yet established.

## 21. Recommended next phase

After local review, complete manual production preflight/migration/postflight and deploy the frontend in a separately controlled release. Candidate Applications, requirement-code handoff, JobPosting structured data and rate limiting should remain independent future milestones.
