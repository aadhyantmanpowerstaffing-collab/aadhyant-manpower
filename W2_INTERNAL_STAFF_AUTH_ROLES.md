# W2 Internal Staff Authentication and Role Authorization

Status: W2 database/security runtime validation, browser/session validation, and synthetic-fixture cleanup are complete on dedicated NONPROD staging.

## Staging runtime validation

Migration 017, checkpoint 017, and the required migration 015/016 regressions passed on dedicated NONPROD staging. Runtime evidence, resolved defect history, browser/session results, and fixture cleanup are recorded in [W2_STAGING_RUNTIME_VALIDATION.md](W2_STAGING_RUNTIME_VALIDATION.md).

## Authority model

Internal staff authenticate with Supabase Auth. Internal identities remain separate from `platform_users`; any Auth user represented in `platform_users` is denied internal staff authority even if a conflicting staff record exists.

Two deliberately distinct authority paths exist:

- `admin_users` is the legacy/bootstrap override. It continues to authorize the existing operational admin application through `private.is_admin()`, does not require a `staff_profiles` row, and can bootstrap the first staff profile and `super_admin` role.
- Ordinary internal staff require an active `staff_profiles` row and at least one active `staff_roles` row. Their W2 authority does not flow through `private.is_admin()` and does not grant access to existing operational tables or RPCs.

This precedence preserves bootstrap access without treating every staff member as a legacy administrator. Removing an Auth user from `admin_users` ends bootstrap authority; the user then needs valid staff membership for shell access.

## Roles

| Role | Admin shell | Staff list/profile | Non-elevated roles | `admin`/`super_admin` roles | Existing operational modules |
|---|---:|---:|---:|---:|---:|
| `super_admin` | Yes | Yes | Manage | Manage | No implicit grant |
| `admin` | Yes | Yes | Manage | Denied | No implicit grant |
| `recruiter` | Yes | Denied | Denied | Denied | Deferred |
| `operations` | Yes | Denied | Denied | Denied | Deferred |
| `viewer` | Yes | Denied | Denied | Denied | Deferred |
| bootstrap `admin_users` member | Yes | Yes | Manage | Manage | Existing bootstrap access |

Suspended or inactive profiles and users without active roles fail authorization immediately at the next server authorization check. A revoked final role removes shell access. Company and contractor identities cannot acquire internal staff access.

## Database helpers and RPCs

Migration `017_internal_staff_auth_roles.sql` adds fixed-search-path, current-caller helpers in `private`: `current_staff_profile_id()`, `current_staff_roles()`, `has_staff_role(text)`, `can_access_admin_shell()`, `can_manage_staff()`, and `can_manage_elevated_roles()`. They derive identity only from `auth.uid()`, accept no caller-supplied identity, use no dynamic SQL, and are not executable by browser roles.

Authenticated browser clients receive only narrow RPCs:

- `get_current_staff_session()` returns authorization flags, bootstrap state, profile ID, display name, active state, roles, shell access, and staff-management access.
- `list_internal_staff()` returns explicit staff list columns, including the Auth email needed for staff administration.
- `create_internal_staff(...)` attaches an existing Auth user to an internal staff profile; it does not create credentials.
- `update_internal_staff_profile(...)`, `set_staff_active_state(...)`, `grant_staff_role(...)`, and `revoke_staff_role(...)` perform authorized mutations.

Anonymous execution is revoked. Direct browser grants and W1 policies on `staff_profiles` and `staff_roles` are removed; reads and writes flow through these RPCs. Browser inserts into `audit_logs` remain denied.

## Last-super-admin protection

Role revocation and profile deactivation serialize changes to the active super-admin roster with a transaction advisory lock. They reject removal, suspension, or deactivation of the final active `super_admin`. An `admin` cannot change elevated staff or grant/revoke `admin` or `super_admin`; only a bootstrap admin or active super-admin can do so.

The bootstrap path remains independently recoverable through `admin_users`. It is not counted as a staff `super_admin`, so the staff roster cannot accidentally collapse to zero after one has been established.

## Audit behavior

Security-definer staff-management RPCs append sanitized events to `audit_logs` for profile creation, profile updates, state changes, role grants, and role revocations. Each event records the Auth actor, staff actor type, action, entity, admin source, optional correlation ID, minimal metadata, and database-generated creation time. No token, password, or connection information is recorded.

## Browser session and route guard

`admin/admin-auth.js` is shared by login and `/admin/` dashboard pages. It requires a Supabase Auth session and calls `get_current_staff_session()` before revealing the shell. Unauthorized direct URLs return to admin login. Authorization is rechecked on auth-state changes, token refresh, window focus, tab visibility, cross-tab Auth storage changes, and a periodic interval. Sign-out, expiry, profile suspension, or role revocation removes access on the next check.

Bootstrap admins retain the existing operational dashboard. Non-bootstrap W2 staff receive only the shell foundation; operational navigation is intentionally withheld until later milestones authorize individual modules.

## Staff Management UI

Authorized managers can list staff, attach an existing Auth user by email, edit display names, activate/suspend/deactivate profiles, and grant or revoke permitted roles. Elevated controls are disabled for ordinary admins, but all authorization remains server-enforced. The UI creates no passwords, reset links, or Auth users and exposes no Auth metadata beyond the approved email projection.

## Tests

`017_internal_staff_auth_roles_test.sql` uses synthetic Auth identities inside one explicit transaction ending in `ROLLBACK`. It covers bootstrap compatibility; all five roles; inactive, revoked, non-member, company, contractor, and anonymous denial; direct staff/audit write denial; elevated-role escalation; last-super-admin protection; audit accuracy; and preservation of migration 015 tenant boundaries.

Dedicated staging applied migration 017 and passed checkpoint 017 plus rollback-scoped regressions 015 and 016. The complete browser/session matrix, permission-boundary retest, unauthorized browser mutation checks, expiry-boundary test, and final fixture cleanup also passed. W2 is complete locally and ready for closure after the evidence commit is pushed under separate authorization.

## Intentional limitations

- W2 does not create or invite Supabase Auth users. An authorized operator must provision the Auth identity through an approved server-side process first.
- W2 does not grant staff access to candidates, requirements, applications, interviews, joinings, company data, contractor data, or tenant RPCs.
- Operational permissions for recruiter, operations, and viewer roles are deferred to later milestones.
- Staff creation and initial role grant are separate RPC calls; an interrupted client can leave an active profile without a role, which has no shell access and can be completed by a manager.
- Production migration, deployment, DNS, Meta, and credential changes are outside this milestone.
