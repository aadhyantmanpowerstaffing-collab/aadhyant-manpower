# W5 Contractor Portal Foundation

Status: implemented locally for static review. Migration 021 is not applied and staging runtime/browser validation is pending.

## Architecture and canonical bridge

W5 is a tenant projection over canonical `contractors`, `contractor_users`, `platform_users`, `employer_requirements`, `requirement_contractors`, `candidate_applications`, `interviews`, and `candidate_joinings`. It creates no duplicate vacancy or recruitment table. A contractor submission creates one private Draft `employer_requirements` row and one contractor-origin `requirement_contractors` link. Aadhyant approval changes that same requirement to Open/Assigned, after which W3 can match candidates against it.

A direct contractor vacancy and a vacancy for an unregistered client worksite use the same model: `company_name` is safe client/worksite display context and `company_id` remains null. The browser cannot provide a company ID. A contractor never inherits Company Portal membership or impersonates a registered company.

## Approval lifecycle

Contractor-facing submission states are Draft, Submitted, Under Review, Correction Required, Approved, Rejected, Closed, and Cancelled. Contractors with Owner, Manager, or Recruiter membership may create, edit Draft/Correction Required records, submit/resubmit, or cancel eligible pre-approval records. Coordinator is read-only. Only bootstrap admin, super admin, or admin can start review, request correction, approve, reject, or close. Recruiter and Operations do not approve vacancies.

Approval is required before recruitment: Draft/Submitted/Under Review remain private and non-matchable. Approval atomically sets the link Approved/Active and the canonical requirement Open/Assigned. Correction and rejection feedback is a bounded contractor-facing field distinct from internal notes. No outbound notification is sent.

## Authorization and privacy

Every Contractor Portal RPC derives exactly one contractor through `auth.uid()`, active platform account, active contractor, and active membership. Multiple memberships fail closed. Company users, internal staff, inactive members, non-members, and anonymous callers are denied unless they independently satisfy the contractor contract. Private helpers are not browser executable; public RPCs are authenticated-only SECURITY DEFINER functions with empty `search_path` and schema-qualified SQL.

Contractors see only their profile, submissions, approval state, and approved-vacancy recruitment progress. Safe candidate fields are display name, qualification, specialization, experience summary, location, application stage, and read-only interview/joining progress. Candidate Master, phone, WhatsApp, Auth/candidate IDs in the UI, internal/recruiter/company notes, unrelated histories, other companies/contractors, staff data, and audit logs are not projected. Candidate contact release is explicitly deferred.

## Portal and RPCs

The separate responsive portal provides Dashboard, My Vacancies, Candidates / Applications, Interviews, Joining Status, Contractor Profile, and Logout. It contains structured controls and no prompt, alert, UUID entry, raw status typing, ISO timestamp typing, Admin shell, or direct browser table access.

Private helpers: `current_contractor_portal_id(boolean)`, `can_manage_contractor_vacancies()`, and `can_edit_contractor_profile()`.

Tenant RPCs: `get_contractor_portal_context`, `get_contractor_dashboard_metrics`, `get_contractor_portal_profile`, `update_contractor_portal_profile`, `list_contractor_portal_vacancies`, `get_contractor_portal_vacancy`, `manage_contractor_portal_vacancy`, `list_contractor_portal_applications`, `get_contractor_portal_application`, `list_contractor_portal_interviews`, and `list_contractor_portal_joinings`.

Internal review RPCs: `list_contractor_vacancy_reviews` and `review_contractor_vacancy`. W3 remains authoritative for candidate matching, application transitions, interview operations, and joining management.

## Future event hooks and limitations

Canonical transitions provide future hooks for Vacancy Submitted, Correction Requested, Vacancy Approved/Rejected, Candidate Presented, Interview Scheduled, Candidate Selected, Joining Pending, and Joined. W5 sends no email, SMS, or WhatsApp.

Candidate contact release, contractor interview feedback, saved filters, bulk operations, optimistic concurrency, and registered-client-company association are deferred. Candidate Portal, WhatsApp automation, AI matching, lead generation, payroll, attendance, PF/ESIC processing, billing, OCR/documents, and mobile applications remain outside W5.

## Validation

Checkpoint `022_contractor_portal_foundation_test.sql` is rollback-scoped and covers tenant resolution, roles, denied identities, submission review gating, cross-contractor isolation, internal approval, canonical W3 visibility, privacy, dashboard progress, read-only interview/joining boundaries, grants, and rollback. Focused frontend tests cover navigation, forms, access, privacy, responsive behavior, and prohibited UI patterns. Migration/runtime validation requires separate staging authorization.
