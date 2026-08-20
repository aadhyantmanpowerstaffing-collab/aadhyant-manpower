# W2 Staging Runtime Validation

## Validation context

| Field | Result |
|---|---|
| Validation dates | 2026-08-19 through 2026-08-20 (Asia/Calcutta) |
| Git branch | `web-platform-development` |
| Runtime Git commit | `5423c80c0f728ebc1e5c8cb18fb3e0faa66d5ff4` |
| UI hardening/retest commit | `e51cb422ed65391ef5bc23527f4c606dea66d068` |
| Environment | Dedicated NONPROD staging |
| PostgreSQL server | 17.6 |
| PostgreSQL client | 18.6 |
| Supabase CLI | 2.111.0 (repository-pinned development dependency) |
| Static staging guard | PASS |
| Read-only database identity verification | PASS |

This evidence intentionally omits project identifiers, endpoints, credentials, keys, and connection details. It does not authorize production migration or deployment.

## Runtime results

| Validation | Result |
|---|---|
| Migration `017_internal_staff_auth_roles.sql` | PASS |
| Migration 017 SHA-256 | `6db9cf43d1a15d1b1451bf5b06f7964e92ba4c467a0c25bb39550b03c5ffe503` |
| Checkpoint `017_internal_staff_auth_roles_test.sql` | PASS |
| Migration 015 tenant-security regression | PASS |
| Migration 016 schema-foundation regression | PASS |

Migration 017 installed all six private authorization helpers and seven authenticated staff RPCs. Runtime catalog checks confirmed fixed empty search paths, security-definer execution, narrow return contracts, authenticated-only public RPC execution, revoked anonymous execution, inaccessible private helpers, enabled RLS, and removal of direct browser grants and policies from the staff tables.

## Authority results

- A bootstrap `admin_users` member without a staff profile retained admin-shell and staff-bootstrap authority.
- An active `super_admin` received shell and full staff-management authority.
- An active `admin` received shell and permitted non-elevated staff-management authority but could not manage elevated roles or elevated staff.
- Active `recruiter`, `operations`, and `viewer` identities received shell access without staff-management authority.
- W2 roles received no implicit candidate, application, company, contractor, interview, joining, or other operational-table authority.

## Denial results

- Inactive and suspended staff were denied.
- Revoked roles were ignored immediately.
- An identity without a staff profile was denied.
- An authenticated non-member was denied.
- Company and contractor identities were denied internal staff access.
- Anonymous access was denied.

## Write and elevated-role protection

- Direct `staff_profiles` mutation was denied.
- Direct `staff_roles` INSERT, UPDATE, and DELETE were denied.
- Direct `audit_logs` insertion was denied.
- Unauthorized elevated-role grant and revocation were denied.
- The final active `super_admin` could not have its role revoked or profile suspended, deactivated, or made inactive.

## Audit and fixture safety

Authorized profile creation, profile update, active-state change, role grant, and role revocation created server-side audit rows with the expected actor, action, `entity_type`, `entity_id`, and source. Browser audit forgery was denied.

All checkpoint identities and data were synthetic and contained in a single transaction ending in `ROLLBACK`. Cleanup checks confirmed that synthetic Auth users, staff profiles, staff roles, platform identities, bootstrap-admin rows, and audit events were absent afterward and relevant counts returned to baseline. No real user or business data was used, and no production endpoint was contacted.

## Resolved runtime defects

Two defects discovered during staging validation were fixed and revalidated:

1. `private.has_staff_role()` initially used an invalid scalar/array ANY expression:

   - Before: `p_role = any((select private.current_staff_roles()))`
   - After: `p_role = any(private.current_staff_roles())`

2. Checkpoint 017 initially performed privileged `staff_roles` verification while still acting as `authenticated`. The test now executes `RESET ROLE` before that privileged verification. Production RLS and grants were not weakened.

## Regression evidence

The rollback-scoped migration 015 tenant-security test and migration 016 schema-foundation test both passed after migration 017. W2 did not broaden company or contractor tenant access and preserved the migration 015 security boundary.

## Browser and session validation

Live localhost validation against dedicated NONPROD staging passed for unauthenticated direct-access redirect; `bootstrap_admin`, `super_admin`, `admin`, `recruiter`, `operations`, and `viewer`; and denial of inactive staff, revoked-role staff, non-members, company users, and contractor users. Logout/back protection, refresh/session restoration, multi-tab logout propagation, live role-revocation access loss, and live inactive-state access loss passed. Mutated fixtures were restored and verified before cleanup.

The Staff Management permission-boundary retest passed after commit `e51cb422ed65391ef5bc23527f4c606dea66d068`. An unauthorized browser test using a synthetic viewer passed all nine checks: staff listing and role-mutation RPCs were authorization-denied, and direct `staff_profiles` INSERT/UPDATE/DELETE, `staff_roles` INSERT/UPDATE/DELETE, and `audit_logs` INSERT were permission-denied. No unauthorized mutation succeeded.

The final session invalidation/expiry-boundary test passed. A disposable viewer session was globally invalidated from an isolated context; after the recorded access-token expiry boundary, the original context returned to login, could not restore the protected shell, and could not refresh the revoked session. No raw token was recorded.

## UI defect and regression history

Manual testing found that elevated role checkboxes appeared actionable to an ordinary admin even though server-side elevated grant/revoke authorization was intact. Commit `e51cb422ed65391ef5bc23527f4c606dea66d068` made elevated controls visibly and semantically non-actionable for ordinary admins and preserved the intended controls for bootstrap and super admins. Focused UI regression tests passed, including the async save/error re-enable invariant.

## Fixture correction and cleanup evidence

During manual mutation testing, the recruiter fixture temporarily became Active with Viewer active and Recruiter revoked. It was restored through the approved W2 revoke/grant RPCs, then verified as Active with Recruiter as its only active role. The viewer and all other fixtures were also verified against the manifest before cleanup.

Manifest-bound application cleanup and its exact-count assertions passed. During the subsequent Dashboard Auth cleanup, an incorrect bulk selection deleted `bootstrap_admin` instead of `non_member`; the associated `admin_users` row was removed automatically by `ON DELETE CASCADE`. No recovery identity was recreated because application cleanup had already succeeded and no further privileged mutation was required. The remaining `non_member` was later deleted individually through the staging Dashboard.

Final read-only verification found zero fixture matches across Auth users, identities, sessions and other inspected Auth dependencies; staff, bootstrap, platform, tenant-membership, and synthetic tenant records; discovered actor/creator references; and fixture-associated audit logs. Unrelated staging baseline counts were preserved. No real data was affected, no production endpoint was contacted, and the local fixture manifest and temporary browser copy were removed after verification.

W2 database/security validation, browser/session validation, and fixture cleanup are complete. W2 is fully complete locally and ready for closure after the final evidence commit is pushed under separate authorization.
