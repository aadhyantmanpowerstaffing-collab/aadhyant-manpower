# Interested registration reply — 14 October 2026

Prepared for review; not deployed. No production mutation or real send was performed while implementing this change.

An imported recipient's Interested button currently records `registration_required` but sends no next-step link. This change responds through the canonical outbox with a fixed Gujarati registration message containing the exact public Requirement code. The existing Candidate registration, email confirmation, sign-in, onboarding and Jobs routes retain that code. Applying remains an explicit action in the Candidate Portal. Already-linked campaign Candidates continue through the existing canonical Application processor.

## Delivery contract

- Only a signed, sender-matched, exactly correlated Interested event can claim a reply.
- One registration reply per original campaign message, including repeated button clicks and webhook retries.
- The provider timestamp must be inside the 24-hour customer service window and not in the future. Check the window, STOP/suppression, contact identity, job eligibility, sender verification and lease again at the provider boundary.
- Do not grant marketing or general transactional consent. Imports, Interested and registration links never subscribe the recipient to future alerts.
- Keep one maximum attempt. Timeout, uncertain receipt or expired provider-call lease requires reconciliation; never resend automatically.
- Reuse `whatsapp_outbound_messages`, receipt/failure RPCs, signed delivery callbacks and audit logs. No duplicate queue, Candidate or Application records.
- Reports show registration-link waiting/sending/sent/delivered/read/failed separately from application results.
- No historical backfill, bulk campaign, scheduler activation or Meta configuration change.

## Release scope and sequence

1. After explicit production approval, apply `20261014084313_whatsapp_interested_registration_reply.sql` to Aadhyant project `wsuctjhbqiedttfnwjvf`.
2. Deploy the reviewed `whatsapp-webhook` with its shared files, retaining `verify_jwt=false` and raw-body HMAC plus exact sender identity validation.
3. Publish the reviewed Admin report change through the existing production Pages artifact workflow.
4. Verify grants, RPCs, runtime source and artifact identity without a real send. A new Interested click from the test recipient can validate the actual link separately; replaying old production webhooks is not part of deployment.

The migration changes the canonical outbox message-type constraint and adds two service-role-only reply RPCs and a private eligibility predicate. Existing browser grants, RLS and campaign worker remain unchanged. Session metadata uses `aadhyant_interested_registration` as an internal descriptor, not a Meta-approved template.

## Validation

PGlite SQL runtime covers unknown consent, exact linkage, once-per-original deduplication, signed provenance, past/future windows, STOP, blocked contacts, closed jobs, late suppression/window expiry, and expired leases. Edge tests cover signed ingress through one mocked provider call, replay, no marketing subscription, boundary rejection, terminal provider errors and ambiguous outcomes. No test calls real Meta.

Production read-only checks confirmed the expected template-only constraint and absence of an existing reply RPC. Candidate registration is already included in the production artifact; its existing job-preserving routes are reused.

Sources checked: Meta service messages (`https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages`) and customer service windows (`https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing`); Supabase changelog and its 12 October TLS cipher announcement (effective no earlier than 10 November 2026, no application change required here), plus Edge Function lifecycle docs. No dependencies were added.

Prepared artifact digest: `7266473e52d3bf9d2cf6e388cc4c0ae53a0fe71e4ecc95c6ae572b776a3a88ed`.

Final full regression: **433 tests passed, zero failed/skipped**. Production artifact build and `--verify` pass; `git diff --check` passes. Browser QA and production runtime validation remain pending deployment approval.
