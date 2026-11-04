# Candidate accounts through WhatsApp OTP

Status: implementation prepared and locally tested; not deployed or activated.

The private Interested registration form keeps the selected job and all profile
fields in one page. When phone authentication is enabled, the candidate verifies
the WhatsApp number that received the private link, then submits once. Supabase
Auth creates and verifies the phone identity. The existing registration RPC saves
the canonical profile/application and links that same verified identity in one
transaction. A failure rolls back the profile/application transaction. A verified
Auth identity can remain without portal access after an unsuccessful submission;
the candidate can retry the original unexpired form without another account.

Future login uses the same mobile number and OTP. Email/password users keep their
existing login. Login requests do not create users; only the registration flow
allows Auth signup. No synthetic email addresses or generated passwords are used.

## Ownership and delivery

- Binding checks the actual Auth user, phone verification, bans, exact original
  registration destination, live token context, candidate status and other roles.
- Never transfer an owned Candidate record. Imported/unowned profiles not created
  by this exact registration require staff review. Marketing consent stays separate.
- An additional audit event records the identity link once without phone/code data.
- Supabase owns OTP verification, validity, rate limits and session tokens. Its
  Send SMS HTTP Hook routes the generated code directly to Meta Cloud API. The client uses the
  normal SMS OTP API; `channel: whatsapp` is reserved for built-in Twilio routing.
- The hook authenticates Standard Webhooks HMAC signatures over the raw body and
  enforces a five-minute signature window and a 16 KiB body limit.
- Its private service-only ledger claims each hook event once. It never stores the
  OTP or raw payload. Accepted replay does not resend; uncertain calls need review.
- Provider acceptance is not a delivery receipt. Neither a fabricated wamid nor a
  marketing template may replace the approved Authentication template.

## Observed provider blocker — 2 November 2026

Signed in to the verified Aadhyant WANotifier account, selected Authentication /
One-time Passcode / English / Copy code, with the standard security recommendation,
and attempted `aadhyant_candidate_login_otp_en_v1`. Submission returned:

> Cannot create message template - This WhatsApp Business account does not have permission to create message template

The template was not submitted for review. Do not claim it is pending or approved.
No real candidate OTP or other message was sent. No provider endpoint was saved.
The cause of the account permission restriction has not been independently established.

## Activation prerequisites

1. Obtain approval for `aadhyant_candidate_login_otp_en_v1` directly on the
   configured Meta WABA. Required category AUTHENTICATION, language en, Copy Code,
   security recommendation and five-minute expiry. The old WANotifier error is
   historical evidence only; current direct Meta template permission is unverified.
2. The hook sends the OTP twice: body text and URL button index 0. It uses the
   existing server-only `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID` and
   `WHATSAPP_BUSINESS_ACCOUNT_ID`; no WANotifier URL/key is used. A successful
   single `wamid.` response is required; malformed, rejected and uncertain calls
   never trigger an automatic resend. Template approval must be confirmed before
   setting the verified gate. Set template TTL to 300 seconds before activation.
3. Obtain production deployment approval under AGENTS.md. Install the additive
   migration, deploy `candidate-whatsapp-auth` with gateway JWT checking off
   because raw-body HMAC authenticates it, and deploy the frontend assets.
4. Keep `SEND_SMS_HOOK_SECRET` server-side in Standard Webhooks format. Keep
   `WHATSAPP_AUTH_ENABLED` and `WHATSAPP_AUTH_TEMPLATE_VERIFIED` false until
   the exact template/sender contract is verified. Old WANotifier Auth flags
   cannot activate this handler.
5. Configure Supabase phone signups with automatic confirmation OFF, OTP length
   six, expiry five minutes and resend interval at least 60 seconds. Configure
   appropriate Auth request limits and abuse protection before public activation.
   Set the Send SMS HTTP Hook to the deployed endpoint with the matching signing
   secret; retain existing email authentication. This is a separate production
   Auth configuration change requiring review.
6. Enable both server gates and `private.candidate_phone_auth_config.enabled`
   only for a separately authorized controlled test: fresh OTP, wrong/expired
   code, matching private link, single profile/application/account, replay,
   logout/login, cross-number and pre-owned candidate denial, STOP/job closure.
   Local tests do not prove provider delivery or a deployed Auth session.
7. The code may be merged into `web-platform-development` while all three gates remain OFF; merging alone does not enable OTP. Do not deploy the migration, Edge Function or frontend, and do not enable Supabase Auth/Meta settings, until the Authentication template is approved and a controlled live OTP/login test is authorized and passes. Public activation follows successful live verification. Roll back activation by turning the private config and hook gates off while retaining canonical identity/application history; do not delete users or transfer ownership.

## Validation

Historical checks on the original feature branch are not evidence that this latest-base branch passed the full suite.

Current latest-base checks performed during integration:
- 12/12 direct Candidate phone OTP client behavior simulations passed, covering signup/login distinction, Indian-number normalization, activation gate, cooldown, invalid verification, cancellation and stale-session revocation.
- 1/1 additional login-context check passed: a verified Auth session is signed out when no active Candidate Portal context exists.
- Earlier focused synthetic Meta Hook checks passed 19/19 and earlier Candidate UI/session tests passed 9/9 before the latest database-only eligibility and cooldown additions.
- Read-only Production schema comparison found no missing columns referenced by the additive migration.

Latest-base CI validation — 4 November 2026:
- Focused Candidate OTP database, UI, hook and registration tests: **59/59 passed**.
- Complete current platform frontend regression: **1,078/1,078 passed**.
- Deterministic production artifact build: **passed**.
- Production artifact boundary suite: **6/6 passed**.
- Final artifact manifest verification: **passed**; 111 files, 1,307,815 bytes, digest `adb2ef400860d0140decc8cabc0683390c2b9585a10bcb450565e5a60210e881`.
- Workflow: https://github.com/aadhyantmanpowerstaffing-collab/aadhyant-manpower/actions/runs/41852945820. This workflow has no deployment step.

Still unverified: a deployed Supabase Auth Hook and controlled real Meta OTP delivery/login.
No OTP migration, Auth hook, feature gate, Meta configuration or frontend deployment has been applied to Production.

## Direct Meta preparation — 3 November 2026

The draft now uses the same Meta sender as the live Manager. The website branch
has been incorporated without dropping the direct campaign, template rebind or
account webhook fixes. No production migration, Auth hook setting, activation gate
or OTP send was performed during this preparation. A provider receipt proves
acceptance only; controlled delivery/login verification remains required.

References: Supabase Send SMS Hook
https://supabase.com/docs/guides/auth/auth-hooks/send-sms-hook
and Meta's Authentication Copy Code template collection
https://www.postman.com/meta/whatsapp-business-platform/request/6vkv46u/create-authentication-template-w-otp-copy-code-button

## Direct Meta submission result — 3 November 2026

After explicit user approval, the prepared Copy Code template was submitted in
Meta WhatsApp Manager on the current account. Meta rejected creation with:

> This WhatsApp Business account does not have permission to create message template

No template entered review and no OTP was sent. The same error is now reproduced
directly at Meta, independently of WANotifier. Reassigning System User Full Access
is not evidence of resolving template-category eligibility. Keep all Auth activation
gates off until Meta accepts the Authentication template and approval is verified.
Do not send bulk messages merely to attempt to unlock account eligibility.

### Meta account eligibility diagnosis

Before retrying template creation, inspect the exact WABA and phone number used by the
Aadhyant sender:
1. Business Settings → Business Info: record whether the Business Portfolio is verified
   or whether verification is pending/rejected.
2. WhatsApp Manager → Account tools → Phone numbers / Limits: record the sender's
   current daily business-initiated messaging tier and quality/status shown by Meta.
3. Business Support Home / Account Quality: check for active restrictions, disabled assets,
   policy issues or pending reviews on both the Business Portfolio and WABA.
4. Confirm the selected WABA and sender phone number are the same assets used by the
   existing Cloud API token and Phone Number ID. Full System User access alone does not
   override account-level category eligibility.
5. If Meta still rejects Authentication template creation after the above checks, open
   a Meta Business Support case. Include the exact error screenshot, WABA ID, Business
   Portfolio ID, Phone Number ID, the local timestamp and any Graph API `code`,
   `error_subcode` and `fbtrace_id`. Ask Meta to identify which eligibility gate
   blocks `AUTHENTICATION` Copy Code template creation for this WABA.

Provider support documentation currently cites a 2,000-per-day business-initiated
conversation tier together with Business Verification / an approved scaling path and
good account standing. These are third-party explanations of Meta eligibility, not a
live reading of this WABA's account state; record the actual tier shown in WhatsApp
Manager rather than assuming the cause or sending unsolicited volume to reach a target.
References:
- https://api.support.vonage.com/hc/en-us/articles/30129084631068-Guidelines-and-Eligibility-Criteria-for-Creating-a-WhatsApp-Authentication-Template
- https://support.wati.io/en/articles/11463212-how-whatsapp-messaging-limits-work-and-how-to-increase-them


Meta support entry points (sign in with the Business Portfolio owner account):
- Account Quality: https://business.facebook.com/accountquality/
- Business Support Home: https://www.facebook.com/business-support-home/
- Contact Support (when offered for this account): https://www.facebook.com/business-support-home/contact-support/

### Ready-to-send Meta Business Support request

Subject: WhatsApp Authentication template creation blocked for our WABA

We manage our WhatsApp Business Account directly through WhatsApp Manager and
use the WhatsApp Cloud API. On 3 November 2026, WhatsApp Manager rejected creation
of an Authentication / Copy Code OTP template with this exact message:

`This WhatsApp Business account does not have permission to create message template`

Please confirm the exact eligibility condition currently blocking Authentication
template creation for this WABA. In particular, please verify:
- Business Portfolio verification / approved scaling-path status;
- the current business-initiated messaging tier for the relevant sender phone number;
- any WABA, sender, Business Portfolio or policy restriction;
- whether this WABA is eligible to create AUTHENTICATION Copy Code templates, and
  what specific action (if any) is required to unlock it.

WABA ID: [enter WABA ID]
Business Portfolio ID: [enter Business Portfolio ID]
Phone Number ID: [enter Phone Number ID]
Sender phone number: [enter business sender number]
Attempt date/time and timezone: 3 November 2026, [enter local time and timezone]
Screenshot: [attach the exact WhatsApp Manager error]

Please do not close this as a System User role issue without confirming the
account-level Authentication template eligibility. We have already reproduced
the same error directly in WhatsApp Manager. We will keep OTP activation disabled
until Meta confirms eligibility and approves the template.

## Latest branch integration — 4 November 2026

Prepared against `web-platform-development` at `002e9a0ee39261e69a3d2ee7b4a5703fb0f3c5b5`. The additive OTP migration is timestamped after the current production migration range through `20261103113526`, so fresh databases apply this wrapper after the latest registration function changes. The latest target regression script and contact-import command are preserved, with three focused OTP tests added to the default regression suite. Full integrated regression and production-artifact checks must pass before merge/deployment.


Security review update — 4 November 2026: The account-link guard also rejects identities present in `public.staff_roles`, in addition to `staff_profiles`, `admin_users`, `company_users`, and `contractor_users`. Both staff role stores have separate regression cases.


HTTP Auth Hook deadline review — 4 November 2026: Supabase documents a five-second execution budget for HTTP Auth Hooks. The Meta request therefore has a two-second abort timeout (rather than the ordinary recruitment sender's fifteen-second timeout), leaving time for the bounded claim/finish database RPCs and HTTP response. The implementation must fail closed when this deadline cannot be met; never queue a code for later or return success without confirmed provider acceptance.


Identity collision review — 4 November 2026: An existing active Candidate `platform_users` row is now reusable only when the canonical Candidate row is already owned by that same Auth user. An orphaned Candidate portal row with no matching `candidates.user_id` is rejected for staff review rather than silently attached to a new WhatsApp registration.


OTP send eligibility — 4 November 2026: The service-only delivery-claim RPC now sends only for either (1) an active, non-inactive Candidate Portal identity whose Auth user, Candidate mobile and account type/status all match, or (2) the exact phone on a currently valid, unexpired, incomplete private WhatsApp registration link. A generic phone-auth OTP request cannot use this hook to send to an unrelated number.


Abuse controls — 4 November 2026: The delivery ledger serializes requests per Auth user with a transaction advisory lock and enforces a 60-second server-side cooldown even when an attacker sends a new Auth hook ID. The browser cooldown is only an additional UX layer. Supabase Auth provider rate limits must still be configured before activation.


Candidate login eligibility refinement — 4 November 2026: Existing portal OTP login also requires the canonical Candidate record to have `mobile_verified = true`; the user ID, Auth phone, Candidate mobile, active profile and active Candidate platform account must all match. New registrations set this flag only after a verified OTP session is linked transactionally.


Meta eligibility follow-up — 4 November 2026: The direct Meta error indicates an account-level creation restriction, not a template-body issue. Third-party WhatsApp platform guidance commonly lists completed Meta Business Verification, an eligible WABA messaging tier (often 2,000 daily business-initiated conversations), and no active Business Portfolio/WABA restrictions as prerequisites. These are checks to verify in Meta Business Info, WhatsApp Manager → Account tools → Messaging limits, and Account Quality; they are not a confirmed diagnosis of this specific WABA. See https://api.support.vonage.com/hc/en-us/articles/30129084631068-Guidelines-and-Eligibility-Criteria-for-Creating-a-WhatsApp-Authentication-Template and https://respond.io/help/whatsapp/getting-ready-for-inbound-conversations.
