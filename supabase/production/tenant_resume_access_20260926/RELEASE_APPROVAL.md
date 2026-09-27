# Admin-controlled resume sharing — concrete release proposal

27 September 2026. Status: READY FOR SCOPED RELEASE APPROVAL; NOT APPLIED OR DEPLOYED.

## Evidence

- Supplied genuine v3 local run `resume-e2e-6d95364f22f9`: all reported stages PASS, including actual Company and Contractor PDF downloads, cross-company denial, Candidate withdrawal, Admin revocation and zero unexpected backend requests. Final `LOCAL_RESUME_BROWSER_REHEARSAL=PASS`.
- Focused v3 harness/component regression: 22 PASS. Prior complete frontend/source suite: 314 PASS; SQL security groups: 22 PASS; artifact build PASS. These are separate evidence sources, not duplicated independent genuine runs.
- Fresh Production read-only preflight: exact `TENANT_RESUME_PREFLIGHT|PASS|none` for project `wsuctjhbqiedttfnwjvf`, using unchanged SQL hash `123d6577a15684e24d419b4c604aa1cdec9a5de9984760db50097171e54d8d18`.
- No new-feature Production writes, commit, push or deployment have occurred.

## What approval would authorize

1. Apply only the additive resume-sharing forward SQL to the pinned Production project, once; run its read-only postcheck immediately.
2. Commit/push only the scoped sharing source, tests and supporting release artifacts; exclude earlier unrelated untracked repair folders, secrets, local stack and generated deployment output. Reconcile the current remote branch before committing; do not overwrite unrelated changes or force-push.
3. Build and deploy through the existing `pages-production.yml` workflow on `web-platform-development` with `deploy_production=true` after the backend postcheck PASS.

The database scope is one private RLS consent/share table, six public authenticated RPCs, five private helpers and one authenticated Storage SELECT policy. Registration alone, Candidate consent alone and document verification alone do not release a resume. Candidate consent for the exact document/application/recipient plus Admin sharing are required. Only the designated Company/Contractor membership can read the resume; other documents remain excluded.

The frontend scope adds Candidate consent, Admin Share/Stop sharing and recipient View Resume controls to existing application views. `release_source_manifest.json` records the exact hashes of 14 changed/new frontend/test/build files and the five SQL artifacts. The complete diff is in `frontend_review.patch`, with implementation in the named files.

## Explicit security-gate change in this proposal

Authenticated EXECUTE is required for the new exact Storage-RLS helper `private.can_read_shared_candidate_resume(text)` only; its body hash is `3a3f6d9d12b973f9be19ee459316aee5`. PUBLIC/anon cannot execute it. Other new private helpers and the private table remain browser-inaccessible. The feature postcheck verifies every new function body/signature/owner/search_path/grant, exact policy and table contract while preserving prior Storage policies and bucket configuration. Historical snapshot gates remain unchanged and no new historical-gate PASS is claimed. Approval includes this explicit additional helper grant, not a blanket permission exception.

## Exact database artifacts

- Forward: `forward_proposed.sql` SHA-256 `d67e84bdc6291bed18cd04a3a5d0dd4c74393ca86ed578589300bf042bdb3bfd`.
- Postcheck: `postcheck_read_only.sql` SHA-256 `cc45a376b9903cd040817d86e7b666cde4b500d4ba5d70686df91007978708d1`.
- Guarded rollback: `rollback_guarded.sql` SHA-256 `3331daf6a47a9304fe74996722c321c682ab1921c2877aa9dde4f64e8898f62b`.

The forward transaction repeats prerequisite/collision checks and transactional postconditions. An error before commit rolls back; an uncertain response or failed postcheck requires investigation, never automatic replay. Rollback after commit requires separate explicit authorization and retains consent/audit records and stored documents.

## Execution and remaining boundary

Reconfirm project identity and hashes, apply exact forward SQL, require exact `TENANT_RESUME_POSTCHECK|PASS|none`, then release the frontend through the existing workflow. Use authenticated Supabase DDL tooling when available; the local rehearsal launcher must never be used against Production. No new manual local rehearsal is needed for unchanged feature contracts.

Live browser confirmation remains pending and must use an expressly approved TEST application/accounts. Local component evidence does not establish every surrounding portal page. This release does not authorize sharing real Candidate resumes, deleting real data, WhatsApp sends, or unrelated features. Revocation prevents future authorized access; it cannot recall already downloaded copies.

Repository `AGENTS.md` requires explicit approval for the new Production mutation and deployment. Earlier Admin document/M037 approvals did not include this resume-sharing scope.
