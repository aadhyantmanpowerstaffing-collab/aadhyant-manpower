# Web Platform Delivery Roadmap

Status: proposed sequence. Dates are not commitments. Each milestone requires its own scope, review, tests, backup, and deployment authorization.

## Delivery rules

- Work on a reviewed `v3-web-platform` branch after reconciling the existing dirty `v2-development` worktree.
- Use local Supabase CLI and a separate development/staging project. Never develop against production service-role credentials.
- Preserve the current public site throughout. New authenticated routes remain feature-flagged and absent from public navigation until approved.
- Every database milestone ships additive migration, preflight, rollback/disable plan, RLS tests, and data reconciliation queries.
- Every external side effect uses idempotency and an outbox/queue.
- No milestone may deploy or publish Meta configuration implicitly.

## W0 — Production-state discovery and branch hygiene

Deliverables:

- reconcile/commit or deliberately shelve current modified/untracked web files;
- create `v3-web-platform` from a reviewed commit;
- read-only production Supabase catalog/grant/policy/function inventory;
- verify which repository migrations 007–015 are actually applied;
- document current static host, DNS, TLS, build/deploy process, Supabase plan/region/backups;
- create isolated dev/staging Supabase projects and secret ownership matrix.

Exit: zero uncertainty about production schema baseline; existing public site smoke suite captured.

## W1 — Architecture, schema alignment, and platform foundation

Deliverables:

- architecture decision records for hybrid Edge ingest + queue + worker;
- target naming/status/phone/timezone standards;
- additive foundation tables: staff profiles/roles, audit logs, stage history framework, settings/feature flags;
- migration registry and source-ID map design;
- CI for SQL lint/preflight/pgTAP plus public-page smoke tests.

Exit: no duplicate candidate/vacancy/application tables; RLS matrix approved.

## W2 — Authentication, staff roles, and route shell

Implementation status: W2 database/security runtime validation, browser/session
validation, and synthetic-fixture cleanup are complete on dedicated NONPROD
staging. Checkpoint 017, regressions 015/016, the full browser security matrix,
and final zero-residue verification passed. W2 is fully complete locally and
ready for closure after the final evidence commit is pushed under separate
authorization.

Deliverables:

- internal staff profiles and least-privilege roles while retaining `admin_users` bootstrap;
- authenticated `/admin/*` shell and session lifecycle;
- server/DB-enforced permission checks;
- company/contractor existing portals regression-tested against migration 015 boundaries;
- audit of role grants/revocations and session expiry.

Exit: direct URL and API tests prove unauthorized roles cannot read/write protected modules.

## W3 — Candidate and Requirement CRM

Implementation status: recruitment operations foundation implemented as
migration 018 and a role-aware admin module. Dedicated NONPROD database/security
runtime validation is COMPLETE, including checkpoint 018, regressions 015–017,
legacy checkpoints 011–014, rollback cleanup, and zero-residue verification.
Live browser validation is PENDING; W3 is not yet fully closed.

Deliverables:

- role-aware Candidate CRM, requirements, applications, interviews, and joining/placement using existing canonical tables;
- normalized search/filter/pagination;
- candidate preferences, tags, notes, assignment;
- requirement structured fields and safe public projection;
- server-validated application stages/history, interview and joining workflows, and audit entries.

Exit: static review is followed by separately authorized rollback-scoped staging validation; public registration, jobs, tenant boundaries, and W2 authorization must remain unchanged.

## W4 — Applications and auditable recruitment pipeline

Deliverables:

- align application status vocabulary;
- `application_stage_history` and controlled transition RPC/service;
- pipeline board/list/detail;
- source attribution and duplicate candidate/requirement guard;
- company/contractor/candidate projections only after privacy review.

Exit: every transition has actor, reason, timestamp, and correlation ID; invalid transitions rejected.

## W5 — Permanent WhatsApp webhook ingestion

Deliverables:

- Supabase Edge Function GET verification and raw-body POST signature verification;
- `webhook_events` idempotent capture;
- logged durable queues and dead-letter/replay operations;
- body/rate limits, redaction, monitoring, alerting;
- shadow mode: capture/process without automated outbound sends;
- stable callback URL runbook (no tunnel dependency).

Exit: replayed Meta fixtures create one event; invalid signatures never enqueue; acknowledgement latency meets target.

## W6 — WhatsApp Team Inbox

Deliverables:

- contacts/conversations/messages/delivery schema;
- realtime list/history/unread state;
- candidate/application/requirement linkage;
- recruiter assignment, tags, notes, search/filter;
- human takeover, bot pause/resume, manual outbox send;
- candidate/bot/recruiter/system visual distinction;
- reconnect/backfill and delivery progression.

Exit: inbound/outbound live test, duplicate webhook test, multiple-agent concurrency test, and RLS isolation pass.

## W7 — Server-side recruitment chatbot runtime

Deliverables:

- port deterministic rules and multilingual content from validated desktop concepts;
- state-aware numbers/navigation, candidate recognition, selected requirement context;
- JOB/REGISTER/STATUS/INTERVIEW/SALARY/LOCATION/DOCUMENTS/HUMAN/STOP;
- fact-only database queries;
- intake review/approval integration;
- cooldown, opt-out, handoff, loop protection, sanitised events.

Exit: no test path fabricates recruitment facts; one inbound event produces at most intended outbox actions.

## W8 — Chatbot Flow Builder

Deliverables:

- versioned flow/node/edge schema;
- admin graph editor and validator;
- immutable publish/rollback;
- typed runtime variables and session state;
- WAIT scheduling, approved SEND_TEMPLATE, restricted HTTP_ACTION connectors;
- flow simulator with deterministic fixtures.

Exit: invalid graphs cannot publish; active sessions remain pinned to immutable versions.

## W9 — Transparent candidate matching

Deliverables:

- normalized criteria/reference data;
- deterministic eligibility and weighted scoring engine;
- per-criterion reasons/hard exclusions;
- matching snapshots/versioning/staleness;
- recruiter review and feedback capture;
- fairness/legal review for age/gender criteria.

Exit: score is reproducible and explainable; no opaque AI ranking.

## W10 — Interview management

Deliverables:

- extend existing R13 schedule/reschedule/results UX;
- candidate/company-approved projections;
- calendar/list views and timezone rules;
- automation events/reminder hooks;
- no-show/attendance synchronization to application stages.

Exit: current RPC transition tests remain green; reminders are idempotent.

## W11 — Joining and placement tracking

Deliverables:

- Candidate Joining UI over existing `candidate_joinings`;
- expected/actual joining, no-show/deferred/left flows;
- application-stage synchronization and audit;
- company/contractor disclosure rules;
- placement reporting dimensions.

Exit: joining status and application stage cannot contradict without an auditable exception.

## W12 — Automation engine

Deliverables:

- versioned rules and runs;
- event/schedule triggers, conditions, actions;
- durable leases, retries, dead-letter handling, cancellation;
- interview/joining reminders, follow-ups, document checklist;
- STOP/handoff suppression gates;
- operational run monitor and replay controls.

Exit: repeated scheduler/worker execution cannot duplicate an action.

## W13 — Campaigns, templates, reports, and analytics

Deliverables:

- Meta template synchronization and version/component validation;
- campaign audience snapshot, recipient state, scheduling, throttling;
- delivery/error reporting and exports;
- operational dashboards for recruitment funnel, inbox SLA, campaigns, interviews, joining;
- privacy-safe aggregate company/contractor reports.

Exit: campaign sends obey consent/template rules and have complete recipient-level audit.

## W14 — Documents and secure storage

Deliverables:

- private Storage bucket and metadata table;
- upload validation, checksums, scanning workflow, signed URL access;
- role/application-based disclosure;
- retention/expiry/deletion request handling;
- access audit.

Exit: no public object URL or cross-tenant document access.

## W15 — Desktop data migration rehearsal and cutover

Deliverables:

- read-only SQLite export tooling and ID maps;
- collision/quality reports;
- staging rehearsal and repeatability proof;
- count/FK/status/message reconciliation;
- production cutover plan with sends disabled;
- desktop read-only fallback period.

Exit: rerun creates zero duplicates; all reconciliation gates signed off.

## W16 — Production hardening and controlled launch

Deliverables:

- threat model, penetration/security review, dependency/SBOM scan;
- load/failure/retry tests for webhook, queue, worker, Realtime, campaigns;
- backup/PITR and restore drill;
- secret rotation and incident runbooks;
- monitoring/SLOs, dead-letter alerts, cost budgets;
- accessibility/browser/mobile QA;
- staged feature-flag rollout and rollback rehearsal.

Exit: production readiness review explicitly authorizes DNS, Meta callback, migration, and deployment changes.

## Cross-milestone test gates

Every milestone must retain:

- public site route and form smoke tests;
- Supabase RLS tests for admin/company/contractor/candidate/anonymous roles;
- migration preflight and transaction rollback tests;
- webhook signature/idempotency fixtures after W5;
- candidate duplicate and phone normalization fixtures;
- application-stage audit tests after W4;
- outbox/automation idempotency after W5/W12;
- no-secret-in-browser/log/static-artifact checks;
- accessibility and mobile viewport checks for touched routes.

## Suggested release slices

1. **Foundation release:** W0–W4, authenticated CRM/pipeline hidden behind flags.
2. **Inbox release:** W5–W7, permanent webhook + Team Inbox + deterministic chatbot, initially limited agents.
3. **Automation release:** W8–W12, Flow Builder/matching/interviews/joining/automation.
4. **Operations release:** W13–W16, campaigns/documents/migration/hardening.

Each slice has a separate go/no-go decision. No roadmap item authorizes automatic deployment.
