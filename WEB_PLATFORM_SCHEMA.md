# Web Platform Schema Blueprint

Status: normalized target model and alignment plan. Repository migration 016 now
implements the W1 foundation described below; no SQL was executed against production.

## 1. Existing Supabase inventory

The inventory below is derived from `supabase/schema.sql` plus migrations 007–015. Production must be compared with `information_schema`, `pg_catalog`, `pg_policies`, grants, and function signatures before any new migration is authored.

| Existing object | Purpose | Disposition |
|---|---|---|
| `admin_users` | Supabase Auth allowlist for Aadhyant administrators | Reuse as-is as admin bootstrap; never merge into tenant roles |
| `platform_users` | Non-admin Auth profile for company/contractor/candidate account types | Reuse; do not add admin authority implicitly |
| `companies` | Verified employer organization | Reuse and extend additively |
| `company_users` | Company membership and owner/HR/recruiter/viewer role | Reuse; retain active membership checks |
| `contractors` | Staffing partner organization | Reuse and extend additively |
| `contractor_users` | Contractor membership and roles | Reuse |
| `candidates` | Public candidate registration and future Auth-linked profile | Canonical Candidate CRM; extend rather than create a Candidate Master duplicate |
| `employer_requirements` | Company manpower requirement/vacancy | Canonical vacancy table; do not create parallel `vacancies` |
| `requirement_contractors` | Admin-controlled assignment of requirement to contractor | Reuse |
| `candidate_applications` | Candidate-to-requirement application lifecycle | Canonical application table; extend statuses/history |
| `interviews` | Repeatable/reschedulable interview rounds | Reuse |
| `candidate_joinings` | Joining lifecycle per application | Reuse; route/UI may call it joining records |

### Existing notable fields

`candidates` already stores full name, age, gender, normalized Indian mobile/WhatsApp number, current location/district/state, qualification, specialization, fresher/experienced status, experience details, prior role, interview availability, preferred location, consent, operational status, Auth link, profile lifecycle, employment/availability state, and verification time.

`employer_requirements` already stores company/contact legacy fields, job role, headcount, qualification/trade, experience/gender preferences, legacy salary text, numeric salary range, shift/working hours, expected joining, facilities, notes, company ownership, department/job location, age range, filled positions, overtime/interview data, visibility, stage, publish/close timestamps, and generated requirement code.

`candidate_applications` already enforces one candidate/requirement pair, source type (including WhatsApp), optional contractor assignment consistency, current application status, creator, timestamps, and admin notes.

`interviews` already has round, superseded interview, schedule, location, mode, status/result, meeting link, contact, instructions, result notes, remarks/internal notes, and creator fields after migration 014.

### Existing authorization functions/RPCs

Private helpers:

- `private.is_admin()`
- `private.set_updated_at()`
- `private.assign_requirement_code()`
- `private.current_active_company_id()`
- `private.current_active_contractor_id()`
- company/contractor Auth signup triggers

Public controlled functions include:

- company/contractor account status administration;
- `get_company_requirements` and `manage_company_requirement`;
- `get_staffing_partner_assignments` and `staffing_partner_respond_requirement_assignment`;
- contractor assignment administration;
- `get_public_job_requirements` safe projection;
- `register_candidate_requirement_interest`;
- `admin_update_candidate_application`;
- interview schedule/reschedule/update functions.

Migration 015 removes tenant base-table read policies for requirements/assignments and requires narrow projection functions. Preserve this security boundary.

Migration 016 additively implements `staff_profiles`, `staff_roles`,
`candidate_preferences`, `application_stages`, `application_stage_history`, and
`audit_logs`, plus nullable application source/correlation metadata. It does not
rewrite existing application statuses or authorize non-admin staff access.

Migration 017 implements W2 internal staff authorization over the W1 tables. It
keeps `admin_users` as a bootstrap override, denies `platform_users` identities,
uses the roles `super_admin`, `admin`, `recruiter`, `operations`, and `viewer`,
and exposes only narrow authenticated session/staff-management RPCs. It removes
browser direct access to `staff_profiles` and `staff_roles` and does not grant W2
roles access to existing operational or tenant data.

Migration 018 implements W3 internal recruitment operations without adding
replacement domain tables. Active W2 staff use projected RPCs for recruitment
permissions/metrics, Candidate CRM, requirements, applications and history,
interviews, and joining/placement. Candidate contact PII is limited to approved
candidate managers; operations is restricted to selected/joining context and
viewer is read-only. No W3 direct table grant or tenant policy is added, so the
migration 015 projections and W2 staff-management boundary remain unchanged.

## 2. Naming and identity decisions

- Keep UUID primary keys for all web domain tables.
- `employer_requirements` remains the physical vacancy table. The service/UI may call it Vacancy without adding `vacancies`.
- `candidate_joinings` remains the physical joining table. Do not add `joining_records` unless a future multi-employment requirement proves one-to-one insufficient.
- `admin_users` remains authoritative for administrator allowlisting.
- Add internal staff membership separately because `platform_users.account_type` intentionally models external company/contractor/candidate accounts.
- Store phone in one canonical searchable form (India E.164 digits, e.g. `919876543210`) plus optional display input. Enforce normalized uniqueness where business rules allow.
- Use `timestamptz` for events and `date` only for date-only facts.
- Use text checks or reference tables for controlled statuses; avoid PostgreSQL enum types when operational additions are expected.

## 3. Existing-table extensions

### `admin_users` and internal users

Keep `admin_users(user_id)` unchanged for bootstrap authorization. Add:

#### `staff_profiles`

| Column | Notes |
|---|---|
| `user_id uuid PK` | references `auth.users`; admin/recruiter identity |
| `display_name`, `mobile` | operational profile |
| `status` | active/suspended |
| `created_at`, `updated_at` | audit timestamps |

#### `staff_roles`

W1 implements `staff_roles(user_id, role, status, granted_by, created_at, updated_at)`.
W2 fixes the initial role vocabulary as `super_admin`, `admin`, `recruiter`,
`operations`, and `viewer`. Bootstrap authority remains in `admin_users`; ordinary
staff authority requires an active staff profile and active role. W2 role grants
do not implicitly authorize existing operational tables or tenant contracts.

### `candidates`

Reuse existing columns. Candidate CRM extensions only where absent:

- `candidate_code` unique human-readable identifier;
- `phone_normalized` generated/backfilled canonical value (after collision report);
- `assigned_recruiter_id` nullable staff FK;
- `source`, `source_reference`;
- `last_contact_at`, `registered_at`;
- optional `deleted_at`/archive metadata only after retention policy approval.

Move repeating/independent data into child tables rather than widening `candidates` indefinitely.

### `employer_requirements`

Reuse as Vacancy/Requirement. Add only missing structured facts required for matching, such as employment type, openings availability, approved document requirements, joining availability window, or recruiter owner. Do not duplicate `required_headcount`, salary bounds, job location, facilities, or interview fields.

### `candidate_applications`

Align `application_status` to the target pipeline. Prefer a new checked vocabulary plus explicit audited transition RPC. If production rows exist, expand accepted values first, map old values, verify, and only later remove obsolete values.

Recommended additive fields:

- `assigned_recruiter_id`;
- `selected_at`, `withdrawn_at`, `rejected_at` where reporting requires direct timestamps;
- `current_stage_changed_at`;
- `source_message_id` or `source_webhook_event_id` for idempotent WhatsApp creation;
- optional matching snapshot ID.

### `interviews`

Reuse current scheduling model. Add reminder state only if automation cannot derive it from `automation_runs`; prefer the latter. Never expose internal notes/contact details through public/candidate projections without a disclosure policy.

### `candidate_joinings`

Reuse existing expected/actual date, status, employee code, remarks, and internal notes. Future compliance/payroll fields should be separate protected tables, not added casually.

## 4. New recruitment tables

### `candidate_preferences`

One current preference profile per candidate:

- candidate FK/PK;
- preferred locations (normalized child rows or text array for initial version);
- salary minimum/maximum;
- shift, working-hours, accommodation, transport preferences;
- joining availability date;
- updated source/actor/timestamps.

### `candidate_documents`

- candidate/application optional FK;
- document type, private storage object path, original filename, MIME, size, checksum;
- verification/status, expiry, uploaded/verified actors and timestamps;
- no public URL persisted.

### `application_stage_history`

- application FK;
- `from_stage`, `to_stage`;
- reason/note;
- actor type and Auth user/service identity;
- source (`admin`, `company`, `contractor`, `candidate`, `whatsapp`, `automation`, `migration`);
- correlation/event ID and timestamp.

Append-only to ordinary roles. Corrections create a compensating event.

### `candidate_matches`

Persist only reviewed/generated matching snapshots:

- candidate and requirement FKs;
- algorithm version;
- total score;
- `reason_breakdown jsonb` with criterion, candidate value, vacancy value, score, and explanation;
- hard-exclusion reasons;
- generated/expired timestamps.

No opaque AI score. Sensitive criteria must be explicitly enabled and legally reviewed.

## 5. WhatsApp and inbox tables

### `whatsapp_contacts`

- `id uuid PK`;
- `wa_id` unique normalized digits;
- profile name;
- candidate FK nullable;
- language;
- consent/opt-out state and timestamps;
- first/last seen;
- merge/link history via audit events.

### `whatsapp_conversations`

- contact FK;
- candidate/application/requirement nullable context;
- assigned recruiter/team;
- state (`open`, `closed`, `archived`);
- bot mode (`active`, `paused`, `human_handoff`, `opted_out`);
- unread count and last-message denormalization;
- selected vacancy;
- version/lock field;
- created/updated/last inbound timestamps.

One active conversation per contact/channel is a starting invariant; allow a future explicit thread key rather than silently duplicating contacts.

### `whatsapp_messages`

- conversation/contact FKs;
- provider message ID unique nullable (local queued messages use client/outbox key);
- direction and actor type;
- message/content type;
- text and safe structured content JSON;
- reply-to/provider context;
- template/Flow references;
- status and provider error fields;
- provider sent/delivered/read/failed timestamps;
- created/received timestamps;
- webhook event/outbox correlation.

Avoid keeping full raw payload here. Reference `webhook_events`, which has a shorter retention policy.

### `conversation_assignments`, `conversation_tags`, `notes`

- assignment history stores recruiter, assigned/unassigned timestamps, actor, reason;
- tags are normalized (`tags` plus join table) and scoped appropriately;
- notes attach to candidate, application, conversation, requirement, company, or contractor through explicit nullable FKs/check constraints or domain-specific join tables. Never expose internal notes to tenant projections.

## 6. Chatbot tables

### `chatbot_contacts`

One-to-one with WhatsApp contact/conversation policy:

- language, bot enabled, handoff, opt-out;
- last intent/reply/menu;
- selected requirement/application;
- unknown count/cooldown;
- no duplicate candidate facts.

### `chatbot_sessions`

- contact/conversation FK;
- flow version/current node;
- status;
- `variables jsonb` limited to transient typed state;
- previous-node stack or transition pointer;
- expiry, version, last inbound event;
- unique active-session constraint.

Candidate intake data should populate `candidates`/preferences only through review/approval. If review sessions are needed, use a dedicated `candidate_intake_sessions` table linked to contact/candidate and do not duplicate finalized Candidate CRM values after completion.

### Flow definitions

- `chatbot_flows(id, code, name, status, active_version_id, created_by, timestamps)`;
- `chatbot_flow_versions(id, flow_id, version, status, settings, published_by/at, checksum)`;
- `chatbot_flow_nodes(id, version_id, node_key, node_type, config jsonb, position)`;
- `chatbot_flow_edges(id, version_id, from_node_id, to_node_id, condition/config, priority)`.

Unique `(flow_id, version)`, `(version_id, node_key)`, and deterministic edge ordering. Published versions are immutable.

## 7. Messaging, campaigns, and automation

### `message_templates`

Meta template ID/name, language, category, status, components, variables, sync metadata, active/archive timestamps. Unique Meta identity and name/language rules.

### `campaigns`, `campaign_recipients`

Campaign definition, template/version, audience snapshot, owner, schedule, status, counts. Each recipient stores candidate/contact, rendered parameter snapshot, idempotency key, queue/send/delivery state, attempts, provider message ID, and error metadata.

### `message_outbox`

Transactional outbound intent:

- unique idempotency key;
- recipient/conversation/template/message payload reference;
- source type/id;
- state, priority, schedule, lease, attempt/retry/error;
- provider message ID after send.

### `automation_rules`, `automation_rule_versions`, `automation_runs`

Rules are versioned; runs store trigger entity/event, idempotency key, status, lease, attempts, next retry, result/error, and timestamps. WAIT/reminders produce scheduled runs/outbox items.

## 8. Integration, delivery, and audit

### `webhook_events`

- provider/topic;
- provider event/message key unique where present;
- payload hash unique fallback;
- signature verified flag;
- minimally retained encrypted/redacted payload;
- received/queued/processed timestamps;
- processing status/attempt/error/correlation.

Never persist token or App Secret. Partition/retention may be introduced after volume measurement.

### `delivery_events`

Provider message ID, status, timestamp, error code/title/details, webhook FK, unique event key. Update current message state monotonically; keep events append-only.

### `audit_logs`

Actor, role/scope, action, entity type/id, before/after safe diffs, IP/user-agent where appropriate, correlation ID, timestamp. Do not record credentials, raw document content, or unrestricted webhook payloads.

## 9. RLS matrix

| Data | Admin/internal recruiter | Company | Contractor | Candidate | Anonymous |
|---|---|---|---|---|---|
| Candidate full CRM | scoped internal role | only approved application projection | only assigned application projection | own profile | insert-only registration RPC/form |
| Requirements | full by role | own via narrow RPC | assigned projection only | public projection | public projection only |
| Applications | full/scoped | own requirement disclosure projection | assigned requirement disclosure projection | own | none |
| Interviews/joinings | full/scoped | own application projection | assigned projection if approved | own disclosed fields | none |
| Inbox/messages | assigned team/admin | none initially | none initially | optional own channel later | none |
| Flow/automation/campaign | privileged internal only | none | none | none | none |
| Documents | privileged/assigned | only explicitly disclosed | only explicitly disclosed | own | none |
| Audit/webhook/outbox | restricted admin/auditor/service | none | none | none | none |

Every service-role write should call an audited domain function or supply actor/correlation context. RLS is still required for browser reads even when backend services exist.

## W5 contractor vacancy review extension

Contractor submissions reuse `employer_requirements` and are linked through `requirement_contractors`. Migration 021 adds contractor-origin metadata and a review lifecycle to the link rather than introducing a second vacancy table. New submissions remain canonical Draft/Private records until an authorized internal review approves the same row as Open/Assigned for W3 matching. Contractor tenant scope is derived from `auth.uid()` and exact active membership; no browser-supplied contractor or company ownership is trusted.

Contractor-safe application, interview, and joining projections are read-only and exclude contact PII, internal identifiers, and internal notes. Profile mutation is allowlisted; legal, registration, verification, email, and account fields remain protected.

### W4 Company Portal projection

Migration 019 adds no business table. It resolves exactly one company membership from `auth.uid()` and projects the tenant's canonical requirements, associated applications, interviews, and joinings through narrow RPCs. Company owners/HR admins may update allowlisted profile fields; company recruiters may manage permitted requirement lifecycle actions; company viewers are read-only. Legal/verification fields and all internal recruitment mutations remain server-controlled.

The company candidate projection deliberately omits contact details, Auth/candidate identifiers, internal notes, staff identities, unrelated history, and other tenant data. Migration 015 base-table isolation remains unchanged, and W3 remains authoritative for candidate, application-stage, interview, and joining mutations.

## 10. Matching model (design only)

Deterministic scoring inputs can include qualification, specialization/trade, experience, current/preferred location, salary range, shift/hours, accommodation/transport, joining availability, and only legally approved age/gender requirements.

Each criterion defines:

- hard requirement vs weighted preference;
- normalization function;
- weight and maximum points;
- missing-data behavior;
- human-readable reason.

Return `eligible`, total percentage, hard exclusions, and per-criterion reasons. Store algorithm version and source-row update timestamps so stale matches can be detected.

## 11. Migration sequencing rules

1. Catalog and back up production; compare actual objects with repository migrations.
2. Add tables/nullable columns/check-compatible values and indexes concurrently where appropriate.
3. Add write-through/domain functions and tests.
4. Backfill in bounded batches with reconciliation reports.
5. Enable RLS and grants before exposing routes.
6. Dual-read and compare counts/keys/statuses.
7. Switch feature flag to new path.
8. Keep legacy fields/tables until a later contract milestone with explicit approval.

No migration in this blueprint is authorized for execution.
