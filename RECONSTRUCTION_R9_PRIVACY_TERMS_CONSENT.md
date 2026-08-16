# Reconstruction R9 — Privacy, Terms and Consent Foundation

## 1. Current data-collection surfaces

The current public and account surfaces are Candidate Registration, Employer Quick Requirement, Company Registration, Staffing Partner Registration, authenticated Company requirements, Staffing Partner assignments and Admin operations.

Candidate fields include name, age, gender, mobile/WhatsApp, location, qualification, trade/specialisation, Candidate type, experience details, interview availability, preferred location and optional notes. Employer submissions include business/contact details and structured workforce requirement conditions. Company and Staffing Partner signup collect account, organisation, contact, location, operational and optional business details visible in their existing forms.

## 2. Privacy architecture

`/privacy/` describes actual collection, purposes, user-specific categories, authentication, communication channels, controlled data sharing, infrastructure, retention, correction/deletion requests, security, minors, browser storage, external links and contact details. It makes no automated-decision or guaranteed-security claim.

## 3. Terms architecture

`/terms/` defines practical website and platform rules for public visitors, Candidates, Employers, Companies and Staffing Partners. It covers accurate information, acceptable use, account security, controlled assignments, service availability, account restrictions and separate commercial agreements without defining fees, payroll, liability allocation, replacement guarantees or penalties.

## 4. Candidate consent

The required, unchecked Candidate checkbox now explains voluntary profile submission, recruitment/workforce use, service contact and the absence of guaranteed job, interview or placement. Privacy and Terms links are separately associated through `aria-describedby`, so activating a link does not toggle the checkbox.

## 5. Employer consent

The required, unchecked Employer checkbox now explains voluntary business/contact/requirement submission, requirement-related contact, no guaranteed Candidate availability or fulfilment and no automatic Company account. The legal links use the same separate accessible pattern.

## 6. Staffing Partner consent

The existing required checkbox and signup contract remain unchanged. A small page-safe frontend module replaces only its displayed explanation and adds associated Privacy and Terms links. It states review/approval, onboarding/workforce use, contact, and no guaranteed assignments, business or revenue.

## 7. Company signup consent status

Company Registration already has a required consent checkbox. Its functional field remains unchanged. The same frontend module improves displayed wording and adds associated legal links without creating a backend dependency. Auditable acceptance version/time is not currently persisted and remains a governance gap.

## 8. Communication and WhatsApp boundary

Users may receive service-related communication through contact details they provide, including phone, email and WhatsApp where used and agreed. The site does not claim an automated official WhatsApp campaign system or promotional consent. A future WhatsApp workflow must use explicit, auditable communication preferences rather than infer marketing consent.

## 9. Data-sharing boundary

Aadhyant remains the coordination layer. Sharing is described only as reasonably necessary for staffing, recruitment, a relevant hiring process or an authorised platform function. The policy does not imply open Candidate or Employer databases. Current role, account, membership and assignment controls remain the security boundary.

## 10. Retention wording

No fabricated fixed period is stated. Data may be retained for as long as reasonably necessary for service operation, legitimate records, dispute handling, security, misuse prevention or applicable obligations. A formal retention schedule remains future governance work.

## 11. Correction and deletion process

Users may contact the verified email or phone to request correction, update, deletion consideration or a communication-preference change. Requests may require verification, and the draft does not promise automatic deletion where legitimate retention is reasonably needed.

## 12. Minor and eligibility handling

The existing Candidate form accepts ages 16–75. R9 does not silently change that contract. The policy states that users must be legally eligible for a relevant opportunity and that guardian assistance should be used where appropriate. Legal review of under-18 handling remains recommended.

## 13. Cookie and tracking finding

The repository contains no Google Analytics, advertising pixel or custom cookie code. No cookie banner was added. The policy only describes necessary authentication session storage that may be used by authenticated portals and commits to review if tracking practices change.

## 14. Third-party service references

Only verified high-level services are named: GitHub Pages for static hosting, Supabase for backend/database/authentication, and user-selected email or WhatsApp links. No keys, secrets or infrastructure internals are published.

## 15. Footer and legal-link migration

The shared public-navigation module adds Privacy Policy and Terms of Use links to every public footer. Legal pages include static copies for resilience and the module detects them to avoid duplication. Portal footers are not converted into public navigation.

## 16. Form regression

Candidate and Employer canonical forms remain unique. All original field names, IDs, required flags, review controls and submission wiring remain. Company and Staffing Partner consent input names, required flags and signup handlers remain unchanged. No form or account is submitted during R9 validation.

## 17. Accessibility

Legal pages use skip links, semantic landmarks, one H1, ordered section headings, narrow readable text and visible link focus. Consent checkboxes remain explicitly labelled; separate legal text is associated using `aria-describedby` and links are outside the label activation area.

## 18. Responsive and browser tests

All thirteen public routes and ten portal routes returned HTTP 200 locally. Every public route passed at 360, 390, 768, 1024 and 1440 pixels with zero page-level horizontal overflow. Privacy and Terms text, mobile navigation, legal footer links and all four consent surfaces remained usable.

Candidate, Employer, Company and Staffing Partner consent controls remained required and unchecked. Their legal links were outside label activation areas, were associated through `aria-describedby`, and did not toggle the checkbox. Browser capture found zero severe console errors, zero failed responses and zero production Supabase requests. No form, account or record was submitted.

## 19. Security and config review

R9 requires no SQL, migrations, schema, RLS, RPC or Auth changes. `config.js`, `supabase-client.js`, submission logic, portal business logic and production configuration must remain unchanged. Changed files are scanned for secrets and local endpoints.

## 20. Future auditable consent model

A separately reviewed schema milestone may introduce versioned, append-oriented consent evidence such as `consent_version`, `privacy_version`, `terms_version`, `consented_at`, `whatsapp_consent`, `whatsapp_consented_at` and structured communication preferences. Candidate, Employer, Company and Staffing Partner flows should store the policy versions actually shown without trusting client-supplied user or account identifiers.

The future Candidate path should remain one Candidate Master: registration → explicit communication consent → requirement matching → WhatsApp vacancy communication → Candidate response → application → interview → joining. It must not create a duplicate WhatsApp Candidate database.

## 21. Legal-review recommendation

These pages are operational website Privacy and Terms drafts based on current repository behavior. Final review by qualified Indian legal/privacy counsel is recommended before broad commercial rollout or major WhatsApp or marketing automation.

## 22. Known limitations

- Consent versions and timestamps are not auditable in the database.
- A formal retention schedule and verified request-handling procedure remain to be established.
- Under-18 Candidate handling needs legal and operational review.
- Live Jobs, LGD data, Candidate Auth and WhatsApp automation remain deferred.

## 23. Recommended next phase

Obtain legal review and define governance decisions for retention, request verification, minors and communication preferences. Only then design a separate additive migration for auditable consent evidence. Do not combine that work with live Jobs access or WhatsApp delivery.
