# Admin documents and joining details — release candidate, not deployed

Requested scope: remove the separate Candidate sharing-consent action; let an authorized Admin explicitly share selected uploaded documents and joining details with the eligible Company/Contractor for an application. Include all 21 existing document categories, bank account holder/name/number/IFSC, UAN and ESIC. No recipient gets automatic access.

## Implementation

- Extends the existing `private.candidate_resume_shares` ledger. Does not introduce a duplicate Candidate, Application, document or sharing system.
- Preserves legacy consent provenance, active resume grants and prior revocations. New grants record Admin authorization without inventing Candidate consent. Old mutation endpoints fail closed and request reload.
- Uses the current account, application, membership, role, recipient and Contractor-assignment boundaries. Documents must be active and verified. Only the exact selected document is shared. Replacement, reassignment and inactive-account cases are rechecked.
- Bank, UAN and ESIC are three independently selectable items. Lists contain labels/status only. Full values require an explicit authorized View details request and remain out of logs, audit metadata, browser persistence, broad Admin projections and notifications.
- Stores newly saved full account numbers in the canonical RLS-protected onboarding row, alongside the existing fingerprint/last4. Browser table access stays revoked. Existing hashed-only account numbers cannot be reconstructed; those Candidates must save the full number once. Blank numbers subsequently preserve stored values. UAN/ESIC checkbox restoration is fixed.
- Every onboarding edit rotates an opaque revision and invalidates earlier joining-detail shares. Admin must explicitly share the new version. Audit records contain grant identity and a boolean, not document paths or numbers.
- Recipient downloads use the authenticated Storage request and current RLS. No public or signed recipient URL. Stopping sharing prevents future authorized access; it cannot recall downloaded files or information already viewed.
- Historical migrations, the applied resume package, Production configuration and completed M037/ACL evidence are unchanged.

## Evidence

| Check | Result | Scope |
| --- | --- | --- |
| Native psql 17 to PostgreSQL 17/PGlite: preflight, upgrade, postcheck | PASS | Local SQL engine, synthetic SQL principals; not genuine Auth/Storage |
| Legacy active/revoked grants, no forged consent | PASS | Local SQL engine |
| All 21 document types, bank/UAN/ESIC, per-item grants | PASS | Local SQL engine |
| Cross-tenant/non-Admin/anonymous denial, no direct table access | PASS | Local SQL engine |
| Revision, replacement, inactive account, recipient membership/assignment | PASS | Local SQL engine |
| Guarded sharing pause preserves documents and onboarding values | PASS | Local SQL engine |
| Focused sharing UI behaviors | PASS | 13 Node DOM-harness tests |
| Full frontend regression | PASS | 317 tests, 0 failures |
| Production artifact build | PASS | Local build only |
| New genuine Auth/Storage/browser rehearsal | v2 PASS | User-supplied run `resume-e2e-998030b5be06`; genuine local services and actual shared browser component |
| New Windows rehearsal runner execution | PASS | Exact delivered v2 package ran through final `LOCAL_DOCUMENT_BROWSER_REHEARSAL=PASS` |
| New read-only review runner | PASS locally | Actual SQL-to-PowerShell 7.4.6 parser (14 cases); mocked transport success/failure, malformed output, missing image and CA mismatch |
| Production read-only preflight | PASS | User-supplied run `document-preflight-864a86a72b5b`; mutation not dispatched |
| New guarded execution runner | PASS locally | Native SQL-to-PowerShell parser: 27 cases; 14 mocked orchestration cases; no remote write |
| Production post-upgrade verification | NOT RUN | Upgrade and deployment await explicit approval |

`storage_compatibility_validation.json` contains the v2 results: 22 PASS groups for each of the standard and versioned Storage schema variants. `local_validation.json` is preserved v1 engine evidence. This package does not reuse the old consent-based genuine browser PASS as proof of the new flow.

## Reproduce

From the repository root:

```sh
python supabase/production/admin_document_sharing_20260927/build_package.py
RESUME_SQL_TOOLS=/path/to/local/psql-and-pglite-tools node supabase/production/admin_document_sharing_20260927/test_local.mjs
npm test
npm run build:production
```

The genuine local rehearsal is in `tools/document-sharing-e2e`. It starts a fresh isolated official stack with migrations and seeds disabled, installs the captured source-faithful baseline, applies this upgrade, creates genuine synthetic Auth accounts, uploads files using Candidate credentials, and tests the actual shared browser component. It never connects to Production/NONPROD. See that directory's README.

## Exact release order / remaining gates

1. COMPLETE: new v2 genuine local rehearsal passed. Preserve `tools/document-sharing-e2e/user_run_v2_20260927.json` and the operator evidence folder. Do not repeat this run unless the tested implementation changes.
2. COMPLETE: user Production preflight PASS is recorded in `production_preflight_20260927.json`. The one bounded read-only preflight is in `review/START_READ_ONLY_CHECK.ps1` (packaged separately as `Admin_Documents_Production_Check.zip`). The SQL is unchanged from the successful genuine local run; the new pinned-TLS wrapper has actual SQL-to-parser and transport orchestration validation. It requires the verified old resume catalog and exact source onboarding getter/save contracts. A mismatch stops the release; inspect the actual deployed definition instead of changing hashes to force PASS. No repeat of unrelated recovery/M037 work is needed absent concrete drift.
3. Obtain approval for this new Production upgrade, including full account-number persistence and Admin-controlled document/metadata sharing. Earlier resume-release approval does not cover this expanded release.
4. Execute only `forward_proposed.sql` once with `psql -X -v ON_ERROR_STOP=1`, native exit checked, after approved artifact/target/CA hash validation. It performs its own preflight and postcheck inside one transaction. Require `ADMIN_DOCUMENT_REPAIR=COMMITTED`. If a connection fails after commit, inspect read-only; do not replay or infer rollback.
5. Independently run `postcheck_read_only.sql`; require native 0, `ADMIN_DOCUMENT_POSTCHECK=PASS`, and rollback. Use `execution/START_APPROVED_UPGRADE.ps1`, whose full dispatch path is guarded and locally validated. Its `VerifyOnly` mode dispatches only the read-only postcheck.
6. Commit only the reviewed source/package scope, push and manually dispatch the existing Pages workflow only after explicit release authorization. Verify the live asset bytes against the tested artifact.
7. On the explicitly approved TEST application: Candidate saves details; no sharing-consent action exists; Admin views data and selects one document, bank/UAN/ESIC separately; correct recipients can open only selected items; other recipients cannot; Admin revokes; changes invalidate old access.

## Operational stop

`pause_sharing_guarded.sql` requires the exact new postcheck, revokes browser execution of the Admin sharing setter, and revokes every active grant while retaining documents, joining details and audit records. It is a separately authorized Production write, never an automatic retry/rollback. Restoration requires a reviewed follow-up and deliberate fresh grants; do not restore the older frontend as a substitute for revocation.

## v2 — actual Storage schema compatibility fix

The user’s genuine local run reached the new upgrade and exited 3 at `column o.is_delete_marker does not exist`, before the transaction’s COMMIT. The initial engine fixture used a captured versioned Storage schema that included that column. The actual non-versioned local service did not. This was a compatibility defect in our upgrade.

Reproduced using native psql against a disposable standard-schema variant. Replaced the direct column reference with `coalesce(to_jsonb(o)->'is_delete_marker','false'::jsonb)='false'::jsonb`. An absent key supports the older schema; a present true or JSON-null marker remains unavailable. No managed Storage schema alteration, permissive policy or data stub is used in the delivered genuine harness. PostgreSQL documents composite-to-JSON conversion and missing-key behavior at https://www.postgresql.org/docs/17/functions-json.html .

Both complete native SQL regression paths now pass (22 groups each), including actual postchecks, unchanged authorization checks, and future-access revocation. The present-true test additionally verifies both recipient RPC denial and Storage SELECT denial. The prior 317 frontend checks remain evidence for the unchanged frontend. The subsequent user-supplied v2 Windows transcript reports every stage PASS, including new document/metadata sharing, genuine downloads, denial, revocation and invalidation after edits. See the v2 evidence record; no Production result is inferred.
