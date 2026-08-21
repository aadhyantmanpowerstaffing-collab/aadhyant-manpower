# W6 Candidate Portal and Document Onboarding Foundation

Status: local implementation and static validation PASS. Migration 023 is not applied; runtime/browser validation is pending separate authorization. No staging or production database was contacted.

## Canonical architecture

W6 extends the existing `candidates`, `candidate_preferences`, `platform_users`, `employer_requirements`, `candidate_applications`, `application_stage_history`, `interviews`, `candidate_joinings`, and `audit_logs` contracts. It does not create a second candidate, job, application, interview, or joining system. The separate authenticated route is `/candidate/portal/`; the existing no-login public registration/interest flow remains available and is not silently linked to Auth accounts.

An authenticated Candidate Portal identity resolves through `auth.uid()` to one active `platform_users` candidate account and exactly one active canonical `candidates` row. Missing, inactive, non-candidate, and ambiguous linkage fails closed. Company, Contractor, internal staff, other candidates, and anonymous callers receive no Candidate Portal scope merely because they are authenticated.

## Required profile and sensitive identifiers

Mobile and Aadhaar are compulsory before a candidate profile is complete or a portal application can be created. Indian mobile numbers normalize to ten digits and must start from 6-9. Aadhaar normalizes to exactly twelve digits. Full Aadhaar is not retained: the database stores a SHA-256 equality fingerprint and last four digits, and portal reads return only `XXXX XXXX 1234`. The fingerprint provides deterministic uniqueness checking but is not encryption and should not be treated as protection against offline enumeration if database contents are compromised. The repository has no reviewed server-side key-management/HMAC facility, so W6 does not invent one or expose a key to browser code. A key-managed HMAC/tokenization review is a production-readiness requirement before collecting real Aadhaar; it does not block rollback-scoped NONPROD W6 runtime validation.

Mobile verification defaults to unverified. W6 does not fake OTP verification; real OTP and verification-state mutation are deferred. Generic duplicate errors avoid disclosing whether another candidate owns a mobile or Aadhaar value. Full Aadhaar, bank account, UAN, and ESIC values are excluded from URLs, lists, client storage, and audit metadata.

Profile completion is calculated server-side across required identity/contact, education, location, preferences, and Resume categories. Joining-document completion is separate. Bank details retain only a deterministic fingerprint and last four account digits; UAN and ESIC values are stored only when the candidate says an existing number is available and are projected masked. W6 never generates or validates these identifiers against external government systems.

## Private documents

`candidate_documents` is a normalized metadata entity with controlled type, private object name, safe display name, MIME type, size, active/replacement state, and verification state. One active record per candidate/type is enforced. Its controlled categories cover Resume/CV, Aadhaar, PAN, photo, 10th/12th, ITI, Diploma, Degree and other education, experience/previous employment, bank proof/passbook/cancelled cheque, driving licence, passport, and Other. Supported uploads are declared PDF, JPEG, and PNG up to 10 MB. The `candidate-private` Storage bucket is private and restricts browser object paths to the authenticated user's UUID prefix; object names, declared MIME, extension, and recorded size are server-validated before metadata registration. This is not magic-byte inspection, malware scanning, or content quarantine; those controls remain required before production document intake. Candidate and authorized Admin views use short-lived signed URLs and never render raw paths.

Verification states are Uploaded, Under Verification, Verified, and Re-upload Required. Bootstrap Admin, Super Admin, and Admin may inspect and review documents. Recruiter and Operations are intentionally excluded from Aadhaar/document verification in W6. Company and Contractor roles have no document or Aadhaar projection. Re-upload feedback is bounded and candidate-facing. Resume remains Candidate/Aadhyant controlled; Company/Contractor release requires a separate consent and stage policy.

The server-derived joining checklist includes Mobile, Aadhaar number/document, Candidate Photo, bank details/proof, and conditional supporting categories. Verified and missing states are not fabricated. A privileged documentation override requires a bounded reason, actor, and timestamp and does not mark documents Verified.

## Opportunities and recruitment flow

Job Opportunities projects only canonical requirements that are Open, Public, have remaining openings, and have a requirement code. Contractor Draft, Submitted, Under Review, Correction Required, Rejected, private, filled, and closed requirements are absent. Candidate identity is server-derived when applying. `apply_candidate_job` inserts one canonical `candidate_applications` row at Applied and the existing unique candidate/requirement constraint prevents duplicates. W3 remains authoritative for application transitions, interview scheduling/outcomes, and joining mutation.

Candidate reads are limited to own applications, safe interview schedules/results, and joining progress. No Candidate Master, other candidate, internal stage-history reason, recruiter note, internal note, audit record, Company private note, or Contractor private detail is projected. Confirmed/Expected joining remains visibly distinct from Actually Joined.

## Frontend and session safety

The responsive portal includes Dashboard, My Profile, Job Opportunities, My Applications, Interviews, Joining Status, Documents, and Logout. Forms use labels, native structured controls, status regions, keyboard-accessible navigation, bounded tables, and mobile breakpoints. It contains no operational `prompt()`, `alert()`, UUID entry, raw status/storage-path entry, or direct business-table access.

Protected content is concealed before logout and on `pagehide`. `pageshow` detects BFCache or back/forward restoration, conceals stale content, and reloads so the server-backed session/context gate runs again. This incorporates the W5 history-cache remediation from the beginning.

## RPC and role surface

Private helpers: `current_candidate_portal_id` and `can_verify_candidate_documents`.

Candidate RPCs cover context, initial profile creation, profile read/update, dashboard metrics, eligible jobs, application creation/list, interview/joining lists, document inventory/registration/access, joining checklist, and masked bank/PF/ESIC onboarding read/update.

Admin RPCs cover document inventory/access, verification/re-upload review, and controlled documentation override. Every W6 helper/RPC is `SECURITY DEFINER` with explicit empty `search_path`, schema-qualified business SQL, no dynamic SQL, private-helper execution revoked, public RPC execution revoked from anonymous, and narrow authenticated execution. Base Candidate/document tables remain unavailable to browsers.

## Testing and limitations

Checkpoint `025_candidate_portal_foundation_test.sql` is transaction- and rollback-scoped. It covers initial onboarding and mandatory-field rejection, Candidate A/B isolation, inactive/non-member/other-portal boundaries, Aadhaar masking/fingerprinting, profile/preferences and masked bank/PF/ESIC persistence, Open/Public opportunity filtering (including pre-approval Contractor exclusion), canonical and duplicate-safe application creation, own interview/joining projections, document registration/replacement and privacy/review roles, joining checklist, Admin override, direct-table denial, grants/storage-policy posture, and audit redaction. Frontend tests cover route/session boundaries, BFCache, responsive/accessibility foundation, private uploads, masked identity, canonical application use, read-only progress, and prohibited patterns.

Deferred: real OTP, antivirus/content scanning and quarantine, checksums, retention/deletion automation, Company/Contractor Resume release, OCR, external Aadhaar/PAN/bank/PF/ESIC validation, PF/ESIC filing, Candidate interview rescheduling, WhatsApp, AI matching, payroll, attendance, billing, mobile apps, and deployment. Storage scanning and stronger key-managed fingerprinting require separately reviewed infrastructure.
