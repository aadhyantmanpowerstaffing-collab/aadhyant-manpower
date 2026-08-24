# W7A WhatsApp Integration Core

Status: W7A database/runtime core and NONPROD Edge validation are COMPLETE. Immutable migration 026 and upgrade-safe corrective migration 027 are installed, checkpoints 029 and 030 pass, required checkpoints 011–028 pass 18/18, and the frontend baseline passes 121/121. The NONPROD `whatsapp-webhook` is deployed and ACTIVE; signature rejection, GET verification, durable webhook acceptance, inbound orchestration with local Edge tests, and real signed status-callback acceptance have been validated. Production was not contacted. Full real inbound live delivery is not claimed because of the Meta test-number limitation documented below.

NONPROD runtime validation of immutable migration 026 exposed PostgreSQL special expressions that had been incorrectly qualified as ordinary `pg_catalog` functions. Upgrade-safe migration 027 replaces only the affected W7A function definitions with PostgreSQL-compatible unqualified `coalesce`, `greatest`, `least`, and `nullif` expressions. Migration 026 remained unchanged, and migration 027 changes no W7A authorization, privacy, idempotency, queue, consent, or delivery semantics.

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

Stores one canonical `+91` provider address and ten-digit Indian comparison key. Only digits and the reviewed formatting characters `+`, spaces, hyphens, and parentheses are accepted; alphabetic or other punctuation contamination fails closed. Candidate linkage is nullable and becomes `ambiguous` rather than selecting arbitrarily when multiple active Candidate rows match. Only `resolved` contacts carry a Candidate ID. Candidate deletion detaches the contact and atomically returns it to `unresolved`. Marketing consent and transactional contact status are separate. Explicit opt-out requires source and timestamp attribution.

### `whatsapp_webhook_events`

Stores only signature-verified durable events. Provider event keys are unique, payload hashes are lowercase SHA-256, categories/states are controlled, and any diagnostic JSON is redacted and capped at 64 KiB. Invalid signatures are rejected before insertion.

### `whatsapp_inbound_messages`

Stores normalized text/button/list/Flow/unsupported metadata with a unique provider message ID. Arbitrary inbound free text is not persisted in W7A. Action IDs, correlation keys, and allowlisted flat Flow responses are bounded. Malformed siblings are skipped without losing valid siblings, and raw provider message objects are not retained.

### `whatsapp_outbound_messages`

Acts as the durable logical outbox. An exact replay of every immutable logical-send field returns the existing message; conflicting reuse of the same idempotency key fails closed. Queue claims are bounded to 100 rows, use leases and `SKIP LOCKED`, increment attempts atomically, and recheck suppression. A claimed lease may be reclaimed only before the worker marks `provider_call_started`. Expiry after that marker becomes terminal `reconciliation_required` with `ambiguous_provider_outcome` and is never automatically resent. Expired final-attempt claims become terminal instead of remaining stranded.

### `whatsapp_message_events`

Stores immutable accepted/sent/delivered/read/failed provider events. Duplicate provider event keys are idempotent. The projected outbound state is monotonic: sent cannot regress delivered/read, delivered cannot regress read, and a late failed event cannot regress delivered/read.

## Consent and STOP

Marketing consent values are `unknown`, `opted_in`, and `opted_out`. Transactional contact values are `unknown`, `allowed`, and `suppressed`. Enqueue and claim functions both recheck the applicable class. The server-only suppression RPC records safe audit metadata. Opt-back-in requires a later reviewed contract; clearing suppression does not silently grant marketing consent.

## Authorization

All five tables have RLS enabled and no direct privileges for `PUBLIC`, `anon`, or `authenticated`. Browser roles cannot execute server mutation RPCs. Only `bootstrap_admin`, `super_admin`, and `admin` may use bounded, masked read projections. Recent inbound projections expose type and safe action metadata, not arbitrary message text. Recruiter, operations, Candidate, Company, Contractor, and anonymous callers are denied.

Every W7A SECURITY DEFINER function has `search_path = ''`, uses schema-qualified objects, and avoids dynamic SQL. Server mutation RPC execution is granted only to `service_role`; service credentials remain server-side.

## Edge webhook boundary

`supabase/functions/whatsapp-webhook/index.ts` implements:

- exact GET verify-token challenge handling;
- JSON content-type and 1 MiB body limits;
- one untouched raw-body read;
- constant-time `X-Hub-Signature-256` verification before JSON parsing;
- deterministic event keys and redacted event summaries;
- durable acceptance through `accept_whatsapp_webhook_event`;
- accept-first status orchestration through the existing `record_whatsapp_message_event` RPC after a service-role lookup by provider message ID;
- prompt `EVENT_RECEIVED` acknowledgement.

It does not call Graph, create Candidates/applications, match jobs, or send reminders. Secrets are read only from the server environment and are not logged or echoed.

Status callbacks for `sent`, `delivered`, `read`, and `failed` are signature-verified and accepted into the webhook ledger before projection. The Edge receiver resolves exactly one outbound message using the provider message ID and delegates the immutable event insert and monotonic state transition to `record_whatsapp_message_event`; it performs no direct table write. Exact duplicates and out-of-order callbacks remain governed by the database idempotency and monotonic projection contract. In particular, sent cannot regress delivered/read, delivered cannot regress read, and late failure cannot regress delivered/read.

## Provider adapter

The shared provider interface defines template send, safe error classification, and provider message-ID extraction. `FakeWhatsAppProvider` produces deterministic success, transient, permanent, and ambiguous outcomes. A real Meta adapter and managed worker are deferred and must use deployment secret management.

## Retry and delivery rules

- Claims require a worker identifier and a 15–900 second lease.
- Attempts and maximum attempts are bounded to ten.
- Transient failures require a future retry timestamp.
- Permanent, exhausted, or ambiguous failures become terminal and auditable.
- Success/failure finalization requires the current lease owner.
- Logical idempotency does not guarantee exactly-once physical provider delivery. The worker must mark `provider_call_started` immediately before invoking the provider; a crash after that point is quarantined for reconciliation rather than automatically resent.

## Privacy

W7A stores only flat, bounded JSON metadata with scalar values, limits key count and lengths, and rejects normalized recognized Aadhaar, bank-account, UAN, ESIC, document URL/path/content, signed-URL, token, and secret keys. Arbitrary inbound free text is discarded rather than exposed through Admin projections. Flow responses use an explicit basic-profile allowlist and Admin projections mask phone numbers. This is deliberate minimization, not perfect DLP: arbitrary text classification, payload/message retention, redaction policy, and deletion periods still require approval before production.

## Final NONPROD validation evidence

Migration 026 installed the five-table WhatsApp integration foundation on dedicated NONPROD. Migration 027 then applied the upgrade-safe PostgreSQL compatibility correction while keeping migration 026 immutable and preserving all business and security semantics.

Focused checkpoint 030 passed after executing all 11 corrected function definitions. Its transaction rolled back and left zero residue. Checkpoint 029 passed the complete W7A schema/catalog, phone/contact, Candidate-detach, consent, webhook/inbound, outbound idempotency, claim/lease, retry/failure, delivery monotonicity, privacy, authorization, audit, and cleanup matrix with client exit code 0, rollback success, and zero residue. The unchanged rollback-scoped checkpoint 029 was repeated only to capture an explicit final client exit status after the first client status was lost during an output-window handoff; both executions used the same checkpoint version.

Required legacy and W2–W6 checkpoints 011–028 pass 18/18. Checkpoint 025 specifically proves direct Uploaded-to-Verified denial, valid Uploaded-to-Under Verification-to-Verified and Uploaded-to-Under Verification-to-Re-upload Required paths, and correct review-start/final attribution. W7A local unit tests pass 12/12 and the complete frontend baseline passes 121/121.

The installed runtime posture contains exactly five W7A tables and 21 W7A functions. Twenty functions are `SECURITY DEFINER`, all 20 use an empty `search_path`, all five tables have RLS enabled, browser base-table grants are zero, server mutations remain browser-denied, and the five Admin read projections remain narrow. Runtime tests validate strict phone normalization, Candidate detach behavior, consent/suppression, webhook and inbound deduplication, structured sensitive-key rejection, outbound idempotency, bounded claims, safe lease/retry behavior, provider-call ambiguity quarantine, final-attempt terminalization, worker ownership, monotonic delivery, immutable message events, safe audit metadata, and omission of arbitrary inbound text from Admin projections. Final verification found zero synthetic residue and no orphan or cross-tenant residue.

## Meta test-number live inbound limitation

Meta Dashboard proved that controlled Retry 3 generated a real text event on the `messages` webhook field in the correct approved test-number/WABA context at `2026-08-24 07:13:32 IST` (`01:43:32 UTC`). A bounded Supabase live observation was already active and covered `01:42:15.479825` through `01:47:10.610994 UTC`. No matching Supabase POST, Edge invocation, request/execution ID, HTTP response, webhook-ledger row, contact, or inbound-message row was recorded. The same NONPROD endpoint has independently accepted signed status callbacks.

No concrete application defect was established for the missing ingress. The unresolved boundary is Meta event generation to recorded Supabase ingress. Repeated test-number retry loops were stopped because they no longer distinguished the remaining causes. Full real inbound validation is deferred to a future controlled test with a real registered number or to Meta-side delivery-history evidence/resolution. This limitation does not invalidate local Edge orchestration, database contracts, signature verification, webhook GET verification, or the status-callback acceptance already proven. W7A does not claim a full real inbound live PASS.

## Remaining production prerequisites

Before deploying the Edge Function or enabling production communication:

- select and approve the permanent worker host;
- approve Meta app, number, templates, consent/STOP policy, retention, monitoring, rate limits, and operational runbooks;
- perform controlled NONPROD provider testing before any production enablement.

Local Edge tests exercise the Web-compatible receiver and status orchestration. Deployed NONPROD Edge validation is complete, but the Meta test-number inbound-delivery limitation above remains open. No production deployment or real-candidate contact occurred. Retention, legal, provider, operational, and production approvals remain deferred.

W7B may add approved-vacancy campaigns and deterministic audience snapshots. W7C may add staged intake and an idempotent canonical application bridge. Neither is part of W7A.
