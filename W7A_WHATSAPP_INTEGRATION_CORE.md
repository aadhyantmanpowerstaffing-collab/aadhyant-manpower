# W7A WhatsApp Integration Core

Status: static implementation only. Migration 026 is not applied, the Edge Function is not deployed, Meta was not contacted, and no message was sent.

## Scope

W7A adds the server-side communication foundation without changing the canonical recruitment model. WhatsApp is not the source of truth for Candidates, requirements, applications, interviews, joinings, or documents.

Included:

- a verified and idempotent webhook-ingress ledger;
- normalized WhatsApp contacts and inbound metadata;
- a durable PostgreSQL outbound outbox with claim leases and bounded retries;
- immutable provider delivery/read/failure events;
- marketing and transactional suppression foundations;
- narrow Admin-only read projections;
- a Supabase Edge webhook receiver, shared parsers, phone normalization, and a fake provider;
- rollback-scoped SQL and deterministic local unit tests.

Excluded:

- campaigns and audience snapshots;
- Candidate matching or Candidate creation;
- INTERESTED-to-application automation;
- interview, joining, offer, or document reminders;
- a real Meta sender or live Meta calls;
- worker or Edge Function deployment.

## Runtime boundary

The selected topology is:

1. A Supabase Edge Function authenticates Meta webhook requests, validates their untouched bytes, stores a durable event through a server-only RPC, and responds promptly.
2. PostgreSQL owns contacts, event ledgers, normalized messages, consent state, and the outbound outbox.
3. A later managed worker will claim leased outbox rows and invoke the real provider adapter.

Migration 026 does not depend on `pgmq`. Availability has not been established for the project, so the outbox is claimable with `FOR UPDATE SKIP LOCKED` and bounded leases.

## Five-table model

### `whatsapp_contacts`

Stores one canonical `+91` provider address and ten-digit Indian comparison key. Candidate linkage is nullable and becomes `ambiguous` rather than selecting arbitrarily when multiple active Candidate rows match. Marketing consent and transactional contact status are separate. Explicit opt-out requires source and timestamp attribution.

### `whatsapp_webhook_events`

Stores only signature-verified durable events. Provider event keys are unique, payload hashes are lowercase SHA-256, categories/states are controlled, and any diagnostic JSON is redacted and capped at 64 KiB. Invalid signatures are rejected before insertion.

### `whatsapp_inbound_messages`

Stores normalized text/button/list/Flow/unsupported metadata with a unique provider message ID. Text, action IDs, correlation keys, and allowlisted Flow responses are bounded. Raw provider message objects are not retained.

### `whatsapp_outbound_messages`

Acts as the durable logical outbox. The unique idempotency key prevents duplicate logical messages. Queue claims are bounded to 100 rows, use leases and `SKIP LOCKED`, increment attempts atomically, and recheck suppression. An ambiguous provider-acceptance result is finalized for reconciliation and is never blindly reclaimed.

### `whatsapp_message_events`

Stores immutable accepted/sent/delivered/read/failed provider events. Duplicate provider event keys are idempotent. The projected outbound state is monotonic: sent cannot regress delivered/read, delivered cannot regress read, and a late failed event cannot regress delivered/read.

## Consent and STOP

Marketing consent values are `unknown`, `opted_in`, and `opted_out`. Transactional contact values are `unknown`, `allowed`, and `suppressed`. Enqueue and claim functions both recheck the applicable class. The server-only suppression RPC records safe audit metadata. Opt-back-in requires a later reviewed contract; clearing suppression does not silently grant marketing consent.

## Authorization

All five tables have RLS enabled and no direct privileges for `PUBLIC`, `anon`, or `authenticated`. Browser roles cannot execute server mutation RPCs. Only `bootstrap_admin`, `super_admin`, and `admin` may use bounded, masked read projections. Recruiter, operations, Candidate, Company, Contractor, and anonymous callers are denied.

Every W7A SECURITY DEFINER function has `search_path = ''`, uses schema-qualified objects, and avoids dynamic SQL. Server mutation RPC execution is granted only to `service_role`; service credentials remain server-side.

## Edge webhook boundary

`supabase/functions/whatsapp-webhook/index.ts` implements:

- exact GET verify-token challenge handling;
- JSON content-type and 1 MiB body limits;
- one untouched raw-body read;
- constant-time `X-Hub-Signature-256` verification before JSON parsing;
- deterministic event keys and redacted event summaries;
- durable acceptance through `accept_whatsapp_webhook_event`;
- prompt `EVENT_RECEIVED` acknowledgement.

It does not call Graph, create Candidates/applications, match jobs, or send reminders. Secrets are read only from the server environment and are not logged or echoed.

## Provider adapter

The shared provider interface defines template send, safe error classification, and provider message-ID extraction. `FakeWhatsAppProvider` produces deterministic success, transient, permanent, and ambiguous outcomes. A real Meta adapter and managed worker are deferred and must use deployment secret management.

## Retry and delivery rules

- Claims require a worker identifier and a 15–900 second lease.
- Attempts and maximum attempts are bounded to ten.
- Transient failures require a future retry timestamp.
- Permanent, exhausted, or ambiguous failures become terminal and auditable.
- Success/failure finalization requires the current lease owner.
- Logical idempotency cannot guarantee exactly-once physical delivery if a provider accepts a request immediately before a worker crash; ambiguous outcomes require reconciliation rather than automatic resend.

## Privacy

W7A does not persist Aadhaar, bank values, documents, signed URLs, provider tokens, signatures, or complete provider error bodies. Admin projections mask phone numbers. Flow responses use an explicit basic-profile allowlist. Payload and message retention/deletion periods must be approved before production.

## Validation and deployment prerequisites

Before applying migration 026 or deploying the Edge Function:

- extend the staging guard separately through migration 026;
- authorize and apply migration 026 only to dedicated NONPROD staging;
- run checkpoint 029 and the W2-W6 regression chain;
- configure Edge Function project files and secrets through reviewed deployment controls;
- select and approve the permanent worker host;
- approve Meta app, number, templates, consent/STOP policy, retention, monitoring, rate limits, and operational runbooks;
- perform controlled NONPROD provider testing before any production enablement.

W7B may add approved-vacancy campaigns and deterministic audience snapshots. W7C may add staged intake and an idempotent canonical application bridge. Neither is part of W7A.
