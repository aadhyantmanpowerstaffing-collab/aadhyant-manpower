# W1 Schema Foundation

## Purpose

W1 adds the minimum shared schema needed for later internal recruitment workflows without replacing existing Candidate, Requirement, Application, Interview, Joining, Company, Contractor, or tenant-access contracts. It is additive design work only and has not been applied to production.

## Migration

`supabase/migrations/016_web_platform_schema_foundation.sql` depends on the repository schema through migration 015. Its preflight refuses missing prerequisites or partial W1 object collisions and wraps all changes in one transaction.

## Tables added

| Table | Purpose |
|---|---|
| `staff_profiles` | Internal Auth-linked staff identity and active/suspended/inactive state, separate from external `platform_users.account_type`. |
| `staff_roles` | Many-role mapping with `super_admin`, `admin`, `recruiter`, `operations`, and `viewer`; assignments can be active or revoked. |
| `candidate_preferences` | One normalized preference profile per existing Candidate, including location/role arrays, salary, shift/hours, facilities, and joining availability. |
| `application_stages` | Controlled target stage vocabulary plus three recognized legacy application values. |
| `application_stage_history` | Append-only initial-stage and transition history for existing `candidate_applications`. |
| `audit_logs` | Restricted generic audit-event storage for later domain-specific server/RPC writers. |

No `candidate_master`, `vacancies`, or `joining_records` replacement is introduced.

## Existing table extension

`candidate_applications` receives nullable `source_reference text` and `correlation_id uuid` columns. Existing rows and the current `application_status` constraint are not rewritten. Existing application creation and administration calls therefore remain compatible.

## Constraints and indexes

- Staff status and role vocabularies use checks and Auth foreign keys.
- Candidate salary ranges must be nonnegative and ordered. Immediate joining cannot also carry a future availability date.
- Stage history references the controlled stage catalog, prevents same-stage transitions, and limits reasons to 2,000 characters.
- History and audit metadata must be JSON objects.
- GIN indexes support candidate preference array lookup.
- Application/history/audit correlation and operational lookup indexes support later workflow tracing.

## Stage compatibility

The target stages are `new_lead`, `registered`, `interested`, `applied`, `screening`, `interview_scheduled`, `interview_attended`, `selected`, `joining_pending`, `joined`, `active`, `rejected`, `no_show`, `withdrawn`, and `left`.

Existing values `shortlisted`, `interview`, and `cancelled` remain recognized as legacy values so the history trigger cannot break current clients. W1 deliberately does not alter or backfill the current application-status constraint. W4 must perform any reviewed vocabulary migration and expose a controlled transition service.

## History behavior

`private.record_application_stage_history()` is a fixed-empty-search-path `SECURITY DEFINER` trigger function. It records new applications and actual status changes, including the authenticated actor when available and the application's correlation ID. Current entry points receive source `database`; future domain RPCs can add richer reason/source metadata without permitting direct browser inserts.

No existing application is backfilled merely by applying migration 016.

## RLS and grants

RLS is enabled on every new table. Anonymous receives no privileges.

- Existing allowlisted administrators may read/create/update staff profiles, staff roles, and Candidate preferences through existing `private.is_admin()` authorization.
- Existing allowlisted administrators may read the stage catalog, stage history, and audit logs.
- History and audit tables grant no browser INSERT, UPDATE, or DELETE capability and have no mutation policies.
- Candidate self-service, company disclosure, contractor disclosure, and non-admin staff authorization are deferred until their boundaries and narrow projections are implemented and tested.
- No migration 015 policy, grant, or tenant projection is changed.

The audit table intentionally has no generic browser writer. Future modules should add narrow domain-specific server/RPC insertion paths instead of a forgeable catch-all audit RPC.

## Compatibility

The migration does not rename, remove, or change the type of any existing column or function signature. Public Jobs, public Candidate registration, Company requirements, Staffing Partner assignments, Admin applications, and Interview management retain their existing contracts. No frontend change is required for W1.

## Risks and limitations

- Runtime behavior must be verified in a disposable local or non-production Supabase before deployment consideration.
- Current application status vocabulary remains transitional until W4.
- Existing applications do not receive synthetic history rows.
- The automatic trigger captures status and actor but not a human reason; a future controlled transition service owns richer semantics.
- Internal role enforcement beyond the existing `admin_users` bootstrap is intentionally deferred to W2.
- Candidate self-access is deferred even where `candidates.user_id` exists, avoiding premature data exposure.
- Audit producers, retention, partitioning, and redaction rules remain future work.

## Intentionally not implemented

W1 does not implement webhook ingestion, WhatsApp messaging, Team Inbox, chatbot runtime, Flow Builder, matching, interview redesign, joining automation, campaigns, documents, AI, settings/feature flags, migration execution, frontend routes, or deployment.

## Validation

Staging runtime validation completed successfully; see `W1_STAGING_RUNTIME_VALIDATION.md`.

`supabase/tests/016_web_platform_schema_foundation_test.sql` checks object presence, RLS, anonymous denial, append-only grants/policies, helper security configuration, controlled stages, absence of duplicate core entities, correlation columns, and migration 015 function/grant compatibility. It is transactional and intended only for a disposable database.
