# Post-W7C Admin Product Phase

Status: implementation and local regression validation complete on `web-platform-development` from the remote-closed W7C closure commit `42f7611a90691d8e52a36c03a3b85b9778ac85d6`. This phase changes the Admin product surface only. It does not authorize a deployment, database mutation, Meta configuration change, WhatsApp message, real-Candidate contact, or production action.

## Product audit

The pre-change audit was completed before implementation. The baseline frontend suite passed 138/138.

### Existing screens and contracts

- The original bootstrap-Admin dashboard exposed anonymous employer submissions, Candidate registrations/interests, Company accounts, Company requirements, Staffing Partners, and staff management in one horizontal tab strip.
- W3 later added a second set of canonical, RPC-only recruitment screens: Dashboard, Candidates, Requirements, Applications, Interviews, and Joining / Placement.
- W6 added Candidate profile, application/interview history, private-document review, and controlled document-state actions to the W3 Candidate detail.
- W7B added an RPC-only vacancy campaign portfolio and the exact eight-stage Select Vacancy -> Matching Criteria -> Candidate Preview -> Include / Exclude -> Template Preview -> Review Campaign -> Approve -> Queue workflow.
- W7A already exposes narrow Admin RPCs for core health, recent inbound metadata, recent outbound metadata, failed outbound items, and masked contact communication status, but none of those projections had a corresponding Admin screen.
- Company, Contractor, and staff administration already have established authorization contracts. The existing Admin Network views use the established RLS-protected legacy contracts; W3 and WhatsApp surfaces remain RPC-only.

### Product and usability gaps

- Navigation mixed legacy submission views, canonical recruitment views, Network administration, staff management, and campaigns in one long, horizontally scrolling tab row. Similar Candidate, Requirement, and Application concepts appeared more than once with inconsistent terminology.
- Bootstrap Admin opened the legacy Employer Requirements tab, while role-based staff opened the W3 Dashboard. There was no consistent product home.
- The legacy six-card summary and W3 seven-card summary were separate and neither included campaign delivery, recent replies, or attention posture.
- Canonical recruitment lists used fixed limits and mostly one search field. Candidate, Application, Interview, and Joining filters did not expose the safe filter options already accepted by their RPCs.
- Requirements had no product-quality detail hierarchy even though the list projection already returns qualification, trade, experience, salary, shift, working hours, facilities, headcount, progress, and stage.
- Applications were a flat table rather than a clearly filterable canonical pipeline. Interview and Joining lists lacked useful upcoming/past/attention and status controls.
- Campaigns had no status filter or pagination controls, list/detail loading and failures had no consistent retry surface, and terminal/audience states were visually shallow.
- There was no inbound/replies screen and no failed/attention workspace, despite safe W7A projections already being available.
- Tables scrolled on small screens but did not consistently preserve context as cards. The tab strip was not a usable mobile navigation system.
- Loading, empty, error, retry, pending, and no-double-submit behavior varied between modules. Some legacy surfaces still load data that is not needed for the canonical product home.
- Several older Admin paths use direct table access. Canonical W3/W7 surfaces correctly use RPCs, and this phase must not expand direct-table access.

### Projection boundaries discovered

- The safe W7B campaign list/detail projection does not return Company name. It will not be fabricated or obtained through per-row direct-table queries.
- The W7A recent-inbound Admin projection does not return the W7C recipient/application foreign keys added by migration 029. Therefore an exact Campaign Recipient -> INTERESTED -> Candidate -> Application trace and a trustworthy campaign conversion count cannot be shown in this phase without a new backend projection, which is outside the UI-first authorization.
- No narrow Admin audit/activity list projection currently exists. Administration will expose staff/roles only; an empty Audit module will not be created.
- Candidate detail safely projects applications and interviews but not Joining rows. Joining remains available in its canonical dedicated view.
- The recruitment dashboard RPC exposes `new_candidates`, not a separate total-active-candidate metric. The UI will label the server value accurately.

## Supported information architecture

- Dashboard
- Recruitment
  - Requirements / Vacancies
  - Candidates
  - Applications
  - Interviews
  - Joinings
- WhatsApp
  - Campaigns
  - Incoming / Replies
  - Failed / Attention
- Network
  - Companies
  - Contractors
- Administration
  - Users / Roles

Legacy duplicate submission panels remain implementation compatibility surfaces only and are removed from the primary navigation. No unsupported or empty module is advertised.

## Architecture and security continuity

- `employer_requirements`, `candidates`, `candidate_applications`, `interviews`, and `candidate_joinings` remain canonical.
- W3 recruitment UI continues to use only W3 projection/mutation RPCs.
- W7B continues to use its server-derived matching, lifecycle, audience, and W7A outbox RPCs. The browser never supplies a phone number or directly sends through Meta.
- W7A inbound and failure views use masked, bounded Admin projections and do not expose arbitrary free text or raw webhook payloads.
- Role, lifecycle, matching, suppression, Candidate linkage, Application state, interview state, and joining state remain server-authoritative. Successful mutations reload canonical server projections.
- No schema, RLS, grant, Edge, Meta, production, or deployment change belongs to this phase.

## Implemented product surface

### Navigation and responsive shell

- Replaced the single horizontal operational tab strip with a grouped sidebar for Dashboard, Recruitment, WhatsApp, Network, and Administration.
- Removed duplicate legacy Candidate, Requirement, and Candidate Interest entries from primary navigation while retaining their hidden compatibility markup for established bootstrap workflows.
- Added hash-restorable module navigation, one-selected-item enforcement, a bounded session/role summary, a mobile menu, responsive table-to-card presentation, keyboard focus styling, and reduced-motion support.

### Dashboard

- Combined `get_recruitment_dashboard`, `get_whatsapp_core_health`, the bounded campaign portfolio, and the six most recent safe inbound metadata rows.
- Shows Open requirements, New candidates, Applications, Upcoming interviews, Selected, Joining pending, Joined, Active campaigns, Campaign audience, Queued, Sent, Delivered, Read, Failed, and Recent replies.
- Adds supported quick actions for Requirements, Candidates, Applications, Interviews, and WhatsApp Campaigns.
- Uses partial-result handling: recruitment remains usable if an optional WhatsApp projection is temporarily unavailable.

### Recruitment

- Requirements / Vacancies: server search/stage filters, 25-row pagination, progress/application counts, a structured business detail, Candidate matching, and the existing Contractor vacancy review bridge.
- Candidates: server search, state, district, qualification, Candidate type, and status filters; 25-row pagination; canonical detail, history, documents, and permission-gated update actions.
- Applications: server search/stage filtering, 25-row pagination, canonical pipeline vocabulary, projected detail/history, controlled stage transitions, interview scheduling, and joining initiation.
- Interviews: bounded All, Upcoming, Past, and Attention views plus the established schedule/reschedule/outcome controls.
- Joinings: bounded canonical status filters and the established Joining/Placement state-machine actions.

### WhatsApp

- Campaign portfolio: server status filter, 25-row pagination, responsive delivery counts, safe recipient detail, empty/error/retry states, supported cancellation, and canonical reloads after lifecycle actions.
- Campaign builder: preserves the exact eight stages: Select Vacancy, Matching Criteria, Candidate Preview, Include / Exclude, Template Preview, Review Campaign, Approve, Queue. Server matching, suppression, lifecycle, audience freeze, approval, and W7A outbox authority are unchanged.
- Incoming / Replies: bounded W7A safe projection with masked contact, time, type, structured action, processing status, status filter, pagination, and no arbitrary free text.
- Failed / Attention: bounded failed outbound, failed campaign, and overdue-scheduled-interview projections. It is read-only and performs no replay, queue, send, or state mutation.

### Network and Administration

- Companies and Contractors remain under the established Admin/RLS contracts and now load only when their product section is opened instead of during every Admin startup.
- Users / Roles reuses the W2 staff-management contracts and preserves elevated-role restrictions.
- Audit / Activity is intentionally absent because no narrow safe list projection exists.

## Performance and state handling

- Removed the eager startup fan-out that previously loaded counts and seven legacy datasets before they were needed.
- W3 Candidate, Requirement, and Application lists now use their existing server-side 25-row pagination. Campaign and inbound lists use bounded 25-row pages. RPCs without offset support remain explicitly bounded to 100 rows.
- Dashboard independent projections load concurrently. No per-row Company lookup or other N+1 query was added.
- Lists and operational workspaces provide loading, empty, safe error, and retry states. Mutation controls retain pending disabling and canonical post-mutation reloads; campaign create/freeze keeps its existing shared in-flight promise and stable operation identity.

## Known limitations

- Exact W7C Campaign Recipient -> INTERESTED -> Candidate -> Application trace and conversion totals remain deferred until an explicitly authorized safe Admin projection exposes the migration-029 links.
- Company name is not available in the current W7B campaign projections and is not fabricated in campaign list/detail.
- Candidate detail does not include Joining rows; Joinings remain available in the dedicated canonical view.
- Interview and Joining RPCs are bounded to the latest 100 rows and do not currently accept an offset.
- Network pages retain established legacy Admin/RLS data contracts. This phase did not add or broaden direct-table access.
- Full real Meta inbound validation remains deferred under the documented Meta test-number ingress limitation. The Admin UI does not alter that conclusion.
- Interactive browser QA could not be run because no local browser engine or Playwright/Puppeteer package was available. No claim of interactive or visual browser PASS is made.

## Validation record

- Pre-change frontend baseline: 138/138 PASS.
- Local executable browser/automation: unavailable at audit time (`msedge`, Chrome, Chromium, Firefox, Playwright, and Puppeteer were not available on PATH or in local packages).
- Focused post-change Admin suites: 90/90 PASS.
- Focused W7B campaign suite: 17/17 PASS.
- Complete frontend regression: 153/153 PASS.
- Unchanged W7A/W7B/W7C Edge suite: 21/21 PASS.
- JavaScript syntax checks: PASS for `admin.js`, `admin-product.js`, `recruitment-operations.js`, and `whatsapp-campaigns.js`.
- HTML structural check: PASS with 76 unique IDs and all nine local/external script references resolved.
- Local HTTP smoke: HTTP 200 for `/admin/`, `admin.css`, `admin-product.js`, `recruitment-operations.js`, and `whatsapp-campaigns.js`.
- Static scans: no blocking browser dialogs, unsafe HTML insertion, secret/service-role references, Graph calls, or direct table access in the new product/W3/W7 controllers.
- `git diff --check`: PASS.

## Production-readiness posture

The Admin product phase is ready for human product review, subject to the known projection and interactive-browser-QA limitations above. Before any production launch, complete authorized interactive desktop/tablet/mobile QA against the intended environment, production security/readiness review, deployment planning, and explicit production deployment approval.

No deployment was performed. Production and Meta were not contacted. No WhatsApp message was sent or queued as part of validation, and no real Candidate was contacted.
