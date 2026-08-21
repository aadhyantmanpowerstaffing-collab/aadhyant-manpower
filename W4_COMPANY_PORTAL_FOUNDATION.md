# W4 Company / Employer Portal Foundation

Status: implemented locally for static review. Migration 019 has not been applied to staging or production.

## Architecture and canonical data

W4 is a tenant-facing projection over the same canonical `companies`, `company_users`, `platform_users`, `employer_requirements`, `candidate_applications`, `application_stage_history`, `interviews`, and `candidate_joinings` used by W3. It creates no replacement requirement, candidate, application, interview, or joining table. Company-created draft requirements enter the same internal W3 requirement workspace without duplicate entry.

Migration 015 remains the tenant-boundary baseline. Migration 019 adds fixed-search-path, security-definer RPCs for Company Portal context, company-scoped metrics and profile, role-aware requirement management, and safe recruitment progress. No browser table grant or tenant base-table policy is added.

## Company authorization model

The actor is always derived from `auth.uid()`. A Company Portal session requires exactly one company membership attached to a `platform_users` company identity. Operational reads require active platform account, company account, and membership. Requirement mutation is limited to active `owner`, `hr_admin`, and `recruiter` memberships; company `viewer` is read-only. Profile mutation is limited to `owner` and `hr_admin`.

Contractors, internal staff, non-members, inactive memberships, and anonymous callers do not acquire Company Portal access. Company identifiers supplied by the browser are never trusted for scope: every RPC resolves the company server-side and verifies requirement/application ownership.

## Company workflow

The purpose-built portal navigation is Dashboard, My Requirements, Candidates / Applications, Interviews, Joining Status, Company Profile, and Logout. It does not reuse or expose the internal Admin shell.

- Dashboard shows company-only active requirements, openings, applications, screening, shortlisted, interview, selected, joining-pending, and joined counts.
- My Requirements supports server-side search/stage filtering, bounded results, draft creation/editing, allowed close/cancel behavior, structured fields, and recruitment progress.
- Candidate/Application views show only candidates already associated with the company's requirements.
- Interview and joining pages are read-only coordination/progress views. W3 recruiter and Operations workflows remain authoritative.
- Company profile updates use an allowlist. Legal name, main email, GSTIN/CIN, verification state, and account state remain Aadhyant-controlled.

The requirement lifecycle remains `draft`, `open`, `on_hold`, `filled`, `closed`, or `cancelled`. Company creation starts at private draft. A company can edit only its own draft and close/cancel only its own draft/open/on-hold requirement. Activation, visibility, filled state, application stages, interviews, and joining state remain internal workflows.

## Privacy and PII

Company users can see their own company, requirements, associated application progress, safe candidate facts, interviews, and joining progress. Candidate-safe projections include display name, qualification, specialization, experience summary, location, canonical stage, interview status, and joining status.

Candidate phone, WhatsApp, Auth linkage, candidate UUID, internal notes, recruiter notes, unrelated applications/history, internal audit metadata, other companies, and contractor data are not projected. W4 does not release candidate contact details at any stage; a later separately reviewed disclosure workflow may define explicit consent and stage requirements.

## RPCs

Private helpers: `current_company_portal_id(boolean)`, `can_manage_company_portal()`, and `can_administer_company_profile()`.

Authenticated projections/actions: `get_company_portal_context()`, `get_company_dashboard_metrics()`, `get_company_profile()`, `update_company_profile(...)`, `list_company_portal_requirements(...)`, `get_company_portal_requirement(uuid)`, `manage_company_portal_requirement(...)`, `list_company_portal_applications(...)`, `get_company_portal_application(uuid)`, `list_company_portal_interviews(...)`, and `list_company_portal_joinings(...)`.

The migration-015 tenant projection remains available for compatible clients. Its mutation signature is retained but hardened to delegate to W4's role-aware wrapper, preventing a read-only company viewer from bypassing W4 while preserving the existing contract.

## Notification-ready events

The canonical state changes already provide future notification triggers for requirement submitted/activated, candidate presented, interview scheduled, selected, joining pending, and joined. W4 sends no email, SMS, or WhatsApp message and adds no notification delivery table.

## Testing and limitations

Checkpoint 019 is rollback-scoped and covers Company A/B isolation, company viewer restrictions, inactive membership, contractor/internal/non-member/anonymous denial, derived requirement ownership, safe candidate projection, interview/joining scope, grants/search paths, and W2/W3/public contract presence. Frontend tests cover navigation, metrics, structured requirement UX, privacy, read-only coordination pages, route gating, responsive behavior, and absence of prompt/alert/UUID/raw-state entry.

Profile legal/verification changes, employer interview feedback, candidate contact release, notification delivery, saved filters, bulk operations, and optimistic concurrency are not part of W4. Contractor Portal, Candidate Portal, WhatsApp, AI matching, payroll, attendance, PF/ESIC, billing, OCR/documents, and mobile applications remain deferred.
