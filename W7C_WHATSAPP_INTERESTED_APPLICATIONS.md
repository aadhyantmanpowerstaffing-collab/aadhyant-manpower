# W7C WhatsApp INTERESTED Applications

Status: implementation and local static/unit review complete; dedicated NONPROD migration and rollback-checkpoint validation remain pending. No Edge deployment, Meta configuration change, real message, or production action is part of this milestone.

## Scope and continuity

W7C turns an exact inbound `INTERESTED` reply to a delivered W7B vacancy campaign message into a link to the canonical `candidate_applications` record. It preserves the W7A webhook ledger, contact model, inbound normalization, delivery outbox, and security boundary, and preserves the W7B campaign/recipient model. It adds no Candidate, Requirement, contact, campaign, outbox, or application table.

Migration `029_whatsapp_interested_applications.sql` extends `whatsapp_inbound_messages` with nullable foreign keys to the correlated W7B recipient and canonical application. The Edge parser captures Meta's bounded reply-context provider message ID in the existing `correlation_key`; Flow correlation remains the existing flow token. The Edge receiver first durably accepts and normalizes the inbound message, then delegates only an exact normalized `INTERESTED` action to the server-only processor RPC.

## Exact correlation chain

`process_whatsapp_interested_response(inbound_message_id)` locks the inbound row and requires all of the following:

1. the stored action is exactly `INTERESTED` after bounded normalization;
2. the inbound reply context identifies exactly one W7A outbound provider message for the same WhatsApp contact;
3. that outbound row identifies the same W7B queued recipient through its immutable correlation ID, Candidate, contact, and Requirement;
4. the W7B campaign and outbound Requirement agree;
5. the campaign is queued, sending, or completed and the outbound purpose/consent class remain `vacancy_campaign`/`marketing`;
6. the outbound message reached `sent`, `delivered`, or `read`;
7. the WhatsApp contact remains resolved to the same active canonical Candidate; and
8. the canonical Requirement remains open.

Any missing or inconsistent correlation is classified with a bounded safe code and leaves both new linkage columns null. A non-`INTERESTED` action is rejected. The processor does not infer a Candidate from message text, phone alone, or browser input.

## Canonical application and idempotency

The successful path inserts `candidate_applications` with source `whatsapp`, stage `interested`, a bounded campaign/recipient source reference, and the inbound message as correlation ID. The canonical unique Candidate/Requirement constraint is authoritative. If that application already exists, W7C links it without changing its source, stage, creator, or other recruitment state. The inbound row is then marked `processed` and linked to the exact recipient and application.

The inbound row lock makes exact replay return `already_processed`. Concurrent or later INTERESTED messages for the same Candidate/Requirement converge through the existing canonical unique constraint. The canonical application-history trigger records newly created applications; W7C adds one safe ID-only audit row per newly processed inbound message.

## Security, privacy, and side-effect boundaries

The processor is `SECURITY DEFINER` with `search_path=''`, no dynamic SQL, and execute permission only for `service_role`. W7A/W7B tables retain RLS and zero browser base-table grants. The Edge function performs RPC orchestration only; it has no direct recruitment-table write and no Graph send path.

No inbound free text, raw phone, Aadhaar, bank, UAN, ESIC, document data, token, or secret is added to application references, audits, or Admin projections. W7C sends no outbound message and does not alter consent. Marketing consent and suppression remain authoritative W7A send-time boundaries; W7C only consumes proof of an already dispatched campaign message and the candidate's inbound action.

## Validation contract

Rollback checkpoint `032_whatsapp_interested_applications_test.sql` verifies catalog objects, foreign keys, indexes, processed-state linkage, RLS/grants, exact correlation, canonical application creation, application-history attribution, existing-application preservation, exact and semantic idempotency, safe audit metadata, fail-closed missing/wrong/closed/undelivered cases, non-INTERESTED rejection, browser denial, transaction rollback, and executable zero-residue checks.

Reviewed pre-runtime artifacts:

- migration 029 SHA-256: `a1214b6beea3e575d4594edef8adacbf34b53ee2da20e52761fdefd3a50ecd1e`;
- checkpoint 032 SHA-256: `545991f1ca889d313e529b6f881df1731d5dff4e2de85b5d8496442aa0171abf`; and
- aggregate `schema.sql` plus migrations 007–029 SHA-256: `7429888214faca7524c1e119674684ab8765052bb36701dd82b22353de07ac46`.

Before applying migration 029 to dedicated NONPROD, the tracked implementation must be committed and clean, the staging guard must be independently reviewed and extended through exactly migration 029, its approved HEAD and aggregate must match, and the exact TLS/read-only NONPROD identity and production denylist must pass. Apply only migration 029, verify the installed catalog/security posture, run checkpoint 032 with `ON_ERROR_STOP=1`, then run W7A checkpoints 029/030, W7B checkpoint 031, Edge tests, the full frontend suite, static/privacy/security scans, and final residue/fingerprint checks.

## Excluded work

W7C does not deploy the Edge function, send or acknowledge a WhatsApp message, contact a real Candidate, alter Meta configuration, create an unlinked Candidate/contact, advance an existing application, schedule an interview, add conversational state, or begin any later chatbot, inbox, automation, or production milestone.
