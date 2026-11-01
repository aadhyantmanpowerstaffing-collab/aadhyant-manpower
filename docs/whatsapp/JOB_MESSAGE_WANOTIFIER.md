# Job Message → WANotifier → Interested → private registration

## Operator workflow

Open **WhatsApp Manager → Job Message**. Select one published vacancy for registration,
choose English or Hindi, and fill qualification, two qualification/role salary groups
(CTC, take home, hourly OT), and benefits/duty. Both groups refer to the selected vacancy;
this version does not guess between unrelated jobs in a single message.

The side-by-side preview includes the fixed **Interested** quick-reply button and
96244 53543 contact number. Existing eligible contact lists/tags and consent checks
select the audience. Save for approval; **View Message** reopens the exact saved
message. Approve and queue reuse canonical campaigns and outbox.

The UI sends new templates through `wanotifier-job-message`, never the Meta worker.
The legacy campaign claim RPC excludes these templates. The dedicated claim RPC
delegates to the existing lease implementation for the exact selected campaign.
New outbox rows allow one provider attempt. Unknown outcomes require reconciliation,
never an automatic retry or fallback. Replies and authoritative delivery reports
remain in WANotifier.

The signed WANotifier webhook preserves the original context wamid and canonical
contact. A fixed button payload `Interested` is normalized to `INTERESTED` only for
an actual button reply; a typed message or a missing/unknown original message is
not inferred. The existing correlated RPC either reuses/creates the canonical
application for a registered candidate or requests the phone/job-bound private
form for a nonregistered contact. The existing form and explicit alert-consent
choice are retained. Pressing Interested alone does not grant marketing consent.

## Saved template contracts

- `aadhyant_job_salary_details_en_v2` (English)
- `aadhyant_job_salary_details_hi_v2` (Hindi)

These exact bodies and one fixed `Interested` quick reply were submitted in
WANotifier on 1 November 2026. Body variables, in order:

| Variable | Field |
| --- | --- |
| 1 | qualification |
| 2 | group_1 |
| 3 | ctc_1 |
| 4 | take_home_1 |
| 5 | ot_1 |
| 6 | group_2 |
| 7 | ctc_2 |
| 8 | take_home_2 |
| 9 | ot_2 |
| 10 | benefits |

Values are one line each, maximum 300 characters, and the rendered body must be
at most 1,024 characters. Templates with changed bodies, extra components, missing
buttons, pending/rejected approval, or stale metadata cannot be used. v1 templates
without Interested are deliberately unsupported by this composer.

Server preparation stores the message fields and canonical public-job snapshot
in the existing campaign criteria. Operation keys are idempotent, and conflicting
replays fail. Approval, queue, claim and the final provider boundary require the
same job snapshot, template, campaign, recipient, permission and suppression state.
No new contact, application, candidate or outbox tables are introduced.

## Source and activation status

Source implementation and local synthetic tests are prepared. This change has
not installed a production migration, deployed functions, saved new provider
Notification endpoints, changed feature flags, refreshed sender readiness, or
sent messages. Template submission does not activate website automation.

The prior production checkpoint intentionally left automated sending paused.
The Hindi v2 template still displayed PENDING after a live refresh during this
task. Provider support previously confirmed top-level `wamid` for `/messages`,
but only promised further Notification API work. Do not infer that the Notification
API now returns per-recipient original-message receipts.

## Production rollout requirements

Obtain production approval under repository AGENTS.md before installing or
deploying anything. Then:

1. Apply `20261101032123_wanotifier_job_message_composer.sql` once; preserve
   installed history. Deploy the new `wanotifier-job-message` Admin-JWT function,
   the updated `wanotifier-webhook`, and their bundled dependencies. Publish the
   allowlisted frontend including `admin/job-message.js`.
2. Confirm both exact v2 templates are approved in WABA 1386833723249335 and sync
   authenticated metadata for that verified account. Do not rebind old Meta
   credentials or silently substitute a differently shaped template.
3. In WANotifier, save one API Notification per v2 template. Verify the generated
   data contract: ten ordered `body_variables`, one `whatsapp_number` recipient,
   no URL/button variables. Do not add lists, tags, names, attributes or consent
   in notification requests. No test or bulk trigger is part of setup.
4. Store the exact provider-generated private URLs server-side as
   `WANOTIFIER_JOB_MESSAGE_EN_URL` and `WANOTIFIER_JOB_MESSAGE_HI_URL` only after
   authorization to transfer those credentials to the existing Aadhyant project.
   Never put keys or private URLs in source, frontend, screenshots, PRs or logs.
5. Obtain a supported per-recipient genuine wamid response (or implement the
   provider's verified lookup contract before using it). Preserve receipt before
   processing Interested. An acknowledgement without wamid is insufficient.
   Only then set `WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED=true`.
6. Verify dedicated sender +919624453543 / Phone ID 1415347881659158 / WABA
   1386833723249335, template freshness, canonical readiness and private web-form
   configuration. Review the whole existing queue before enabling any sends.
7. Enable `WANOTIFIER_JOB_MESSAGES_ENABLED=true` and the existing separate
   `WANOTIFIER_INTERESTED_ENABLED` only for an explicitly approved controlled
   test. Confirm one job message reaches the selected recipient, Interested
   carries the exact original wamid, the correct private form arrives, and form
   submission and repeat replies do not create duplicate records or implicit opt-in.

The new endpoint rejects requests before claiming if sending, receipt verification,
sender identity or private route configuration is unavailable. No support request,
phone call, bulk campaign or real candidate contact was made by this source work.

## Pause / rollback

Set `WANOTIFIER_JOB_MESSAGES_ENABLED=false` to pause new dispatch without deleting
campaigns or provider history. Keep receipt verification false until proven. Keep
existing automatic alert/scheduler flags unchanged. If pausing registration replies,
use the existing Interested flag; inbound storage remains independently available.
Do not roll back by deleting outbox history or replaying/reverting installed migrations.

## Verification

`npm test` includes the new in-memory SQL lifecycle, UI interaction and synthetic
WANotifier dispatch suites. `node scripts/build-production-artifact.js` followed by
`--verify` verifies the frontend allowlist and deterministic package. Browser QA
uses a local synthetic fixture with no network-backed database or WhatsApp sends.
Passing synthetic tests is not a production end-to-end delivery claim.
