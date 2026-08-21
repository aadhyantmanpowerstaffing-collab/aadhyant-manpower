# W4 Staging Runtime Validation Evidence

Status: W4 database/security runtime validation, live localhost Company Portal browser validation, and manifest-bound fixture cleanup COMPLETE. W4 is ready for formal closure after commit review, authorized push, and remote HEAD verification.

## Scope and results

Validation ran only against dedicated NONPROD staging over TLS. Production was not contacted, no deployment or outbound integration ran, and W5 was not started. Transaction-scoped checkpoint fixtures rolled back with zero residue; persistent browser fixtures were subsequently removed through their ignored manifest with zero residue. This record omits project identifiers, hosts, URLs, credentials, keys, tokens, and fixture UUIDs.

- Migration 019 applied successfully (`02b99268283e2de56b3c67d4b951ec145b5073f982e578753b824e8c7cc5efd3`).
- Corrective migration 020 applied successfully (`0af32da842d969d615ef70ebd9951557060444e575f6d98b3f69f8abe653e7e2`).
- Focused checkpoint 020, full checkpoint 019, and focused coverage checkpoint 021: PASS.
- Current checkpoints 015–018 and legacy checkpoints 011–014: PASS.
- Final synthetic fixture and audit-marker counts: zero.

## Runtime role matrix

- **Owner / HR Admin:** own context, requirements, safe applications/interviews/joinings, approved requirement management, and allowlisted profile administration.
- **Company Recruiter:** own portal and approved requirement management; protected profile administration and internal W3 access denied.
- **Company Viewer:** approved projections read-only; W4 and migration-015 compatibility mutations denied.
- **Inactive member, contractor, internal W3 staff without membership, non-member, anonymous:** Company Portal denied.

## Tenant, workflow, and metrics evidence

Company A and B resolved only their server-derived tenant scope. Company B could not access Company A profile context, requirements, applications/history, interviews, or joinings. Cross-company mutation and ownership spoofing were denied. Exactly one active company membership is required; ambiguous membership fails closed by reviewed helper logic, although a multi-membership fixture was not separately exercised.

Canonical private/draft creation, field bounds, draft edit, close/cancel, terminal protection, Viewer denial, cross-company denial, and tenant activation denial passed. Company-scoped active requirements, remaining openings, applications, screening, shortlisted, interviews, selected, joining-pending, and joined metrics passed. Applications did not multiply openings; a zero-data company returned numeric zero for every metric.

## Privacy and internal-operation boundary

Safe projections are limited to own-requirement candidate display name, qualification, specialization/trade, experience summary, location, application stage, interview status, and joining status. Candidate Master, phone, WhatsApp, Auth linkage, candidate UUID, internal/recruiter notes, unrelated history, and other-company data were absent.

Own interviews and joinings are read-only. Company identities were denied interview schedule, reschedule, outcome/finalization, joining creation/update, and internal W3 recruitment mutation RPCs at the authorization boundary.

## Resolved validation history

Checkpoint-only defects corrected: missing Company B `created_by_user_id`; candidate fixture age/gender schema drift; stale candidate status `active`; and a stale zero-argument public-jobs signature assertion.

One production RPC defect was established: migration 019's `list_company_portal_applications` had an ambiguous PL/pgSQL `stage` reference. Corrective migration 020 qualified the variables without changing tenant scope, projection, privacy, or ACLs. Focused checkpoint 020 and full checkpoint 019 subsequently passed. Focused checkpoint 021 closed the remaining explicit runtime combinations.

## Manual localhost browser validation

Manual validation on dedicated NONPROD staging passed for anonymous access; Company A HR Admin, Recruiter, Viewer, and suspended member; Company B Owner; contractor; internal staff; and non-member identities. Company A requirement creation, draft editing, persisted headcount `12`, safe application projection, read-only interview/joining views, allowlisted profile updates, and logout/session boundaries passed. Company B saw only its tenant and correct zero-data metrics. Candidate contact details, Auth linkage, UUIDs, internal notes, other-company data, Candidate Master, Staff Management, and the internal Admin shell remained unavailable.

The browser-created draft requirement `AAD-2026-000060` was bound to the ignored fixture manifest for deterministic cleanup. The profile false-success defect was corrected and retested through a hard refresh; the Contact person persisted as `W4 Synthetic HR Updated` while legal, verification, and account fields remained protected. Suspended-member wording now distinguishes account, company, membership, and effective access states.

## Final fixture cleanup

Manifest-bound cleanup removed nine Auth users, six platform users, one bootstrap linkage, two companies, five company memberships, one contractor and membership, one staff profile and role, four requirements, one candidate, one application and history row, one interview, and one joining. `AAD-2026-000060` was removed. Recovery was verified before its linkage and Auth identity were removed last.

Post-cleanup verification found zero manifest-bound residue, no orphan histories/interviews/joinings/memberships/dependencies, and no change to the unrelated staging baseline. Migration 019 objects and the migration 020 correction remained intact; all 15 reviewed functions retained SECURITY DEFINER and empty `search_path`, all 11 W4 RPCs remained authenticated-only, and anonymous/private execution remained revoked. Frontend regressions passed 71/71. The ignored manifest and temporary browser copy were removed, and loopback port 4174 was stopped.

## Non-blocking limitations

The suite is not every permutation of search/filter/pagination, invalid field combinations, lifecycle ordering, or multiple active memberships. Employer feedback, contact release, notifications, concurrency UX, and bulk operations are deferred. These are non-blocking future-scope limitations, not W4 closure blockers.
