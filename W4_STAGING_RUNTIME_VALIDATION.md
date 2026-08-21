# W4 Staging Runtime Validation Evidence

Status: W4 database/security runtime validation COMPLETE. Live Company Portal browser validation PENDING; W4 is not formally closed.

## Scope and results

Validation ran only against dedicated NONPROD staging over TLS. Production was not contacted, no deployment or outbound integration ran, and all synthetic transaction-scoped fixtures were rolled back with zero residue. This record omits project identifiers, hosts, URLs, credentials, keys, tokens, and fixture UUIDs.

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

## Non-blocking limitations

The suite is not every permutation of search/filter/pagination, invalid field combinations, lifecycle ordering, or multiple active memberships. Employer feedback, contact release, notifications, concurrency UX, and bulk operations are deferred. Live browser validation remains required for W4 closure.
