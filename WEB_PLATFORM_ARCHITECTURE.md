# Aadhyant Web Platform Architecture Blueprint

Status: design only. No deployment, DNS, Supabase production data, Meta configuration, or credentials were changed.

## 1. Current web architecture

The repository is a static, multi-page site on the `v2-development` branch, published under the root-domain CNAME `aadhyantmanpower.in`. It uses HTML/CSS/vanilla JavaScript and the Supabase JavaScript v2 CDN client. `config.js` contains only the public Supabase URL and publishable browser key; `supabase-client.js` deliberately persists sessions only for `/admin`, `/company`, and `/contractor` routes.

Current route families:

- Public: `/`, `/jobs`, `/services`, `/industries`, `/about`, `/contact`, `/privacy`, `/terms`, `/data-deletion`, `/staffing-partner`, `/hire-manpower`.
- Candidate: `/candidate` and `/candidate/register` (public registration/job-interest experience; no mature authenticated candidate portal yet).
- Company: `/company`, `/company/login`, `/company/register`, `/company/requirements`.
- Contractor: `/contractor`, `/contractor/login`, `/contractor/register`, `/contractor/assignments`.
- Admin: `/admin/login` and `/admin`.

Supabase provides Auth, Postgres, RLS, anonymous insert-only public forms, authenticated admin operations, organization onboarding, tenant-scoped requirement/assignment RPCs, a safe public-jobs RPC, candidate-interest RPC, application administration, and interview scheduling. The repository contains numbered migrations 007–015 and SQL security tests. Migration 015 intentionally removes tenant reads from sensitive base tables and replaces them with narrow security-definer projections.

The worktree already contains unrelated modified/untracked reconstruction files. They must be preserved and reviewed before any future branch or release operation.

## 2. Current desktop reference architecture

The desktop V3 application is PySide6 + SQLite with repository/service/controller separation. Its reusable design concepts are:

- idempotent webhook dispatch into delivery, Flow, and inbound-message services;
- raw-body Meta signature validation and verify-token challenge handling;
- normalized Indian phone matching and candidate linkage;
- conversations/messages with incoming, bot, recruiter, and system-event semantics;
- deterministic multilingual chatbot state, handoff, pause, opt-out, selected-vacancy context, and event history;
- candidate intake and WhatsApp Flow submission review before explicit Candidate Master creation;
- Cloud API sender, templates, campaigns, queue/retry state, delivery events, and reports;
- credentials separated from ordinary settings (Windows keyring).

Do not port PySide controllers, SQLite SQL, Windows threads, keyring calls, or the local HTTP server. Port contracts, invariants, state transitions, test fixtures, and sanitized logging events.

## 3. Target product boundaries

Keep public and authenticated surfaces logically separated on the same domain:

```text
Public site
  / /jobs /candidate /company /contractor

Authenticated platform
  /admin
  /admin/candidates
  /admin/companies
  /admin/contractors
  /admin/vacancies
  /admin/applications
  /admin/interviews
  /admin/joining
  /admin/whatsapp
  /admin/chatbot
  /admin/automations
  /admin/reports
```

Public bundles must never import internal service-role clients. Admin route hiding is not authorization; Supabase RLS/RPC checks remain authoritative.

## 4. Recommended 24x7 topology

```text
Meta WhatsApp Cloud API
        |
        v
Permanent HTTPS webhook ingestion
  - raw request body
  - X-Hub-Signature-256 verification
  - GET verification challenge
  - rate/body-size checks
        |
        +--> webhook_events (unique provider/event/message key)
        +--> durable queue: whatsapp-events
        |
        v immediate 200 after durable acceptance

Continuous worker service
  - claims queue message with visibility timeout
  - normalizes contact/message/status/Flow response
  - executes chatbot/automation transaction
  - writes outbox jobs
        |
        +--> Supabase/Postgres domain tables
        +--> message-outbox / automation queue
        |
        v
Outbound worker --> Meta Graph API --> delivery webhooks
        |
        v
Supabase Realtime (private, RLS-scoped) --> Web Team Inbox
```

### Recommendation

Use a **hybrid Supabase + dedicated worker**:

1. Supabase Edge Function for the permanent webhook boundary. It is colocated with existing Supabase data, suitable for webhook receivers, holds server-side secrets, verifies the raw body, performs an idempotent insert/enqueue, and returns quickly.
2. Supabase Queues/`pgmq` basic logged queues for durable work and retry visibility. Queues must remain server-only; do not expose queue APIs to browser roles.
3. One small managed container service (for example Cloud Run, Render, Fly.io, or an equivalent approved host) as the continuously running queue/outbox/automation worker. Run at least one instance where the chosen host supports it, with health checks and controlled concurrency.
4. Supabase Postgres/Auth/Storage/Realtime remain the system of record and identity/data plane.

Why not Edge-only: Edge Functions support webhook receivers and background tasks, but documented memory/CPU/wall-clock limits make them a poor sole owner for campaign draining, scheduled reminders, long retry chains, and continuously polling a pull queue. Edge-only is acceptable for an early low-volume ingestion proof, not the final automation runtime.

Why not one monolithic server: it couples public acknowledgement latency to business processing and creates a larger failure domain. Separating ingest, durable work, and outbound delivery allows replay and independent scaling.

Official design references:

- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Edge Function limits](https://supabase.com/docs/guides/functions/limits)
- [Supabase Queues](https://supabase.com/docs/guides/queues)
- [Supabase Realtime subscriptions](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)
- [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization)

### Permanent URL

Initially use the stable Supabase Function HTTPS URL as Meta's callback, never a tunnel URL. If product policy later requires `https://aadhyantmanpower.in/api/whatsapp/webhook`, place a reviewed edge/reverse-proxy route in front of the same function while leaving public paths unchanged. This requires a separate DNS/hosting milestone and rollback plan; it is not part of this blueprint delivery.

## 5. Service boundaries

| Service | Responsibility | Must not do |
|---|---|---|
| Webhook ingestion | signature/challenge, size/rate checks, idempotent event capture, enqueue, fast response | chatbot logic, Graph sends, browser auth |
| WhatsApp event processor | parse messages/status/Flow replies, normalize phone, link conversation | fabricate recruitment data |
| Chatbot runtime | deterministic state/node execution, language, navigation, handoff/STOP | read secrets in browser, auto-create candidate without policy |
| Recruitment service | candidates, requirements, applications, stages, interviews, joinings | bypass RLS/audit contracts |
| Message outbox worker | Cloud API sends, retries, provider IDs, failure classification | accept arbitrary client-supplied tokens |
| Automation scheduler | due rules/runs/reminders with locking and dedupe | send outside consent/template rules |
| Realtime gateway | scoped inbox updates/presence | broadcast unrestricted PII |
| Web admin | authenticated UX and RPC calls | service-role access or authorization by hidden routes |

## 6. Team Inbox architecture

Canonical tables are `whatsapp_contacts`, `whatsapp_conversations`, and `whatsapp_messages`; do not create a second inbox store.

Inbox query model:

- conversation row holds contact/candidate/application/vacancy context, assignment, bot mode, unread counters, last-message denormalization, and optimistic version;
- message row holds provider message ID (unique), direction, actor type (`candidate`, `bot`, `recruiter`, `system`), content type, text/structured content, status, timestamps, reply context, and safe payload reference;
- notes and tags are separate many-to-many/domain tables, not WhatsApp messages;
- `conversation_assignments` or assignment fields track recruiter ownership with history in audit/system events;
- delivery events update message status monotonically (`queued -> sent -> delivered -> read`, with failed metadata).

Realtime:

- subscribe only after authenticated authorization;
- use private channels/Broadcast for production fan-out, scoped by team/organization topic;
- use Postgres Changes initially only if load is modest and RLS predicates are indexed;
- fetch canonical rows after notifications rather than trusting broadcast payloads for authorization;
- maintain reconnect/backfill cursor so missed WebSocket events do not lose messages.

Human takeover is a server-side conversation mode. The bot processor checks it transactionally before replying. Manual send inserts an outbox record attributed to the authenticated recruiter; the browser never calls Graph directly.

## 7. Chatbot runtime

Retain the validated concepts: Gujarati/Hindi/English, language selection, state-aware numbers, menu/navigation, JOB/REGISTER/STATUS/INTERVIEW/SALARY/LOCATION/DOCUMENTS/HUMAN/STOP, candidate recognition, selected requirement context, cooldown, unknown escalation, pause, and handoff.

Server-side execution contract:

1. Lock the `chatbot_session`/conversation version for the inbound event.
2. Reject already processed `webhook_event_id`/message ID.
3. Re-read bot/handoff/opt-out state.
4. Resolve explicit command or current flow node deterministically.
5. Read vacancy/application/interview facts only from canonical tables.
6. Persist state transition, system event, and outbound outbox record in one transaction.
7. Mark the event processed only after the transaction commits.

No LLM is required. A future AI fallback may propose an intent, but deterministic policy must validate it and an AI response must never invent vacancy, compensation, selection, company, or interview facts.

## 8. Flow Builder architecture

The admin editor writes versioned definitions; the runtime executes only immutable published versions.

```text
chatbot_flows
  -> chatbot_flow_versions
       -> chatbot_flow_nodes
       -> chatbot_flow_edges
chatbot_sessions -> flow_version_id + current_node_id + variables
```

Node types: START, SEND_MESSAGE, ASK_TEXT, ASK_NUMBER, ASK_CHOICE, CONDITION, SET_FIELD, LANGUAGE_SELECTION, FIND_JOBS, SHOW_JOBS, SELECT_JOB, CREATE_APPLICATION, APPLICATION_STATUS, INTERVIEW_DETAILS, SEND_TEMPLATE, WAIT, ASSIGN_RECRUITER, HUMAN_HANDOFF, HTTP_ACTION, END.

Publishing validations:

- exactly one START; reachable END or handoff;
- valid edges and unique choice keys;
- no unbounded synchronous cycle;
- variable types and required inputs match;
- HTTP actions use administrator-approved connectors, allowlisted destinations, secret references, timeouts, and response schemas;
- SEND_TEMPLATE references an approved template/language;
- published versions are immutable and support rollback.

WAIT creates a durable scheduled job; it never sleeps in a request. CREATE_APPLICATION uses the canonical unique candidate/requirement constraint.

## 9. Recruitment pipeline

Canonical application stages:

```text
new_lead -> registered -> interested -> applied -> screening
         -> interview_scheduled -> interview_attended -> selected
         -> joining_pending -> joined -> active
```

Terminal/exception stages: `rejected`, `no_show`, `withdrawn`, `left`.

`candidate_applications.application_status` stores current state. Every change inserts `application_stage_history` with previous/new stage, actor, reason, source, timestamp, and correlation ID. Interview and joining tables remain detailed sub-lifecycles; triggers/service functions synchronize the current application stage without deleting history.

## 10. Automation engine

Rules are versioned event-condition-action definitions. `automation_runs` provides idempotency, lease/lock state, attempts, next retry, outcome, and correlation IDs.

Initial triggers:

- inbound new contact -> welcome;
- candidate registered -> approved job suggestions;
- application created -> confirmation;
- interview scheduled / due tomorrow -> confirmation/reminder;
- interview no-show -> controlled follow-up;
- selected -> document checklist;
- joining due tomorrow -> reminder;
- joined -> follow-up;
- human handoff or STOP -> suppress bot/automation.

All sends use an outbox unique key such as `(rule_version_id, entity_id, scheduled_for, action_index)` so worker retries cannot duplicate messages.

## 11. Security model

- Store Meta token, App Secret, verify token, Supabase service role, and connector secrets only in server secret stores. Never return them from RPCs or embed them in JavaScript.
- Verify `X-Hub-Signature-256` over the untouched request bytes with constant-time comparison before parsing.
- Preserve GET verify-token challenge independently from POST signature verification.
- Insert `webhook_events` with unique provider keys and payload hashes; acknowledge duplicates safely.
- Keep `admin_users` as the internal-admin bootstrap/allowlist. Add explicit internal staff roles rather than treating `platform_users.account_type` as admin authorization.
- Keep company/contractor access through active membership and projection RPCs. Never grant broad `candidates` or requirement-base-table reads.
- Put RLS on every exposed table; use indexed predicates and narrow security-definer RPCs with `search_path=''`, revoked PUBLIC execution, explicit grants, and internal authorization checks.
- Service-role clients are server-only and still call audited domain functions instead of unrestricted ad-hoc writes where practical.
- Documents use private Storage buckets, short-lived signed URLs, MIME/size validation, malware scanning, retention rules, and access audit.
- Rate-limit by provider/IP/contact/action; cap webhook bodies and outbound concurrency.
- Minimize raw payload retention; encrypt or redact sensitive payload fields and define deletion/DSAR retention policies.
- Use PITR/backups appropriate to the Supabase plan and periodically test restore into an isolated project.
- Rotate secrets with overlapping versions and a documented rollback; never log their values.

## 12. Live-site-safe development and rollout

1. Preserve current dirty worktree; commit/reconcile it before creating a new workstream.
2. Create `v3-web-platform` from a reviewed `v2-development` commit, not from unreviewed local state.
3. Use a separate Supabase development project and local CLI migrations; never point development service-role credentials at production.
4. Make every migration additive, repeatability-aware, preflighted, transaction-wrapped where supported, and paired with pgTAP/SQL security tests.
5. Hide new admin navigation behind server-evaluated feature flags and role checks; direct-route access must still be denied by RLS.
6. Deploy static/public changes independently from backend/migrations. Existing public pages remain the fallback.
7. Use expand -> backfill -> dual-read verification -> switch -> contract-later. No destructive contract step until backup and rollback rehearsal.
8. Canary the webhook with shadow event recording before allowing outbound automation.
9. Rollback by disabling feature flags/workers and restoring the previous frontend artifact; additive tables remain harmless. Never roll back by deleting production rows.

## 13. Major risks and blockers

- The repository's dirty `v2-development` worktree must be reconciled before branching.
- Repository migrations describe intent but do not prove exact production Supabase state; run read-only catalog/preflight comparisons before planning new migration numbers.
- Candidate age constraints differ between desktop intake (18–65) and web schema (16–75); product/legal policy must choose one rule.
- Web and desktop have two candidate concepts in desktop SQLite (`candidate_master` and legacy `candidates`); only reviewed canonical records should migrate.
- Current static hosting cannot itself run a same-domain webhook or server-side secrets.
- Existing `platform_users.account_type` excludes internal staff/admin; roles need an additive internal model without weakening `admin_users`.
- Existing application statuses require alignment/backfill for `new_lead`, `registered`, `interview_scheduled`, `interview_attended`, `no_show`, `withdrawn`, and `active`.
- Meta template policy, 24-hour customer-service rules, consent/STOP semantics, and India privacy/legal requirements require formal operational review.
- Realtime authorization and high-volume fan-out require load tests; database notifications are not a durable job queue.
