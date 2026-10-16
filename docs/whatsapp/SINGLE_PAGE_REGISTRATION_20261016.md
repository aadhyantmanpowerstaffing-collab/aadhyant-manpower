# Single-page WhatsApp registration — 16 October 2026

The user requested a complete English form on one page with dropdowns, optional fields and a separate all-job-alert checkbox. The user explicitly approved production deployment at 15:15:41 IST. The verified release is live; closure details are below.

## User experience

A new signed Interested reply on an exact delivered campaign can issue a private registration link. The entire form is visible together, including personal details, State/District, education/trade, experience, interview availability, optional pincode and preferred work locations. State controls District; qualification controls trade choices and Other input; Experienced reveals duration/role. No grouped chat answer parsing is needed.

Submit creates/reuses canonical Candidate and the exact job's interested Application atomically. All-job permission is optional, unchecked by default, recorded at actual submit time. Leaving it unchecked preserves any independent existing preference. STOP/suppression and closed jobs block submission. The form does not enable bulk sends or a scheduler.

Important product distinction: this saves the same canonical basic Candidate registration used by the existing WhatsApp intake. It does not create an Auth user, password, complete portal onboarding, Aadhaar record or Resume/CV. Portal account creation and its existing sensitive-intake gate are unchanged. The form explicitly says Candidate Portal sign-in is a separate step. Earlier conversational suggestions of automatic full portal-login registration or phone OTP are not implemented here and must not be represented as live.

## Capability and canonical boundaries

- Private capability generated only in the canonical sender claim for signed Interested ingress; 24-hour expiry from that ingress. Existing once-only lease/timeout/receipt logic retained. Final provider boundary refuses a disabled form mode.
- Token uses two random UUIDs (244 random bits), exact 64 lowercase hex format, SHA-256 lookup in private RLS storage; plaintext exists only in the already-private canonical outbox for delivery. Link fragment never reaches the static hosting server; no-referrer policy and preview_url=false. No phone or candidate details in the link.
- Public RPCs require the capability. Callers cannot choose a contact, mobile, recipient or job. Context returns published job information and masked phone only. No Candidate/Application ID or personal data is returned.
- Reuses the existing locked canonical completion helper; accepts a distinct whatsapp_web source and policy. No fabricated signed webhook or alternate recruitment/outbox tables. Inbound original Interested provides the actual signed identity/job proof; web submit is audited as web registration, not as a new Meta event.
- Token row serialized for idempotent repeats; durable minimal receipt. No raw form data in that row, browser storage, logs or Admin reply projections.
- Required consent and exact enums validated server-side; bounded optional fields validated independently. Optional profile extras only update a Candidate created by this exact registration; existing profile details are not overwritten from a bearer link. Duplicate phone identities stay for staff review without new consent/application.
- Existing active legacy/compact chat sessions continue; only new Interested sessions use the form after explicit activation. Native Meta Flow publication and integrity block remain unchanged.
- New migration installs disabled by default. Form mode was enabled only after reviewed runtime and website publication were verified. No real send, consent change or profile creation was used as a deployment test.

## Review and validation

`tests/fixtures/single-page-form-preview.html` is a standalone design preview with the actual CSS and shared dropdown behavior. Its submit handler sends nothing. It is documentation only and excluded from the production allowlist.

Automated tests cover canonical registration, consent independence, replay, expiry, invalid/missing token, delivery binding, STOP, closed job, identity ambiguity, permissions, canonical capability issuance and sender mode changes. Frontend handler tests cover dropdown selections, immutable phone/job binding, double-submit latch, safe ambiguous-failure recovery and missing-link gating. The allowlisted artifact adds exactly one HTML route and its two assets. Existing production safeguards remain.

Managed browser QA was unavailable because no control-browser skill is available in this environment. No visual browser verification is claimed.

## Proposed release after approval

1. Apply the new additive migration to the explicitly approved Aadhyant production project with web mode disabled; check live grants, RLS and schema advisors.
2. Deploy the exact reviewed webhook/runtime dependency containing web link payload support; compare downloaded runtime bytes with source.
3. Publish the allowlisted website artifact including candidate/apply/ and verify live assets.
4. Only then enable registration_web_enabled. Preserve chat_enabled and existing sessions.
5. Verify safe readiness/grants without a real send. Any new live test message needs a specific user request; do not replay historical Interested events.

Operational rollback is registration_web_enabled=false; no Candidate, Application, outbox or historical session deletion is needed. Already-issued links become unavailable while disabled.

## Verified production closure

- Aadhyant production project: wsuctjhbqiedttfnwjvf. Installed migration ledger: 20261016094631 / whatsapp_single_page_registration.
- Webhook v24 ACTIVE, verify_jwt=false retains existing exact raw-body HMAC/WABA/phone authentication. Archive hash dcbaba8a1701aed7b1fd71ffacf34074b499dc725881bf468fc42154a9842ca0. All six emitted runtime modules match reviewed source exactly (types-only dependency erased). Unsigned live POST returns 403.
- Existing manual pages-production.yml dispatched on source eb2e54ff8ff30eb2538b6c0ea18b06d2a3750f09. Run 38883515806 succeeded; build job 116915649003 and deployment job 116916033232 succeeded. CI: 501 passed, zero failures. Artifact digest 6ce561d254f28399654b3e9cbcab48317806f5761fca5222e6020979e53abb17.
- /candidate/apply/ HTTP 200 and exact reviewed artifact HTML, SHA-256 f6593a2f498ac813ac4c92774c33a60b568526f341cd5ce9020a7f6e223116e7. CSS and JS HTTP 200, byte-equal source, hashes 7b98c2a297e64038a2c3ebed89b7d4655e199c7c34bd9adca5bc416ecb95a3e7 and 0efdc7722d6bc9ef5d454909f89b5321dc3f4f723f6710422845c0fdc47a29c8.
- Public API negative validation: invalid token context returns HTTP 200/null; invalid-token submit returns HTTP 400 without a write. Private table RLS=true, anon table read=false, anon canonical helper execution=false; only capability context/submit RPCs have intentional browser execution. Advisor notices for these SECURITY DEFINER endpoints are expected capability APIs; remediation reference: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable . No permissive direct-table policy added.
- registration_web_enabled=true; existing chat_enabled=true; scheduler_ready=false. Deployment before/after counts unchanged: Candidates 4, Applications 6, outbound 25, opted-in contacts 0. New private web sessions 0. No historical event replay or real test send.
- The first manual build rejected a documentation preview outside the runtime allowlist. Preview was moved into the existing tests/fixtures exclusion; runtime inventory checks remained strict. The corrected artifact and CI passed.
- Automatic approval review rejected adding a persistent auto-deploy workflow. No such workflow was created; the existing manual workflow completed publication without additional triggers or access changes.
- Real user-device form submission has not been claimed as tested. Existing duplicate Candidate identities and active chat sessions remain unchanged and may still require review/continuation.
