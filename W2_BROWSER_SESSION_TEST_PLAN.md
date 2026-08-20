# W2 Live Staging Browser and Session Validation Plan

Status: execution complete on dedicated NONPROD staging; the browser/session matrix and fixture cleanup passed.

## Safety boundary

This plan is for the dedicated NONPROD staging environment only. It does not authorize production access, deployment, DNS changes, external tunnels, Meta/WhatsApp integration, real identities, or outbound email/SMS. No credential, token, endpoint, host, project identifier, or connection string belongs in this document or Git.

Before every fixture create/cleanup or browser-test session:

1. verify the reviewed branch, commit, clean worktree/index, and synchronized upstream;
2. run the static staging guard;
3. run the approved read-only staging identity probe when database work is authorized;
4. confirm all fixture labels and IDs belong to the approved synthetic fixture manifest; and
5. stop on any production denylist match or unexpected existing record.

## Recommended Auth creation method

Use the Supabase Dashboard for the dedicated staging project to create the synthetic Auth users manually. Create users directly with auto-confirm enabled and invitation delivery disabled, if supported by the staging Dashboard workflow. An operator should generate unique passwords in an approved password manager and share them only through the approved secret channel.

This is preferred because it uses the supported Auth administration surface without placing a secret/service credential in the repository, browser, shell history, or helper script. Do not insert directly into `auth.users`. Do not automate user creation with a browser publishable key. An Admin/Auth API helper should be considered only under a separate review with a server-only staging credential and an explicit cleanup authorization.

## Synthetic fixture matrix

Use the reserved `.test` namespace and no phone numbers. Emails are labels, not real mailboxes.

| Fixture label | Synthetic email | Auth user | `admin_users` | Staff profile | Staff roles | `platform_users` | Tenant linkage | Shell | Staff management |
|---|---|---:|---:|---:|---|---|---|---:|---:|
| `bootstrap_admin` | `w2.bootstrap@browser-validation.test` | Yes | Yes | No | None | No | None | Yes | Yes |
| `super_admin` | `w2.super-admin@browser-validation.test` | Yes | No | Active | `super_admin` | No | None | Yes | Yes, including elevated roles |
| `admin` | `w2.admin@browser-validation.test` | Yes | No | Active | `admin` | No | None | Yes | Yes, non-elevated only |
| `recruiter` | `w2.recruiter@browser-validation.test` | Yes | No | Active | `recruiter` | No | None | Yes | No |
| `operations` | `w2.operations@browser-validation.test` | Yes | No | Active | `operations` | No | None | Yes | No |
| `viewer` | `w2.viewer@browser-validation.test` | Yes | No | Active | `viewer` | No | None | Yes | No |
| `inactive_staff` | `w2.inactive@browser-validation.test` | Yes | No | Suspended or inactive | `viewer` active | No | None | No | No |
| `revoked_role_staff` | `w2.revoked@browser-validation.test` | Yes | No | Active | `viewer` revoked | No | None | No | No |
| `non_member` | `w2.non-member@browser-validation.test` | Yes | No | No | None | No | None | No | No |
| `company_user` | `w2.company-a@browser-validation.test` | Yes | No | No | None | Company, active | Synthetic Company A membership only | No | No |
| `contractor_user` | `w2.contractor-a@browser-validation.test` | Yes | No | No | None | Contractor, active | Synthetic Contractor A membership only | No | No |
| `anonymous` | Not applicable | No | No | No | None | No | None | No | No |

Do not combine fixture roles or reuse tenant identities as staff. Before creation, read-only checks must confirm the synthetic emails and planned IDs do not already exist.

## Bootstrap recovery strategy

`bootstrap_admin` is the recovery identity. Keep it solely in `admin_users`, without a staff profile or `platform_users` row. Verify it can log in and reach Staff Management before changing any other fixture. Never deactivate it, remove its bootstrap row, use it as a role-revocation target, or include it in session-expiry experiments. Record the recovery identity by fixture label only; never record its password.

Keep at least one known-good recovery browser session available while testing role/state changes in a separate browser profile. Cleanup removes the synthetic bootstrap row only after every other fixture is removed and cleanup verification succeeds.

## Fixture creation and linkage sequence

Fixture creation requires a separate authorization and an approved fixture manifest containing the Dashboard-created Auth UUIDs without passwords.

1. Create the eleven Auth users in the staging Dashboard without invitations or outbound email.
2. Run read-only duplicate and tenant-conflict checks for every Auth UUID.
3. Add only `bootstrap_admin` to `admin_users` using narrowly scoped, separately authorized staging SQL; no public RPC exists for bootstrap allowlisting.
4. Log in locally as `bootstrap_admin` and use W2 RPC-backed Staff Management to create profiles and grant initial roles for `super_admin`, `admin`, `recruiter`, `operations`, and `viewer`.
5. Use the same W2 RPCs to create `inactive_staff` and `revoked_role_staff`, then set the former inactive/suspended and revoke the latter's final active role.
6. Leave `non_member` as Auth-only.
7. Create Synthetic Company A and link only `company_user` through the existing company/platform contracts. Create no requirement or candidate data.
8. Create Synthetic Contractor A and link only `contractor_user` through the existing contractor/platform contracts. Create no assignment or candidate data.
9. Run a read-only fixture inventory and confirm the expected shell/management matrix before browser execution.

Staff profile, role, and state mutations must use the W2 RPCs. The narrow bootstrap and tenant-link SQL is an exception only because those fixture relationships have no W2 staff-management RPC; it requires separate review and authorization.

## Cleanup plan

Create and review a cleanup manifest before fixture creation. It must contain only the synthetic Auth UUIDs and synthetic tenant entity IDs generated for this test. Cleanup must fail closed if any target falls outside that manifest or if target counts differ from the plan.

Cleanup order:

1. revoke all active synthetic staff roles through W2 RPCs;
2. remove synthetic `staff_roles`, then synthetic `staff_profiles`, using narrowly scoped privileged staging cleanup because no delete RPC exists;
3. remove Synthetic Company A and Contractor A memberships;
4. remove the synthetic company/contractor entities after confirming they own no non-fixture records;
5. remove the corresponding synthetic `platform_users` rows;
6. remove synthetic audit rows associated with the fixture actors/entities only under separately authorized privileged cleanup, after retaining sanitized validation evidence;
7. remove the synthetic `bootstrap_admin` row from `admin_users` after all other cleanup checks pass;
8. delete the eleven Auth users through the staging Dashboard last; and
9. run read-only zero-residue checks across Auth, staff, tenant membership, tenant entity, platform-user, and audit records.

Never delete a shared baseline object, loosen RLS, cascade into unlisted records, or broaden a cleanup target after a failure.

## Localhost-only staging browser configuration

Do not edit or deploy the tracked `config.js`. Prepare a temporary serving directory outside the repository:

1. copy the static site into a newly created temporary directory, excluding `.git`, `.env*`, `node_modules`, and local secret material;
2. generate the temporary copy's `config.js` privately from `AADHYANT_STAGING_URL` and `AADHYANT_STAGING_PUBLISHABLE_KEY`;
3. never place a database password, database URL, secret/service-role key, or management token in browser configuration;
4. inject a local-only banner into the temporary admin pages reading `NONPROD / STAGING`; and
5. delete the temporary serving directory after testing.

The generated configuration must remain ignored/untracked, must not print values, and must never overwrite the repository's tracked configuration. Validate that the temporary URL is the approved staging project before starting the server.

Serve only on loopback from the temporary directory:

```powershell
python -m http.server 4173 --bind 127.0.0.1 --directory <temporary-staging-copy>
```

Open `http://127.0.0.1:4173/admin/`. Do not bind to all interfaces, create a tunnel, or publish the temporary directory.

No fixture or localhost helper script is included in this preparation. The Dashboard method avoids embedding an Auth administration credential, and the temporary browser-copy generator should be reviewed separately before it is allowed to read staging values.

## Browser/session test sequence

Use separate browser profiles for manager and target sessions. Capture pass/fail evidence by fixture label only.

1. Open `/admin/` anonymously and confirm redirect before protected content appears.
2. Log in as `bootstrap_admin`; confirm operational dashboard and Staff Management.
3. Log in as `super_admin`; confirm shell and elevated staff controls.
4. Log in as `admin`; confirm non-elevated staff management and denial of elevated controls/RPCs.
5. Log in separately as `recruiter`, `operations`, and `viewer`; confirm shell-only behavior and no operational data.
6. Test direct `/admin/` navigation and direct Staff Management navigation for every unauthorized identity.
7. Confirm `inactive_staff`, `revoked_role_staff`, `non_member`, `company_user`, and `contractor_user` are redirected/denied.
8. Log out and confirm logout removes access, redirects correctly, and denies browser-history access.
9. Refresh authorized and unauthorized sessions and confirm correct restoration or denial.
10. Invalidate a disposable non-recovery session and confirm session expiry/refresh failure removes access.
11. Open multiple tabs; sign out or change authorization in one and confirm the others recheck.
12. Grant and revoke permitted roles through Staff Management; confirm UI refresh and server enforcement.
13. Activate, suspend, deactivate, and reactivate an allowed target; confirm immediate or next-check access loss/restoration.
14. From the browser console, attempt unauthorized staff-list/mutation RPCs, direct `staff_profiles`/`staff_roles` mutations, and direct `audit_logs` insertion; confirm server denial.
15. Confirm no W2 role gains implicit candidate, application, company, contractor, interview, or joining access.
16. Restore planned fixture state, capture sanitized results, and run the approved cleanup procedure.

## Pass/fail criteria

PASS requires every expected-access case to succeed, every denial case to fail server-side, cross-tab/session changes to converge without stale access, direct URL navigation to remain guarded, and cleanup to return all fixture counts to zero.

Immediately stop and mark FAIL if any tenant identity enters the staff shell, any unauthorized user invokes a staff RPC, any browser role writes staff/audit tables directly, a revoked/inactive identity retains access after recheck, the recovery admin becomes unavailable, staging identity becomes uncertain, or any fixture cannot be safely cleaned up.

## Execution record

The following manual localhost staging checks passed:

- unauthenticated direct-access redirect;
- authorized access for `bootstrap_admin`, `super_admin`, `admin`, `recruiter`, `operations`, and `viewer`;
- denial for inactive staff, revoked-role staff, non-members, company users, and contractor users;
- logout/back protection, refresh/session restoration, and multi-tab logout propagation;
- live role-revocation and inactive-state access loss, followed by fixture restoration;
- Staff Management permission-boundary retest after commit `e51cb422ed65391ef5bc23527f4c606dea66d068`;
- unauthorized browser RPC/direct-table denial, nine of nine checks; and
- deterministic session invalidation across the recorded access-token expiry boundary.

An ordinary-admin presentation defect made elevated controls appear actionable even though server authorization denied elevated mutations. Commit `e51cb422ed65391ef5bc23527f4c606dea66d068` made those controls visibly and semantically disabled and added focused passing regression coverage.

The recruiter fixture temporarily drifted to Active + Viewer with Recruiter revoked. It was corrected through the W2 role RPCs and verified as Active + Recruiter before cleanup.

Manifest-bound application cleanup passed. During Dashboard Auth cleanup, an incorrect bulk selection deleted `bootstrap_admin` instead of `non_member`, and its `admin_users` row cascaded automatically. No recovery identity was recreated. The remaining `non_member` was subsequently deleted individually. Final read-only checks proved zero fixture residue across Auth, application, tenant, dependency, and audit records while preserving unrelated staging baseline counts. No real data was affected and production was not contacted.

W2 browser/session validation and fixture cleanup are complete. W2 is fully complete locally and ready for closure after the final evidence commit is pushed under separate authorization.
