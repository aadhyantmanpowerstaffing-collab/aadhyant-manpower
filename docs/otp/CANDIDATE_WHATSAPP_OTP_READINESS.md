# Candidate WhatsApp OTP registration

## Design

This flow uses Supabase Auth as the only OTP authority. It does **not** use
WANotifier, generate a second OTP, or store a plaintext OTP in Aadhyant's
database.

1. A Candidate completes the one-page registration form and consents to a
   WhatsApp verification code.
2. A free Cloudflare Turnstile check protects the OTP request.
3. `signInWithOtp()` asks Supabase Auth to create or sign in to the phone
   account. Supabase creates the Auth account when needed.
4. Supabase Auth calls the signed `candidate-auth-whatsapp-hook`. The hook
   sends the Auth-generated code through the approved Meta Authentication
   template.
5. The Candidate enters the six-digit code. `verifyOtp()` creates the signed
   Supabase session.
6. Only that verified session may call
   `register_authenticated_candidate()`, which links or creates the Candidate
   profile and marks the mobile as verified.

The browser never receives a service key, Meta token, hook secret, or a
database proof token.

## Included safeguards

- `candidateOtpEnabled` remains `false` by default. A browser flag is not the
  authorization boundary; the final enforcement migration removes the legacy
  anonymous database path.
- The hook verifies the Supabase Standard Webhooks signature before using the
  payload and returns no code, phone number, token, or provider response.
- It uses the existing `WHATSAPP_ACCESS_TOKEN` and
  `WHATSAPP_PHONE_NUMBER_ID` secrets. No new messaging provider, sender, or
  paid product is added.
- `private.candidate_whatsapp_otp_dispatches` holds HMAC hashes only. It is
  RLS-protected and not browser-readable.
- The dispatch guard permits at most three attempts per phone hash in 24 hours
  and never deliberately sends a second copy of the same Auth OTP during its
  ten-minute idempotency window. It then safely recycles the keyed-hash record
  so a future Auth code that happens to have the same six digits is not
  suppressed forever.
- The hook limits its database and Meta calls to remain below the five-second
  Auth HTTP Hook budget.
- Candidate mobile and declared WhatsApp number must match when a WhatsApp
  number is entered; this is enforced in the browser and again by the
  authenticated database function.
- `register_authenticated_candidate()` requires `auth.uid()`, a confirmed
  phone, matching candidate mobile, consent, strict field allowlisting, and a
  transaction lock around duplicate handling. A verified phone cannot link to
  or overwrite a differently named/aged Candidate record; that case requires
  manual review.

## Required production settings

These settings are intentionally not changed by this PR.

| Setting | Required value |
| --- | --- |
| Meta template | `aadhyant_candidate_otp_v1`, Authentication / Copy Code, approved, `en_US` |
| Auth phone provider | Enabled |
| Auth OTP expiry | `300` seconds (5 minutes) |
| Auth resend interval | At least `60` seconds |
| Auth project SMS limit for first rollout | At most `30` per hour |
| CAPTCHA | Configure Cloudflare Turnstile in Supabase Auth and set its public site key in `config.js` |
| Send SMS HTTP Hook | `candidate-auth-whatsapp-hook`, signed with `SEND_SMS_HOOK_SECRET`, JWT verification disabled because the hook verifies the Standard Webhooks signature |
| Hook secrets | `SEND_SMS_HOOK_SECRET`, `META_WA_OTP_TEMPLATE_NAME=aadhyant_candidate_otp_v1`, `META_WA_OTP_TEMPLATE_LANGUAGE=en_US`; retain the existing WhatsApp token and sender secrets |

Use a new long random value for `SEND_SMS_HOOK_SECRET`. Never add it, a Meta
token, a service-role key, or a Turnstile secret to this repository.

## Controlled rollout

Do not merge, deploy, enable the flag, or send a real OTP until the repository
production checklist has explicit approval.

1. Meta review for `aadhyant_candidate_otp_v1` was submitted on 5 November
   2026. Wait for Meta's confirmed approval before configuring the live hook
   or sending a test code.
2. Create the free Turnstile widget for `aadhyantmanpower.in`, configure the
   matching secret in Supabase Auth, and put only its public site key in
   `config.js`.
3. In a disposable environment, apply and test
   `20261105111500_authenticated_candidate_registration.sql` and
   `20261105120000_candidate_otp_dispatch_guard.sql`; do not use a paid branch
   or reactivate an inactive branch without approval.
4. Deploy `candidate-auth-whatsapp-hook` with `verify_jwt=false`, set only the
   server-side secrets above, and configure the Supabase Auth Send SMS HTTP
   Hook.
5. Run the approved test matrix below. Supabase test phone numbers with a fixed
   code can test Auth and registration without an actual Meta delivery.
   `supabase/tests/20261105_candidate_otp_security_test.sql` is the required
   disposable-database RLS, rate-cap, and account-link regression test.
6. During a short, approved maintenance window, deploy the browser build with
   `candidateOtpEnabled: true`, then run
   `20261105121500_candidate_otp_rollout_enforcement.sql` as the final cutover.
   This removes anonymous Candidate INSERT and the public vacancy-interest RPC.
7. Review Auth, Edge Function, and Meta delivery errors before expanding the
   rate limit. Do not automatically send a real OTP to any phone number.

The repository build also produces an allowlisted artifact only: PR previews
have no Supabase configuration, staging receives only staging public settings,
and the production artifact rejects server-secret references and symlinks.

## Test matrix

- Valid consented registration: Auth user exists, phone is confirmed, Candidate
  profile is linked to the same `user_id`, and `mobile_verified=true`.
- Incorrect, expired, replayed, and changed-phone OTP: denied.
- Same OTP hook retry: no second Meta delivery; three requests in 24 hours:
  fourth is rate limited; a stale idempotency record can safely be recycled.
- CAPTCHA absent, invalid, expired, or failed: OTP request is denied.
- Direct anonymous Candidate INSERT and direct
  `register_candidate_requirement_interest()` call: denied after cutover.
- Authenticated user cannot register a different phone, read another
  Candidate, overwrite a different identity sharing the same phone, or invoke
  dispatch functions.
- Hook signature failure, missing secret, Meta error, malformed provider ID,
  and timeout: no code or personal data is returned or logged.
- Mobile and desktop accessibility: keyboard entry, focus, labels, status text,
  and an actual Candidate verification journey.

## Current status

PR #49 is still a draft and `candidateOtpEnabled` is still `false`. The Meta
template is now visible in WhatsApp Manager as `Active – Quality pending` after
submission for review, but no production migration, Auth hook, browser
enablement, or WhatsApp OTP delivery has occurred from this implementation.
This keeps the live registration flow unchanged until the final security and
deployment approval.
