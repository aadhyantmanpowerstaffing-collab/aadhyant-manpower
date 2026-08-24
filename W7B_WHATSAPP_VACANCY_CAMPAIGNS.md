# W7B WhatsApp Vacancy Campaigns

## Scope

W7B adds an Admin-only vacancy campaign foundation on canonical recruitment data and the W7A WhatsApp core. An Admin selects an open `employer_requirements` row, previews server-derived Candidate matches, reviews manual inclusion/exclusion, freezes the audience, explicitly approves it, and queues through `enqueue_whatsapp_outbound_message`.

Only `whatsapp_campaigns` and `whatsapp_campaign_recipients` are added. The design reuses `candidates`, `employer_requirements`, `candidate_applications`, `whatsapp_contacts`, `whatsapp_outbound_messages`, and `whatsapp_message_events`.

## Matching and audience safety

The selected requirement is authoritative. When populated, its qualification, ITI trade, `Fresher`/`Experienced` requirement, and job/company location must match the Candidate; a location matches Candidate current location, district, or state. A blank requirement attribute imposes no condition, and `Both` imposes no Candidate-type condition. Admin filters for state, district, location, qualification, specialization, Candidate type, and interview availability can only narrow that server-derived population. Empty optional filters therefore mean “all Candidates matching this requirement,” never all active Candidates. Age and gender are intentionally not campaign filters. Preview is bounded to 100 rows with an offset capped at 5,000 and returns masked identity/contact plus recruitment, match, application, suppression, and eligibility posture.

The server resolves contacts and rechecks requirement eligibility, active Candidate posture, exact resolved Candidate/contact linkage, duplicate Candidate/contact constraints, existing applications, marketing opt-in, and suppression during freeze, approval, and queueing. The browser submits no phone number. The audience is immutable after approval.

## Lifecycle and queueing

The fail-closed lifecycle is `draft -> audience_ready -> approved -> queued -> sending -> completed`; `cancelled` and `failed` are terminal. Queueing owns `approved -> queued`. The narrow reconciliation RPC retains `queued` while every outbound is queued, moves to `sending` once any outbound is sending/sent/delivered/read/failed, marks `failed` only when every intended outbound is failed, and marks `completed` when every intended outbound is delivered, read, or permanently failed and at least one succeeded. Thus completed means processing finished; mixed permanent failures remain visible in the failed count. Terminal campaigns cannot return to active states.

Every approved recipient is queued through the existing W7A outbox RPC. Creation uses a stable operation UUID and immutable replay checks, while each recipient uses a stable W7A idempotency key. Template variables carry non-text campaign, requirement, recipient, and future `INTERESTED` correlation. `audience` is the included/queued recipient population; `queued` is the number linked to an outbox row; `sending`, `sent`, `delivered`, `read`, and `failed` are mutually exclusive current W7A outbox states. Queue-started and queue-completed audits are committed atomically; a failed queue transaction retains neither. W7B adds neither a sender nor another queue.

## Security and privacy

All exposed operations are authenticated Admin-only `SECURITY DEFINER` RPCs with `search_path=''` and fully qualified objects. New tables have RLS and no browser base-table grants. Actor IDs come from `auth.uid()`. Audit metadata contains IDs and counts only. No raw phone, arbitrary body, webhook payload, private document, Aadhaar, bank, UAN, ESIC, token, secret, or signature is stored or returned.

## W7C boundary

W7B prepares deterministic `INTERESTED` correlation metadata only. It does not handle replies, create or mutate Candidates or Applications, trigger registration, transition applications, automate interviews, schedule reminders, or implement a live Graph sender. Those workflows remain W7C or later scope.

## Validation boundary

Migration `028_whatsapp_vacancy_campaigns.sql` installs the model/contracts. Rollback checkpoint `031_whatsapp_vacancy_campaigns_test.sql` covers catalog/FKs/indexes/uniqueness, RLS and function grants, exact authorization denial, missing/closed requirements, requirement mismatches, masking/suppression, freeze and detached-contact approval denial, invalid transitions, idempotent W7A queue reuse, queue audit rollback, reconciliation, attribution/count projections, fixture-scoped recruitment immutability, and post-rollback residue. Row locks and constraints are inspected, but true multi-session concurrency remains a separate runtime exercise. This correction task performs static/local tests only; migration and checkpoint runtime validation remain pending and neither database nor Meta is contacted.
