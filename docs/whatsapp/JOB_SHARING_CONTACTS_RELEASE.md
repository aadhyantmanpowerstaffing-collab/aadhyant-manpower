# Job updates and sharing contacts

Prepared 13 October 2026 from development HEAD `0b0fddcec90c748e392c92a9206fb69502ba049c`.
The user explicitly approved source publication, production migration, webhook
and site deployment on 13 October 2026 at 10:50:50 IST. Source publication and
the database/webhook installation have completed; see deployment evidence below.

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
- New import/database/subscription/vacancy-selection tests: 20 PASS using an isolated PGlite database
  with canonical contact/campaign constraints; no external sends. Provider enqueue
  and environment authorization are declared test doubles. This does not prove
  production concurrency or genuine Meta delivery.
- Existing webhook plus new signed-subscription regression: 24 PASS.
- Existing bounded scheduler tests: 35 PASS.
- Actual uploaded Data.xlsx: 6 unique valid records, zero validation errors; not
  committed to Git and not imported to production.
- Production artifact build, runtime-route checks and `git diff --check`: PASS.
- Browser visual QA was unavailable in this environment and is not claimed.

## Deployment evidence

- Source published in the existing `web-platform-development` branch. The initial
  runtime source is `eb0e5420b21f43832b4961bc799356839be9e6a5`.
- Production migration ledger: `20261013052449`, `job_sharing_contacts`.
- Webhook version 15 is ACTIVE with the existing HMAC/verify_jwt=false contract.
  Downloaded deployed files match the reviewed upload exactly. An unsigned GET
  returns 403 and performs no persistence.
- Initial GitHub Pages run `38351596855` completed all build, test, upload and
  deployment steps successfully. Public `/job-updates/` returns 200. Its deployed
  artifact digest initially matched `ca3c2d096a189aed24225341a60f9e65fa2addce48c7f9ac63c61f4dba35b26c`.
- Live contract inspection found that `list_recruitment_requirements` does not
  project `requirement_visibility`. Corrective source
  `95b52f3493b054f37df437c6e93adf788e9be33e` resolves canonical Admin IDs against
  the public job-code projection. Two executed selection regressions cover this
  contract. The dropdown uses bounded current lists (100 Admin / 50 public jobs).
- Corrective GitHub Pages run `38352218440` also completed every build/test/upload
  and deploy step successfully. Final deployed artifact digest:
  `80ed0705e7132480257b4ccb578ec634cbcafb5f81289457653c66e157206e0a`.
- Postflight retains 2 WhatsApp contacts, 4 Candidates, 0 sharing campaigns and
  0 queued/sending messages. Anonymous import and authenticated subscription RPC
  execution are denied; the signature-verified service subscription is allowed.
- The supplied six contacts remain unimported. No consent, campaign, outbound
  message, worker secret or Meta template was changed by validation.
- Publication uses a source-pinned push workflow constrained to the approved
  one-hour window, exact branch/repository and first run attempt. This temporary
  workflow is removed after the corrective publication; the ordinary manual
  production workflow and hard-disabled WhatsApp scheduler are preserved.

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
