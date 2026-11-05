# Candidate WhatsApp OTP — staged implementation (not live)

## Implemented on draft PR #49
- Disabled-by-default `candidateOtpEnabled` registration feature flag.
- Candidate form remains a direct one-page form; staged UI requests a WhatsApp OTP on its review screen, verifies the six-digit code, then sends candidate registration using a one-use server-issued proof.
- RLS-protected OTP table with server-only access. No plaintext OTP is saved.
- Atomic server-side OTP issuance and verification (60-second resend cooldown, three sends per rolling 24 hours, five-minute OTP validity, five attempts).
- Verification issues a random one-use registration proof, valid for ten minutes. The registration RPC locks the OTP row, consumes proof in the same database transaction as the registration/interest operation, and marks the candidate mobile verified. The direct general and vacancy-specific candidate paths remain compatible.
- Safe failure behavior when WhatsApp provider secrets or approved Authentication template config are unavailable.
- Static safety regression tests in `tests/candidate-whatsapp-otp-foundation.test.js`.

## Production blockers (do not merge/deploy yet)
1. Confirm Meta Authentication template approval and exact message component language/format; the Supabase template catalog previously did not show any matching OTP/Authentication template.
2. Configure the designated WhatsApp Business API token, sender phone ID and approved Authentication template name securely. Set `CANDIDATE_OTP_HASH_SECRET` using a long random server-only value. Never place secrets in `config.js`.
3. Complete threat review: IP/device-wide abuse defense and business-level spending limits, security testing, actual Meta response verification and template compatibility.
4. Confirm account auto-creation/sign-in requirements. The current OTP registration marks the `candidates` profile as verified but does not create an `auth.users` account.
5. Migrate away from legacy public direct candidate insert/RPC access for OTP-required registrations, only after the fully tested alternative is ready. A browser feature flag is not an authorization boundary.
6. Validate database migration in non-production and test valid/incorrect/expired/replayed OTP, resend race, matching candidate duplicates, vacancy interest links, provider failure, accessibility, and consented test number delivery. Review existing project deployment requirements.
7. Only then merge, deploy backend, turn on feature flag and test production end-to-end.

## Current verification
The staged JavaScript controller and the Node regression test file passed JavaScript syntax parsing. Static checks found RLS, server-role checks, locked OTP row and one-use proof consumption. End-to-end tests and production database migration have **not** been run.

## Costs and rollout
No WhatsApp messages were triggered while preparing this branch. No production database schema or live registration behavior has been changed. Meta may charge for actual Authentication template deliveries when testing and rollout are authorized.
