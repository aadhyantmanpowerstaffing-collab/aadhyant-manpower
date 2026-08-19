# W0 Supabase Baseline

This is a repository inventory, not a production database audit. No Supabase API, SQL endpoint, dashboard, migration runner, or production data was accessed.

## Base schema proven from files

`supabase/schema.sql` defines `admin_users`, `employer_requirements`, and `candidates`; `private.is_admin()` and `private.set_updated_at()`; RLS on all three tables; anonymous insert-only public intake policies; authenticated admin read and narrowly scoped workflow updates. It revokes broad table access before granting the minimum stated operations.

## Ordered migration inventory

| No. | File | Tables affected | Functions / RPCs | RLS / policies | Grants and dependencies |
|---:|---|---|---|---|---|
| 007 | `007_platform_roles_architecture.sql` | Creates `platform_users`, `companies`, `company_users`, `contractors`, `contractor_users`, `requirement_contractors`, `candidate_applications`, `interviews`, `candidate_joinings`; adds candidate account/profile fields and employer requirement ownership/lifecycle fields; creates `requirement_code_seq`. | `private.assign_requirement_code()` plus trigger. | Enables RLS on all new tables; creates admin select/insert/update policies for each. | Revokes anon/auth broad access, grants authenticated select/insert/update subject to RLS; depends on base three tables, `admin_users`, `private.is_admin`, `private.set_updated_at`; deliberately refuses an already-partial install. |
| 008 | `008_company_onboarding_rls.sql` | Adds company contact person, workforce size, onboarding notes/consent fields; auth signup trigger populates company/account/membership records. | `private.handle_company_signup()`; `public.set_company_account_status(uuid,text)`. | Company users can read their own platform account, membership, and member company; admin policies from 007 remain. | Public/anon cannot execute approval RPC; authenticated execution is RLS/admin checked. Depends on 007 and `auth.users`. |
| 009 | `009_company_requirements_rls.sql` | Reads/writes `employer_requirements` owned by active companies. | `private.current_active_company_id()`; `create_company_requirement`, `update_company_requirement`, `close_company_requirement`, `set_company_requirement_stage`. | Adds active-company read-own-requirements policy (later dropped by 015). | Authenticated execute on lifecycle RPCs; depends on 007/008 and active-company membership/status. |
| 010 | `010_contractor_assignment_rls.sql` | Adds contractor website/pincode/categories/onboarding fields and assignment decline/response fields; auth trigger creates contractor/account/membership. | `private.handle_contractor_signup()`, `private.current_active_contractor_id()`; `set_contractor_account_status`, `assign_requirement_contractor`, `respond_requirement_assignment`, `set_requirement_assignment_status`. | Own platform account/membership/profile; active contractor reads own assignments and assigned requirements (two base-table policies later dropped by 015). | Authenticated execute on controlled RPCs; depends on 007–009 and `auth.users`. |
| 011 | `011_public_jobs_projection.sql` | No table mutation; reads publishable/open `employer_requirements` through a narrow projection. | `get_public_job_requirements(integer,integer)`. | Leaves base-table RLS unchanged. | Execute to anon/authenticated; depends on required employer requirement columns from prior schema/migrations. |
| 012 | `012_candidate_requirement_interest.sql` | Transactionally validates an eligible requirement, inserts/uses `candidates`, and creates `candidate_applications`. | `register_candidate_requirement_interest(text,jsonb)`. | No new base-table policy; security-definer function is the narrow public boundary. | Execute to anon only; depends on 007 application table and 011 projection. Normalizes phone and prevents unsafe arbitrary application creation. |
| 013 | `013_admin_candidate_application_management.sql` | Adds `candidate_applications.admin_notes` and applied-date index; updates application workflow. | `admin_update_candidate_application(uuid,text,text)`. | Uses `private.is_admin`; no new policy. | Execute authenticated, denied public/anon; depends on 011–012 and application/candidate/requirement tables. |
| 014 | `014_interview_scheduling_management.sql` | Adds interview round, supersession, meeting/contact/instruction/result fields, constraints/index; removes authenticated direct interview insert/update. | `admin_schedule_candidate_interview`, `admin_reschedule_candidate_interview`, `admin_update_candidate_interview`. | Existing admin read policy remains; mutation authorization is inside RPCs. | Authenticated execute, denied public/anon; depends on 007 interview trigger/helpers and 011–013. |
| 015 | `015_tenant_requirement_security_boundary.sql` *(untracked)* | Reads `employer_requirements` and `requirement_contractors`; no destructive table rebuild. | `get_company_requirements`, `get_staffing_partner_assignments`, `manage_company_requirement`, `staffing_partner_respond_requirement_assignment`. | Drops company/contractor tenant base-table read policies while retaining admin policies; replaces tenant reads with narrow security-definer projections. | Grants authenticated wrapper/projection execution and revokes authenticated execution on selected underlying tenant mutation RPCs. Depends on 009/010 helpers and RPC signatures. Companion test and client changes are also uncommitted. |

Migration files span 007–015 with no 001–006 files in this checkout. That absence does not prove those migrations never existed or were not applied elsewhere. Tests are present for 009–015; no matching repository SQL tests were found for 007–008.

## Repository-proven capabilities

- Public employer requirement and candidate registration tables with consent fields and RLS.
- Authenticated admin allow-list and workflow management.
- Company and contractor onboarding/membership/account-status models.
- Company-owned requirements and contractor assignments.
- Public job projection and transactional candidate interest/application registration.
- Admin application status/internal notes.
- Multi-round interview scheduling/rescheduling/outcome support.
- Joining table exists from 007, but no later full joining workflow migration/UI was found.
- Migration 015 is designed to remove tenant access to sensitive base-table columns, but it is untracked and therefore only a proposed repository change.

## Production facts not proven

The following require a read-only production Supabase audit and cannot be inferred from files:

- Which migrations, if any, were applied, in what order, and whether SQL differs from repository copies.
- Actual tables, columns, constraints, indexes, triggers, functions, owners, `SECURITY DEFINER` settings, search paths, grants, RLS enable/force state, and policies.
- Whether migration 015 or any hand-applied equivalent is live.
- Supabase Auth provider, redirect URL, password/MFA, session, SMTP, CAPTCHA, and rate-limit settings.
- Current users, memberships, orphan records, tenant isolation, data volume, duplicate phones, or production data quality.
- Storage buckets/policies, backups/PITR, logs, Realtime publications, Edge Functions, Vault secrets, network restrictions, or project region/tier.
- The deployed site's exact commit and whether its `config.js` matches this checkout.

## Safe production verification plan (future, read-only)

When separately authorized, capture Supabase migration history, catalog objects, grants, policies, triggers, function definitions/owners/search paths, Realtime publications, storage policies, Auth configuration, and deployed commit. Compare by object identity and definition—not merely migration filenames. Do not apply 015 until its preflight and tests pass in staging and production drift is resolved.
