# Resume sharing — proposed release package

Status: local implementation, SQL/frontend checks and genuine local browser component rehearsal PASS. Fresh bounded Production preflight PASS on 27 September 2026. **Production database applied and postcheck PASS under explicit approval on 27 September 2026. Frontend release pending.**

## Review inputs

- `SCOPE_REVIEW.md`: business decision, exact disclosure boundary and limitations.
- `contracts.sql`: new definitions only.
- `catalog.json`: captured catalog-only prerequisite evidence, no business data.
- `manifest.json`: hashes of the proposed SQL and exact function contracts.
- `local_validation.json`: 22 PostgreSQL security/runtime groups, PASS.
- `frontend_validation.json`, `frontend_test_output.txt`, `artifact_build_output.txt`: 314 frontend/source tests and clean artifact build, PASS.
- `tools/resume-sharing-e2e/`: reproducible genuine local rehearsal; see its README.
- `genuine_rehearsal_user_result_v3.json`: supplied genuine Windows run `resume-e2e-6d95364f22f9`, all 25 reported markers PASS. Earlier failed runs remain preserved.
- `production_preflight_20260927.json`: authenticated, read-only Production result `TENANT_RESUME_PREFLIGHT|PASS|none` using the unchanged SQL.
- `RELEASE_APPROVAL.md`, `release_source_manifest.json`: exact proposed release scope and file hashes.

## Guard behavior

Preflight compares current helpers, owners, security paths, effective grants, public table dependencies, private bucket configuration and existing Storage policies with the reviewed catalog. Any new function/table/policy collision fails closed. The requirement table comparison includes identity, columns and primary/foreign/unique keys; unrelated vacancy business CHECK constraints are not new-sharing prerequisites.

The forward transaction creates only the new consent/grant table, helpers, RPCs, and SELECT policy. It has lock/statement timeouts, explicit grants/revokes, body/signature checks, complete new-table shape checks and transactional postconditions. Existing documents, applications, bucket configuration and policies are preserved. A repeat invocation fails before changing state.

The standalone rehearsal bootstraps materialized source definitions into a newly created isolated database; it does not replay the historical migration directory. The synthetic accounts are created by genuine Auth signup, not direct Auth inserts. Resume upload uses Storage API and source registration/verification RPCs.

## Remaining release sequence

1. COMPLETE: supplied genuine v3 run passed the full local sequence and final loopback guard. Evidence saved by the runner before cleanup; terminal evidence reconciled locally. Do not repeat this completed rehearsal absent a concrete code or contract change. A component-flow PASS does not prove every surrounding portal page.
2. Review the complete frontend diff and proposed SQL hash manifest alongside that evidence. The release proposal explicitly includes authenticated EXECUTE for only `private.can_read_shared_candidate_resume(text)` among the new private functions, required by the new Storage SELECT policy. The unchanged feature postcheck verifies its exact body, owner, empty search_path, ACLs and policy, plus the other new objects. Historical snapshot gates remain unchanged and are not reported PASS for this proposed release; this allowance is part of the new scoped approval.
3. COMPLETE: explicit user approval received at 2026-09-27 09:13:04 IST for this resume-sharing database update plus scoped commit/push/Production deployment.
4. CURRENT EVIDENCE: unchanged bounded `preflight_read_only.sql` returned exactly `TENANT_RESUME_PREFLIGHT|PASS|none` on pinned Production `wsuctjhbqiedttfnwjvf` through authenticated Supabase tooling. At execution, recheck the target and artifact hashes; the forward transaction repeats its prerequisite guards atomically. A mismatch stops the release for review.
5. Only after explicit approval, apply the exact reviewed `forward_proposed.sql` once to project `wsuctjhbqiedttfnwjvf` through authenticated Supabase DDL tooling, or psql `-X -v ON_ERROR_STOP=1` through the pinned CA/target connection. For psql require exit 0 and its final committed marker. For managed tooling record its execution result and require the independent postcheck; tool success alone does not establish contract correctness. No automatic retry and no historical migration replay.
6. Run `postcheck_read_only.sql`; require the exact structured row or psql marker `TENANT_RESUME_POSTCHECK|PASS|none` with successful native/tool execution. Capture any fail state without replaying the repair.
7. Commit/push only the reviewed scoped source changes and dispatch the existing approved Pages workflow. Deployment is separately gated by actual authorization; do not publish from this local package.
8. Confirm the live Candidate consent, Admin share/revoke and own-recipient View Resume controls using only an approved test application. Verify unshared/cross-tenant denial. No real applicant may be used as an implicit test subject.

No Production execution runner is included in the local-only launcher. The approved database update was applied once through Supabase tooling and independently postchecked PASS; see `production_execution_result.json`. Frontend commit/push/deployment and live new-feature verification remain pending. Do not replay the database update.

## Rollback

Before transaction commit, any SQL guard failure rolls back the transaction. After commit, `rollback_guarded.sql` is a separately approved rollback: it first verifies the installed contract, removes the one policy and the new functions, and retains the private consent/grant table and audit history. It does not delete documents, applications, bucket contents or evidence. The frontend change must be reverted through the same approved release workflow. Retained table collisions intentionally prevent an unreviewed forward replay.

## Reproduction in the repository

`python3 supabase/production/tenant_resume_access_20260926/build_package.py`

SQL-engine test requires the documented local PGlite and native psql 17 tools used by `test_local.mjs`; see the `RESUME_SQL_TOOLS` input in that script. It is distinct from the genuine Windows Supabase rehearsal.

On 27 September 2026 the user authorized this scoped release. Production preflight PASS, one approved additive database apply succeeded, and the independent read-only postcheck PASS. No real Candidate sharing action, business-row creation or deletion occurred. Commit/push/deployment status is recorded separately.
