# WhatsApp workspace update — 30 October 2026

The user requested completing the existing Aadhyant WhatsApp console with a WANotifier-style design and workflow. This change extends the established console, canonical RPCs, outbox and authorization. It does not migrate the sender to WANotifier or change the contact number.

## Implemented in this revision

- Responsive green messaging workspace with desktop navigation rail, horizontal narrow-screen navigation, accessible named tab panels and an expanded workspace mode.
- Overview with current sender/worker/template status, quick navigation, recent campaign reports and clearly labelled page-bounded delivery figures. Loaded campaigns are not presented as account-wide totals.
- Inbox/Sent retain canonical conversation history, once-only manual replies, separate delivery receipts and per-operator read markers. Added opt-in 15-second read-only polling, paused while the page is hidden or a content control is focused; typed drafts and durable pending-reply IDs survive rerenders. Polling never sends or marks messages read.
- Search within the loaded conversation history and reviewable English/Hindi quick reply insertion. Insertion never sends.
- Contact name/masked-number/list/tag search and consent filter on the loaded page. Select-all selects only visible matches; existing cross-page selection and consent/STOP checks remain.
- Template text/name, approval and language filters; compatible campaign count; immediate selected-template preview; existing approved Hindi fallback remains intact.
- Campaign search/state filter and visible setup → audience → preview steps. Existing approval, cancellation, scheduling and report exports are reused.
- Settings surface for real connection status, supported messaging behaviour and existing Users/Roles management.

## Existing supported backend capabilities retained

Contacts import (Excel/CSV/numbers), deduplication, lists/tags, provenance-based permissions, canonical job campaigns, registered/imported audiences, supported Hindi/English templates, manual job-video and registration-video campaigns, delivery reports, operator replies in the permitted window, registration/application response processing, POST JOB, STOP and automatic publication alerts. Actual sending still depends on current Meta approval, sender readiness, preferences and worker configuration.

## Read-only production findings

Checked the authenticated Admin page and the Aadhyant connection, project `wsuctjhbqiedttfnwjvf` (ACTIVE_HEALTHY). No production changes or real messages were made.

At approximately 16:25 IST:

- Automatic alerts were enabled, but the Admin panel reported template approval/sync pending and worker heartbeat pending.
- Sender was verified at 09:20 UTC; automatic heartbeat was last recorded at 09:05 UTC. Manual scheduling readiness was false.
- The database minute cron was active and recent cron invocations succeeded. Cron success alone does not prove downstream provider delivery or fresh heartbeat.
- `aadhyant_registered_job_alert_hi_v1` was approved/compatible; its v2 replacement, English v5, job-video, registration-video and image templates remained pending.
- Interview invitation/schedule templates existed and were approved, but were incompatible with the current job-campaign sender. Approval alone does not add interview parameter mapping.

These states are time-bound observations, not proof of a permanent platform outage. Activation or configuration repair can release real sends and requires the repository's explicit production/send approval boundary.

## Full WANotifier parity is not complete

Do not describe this revision as a complete clone. Remaining backend work includes per-chat assignment/internal notes and team permissions beyond existing roles; configurable greeting/away/keyword automation; visual chatbot and drip builders; generic/interview/image/document template composition and media transport; full incoming attachment preview; whole-account analytics/costs and CTWA attribution; third-party API/webhook integrations. Existing job/registration automations are not substitutes for these features.

The current release is a concrete first improvement to the existing console. Remaining features require separate canonical backend extensions, dedicated tests and provider verification. Do not enable nonfunctional placeholder controls or imply paid-provider feature parity.

## Validation / release

Full existing suite: 760 passed, no failures/skips. Final workspace/reply/contact focused suite: 30 passed after expanded-mode polish. Build, artifact boundary and digest verification must pass before release. Browser QA uses temporary synthetic data only; its files must not enter the production artifact or Git. Production deployment requires explicit approval under AGENTS.md; no real recipient was contacted.
