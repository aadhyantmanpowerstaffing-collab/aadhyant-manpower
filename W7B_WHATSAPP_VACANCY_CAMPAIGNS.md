# W7B WhatsApp Vacancy Campaigns

## Scope

W7B adds an Admin-only vacancy campaign foundation on canonical recruitment data and the W7A WhatsApp core. An Admin selects an open `employer_requirements` row, previews server-derived Candidate matches, reviews manual inclusion/exclusion, freezes the audience, explicitly approves it, and queues through `enqueue_whatsapp_outbound_message`.

Only `whatsapp_campaigns` and `whatsapp_campaign_recipients` are added. The design reuses `candidates`, `employer_requirements`, `candidate_applications`, `whatsapp_contacts`, `whatsapp_outbound_messages`, and `whatsapp_message_events`.

## Matching and audience safety

Matching uses available job-relevant fields: state, district, current location, qualification, specialization/trade, Candidate experience type, and interview availability. Age and gender are intentionally not campaign filters. Preview is bounded to 100 rows and returns masked identity/contact plus recruitment, match, application, suppression, and eligibility posture.

The server resolves contacts and rechecks active Candidate posture, duplicate Candidate/contact constraints, existing applications, blocked/ambiguous contacts, marketing opt-in, and suppression during freeze, approval, and queueing. The browser submits no phone number. The audience is immutable after approval.

## Lifecycle and queueing

The fail-closed lifecycle is `draft -> audience_ready -> approved -> queued -> sending -> completed`; `cancelled` and `failed` are terminal. Approval and queueing lock the campaign row. Recipient uniqueness constraints and stable logical idempotency keys prevent duplicate rows during retries or races.

Every approved recipient is queued through the existing W7A outbox RPC. Template variables carry non-text campaign, requirement, recipient, and future `INTERESTED` correlation. Delivery counts project from the canonical W7A outbox. W7B adds neither a sender nor another queue.

## Security and privacy

All exposed operations are authenticated Admin-only `SECURITY DEFINER` RPCs with `search_path=''` and fully qualified objects. New tables have RLS and no browser base-table grants. Actor IDs come from `auth.uid()`. Audit metadata contains IDs and counts only. No raw phone, arbitrary body, webhook payload, private document, Aadhaar, bank, UAN, ESIC, token, secret, or signature is stored or returned.

## W7C boundary

W7B prepares deterministic `INTERESTED` correlation metadata only. It does not handle replies, create or mutate Candidates or Applications, trigger registration, transition applications, automate interviews, schedule reminders, or implement a live Graph sender. Those workflows remain W7C or later scope.

## Validation boundary

Migration `028_whatsapp_vacancy_campaigns.sql` installs the model/contracts. Rollback checkpoint `031_whatsapp_vacancy_campaigns_test.sql` covers catalog, RLS/grants, authorization denial, lifecycle, matching/masking, suppression, audience review, approval, idempotent W7A queue reuse, privacy, audit, uniqueness, no Candidate/Application mutation, and rollback. This implementation task performs static/local tests only and contacts neither database nor Meta.
