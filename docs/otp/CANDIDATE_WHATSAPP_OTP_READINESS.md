# Candidate WhatsApp OTP — staged foundation (not live)

## Goal
Candidate opens the existing registration form directly, fills the fields, receives an official WhatsApp Authentication OTP, verifies it within five minutes, and only then completes one account/profile registration.

## Added in this branch
- RLS-protected service-role-only `candidate_phone_otp` data store.
- Separate edge transport for requesting an OTP (60-second cooldown; 3 sends / 24-hour window) and checking it (five-minute expiry; up to five verification attempts).
- A required server-side secret for keyed OTP digests. No plaintext code is saved or returned from the endpoint.
- All WhatsApp sends are disabled until environment variables are configured for an approved Meta Authentication template.

## Must complete before deployment
1. Confirm Meta has approved **Authentication**, not Marketing, template with OTP-copy button and exact expected language/components. Do not bypass Meta approval or substitute a marketing message.
2. Independently review security. The current edge function is a **foundation**: rate-limit writes use read–modify–write operations that must become atomic database operations to resist concurrent requests. Add IP/abuse defenses and message-cost controls before enabling it.
3. Implement an atomic server-side OTP-to-registration handoff: verification must mint a short-lived one-use proof tied to the mobile number and the final candidate submission endpoint must consume it. Do **not** rely on a client-side boolean or `verified:true` API response. Disable anonymous direct candidate insertion for the OTP-enforced route only when the replacement registration endpoint has been tested and activated.
4. Preserve the existing requirement-specific interest flow, duplicate handling, explicit messaging consent, and registration without a separate Create Account step.
5. Add integration tests for correct code, wrong code, expired code, reused code, resend race, duplicate candidate, Meta failure and return URL; test in staging, then production with a consenting test number.
6. Review existing project deployment instructions and obtain any required approval before a production deployment.

## Required secrets (server-only)
- `CANDIDATE_OTP_HASH_SECRET`: long random secret, distinct from Meta access token.
- `META_WA_ACCESS_TOKEN`, `META_WA_PHONE_NUMBER_ID`, `META_WA_OTP_TEMPLATE_NAME`: use only after Meta Authentication template approval.
- Standard Supabase edge environment: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

Never place any secret in `config.js` or browser JavaScript.

## Current operational state
The previous Supabase template catalog check returned **no** Authentication or OTP template matching name, and provider approval was not independently confirmed. Accordingly, this branch is isolated, **not merged**, and does not change live registration or send messages. The scaffold is not production-ready.
