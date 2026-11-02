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
  Send SMS HTTP Hook routes the generated code to WANotifier. The client uses the
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

1. Resolve the observed provider account permission error. Obtain approval for
   the Authentication template and create its dedicated Notification API route.
2. Inspect the provider-generated example and confirm the exact one-recipient
   contract: `data.body_variables: [OTP]`, `data.button_variables: [OTP]` and
   `recipients: [{whatsapp_number: +91...}]`. The current adapter is gated and
   must be corrected if the actual generated schema differs. Disable provider
   retry schedules for time-sensitive OTP messages.
3. Obtain production deployment approval under AGENTS.md. Install the additive
   migration, deploy `candidate-whatsapp-auth` with gateway JWT checking off
   because raw-body HMAC authenticates it, and deploy the frontend assets.
4. Keep secrets server-side: `SEND_SMS_HOOK_SECRET` in Standard Webhooks format
   and the private `WANOTIFIER_AUTH_NOTIFICATION_URL`. Keep
   `WANOTIFIER_AUTH_ENABLED` and `WANOTIFIER_AUTH_TEMPLATE_VERIFIED` false until
   the generated provider contract is verified.
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
7. Public activation follows successful live verification. Roll back activation
   by turning the private config and hook gates off while retaining canonical
   identity/application history; do not delete users or transfer ownership.

## Validation

Full regression at the initial implementation: 955/955 passed. After final audit
and stale-verification protections, 86/86 focused database/auth/form/portal/artifact
tests passed. Production artifact packaging and `git diff --check` pass. All local
runtime tests use disposable PGlite fixtures and synthetic provider responses.
The new migration and Auth settings have not been installed on production.
