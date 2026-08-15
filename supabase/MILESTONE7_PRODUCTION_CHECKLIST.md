# Milestone 7 Production Migration Checklist

## Stop condition

Do not apply the migration until disposable-environment execution and RLS validation have passed. Static validation alone is not production approval.

Reviewed migration file:

```text
supabase/migrations/007_platform_roles_architecture.sql
```

## Before

- [ ] Obtain explicit approval for the reviewed architecture and SQL.
- [ ] Confirm the selected Supabase project is the intended production project.
- [ ] Confirm no CLI/project link points to an unintended environment.
- [ ] Take and verify a current database backup/export using the approved Supabase process.
- [ ] Save a schema snapshot including tables, columns, constraints, indexes, triggers, functions, grants, and RLS policies.
- [ ] Confirm `admin_users`, `employer_requirements`, and `candidates` exist.
- [ ] Confirm `private.is_admin()` and `private.set_updated_at()` exist.
- [ ] Confirm no Milestone 7 table, extension column, sequence, trigger, or helper function already exists.
- [ ] Record current row counts without exporting personal data:

```sql
select count(*) from public.employer_requirements;
select count(*) from public.candidates;
```

- [ ] Verify the current public Employer submission works.
- [ ] Verify the current public Candidate submission works.
- [ ] Verify approved Admin login, lists, filters, and status updates work.
- [ ] Capture current RLS policies and table grants for the three existing tables.
- [ ] Schedule a maintenance window and prevent concurrent schema changes.
- [ ] Reconfirm the SQL file contains no production credentials or destructive commands.

## Apply

- [ ] Open the correct Supabase project's SQL Editor manually.
- [ ] Open the reviewed `007_platform_roles_architecture.sql` file locally.
- [ ] Confirm the file begins with `BEGIN;` and ends with `COMMIT;`.
- [ ] Execute the complete reviewed migration once, not selected fragments.
- [ ] Observe all SQL Editor output and stop on the first error.
- [ ] If any statement fails, do not rerun blindly.
- [ ] Confirm transaction rollback before investigating a failed application.
- [ ] Do not weaken RLS or remove constraints to force success.

## After: schema

- [ ] Confirm all nine new tables exist.
- [ ] Confirm existing tables and row counts remain present and unchanged.
- [ ] Confirm candidate and requirement extension columns exist with expected defaults/nullability.
- [ ] Confirm `required_headcount` remains intact.
- [ ] Confirm RLS is enabled on every new table.
- [ ] Confirm exactly the reviewed `M7 ...` admin policies exist.
- [ ] Confirm no anonymous SELECT/UPDATE/DELETE policy was introduced.
- [ ] Confirm no DELETE grant or policy exists for authenticated browser roles.
- [ ] Confirm indexes and updated-at triggers exist.
- [ ] Confirm the requirement-code sequence/function/trigger exist.

## After: existing data and flows

- [ ] Inspect one existing Employer row and confirm original values are unchanged.
- [ ] Confirm its `company_id` and `created_by_user_id` may remain null.
- [ ] Confirm its requirement code remains null as documented.
- [ ] Inspect one existing Candidate row and confirm original values are unchanged.
- [ ] Confirm its `user_id` remains null and no automatic account link occurred.
- [ ] Perform one authorized public Employer test insert using the existing form.
- [ ] Confirm it appears in the Admin Dashboard and receives a unique requirement code.
- [ ] Perform one authorized public Candidate test insert using the existing form.
- [ ] Confirm it appears in the Admin Dashboard.
- [ ] Verify employer and candidate counts, lists, search/filter, and pagination.
- [ ] Verify one Employer status update and one Candidate status update.

## After: negative RLS tests

- [ ] Anonymous Employer INSERT is allowed with valid current-form columns and consent.
- [ ] Anonymous Candidate INSERT is allowed with valid current-form columns and consent.
- [ ] Anonymous SELECT/UPDATE/DELETE on existing protected tables is denied.
- [ ] Anonymous access to `admin_users` and every new table is denied.
- [ ] Authenticated non-admin SELECT/INSERT/UPDATE/DELETE on new tables is denied by RLS.
- [ ] Authenticated non-admin cannot read candidate, company, contractor, requirement, or admin notes data.
- [ ] Approved admin can SELECT/INSERT/UPDATE new operational tables.
- [ ] Approved admin DELETE remains denied.
- [ ] Public access cannot add rows to `admin_users`.

## After: relational workflow tests

- [ ] Create disposable Company, Contractor, and platform-user fixtures through an approved admin context.
- [ ] Confirm valid company and contractor memberships succeed.
- [ ] Confirm invalid foreign keys fail.
- [ ] Confirm assigned headcount must be positive.
- [ ] Confirm a contractor-sourced application requires an assignment.
- [ ] Confirm an assignment for requirement A cannot be attached to an application for requirement B.
- [ ] Confirm multiple interviews can belong to one application.
- [ ] Confirm only one current joining row can belong to an application.
- [ ] Confirm invalid controlled statuses fail.
- [ ] Confirm updates advance `updated_at` without overwriting business fields.

## Failure response

- [ ] Stop feature rollout immediately.
- [ ] Do not rerun the migration until database state is inventoried.
- [ ] Confirm whether the explicit transaction rolled back.
- [ ] Compare current schema and row counts with the saved baseline.
- [ ] Preserve SQL Editor error output.
- [ ] Prepare a reviewed forward-fix migration if necessary.
- [ ] Do not drop new tables that may contain required operational data.
- [ ] Restore from backup only through the approved recovery process when required.

## Approval record

- [ ] Record who reviewed the architecture.
- [ ] Record who reviewed RLS and grants.
- [ ] Record disposable-environment test results.
- [ ] Record backup identifier/time.
- [ ] Record production execution time and operator.
- [ ] Record post-migration validation result.
