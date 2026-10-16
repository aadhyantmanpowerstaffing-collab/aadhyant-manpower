# Automatic registered-candidate job alerts

Implementation prepared on 16 October 2026. Not deployed or enabled. No real messages were sent during development.

## Intended behavior

Company, contractor and Aadhyant vacancies use the existing vacancy review workflow. A new vacancy becomes broadcast-eligible only when the canonical gate says approved, public, open and not filled. Admin approval happens in Aadhyant; employers do not submit each vacancy to Meta.

Meta reviews the reusable English marketing template `aadhyant_registered_job_alert_v1`. Its six parameters are vacancy code, role, location, qualification, salary and benefits/duty. The URL button opens the public job details and existing Apply route; the other button is Stop alerts. This alert has no Interested/registration action. The candidate can share the public job. Existing manually selected outreach and private registration links remain separate.

The reviewed submission request is `registered-job-alert-template.json`. Example amounts in that request are synthetic template examples, never default vacancy pay. Runtime values come from saved, Admin-reviewed vacancy fields. Missing salary/facility information is not invented; the job page remains authoritative for complete terms. Each vacancy currently has its own compensation record; this change does not fabricate separate qualification-specific salary slabs.

## Audience and controls

Only uniquely resolved active Candidate profiles with actual opted-in job-alert permission qualify. Accepted sources are the single-page/chat/Flow all-job registration consent; all-scope sharing subscriptions linked to a Candidate; or the existing authenticated Candidate portal job-alert policy. The canonical purpose/suppression check still applies. Registration or importing a number alone does not grant consent. Legacy `registered` profiles and ambiguous duplicate identities require normal account review rather than automatic repair.

Qualification, trade, experience, age and location do not filter this audience. Existing applications do not suppress informational alerts. An inactive profile, STOP, withdrawn permission, changed contact linkage, closed/filled/unpublished vacancy, changed advertised job details, changed/rejected/stale template, or paused automation blocks pending sends. These checks run again at the existing provider boundary. A check before HTTP cannot revoke a provider request already in flight.

The publication marker is unique per vacancy. Repeated saves, republishing and toggling automation cannot create a second broadcast. Existing eligible jobs and jobs published while automation is off are marked without campaigns and never replayed. A template outage after enablement leaves an authorized publication pending for later recovery; only contacts/Candidates and consent already present by publication time can be included. Audience eligibility is re-evaluated when that deferred campaign is prepared.

The canonical campaign, recipient and outbox tables remain the delivery source of truth. `private.whatsapp_job_publications` is only a publication/deduplication marker. It contains no delivery receipts or phone numbers. Actor attribution uses the actual Admin who enabled the standing automation permission, never an invented user or impersonated auth context.

## Bounded worker

The existing worker has a scheduler-only `{ "automatic": true }` mode. It verifies the configured Meta account owns the exact sender phone, fetches the complete bounded template list, syncs current approval, refreshes sender readiness and then claims only automatic registered campaigns. It cannot select a manual campaign in this mode. Manual Process Pending cannot claim automatic campaigns.

At most 10 messages are claimed per run. A config-row lock serializes automatic reservations. Default rolling 24-hour limit is 100 attempts, adjustable by Admin from 10 to 1000. Quota accounting is deliberately conservative: receipt/status changes may hold an attempt in the window longer; fewer than ten remaining slots defer the next batch. The remaining audience stays included, not discarded. There is one provider attempt per automatic recipient; rejected/ambiguous delivery is terminal and never blindly retried. The canonical worker records reconciliation outcomes. Reports distinguish sent from delivered/read.

The existing GitHub scheduled workflow remains installation-locked with literal `false`. The prepared scheduler calls only the fixed canonical endpoint, requires the exact repository/main/schedule identity, immutable reviewed source SHA, a worker secret, an enable variable and bounded result validation. No persistent automation was activated.

## Production activation boundary

Before activation, review and explicitly approve the migration, Edge worker, frontend and template request. AGENTS.md requires explicit approval before production database mutations/deployment, Meta production configuration or real bulk sending.

1. Apply `20261016105424_automatic_registered_job_alerts.sql` after verifying the production project identity and prerequisite function/table contracts. Installation leaves alerts off and marks existing jobs without broadcasts.
2. Deploy the reviewed existing `whatsapp-outbox-worker` and website artifact. Preserve custom worker authentication; no browser/service credentials are embedded in the website.
3. Submit the reviewed template to the intended WhatsApp Business Account, wait for actual Meta APPROVED status, and sync. Do not manufacture catalog approval. If Meta requires wording changes, update the exact template contract and tests in a new migration before deployment.
4. Configure the existing scheduler credential securely on Edge and GitHub. Set Edge `WHATSAPP_AUTOMATIC_ALERTS_ENABLED=true`, explicit phone/account IDs, approved immutable scheduler source SHA and GitHub enable variable. Review a separate removal of the literal workflow installation lock on the default `main` branch. Workflow source must actually exist on the default branch; a development-branch push alone does not start cron.
5. Run the scheduler while database alerts remain off: it verifies metadata and records its heartbeat but claims no automatic sends. Confirm readiness in Admin → WhatsApp Manager → Automatic Alerts.
6. With explicit live-sending approval, enable future publications in that panel, initially at the reviewed daily cap. Do not publish a real vacancy as an unapproved test. Use an explicitly authorized owner-controlled test when requested.

Pause with the Admin control and/or disable the external worker gate/workflow. Pausing does not delete campaigns, applications, contacts or audit history. Pending pre-provider messages stop on the final eligibility guard. No destructive rollback is required.

## Validation

Disposable PGlite SQL runtime tests exercise the migration plus the corrected canonical enqueue, claim and provider-boundary contracts. Synthetic fixtures cover approval/publication, no matching filters, consent sources, duplicate publications, template outage recovery, manual-claim isolation, late permission withdrawal, changed job/template, ambiguous identity, pause, role grants, ten-row batches, quota deferral and idempotent queue counts. Edge tests mock Meta/DB only and verify URL/STOP payload, scheduler authentication, feature gate, exact sender ownership, incomplete metadata failure, provider-boundary rejection and immutable scheduler input checks. Full regression and production artifact checks are recorded with the implementation commit.

Validation result: full regression **511/511 passed**; retained scheduler safety tests **35/35 passed**; production artifact build and `git diff --check` passed. No production write or Graph send was made.
