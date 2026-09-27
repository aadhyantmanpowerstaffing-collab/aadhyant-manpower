# Admin-controlled resume disclosure

Decision recorded: the user selected **ADMIN SHARE KRYA PACHI** on 2026-09-26. Local implementation was authorized first. On 27 September 2026 at 09:13:04 IST the user explicitly authorized this new resume-sharing Production database update plus scoped frontend commit/push/deployment.

## Resulting behavior

1. Candidate applies to a canonical requirement and uploads a resume through the existing flow.
2. On Applications → Resume sharing, Candidate explicitly consents to the particular resume, application, and named Company/Contractor. The checkbox starts unchecked and explains that the PDF may contain contact details.
3. Admin verifies the resume using the completed existing document-review flow. On Application Detail → Share Resume, Admin explicitly releases the consented resume to that recipient.
4. Authorized members of that recipient see View Resume in application details. Consent or verification alone never releases it.
5. Candidate may withdraw consent; Admin may stop sharing. New authenticated access checks the live grant each time. A replacement document or changed Storage object requires new consent and a new Admin share.

Registration never grants tenant access. Other documents, including Aadhaar, PAN and bank proofs, remain excluded. Unrelated internal notes and contact projections are unchanged. Resume access itself necessarily discloses whatever contact information the Candidate put in the file.

## Scope and authorization

The additive backend contains one private RLS table, six authenticated public RPCs, five private helpers, and one authenticated Storage SELECT policy. Only the new Storage authorization helper is browser-executable; the other private helpers and private table remain inaccessible directly.

Company membership roles: owner, hr_admin, recruiter. Contractor roles: owner, manager, recruiter. Active accounts and membership are required. The recipient is derived server-side from the canonical requirement and, for Contractor submissions, an approved active/canonical assignment. Viewer/coordinator/anonymous/cross-tenant access is denied.

Eligible application stages: applied, screening, shortlisted, interview, selected, joining_pending, joined. Other stages deny access. A temporary eligibility/account restriction is evaluated live; reinstatement may make a still-valid grant usable again unless consent or the Admin grant was explicitly revoked.

A share binds the document ID, Storage object ID/version/update timestamp, application and recipient. Optimistic consent revisions prevent stale Admin actions. Audit events record grant identities and actions without file contents, names, paths or contact data.

## Evidence and limits

- Existing Admin PDF opening remains user-confirmed evidence; no prior Admin repair is replayed.
- A bounded Production catalog read was used to capture current prerequisite metadata. No business rows were read and no remote write occurred.
- Native psql 17 through a local PostgreSQL 17/PGlite engine: 22 security/runtime groups PASS. These use synthetic SQL principals, not genuine Auth/Storage services.
- Frontend/source suite: 314 PASS, 0 FAIL. Includes 11 new module/integration tests using DOM/transport doubles.
- Clean-snapshot Production artifact build: PASS; the new asset is explicitly allowlisted.
- Genuine Auth/Storage/browser component rehearsal: PASS in supplied Windows v3 run `resume-e2e-6d95364f22f9`, including both actual PDF downloads, tenant isolation, Candidate withdrawal, Admin revocation and backend loopback guard. Terminal evidence recorded in `genuine_rehearsal_user_result_v3.json`; raw evidence files have not been imported.
- Fresh authenticated Production preflight: PASS on 27 September 2026; exact unchanged read-only SQL, no mutations.
- Whole portal browser E2E and deployed behavior of the new feature: NOT VERIFIED.

## Download limitations

The new UI uses authenticated Storage download and a local PDF Blob URL; it does not create a public or signed URL. Revocation prevents subsequent authorized downloads. It cannot recall downloaded copies, cancel bytes already fetched, or invalidate any previously issued signed URL created through another authorized client. Such URLs remain usable until their expiry under the Storage service contract.

## Release status

LOCAL REHEARSAL COMPLETE; APPROVED PRODUCTION DATABASE APPLIED AND POSTCHECK PASS. Frontend release is authorized and pending. `RELEASE_APPROVAL.md` identifies the exact SQL, Storage-helper grant and frontend release scope. See README.md for dependency order and rollback behavior.
