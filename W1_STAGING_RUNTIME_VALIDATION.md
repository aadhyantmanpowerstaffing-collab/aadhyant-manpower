# W1 Staging Runtime Validation

## Validation context

| Field | Result |
|---|---|
| Validation date | 2026-08-19 (Asia/Calcutta) |
| Git branch | `web-platform-development` |
| Reviewed Git commit | `24356489702eb5b2c825433845e6a47452222505` |
| Environment | Dedicated NONPROD staging |
| PostgreSQL server | 17.6 |
| PostgreSQL client | 18.6 |
| Supabase CLI | Not available in the validation environment (command not found) |
| Static staging guard | PASS |
| Read-only database identity verification | PASS |

This document intentionally omits environment identifiers, endpoints, credentials, keys, and connection details. It does not authorize production migration or deployment.

## Migration and checkpoint results

| Migration | Purpose | SHA-256 | Runtime Result | Checkpoint Test | Test Result |
|---|---|---|---|---|---|
| 007 | Platform roles and core company/contractor workflow architecture | `fba6ba2a6819aacaba02be03a9008ed26e79d30cad487e3a5c08b9b6be433273` | PASS | Not run in this validation sequence | not recorded |
| 008 | Company onboarding and tenant RLS | `a510d420096016e92d0288da046110b0a851f083b48ca50b5dbfec3f4c87f288` | PASS | Not run in this validation sequence | not recorded |
| 009 | Company requirement management and isolation | `31ebc12c076ee0ac2245ad193ef1d94fa6d6f0556f09827b14f0b15f59ec5fef` | PASS | `009_company_requirements_test.sql` | PASS |
| 010 | Contractor onboarding and controlled requirement assignments | `a61f4f86eaa8aa242a91983e66869df99081a51ca68aafcd665796f09ba05550` | PASS | `010_contractor_assignment_test.sql` | PASS |
| 011 | Narrow anonymous public-jobs projection | `2dd52c9d29dbac50eacae615d0b457ab65d499eccc89c3cc7466fd3cc60daad2` | PASS | `011_public_jobs_projection_test.sql` | PASS |
| 012 | Candidate interest registration for eligible requirements | `589ce5cd113babb59d20cabf5b213682dcf7c9358f93ddfbd4e38e879d587c9f` | PASS | `012_candidate_requirement_interest_test.sql` | PASS |
| 013 | Admin candidate-application status and note management | `832c6eee836e57afd8b04a67a2a4c30ea5b22b279dea0a676d6c9b73e20b564a` | PASS | `013_admin_candidate_application_management_test.sql` | PASS |
| 014 | Admin interview scheduling, rescheduling, and results | `6cf74864dee5d187f7e5d4d807bc82df32fec04e6ae02356825fa3d74117adbd` | PASS | `014_interview_scheduling_management_test.sql` | PASS |
| 015 | Tenant requirement and assignment security boundary | `8469096d30383641ac0abe925640e2ef7eff3e88430da21dcc1534229b55519a` | PASS | `015_tenant_requirement_security_boundary_test.sql` | PASS |
| 016 | W1 web-platform schema foundation | `911f082d8d147ab5fe6be4c7e9765368f217c0f604e18fd6873bf86461018638` | PASS | `016_web_platform_schema_foundation_test.sql` | PASS |

The repository baseline `supabase/schema.sql` also executed successfully before migrations 007-016.

## Runtime security evidence

### Checkpoint 009

- Company A and Company B were restricted to their own requirements.
- Anonymous public submission remained available while anonymous base-table reads were denied.
- Pending, suspended, candidate, and other non-member identities could not use company operations.
- Approved administrator reads and operational stage changes succeeded.

### Checkpoint 010

- Contractors saw only their own assignments and assigned requirements.
- Assignment acceptance, decline, and administrator lifecycle transitions were enforced.
- Pending and suspended contractors could not receive assignments.
- Cross-contractor responses and direct protected writes were denied.

### Checkpoint 011

- The public-jobs projection returned only open, public requirements with remaining positions.
- Private, draft, and closed requirements were excluded.
- Anonymous reads of requirement, candidate, and assignment base tables remained denied.

### Checkpoint 012

- Anonymous candidate interest registration succeeded only for an eligible open/public requirement.
- Duplicate interest registration was idempotent.
- Draft, private, closed, and unknown requirements were rejected.
- Candidate and application base-table reads remained denied to anonymous and non-member sessions.

### Checkpoint 013

- Approved administrators could update application status and internal notes.
- Invalid statuses, unknown applications, and oversized notes were rejected.
- Company and staffing-partner sessions could neither read applications nor invoke the admin operation.

### Checkpoint 014

- Eligible interviews could be scheduled with controlled round numbering.
- Rescheduling preserved the replaced interview and linked replacement history.
- Result, absence, completion, and cancellation transitions were enforced.
- Direct authenticated interview writes, duplicate current interviews, invalid transitions, and tenant scheduling were denied.

### Checkpoint 015

- Tenant base-read policies for requirements and assignments were removed while admin policies remained.
- Companies and contractors used narrow, ownership-checked projections and mutation wrappers.
- Company and contractor cross-tenant access was denied.
- Authenticated execution of four legacy full-row tenant mutation RPCs was revoked.
- Tenant projections did not expose internal notes or private ownership/contact columns.

### Checkpoint 016

- Staff profiles/roles, candidate preferences, controlled stages, stage history, and audit foundations were present with RLS enabled.
- The stage catalog contained the W1 vocabulary plus recognized legacy compatibility values.
- Browser roles could not directly forge stage-history or audit rows.
- The history trigger function was a fixed-empty-search-path `SECURITY DEFINER` with no browser execution grant.
- Migration 015 tenant policy, projection, and grant boundaries remained intact.

## Rollback and fixture safety

- Checkpoint synthetic identities and business fixtures were scoped to explicit transactions ending in rollback.
- Post-test cleanup was verified with read-only queries.
- Relevant pre-test and post-test row counts returned to their baseline values.
- No synthetic fixture persisted.
- No real users, candidates, companies, contractors, or contact data were used.
- No production endpoint was contacted.

## Remaining gaps and authorization boundary

- The W1 schema foundation is staging runtime-validated.
- W2 workflows are not yet validated.
- The migration 016 catalog test does not exercise full live staff-profile, staff-role, or candidate-preference writes.
- The application-stage trigger should receive behavioral insert/update coverage during W2.
- Audit writing remains intentionally deferred; W1 provides protected storage but no generic writer.
- End-to-end frontend/API workflows and production deployment remain unvalidated.
- Production migration is **not authorized** by this document.
