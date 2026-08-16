# Reconstruction R11 — Candidate Job Interest Foundation

## 1. Existing Candidate model

`public.candidates` is the canonical Candidate master. Public registration currently inserts one profile through an allowlisted anonymous `INSERT`; anonymous `SELECT`, `UPDATE`, and `DELETE` are denied. The primary key is an internal UUID. Mobile is indexed but is not unique, email is not collected, and Milestone 7 added nullable future Auth linkage without changing public registration. Approved Admins can read Candidates through `private.is_admin()`.

The canonical form remains `/candidate/register/` with `id="candidate-registration-form"` and `data-lead-form="candidate"`.

## 2. Requirement linkage model

Milestone 7 already created `public.candidate_applications` as the canonical Candidate↔Requirement relation. R11 reuses it rather than creating a competing interests table. A public interest uses `source_type = 'direct'` and the existing minimal `application_status = 'interested'`. Interview and joining tables are untouched.

## 3. Canonical Candidate strategy and duplicate limitation

Job-linked registration is transactional. The RPC conservatively reuses a Candidate only when normalized mobile, case-insensitive trimmed full name, and age match exactly and exactly one Candidate satisfies that identity tuple. No merge occurs on mobile alone. An ambiguous multiple match is rejected for manual review. This reduces duplicate masters without claiming that mobile is a permanent identity key.

The legacy general registration route still has no database uniqueness constraint, so general submissions can create duplicate profiles. A future identity-governance milestone should establish verified identity and merge rules before adding Candidate Auth.

## 4. Duplicate interest protection

The existing `unique (candidate_id, requirement_id)` constraint remains authoritative. The RPC also takes a transaction-scoped advisory lock for normalized mobile across all job-linked submissions, then checks existing interests for the selected requirement. Repeated/concurrent submission returns `already_registered` and does not create a second Candidate or application.

## 5. Public identifier and eligibility

The browser carries only canonical `requirement_code`, for example `?requirement=AAD-2026-000001`. UUIDs never enter public URLs or function output. The backend accepts a bounded canonical code and resolves it internally only when the requirement is `open`, `public`, has a non-null code, and `required_headcount > filled_positions`.

## 6. Public registration RPC

`public.register_candidate_requirement_interest(text,jsonb)` is `SECURITY DEFINER`, has `search_path = ''`, uses schema-qualified objects, contains no dynamic SQL, explicitly allowlists Candidate JSON keys, validates the Candidate through existing table constraints, and returns only `registered` or `already_registered`. It is executable only by `anon`; `PUBLIC` execution is revoked. It creates the Candidate and interest in one transaction, so partial completion cannot occur.

General Candidate registration without a requirement continues through the existing anonymous table insert.

## 7. RLS and access boundaries

`candidate_applications` already has RLS enabled. R11 adds no anonymous or broad authenticated table grants/policies. Existing M7 Admin policies remain the only application read/update path. Company and Staffing Partner users therefore receive zero Candidate-interest rows. Candidate Auth, Company sharing, Partner sharing, arbitrary public update, and delete remain absent.

## 8. Admin visibility

The existing Admin Dashboard gains a read-only **Candidate Interests** tab. It reads `candidate_applications` with its Candidate and requirement relationships under existing Admin RLS and displays requirement code/role, Candidate contact/profile summary, date, and status. Filters cover requirement code, role, Candidate name/mobile, and status. R11 does not add interview/joining actions or expose the data outside Admin.

## 9. Frontend behavior

Public Jobs cards use **Register Interest** and route to `/candidate/register/?requirement=<encoded-code>`. Candidate Registration uses the existing R10 safe projection to show only code, role, and location. Invalid/unavailable context is announced without raw errors and general registration remains available. The backend revalidates eligibility at submission time. Linked success and duplicate-interest messages are distinct; the canonical form and its consent/review/fallback contracts remain unchanged.

## 10. Consent and privacy

The existing Candidate consent remains authoritative. The context panel states that the Candidate profile may be considered for the selected requirement. No marketing or WhatsApp consent is added. R9 Privacy/Terms already cover voluntary Candidate registration and recruitment/workforce coordination, so no legal-page change is required.

## 11. Local SQL tests

Run `supabase/tests/012_candidate_requirement_interest_test.sql` only after schema and migrations 007–012 in a disposable local Supabase database. It tests open/public success, draft/private/closed/unknown rejection, duplicate/concurrent-safe behavior, Candidate and application privacy, non-admin denial, Admin review, R10 preservation, and general Candidate registration preservation. The test transaction rolls back all fixtures.

## 12. Production preflight — SELECT only

Run separately in the Production SQL Editor. Stop before migration application and review every result.

```sql
-- R11 STEP A: READ-ONLY PRODUCTION PREFLIGHT

select to_regclass('public.candidates') as candidates,
       to_regclass('public.employer_requirements') as employer_requirements,
       to_regclass('public.candidate_applications') as candidate_applications;

select table_name, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and ((table_name = 'candidates' and column_name = any(array[
    'id','full_name','age','gender','mobile','whatsapp_number','current_location',
    'district','state','highest_qualification','specialization','candidate_type',
    'total_experience','previous_job_role','interview_available',
    'preferred_job_location','additional_information','consent','created_at'
  ])) or (table_name = 'employer_requirements' and column_name = any(array[
    'id','requirement_code','requirement_stage','requirement_visibility',
    'required_headcount','filled_positions'
  ])) or (table_name = 'candidate_applications' and column_name = any(array[
    'id','candidate_id','requirement_id','source_type','application_status',
    'applied_at','created_at','updated_at'
  ])))
order by table_name, column_name;

select conrelid::regclass as table_name, conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid in ('public.candidates'::regclass, 'public.employer_requirements'::regclass, 'public.candidate_applications'::regclass)
order by conrelid::regclass::text, conname;

select requirement_stage, requirement_visibility, count(*) as row_count
from public.employer_requirements
group by requirement_stage, requirement_visibility
order by requirement_stage, requirement_visibility;

select count(*) as candidate_count,
       count(*) filter (where mobile is null or mobile !~ '^[6-9][0-9]{9}$') as invalid_mobile_count,
       count(*) - count(distinct mobile) as duplicate_mobile_row_count
from public.candidates;

select to_regprocedure('private.is_admin()') as admin_helper,
       to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_jobs_function,
       to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') as existing_r11_function;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('candidates','candidate_applications','employer_requirements')
order by tablename, policyname;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('candidates','candidate_applications','employer_requirements')
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema = 'public'
  and routine_name in ('get_public_job_requirements','register_candidate_requirement_interest')
order by routine_name, grantee;
```

Expected: all three tables and all listed columns/constraints exist; R10 and `private.is_admin()` exist; `existing_r11_function` is null; `candidate_applications` has RLS/Admin policies but no anon or non-admin tenant read policy; Candidates retain only the narrow anonymous insert path; lifecycle values are supported. Duplicate mobile rows may exist and must be reviewed as a known identity limitation.

**STOP** if an object/column/constraint is missing or differs, the R11 function already exists, anonymous Candidate/application SELECT exists, Company/Partner Candidate access exists, R10 is missing, or unexpected partial R11 objects are present.

## 13. Manual application boundary

1. Run and review the SELECT-only preflight.
2. Verify the reviewed migration fingerprint and take the normal production backup/change record.
3. Manually run only `supabase/migrations/012_candidate_requirement_interest.sql` in Production SQL Editor.
4. Stop on any error; do not work around partial state blindly.
5. Run the read-only postflight below.

No automated production connection, CLI link, `db push`, deployment, or production test record is part of R11 development.

## 14. Production postflight — read only

```sql
-- R11 STEP D: READ-ONLY PRODUCTION POSTFLIGHT

select to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') as r11_function,
       to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_jobs_function;

select p.prosecdef as security_definer,
       p.provolatile as volatility,
       p.proconfig as function_config,
       pg_get_function_result(p.oid) as return_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.oid = 'public.register_candidate_requirement_interest(text,jsonb)'::regprocedure;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where specific_schema = 'public'
  and routine_name = 'register_candidate_requirement_interest'
order by grantee;

select c.relname, c.relrowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('candidates','candidate_applications','employer_requirements')
order by c.relname;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename in ('candidates','candidate_applications','employer_requirements')
order by tablename, policyname;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name in ('candidates','candidate_applications','employer_requirements')
  and grantee in ('anon','authenticated')
order by table_name, grantee, privilege_type;

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid='public.candidate_applications'::regclass
order by conname;
```

Expected: R11 and R10 functions exist; R11 is security-definer with `search_path=""` and returns text; only `anon` has R11 execute; RLS stays enabled; Admin policies and the unique Candidate/requirement constraint remain; no anonymous SELECT or Company/Partner Candidate-interest policy/grant appears.

## 15. Rollback — manual only

Rollback removes only the R11 function because R11 reuses the existing M7 table/policies and creates no new relation.

```sql
begin;
revoke execute on function public.register_candidate_requirement_interest(text, jsonb) from anon;
drop function public.register_candidate_requirement_interest(text, jsonb);
commit;
```

Do not alter `candidates`, `candidate_applications`, requirements, R10, interviews, or joinings. Existing Candidate/application rows intentionally remain as operational history; review any production test record separately by exact IDs before considering cleanup.

## 16. Accessibility, responsive, and security regression

The context panel is semantic and live-announced; unavailable state is readable, keyboard-safe, and not color-only. Jobs CTA remains a link. Admin interests use the established scroll-contained table and filters. Validate `/jobs/`, Candidate Registration with/without valid/invalid context, and Admin at 360, 390, 768, 1024, and 1440 px. Verify zero unexplained console/network errors and all Company/Staffing Partner/Admin/public route regressions.

## 17. Known limitations and next phase

- No Candidate Auth/dashboard or verified Candidate identity.
- Exact name/mobile/age reuse is conservative but not a legal identity guarantee.
- General registrations retain the legacy duplicate model.
- Public opportunity context searches the bounded R10 feed; backend eligibility remains authoritative.
- Admin interest review is read-only in R11.
- Company and Staffing Partner Candidate sharing, interview/joining, and WhatsApp are deferred.

Recommended next: a separately approved Candidate review/status and controlled handoff milestone, preceded by Candidate identity/deduplication governance.

## 18. R11 local validation result

Migration 012 executed after schema and migrations 007–011 in disposable local Supabase CLI 2.114.0 / Docker Engine 29.7.2. The transactional SQL suite passed and rolled back its fixtures. Actual Chrome/Selenium testing against loopback-only Supabase passed linked registration, duplicate response, general registration, invalid/private/closed context, authenticated Admin review, all required responsive widths, and console/network capture. Two browser Candidates produced two distinct applications and zero duplicate Candidate/requirement pairs. One PostgreSQL compatibility defect (`min(uuid)`) and two frontend containment/hidden-state defects were fixed and their affected tests rerun. No production endpoint or data was used.
