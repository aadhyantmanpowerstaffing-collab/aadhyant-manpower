# Single-page WhatsApp registration — 16 October 2026

The user requested a complete English form on one page with dropdowns, optional fields and a separate all-job-alert checkbox. This change is prepared locally; production is unchanged pending explicit publication approval under AGENTS.md.

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
- New migration disabled by default; no real send, consent change, profile creation or production mutation performed for this implementation.

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
