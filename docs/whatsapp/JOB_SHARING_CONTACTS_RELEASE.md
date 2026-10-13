# Job updates and sharing contacts

Prepared 13 October 2026 from development HEAD `0b0fddcec90c748e392c92a9206fb69502ba049c`.
This is a reviewed source proposal. It is not installed or enabled on production.

## Behavior

Admin can import the first sheet of an XLSX file or UTF-8 CSV with Name, Email,
Mobile, Gender, Age, State and District. Each file is limited to 500 contacts and
5 MB. Indian mobiles normalize before duplicate checks. Invalid rows require
correction. Import reuses canonical WhatsApp contacts and preserves their existing
identity, STOP state and consent. It never fabricates Candidate education or
experience, registers a Candidate, records consent or queues a message.

`/job-updates/` allows All Jobs or exact job-location/trade subscriptions. The
subscriber explicitly checks consent and sends the prepared command from their
own WhatsApp number. Only a signature-verified inbound webhook may record that
subscription. Merely opening WhatsApp, clicking INTERESTED, uploading a contact
file or visiting the page does not subscribe anybody. Replayed/older subscription
events cannot override a later STOP or newer preference.

The Admin sharing audience filters contact State, District, Gender and Age;
selects exact contact IDs; freezes a canonical campaign audience; and then requires
separate Approve and Queue actions. These are sharing subscribers, so Candidate
qualification/experience matching is explicitly unverified. A subscriber's own
location/trade preferences, unresolved/blocked/ambiguous identity, existing
application, marketing consent and vacancy status remain server-enforced. The
canonical claim and provider-start RPCs already call the send guard, which now
recognizes both Candidate and sharing audiences without relaxing the existing
Candidate branch. Job closure, cancellation, STOP and changed subscriber
preferences prevent a subsequent send attempt.

The public job detail keeps Apply and adds Share Job on WhatsApp plus Subscribe.
Forwarded links identify a published requirement code. The recipient applies
through their own Candidate account; forwarding does not create an application.

## Delivery limits

- All Jobs is an audience preference, not automatic publication-triggered sending.
  Each job alert still uses an explicitly prepared/approved campaign. The existing
  hard-disabled scheduler and sender configuration are unchanged.
- Reuses the existing reviewed vacancy-template/provider contract. New View/Share
  buttons in the WhatsApp message itself require a separately approved Meta
  template/provider change. The Share action implemented here is on the public job
  page. Verify that the selected approved template directs recipients to the site
  before any pilot.
- An unregistered subscriber is not automatically made a Candidate by INTERESTED.
  They use the public job page to register/apply. Existing W7C Candidate/application
  identity rules remain unchanged.
- Location matching is exact (case-insensitive). It does not infer that Sanand is
  in Gujarat, or expand a trade to aliases/related qualifications.
- This release adds contact profile columns, a subscription preference column,
  campaign audience mode and optional Candidate linkage for sharing recipients.
  No parallel Candidate/contact/outbox tables are introduced. Canonical RLS and
  browser table grants are preserved; new Admin RPCs check server-side Admin
  authorization and the subscription RPC is service-role-only.

## Verification

- Existing frontend regression: 350 PASS.
- New import/database/subscription tests: 18 PASS using an isolated PGlite database
  with canonical contact/campaign constraints; no external sends. Provider enqueue
  and environment authorization are declared test doubles. This does not prove
  production concurrency or genuine Meta delivery.
- Existing webhook plus new signed-subscription regression: 24 PASS.
- Existing bounded scheduler tests: 35 PASS.
- Actual uploaded Data.xlsx: 6 unique valid records, zero validation errors; not
  committed to Git and not imported to production.
- Production artifact build, runtime-route checks and `git diff --check`: PASS.
- Browser visual QA was unavailable in this environment and is not claimed.

## Installation and rollback

Production read-only preflight confirmed zero queued/sending messages, contact RLS
enabled and the current send-guard MD5
`aa855103a4239ea9c453a343fd2e7175`. The migration itself refuses a different
guard or missing RLS. Freshly verify project identity, backup/recovery and the
no-send posture before applying it; do not replay if already installed.

After explicit production approval, install
`20261013045750_job_sharing_contacts.sql`, deploy the four webhook files based on
the exact downloaded production webhook version 14 with only the subscription
extension, and deploy the allowlisted frontend artifact. The reviewed branch
does not alter the worker or the scheduler. Then run read-only catalog/route
checks. Keep sender and scheduler disabled and import contacts with Unknown
consent. Do not queue or send a real pilot without its own reviewed job, template,
exact subscriber audience and authorization.

The SQL is transactional during installation. After commit, rollback uses the
previous frontend/webhook plus a reviewed forward fix. Do not remove new columns,
delete contacts or restore NOT NULL while sharing recipients exist. The upgraded
guard's Candidate branch continues to work with the previous frontend.
