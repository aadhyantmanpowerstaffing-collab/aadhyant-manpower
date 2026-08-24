# W7B WhatsApp Vacancy Campaigns

Status: NONPROD database/runtime validation is complete. Migration 028 is installed on the dedicated approved NONPROD project, corrected checkpoint 031 passes with client exit 0, W7A checkpoints 029/030 pass, W7A Edge unit tests pass 20/20, and the complete frontend regression passes 138/138. All synthetic fixtures rolled back with zero residue, canonical recruitment fingerprints were unchanged, production and Meta were not contacted, and no message was sent. W7C has not started.

## Scope

W7B adds an Admin-only vacancy campaign foundation on canonical recruitment data and the W7A WhatsApp core. An Admin selects an open `employer_requirements` row, previews server-derived Candidate matches, reviews manual inclusion/exclusion, freezes the audience, explicitly approves it, and queues through `enqueue_whatsapp_outbound_message`.

Only `whatsapp_campaigns` and `whatsapp_campaign_recipients` are added. The design reuses `candidates`, `employer_requirements`, `candidate_applications`, `whatsapp_contacts`, `whatsapp_outbound_messages`, and `whatsapp_message_events`.

## Matching and audience safety

The selected requirement is authoritative. When populated, its qualification, ITI trade, `Fresher`/`Experienced` requirement, and job/company location must match the Candidate; a location matches Candidate current location, district, or state. A blank requirement attribute imposes no condition, and `Both` imposes no Candidate-type condition. Admin filters for state, district, location, qualification, specialization, Candidate type, and interview availability can only narrow that server-derived population. Empty optional filters therefore mean “all Candidates matching this requirement,” never all active Candidates. Age and gender are intentionally not campaign filters. Preview is bounded to 100 rows with an offset capped at 5,000 and returns masked identity/contact plus recruitment, match, application, suppression, and eligibility posture.

The server resolves contacts and rechecks requirement eligibility, active Candidate posture, exact resolved Candidate/contact linkage, duplicate Candidate/contact constraints, existing applications, marketing opt-in, and suppression during freeze, approval, and queueing. The browser submits no phone number. The audience is immutable after approval.

## Lifecycle and queueing

The fail-closed lifecycle is `draft -> audience_ready -> approved -> queued -> sending -> completed`; `cancelled` and `failed` are terminal. Queueing owns `approved -> queued`. The narrow reconciliation RPC retains `queued` while every outbound is queued, moves to `sending` once any outbound is sending/sent/delivered/read/failed, marks `failed` only when every intended outbound is failed, and marks `completed` when every intended outbound is delivered, read, or permanently failed and at least one succeeded. Thus completed means processing finished; mixed permanent failures remain visible in the failed count. Terminal campaigns cannot return to active states.

Every approved recipient is queued through the existing W7A outbox RPC. Creation uses a stable operation UUID and immutable replay checks, while each recipient uses a stable W7A idempotency key. Template variables carry non-text campaign, requirement, recipient, and future `INTERESTED` correlation. `audience` is the included/queued recipient population; `queued` is the number linked to an outbox row; `sending`, `sent`, `delivered`, `read`, and `failed` are mutually exclusive current W7A outbox states. Queue-started and queue-completed audits are committed atomically; a failed queue transaction retains neither. W7B adds neither a sender nor another queue.

Campaign and template metadata is entered before campaign creation. When an existing draft is resumed, the server-returned campaign name, template name, language, and version are authoritative and read-only; review uses those persisted values and does not permit unsaved browser-only template edits.

## Security and privacy

All exposed operations are authenticated Admin-only `SECURITY DEFINER` RPCs with `search_path=''` and fully qualified objects. New tables have RLS and no browser base-table grants. Actor IDs come from `auth.uid()`. Audit metadata contains IDs and counts only. No raw phone, arbitrary body, webhook payload, private document, Aadhaar, bank, UAN, ESIC, token, secret, or signature is stored or returned.

## W7C boundary

W7B prepares deterministic `INTERESTED` correlation metadata only. It does not handle replies, create or mutate Candidates or Applications, trigger registration, transition applications, automate interviews, schedule reminders, or implement a live Graph sender. Those workflows remain W7C or later scope.

## Validation boundary

Migration `028_whatsapp_vacancy_campaigns.sql` installs the model/contracts. Rollback checkpoint `031_whatsapp_vacancy_campaigns_test.sql` covers catalog/FKs/indexes/uniqueness, RLS and function grants, representative role denials, missing/closed requirements, requirement mismatches, existing-application exclusion, masking/suppression, conflicting create replay, repeated freeze, detached-contact approval denial, invalid transitions, idempotent W7A queue reuse, queue audit rollback, all-failed and mixed-terminal reconciliation, attribution/count projections, fixture-scoped recruitment immutability, and executable post-rollback residue checks. Row locks and constraints are inspected, but true multi-session concurrency remains a separate runtime exercise. Focused frontend tests execute the production controller against mocked RPC responses for state gating, canonical template resume, retry identity, duplicate-submit suppression, and server reload; they are not a full browser or live-runtime validation.

## Final NONPROD validation evidence

At the start of the closure run, the approved NONPROD object catalog already contained both migration-028 tables with zero campaign/recipient rows. Migration 028's fail-closed preflight correctly prohibited a replay, so no duplicate or replacement migration was attempted. The project has no application `supabase_migrations.schema_migrations` relation; installation was therefore verified from the exact object/security posture and runtime behavior rather than an application migration-ledger row.

Checkpoint 031 initially exposed two checkpoint-only role-context defects: synthetic fixture updates impersonated `service_role` despite W7A's RPC-only server mutation boundary, and successful Admin behavior remained under `authenticated` while making owner-only base-table assertions. The checkpoint was corrected without changing migration 028 or runtime grants. Its final SHA-256 is `3c72239de0d9941e9115f1297fd841073a3c5857b441e87d777d94f673e3cfda`, and it passes with `ON_ERROR_STOP=1` and client exit 0.

The installed posture has both W7B tables under RLS, zero browser table grants, all nine public W7B RPCs as `SECURITY DEFINER` with empty `search_path`, all nine authenticated RPC grants, zero anonymous W7B RPC grants, and the expected FK, uniqueness, and index counts. Campaign and recipient tables remain empty. Candidate, Application, and Requirement counts/digests match the pre-run baseline; retained W7A contact, webhook, inbound, outbound, and message-event fingerprints also match. Synthetic W7A/W7B residue is zero.

Checkpoint 029 was made forward-compatible by permitting only the two canonical W7B tables while retaining its exact five-table W7A contract and rejection of every other unexpected `whatsapp_*` table. Checkpoints 029, 030, and 031 pass. W7A Edge unit tests pass 20/20 and the full frontend suite passes 138/138. Production was not touched, Meta configuration was not changed, no real Candidate was contacted, and no WhatsApp send occurred.
