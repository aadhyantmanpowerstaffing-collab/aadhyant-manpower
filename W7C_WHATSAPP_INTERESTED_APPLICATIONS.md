# W7C WhatsApp INTERESTED Applications

Status: implementation, dedicated NONPROD migration/runtime validation, regression, Edge version 5 deployment, signed deployed-endpoint integration validation, and final closure review are complete. Full real Meta inbound validation remains deferred under the documented test-number ingress limitation. No production action, Meta configuration change, automated WhatsApp send, or real-Candidate contact occurred.

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
- checkpoint 032 SHA-256: `4fddf27c4246737c80bf5fc3243d0b0052b37a67b65ce98c844eb63027b3989f`; and
- aggregate `schema.sql` plus migrations 007–029 SHA-256: `7429888214faca7524c1e119674684ab8765052bb36701dd82b22353de07ac46`.

The runtime procedure requires a committed clean implementation, a staging guard independently reviewed through exactly migration 029, matching approved HEAD/aggregate, and the exact TLS/read-only NONPROD identity with a clear production denylist. Only migration 029 may be applied before verifying catalog/security posture, executing checkpoint 032 with `ON_ERROR_STOP=1`, and running W7A checkpoints 029/030, W7B checkpoint 031, Edge tests, the full frontend suite, static/privacy/security scans, and final residue/fingerprint checks.

## Final NONPROD validation evidence

The guard passed on branch `web-platform-development` at runtime-validation HEAD `2fe4de1fb5f39ecad357a6564e0484b03969df6c`, with the approved 007–029 aggregate and allowlisted session-pooler project identity. The immediate identity transaction verified TLS required, database `postgres`, backend role `postgres`, port 5432, PostgreSQL 17.6, and `transaction_read_only=on`; the production project/host denylists were clear.

Pre-state verification proved W7C objects absent, W7B campaign/recipient tables empty, and captured Candidate, Application, Requirement, and retained W7A count/digests. Only exact migration 029 was applied, with client exit 0 and transaction commit. Post-install catalog verification found both foreign keys, both partial indexes, the processed-state/link checks, RLS retained, zero W7A/W7B browser grants, and execute permission only for `service_role` on the W7C RPC. All four retained inbound rows received null W7C links and their prior-shape digest was unchanged.

Checkpoint 032 passes with `ON_ERROR_STOP=1`, rollback, client exit 0, and its executable zero-residue assertion. Pre-execution catalog review found and corrected one checkpoint-only issue: the first assertion incorrectly rejected the canonical `candidate_applications` table's pre-existing authenticated grants despite its authoritative RLS policies. The corrected assertion verifies RLS on all involved canonical tables while keeping zero browser grants mandatory for the W7A/W7B tables W7C extends. Migration 029 and runtime grants were unchanged.

At completion of the dedicated database-validation stage, unchanged W7A checkpoints 029/030 and W7B checkpoint 031 passed after fresh guard/identity gates. Edge tests passed 21/21, focused W7B tests passed 17/17, the complete frontend suite passed 138/138, and static/privacy/security scans plus `git diff --check` passed. That stage's final read-only reconciliation found zero W7C fixture residue, zero W7B campaign/recipient rows, zero retained inbound W7C links, and exact pre/post count+digest matches for Candidates, Applications, Requirements, and all retained W7A rows. Production and Meta were not contacted, no message was sent, no Edge or application deployment occurred, and no milestone beyond W7C started during that stage.

## Final controlled NONPROD Edge validation

The final deployment gate passed again at authorized and remote-closed HEAD `eed8fe73ceadcad3f7669193441005466737c17e`, with the exact approved 007–029 aggregate, clean tracked tree, approved session-pooler identity, TLS required, read-only identity transaction, and clear production denylists. Only `supabase/functions/whatsapp-webhook` was deployed. The existing function advanced from version 4 to version 5, remained ACTIVE at the same endpoint/function identity, and preserved `verify_jwt=false`; no other Edge function or frontend was deployed. A downloaded runtime-source comparison matched `index.ts`, `parser.ts`, and `signature.ts` exactly to the authorized HEAD, and the deployment log confirmed the type-only asset.

Human authority verification in Meta Developer Dashboard established that the already-deployed `WHATSAPP_APP_SECRET` was authoritative and that the ignored local staging value was stale. The deployed secret and Meta configuration were not changed. After the local ignored value was aligned privately, one-way digests matched and an exact-byte signed malformed POST returned the expected HTTP 400, proving deployed signature validation without accepting an event.

One explicitly synthetic, non-message fixture then exercised the deployed endpoint end to end. It used a completed campaign and an already-delivered synthetic outbox row, so no campaign or outbound row was ever sendable after commit and no Graph API call occurred. One signed synthetic `INTERESTED` event produced exactly one durable webhook, resolved synthetic contact, processed inbound link, canonical WhatsApp `interested` Application, stage-history row, and safe audit. Exact signed replay retained one of each. Existing W7A contact/webhook/inbound fingerprints matched their pre-state; interviews and joinings remained empty; audits/webhook projections contained no phone, token, or secret.

The retained controlled-validation residue is exactly one synthetic auth/Admin, Requirement, Candidate, resolved contact, completed campaign, queued recipient linked to the already-delivered synthetic outbox row, webhook, inbound, Application, history, and audit chain. It is documented rather than deleted. Queued/sending campaign count and queued/claimed/sending outbound count are both zero.

## Final Meta test-number ingress limitation

After all deployed application-side gates passed, the human performed exactly one final live action: a text from the approved operator-controlled number ending `5800` to the approved NONPROD Meta test-number/WABA at `2026-08-24 13:25:42 IST` (`07:55:42 UTC`). A bounded observer and final read-only reconciliation through `08:02:47 UTC` found zero new webhook-ledger rows and zero new operator inbound rows. No retry, automated message, Meta configuration change, real-Candidate contact, or production action occurred.

This result does not establish an application defect. Signed requests reach the deployed endpoint and complete W7A/W7B/W7C orchestration; the unresolved boundary is real Meta test-number event generation/delivery to the Edge endpoint. Full real Meta inbound validation remains deferred to Meta-side delivery-history evidence/resolution or a future separately authorized controlled test with an appropriate registered number.

## Excluded work

W7C does not deploy any other Edge function or frontend, call Graph, send or acknowledge an automated WhatsApp message, contact a real Candidate, alter Meta configuration, create an unlinked real Candidate/contact, advance an existing application, schedule an interview, add conversational state, or begin any later chatbot, inbox, automation, or production milestone.
