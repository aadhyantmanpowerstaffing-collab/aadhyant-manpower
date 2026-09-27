# Proposed release for explicit user approval

Approval status: PENDING for this expanded document and joining-details release.
The earlier resume-only approval does not authorize this upgrade or deployment.

## Concrete changes

1. Apply the guarded, unchanged `forward_proposed.sql` to Production project
   `wsuctjhbqiedttfnwjvf`, SHA-256
   `810a67ea870655a6df6df8e1bc8cdda8a853e659c10c86cc85f40ca8bc1f8229`.
2. Commit/push the scoped source manifest to `web-platform-development`, then
   deploy with the existing `pages-production.yml`, `deploy_production=true`.
   Verify fresh remote branch state and the exact scoped diff before doing so.
3. Preserve existing business records and legacy grant provenance. No historical
   migration replay, unrelated database changes, automatic recipient access, or
   real-candidate testing is included.

Admin selects individual active, verified documents (all existing categories),
bank details, UAN and ESIC for the eligible Company/Contractor per application.
The separate Candidate sharing-consent action is removed. Newly saved full bank
account numbers are stored in the existing private onboarding contract alongside
the fingerprint/last4; old hashed numbers must be saved once to become available.
Role/recipient checks and current Storage authorization remain mandatory.
Edits, replacement and revocation stop subsequent access until appropriate fresh
Admin sharing. Previously downloaded copies cannot be recalled.

## Evidence

- Genuine user v2 local run `resume-e2e-998030b5be06`: all reported markers PASS.
- User Production read-only run `document-preflight-864a86a72b5b`: preflight PASS,
  mutation not dispatched. No repeat manual review needed.
- All six tracked frontend/test patch sections exactly match the genuine v2
  package. Existing 317 frontend tests and artifact-build results remain applicable.
- Both Storage-schema native SQL variants: 22 checks per variant PASS.
- New execution wrapper: actual native SQL output through PowerShell parser and
  failure-sequencing tests; see `execution/validation.json`.
- No Production mutation, commit, push or deployment performed for this upgrade.

## Approval boundary and release behavior

Repository `AGENTS.md` requires explicit approval before a new Production write
and deployment. After approval, the guarded runner performs a fresh preflight,
one transaction with internal guards/postcheck, then an independent read-only
postcheck. `VerifyOnly` never dispatches the upgrade. Failures never trigger
automatic retry or an inferred rollback.

After database verification, deploy the scoped frontend. Until deployment, the
old consent/share mutation endpoints intentionally fail closed. Source manifests
and the complete reviewable patch accompany this package. No force push or
unrelated changes are authorized. Keep existing backup/recovery/M037 evidence;
revalidate only if a concrete new condition requires it.

The genuine local browser evidence covers the actual sharing component. Final
live portal validation remains a separate check using the approved TEST application.
