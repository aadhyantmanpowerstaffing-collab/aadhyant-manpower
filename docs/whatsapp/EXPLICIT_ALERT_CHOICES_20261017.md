# Explicit job-alert choices — 17 October 2026

## User-approved behavior

Two required, independent Yes/No answers, with no preselected answer for a new choice:

1. Receive WhatsApp Job Alerts?
2. Receive Same-Day Pay Job Alerts?

No does not prevent registration/application. Stored existing answers are shown when editing. Same-Day Pay eligibility uses Sanand/Sanand GIDC in current living location, current job location or preferred work locations. The current-job location is separate from the place of residence. Gujarati સાણંદ is recognized; substring lookalikes such as Sanandpur are not. The initial area remains Sanand GIDC; no location is inferred from an imported phone number.

## Implementation

Updated Candidate onboarding/My Profile, the private WhatsApp registration form, and the Same-Day Pay preference panel. The email/password signup step remains identity-only. Existing profile/application/document/registration-capability security boundaries are retained.

`private.candidate_alert_choices` records the explicit two booleans, current job location, source/policy and timestamp; RLS is enabled and browser/service roles have no direct table grants. Authenticated read/save RPCs resolve the caller's canonical active Candidate; no caller-provided Candidate/contact identity is accepted. No new candidate/contact/application system is introduced.

Private WhatsApp form completion delegates to the retained canonical validator/identity/application commit and capability checks. New optional payload fields are removed before that validator, then both choices are saved in the same transaction. Completed-token replay returns its original receipt without changing choices. Legacy callers remain compatible, without inventing Same-Day Pay consent.

Either Yes can authorize the canonical contact's marketing transport, but per-job audience filters enforce the independent answers: general No + shift Yes cannot receive regular jobs, and general Yes + shift No cannot receive shifts. Both No withdraw future alerts while keeping profile/application records. A later explicit Yes can replace a prior portal No; an existing WhatsApp STOP/suppression is preserved and requires review. Private helpers remain inaccessible to browser roles; no consent is granted by default.

Same-Day Pay enrollment reuses the established private preference. Location and consent are checked when preparing a publication and again before the provider boundary. No-op saves retain enrollment timestamps. New or changed choices cannot be retroactively added to a frozen publication. The existing v4 template, outbox, deduplication, STOP guards and disabled automatic-alert state are preserved. No send or Meta change is part of this work.

Authenticated profile creation/update and the separate alert save are sequential RPCs; a network/error after profile persistence can leave the profile saved while alert saving is unconfirmed. The client does not claim confirmed alert success in that situation and directs the user to review My Profile. Private-link registration and its two choices are atomic.

## Validation

Focused runtime tests cover blank/null rejection, independent answers, narrow grants, all three Sanand location routes, Gujarati and non-matching lookalikes, withdrawal/reselection, STOP preservation, identity/blocked-contact rejection, private-link atomic receipt/replay, and canonical publication/final-provider behavior after location changes. Client tests execute the real private-form script to prove blank answers do not submit and No/Yes are transmitted independently. Existing Same-Day Pay and WhatsApp registration setup code was extracted into shared test fixtures without changing those workflow contracts.

Production build/manifest verification passes. Latest focused backend/Candidate UI checks pass 50/50; private-form UI checks also cover blank rejection. Frontend payload SHA-256 is `04cd2059667a17df3c6ba4a0c865dbf257242d96c5bd3f56668195de492fd894` (93 runtime payload files, 47 HTML routes). Complete regression passes 595/595 with zero failures/skips; the final focused 50/50 checks and production build/verification also pass after the final location/timestamp refinements. No authenticated live walkthrough was performed for these undeployed forms. The user explicitly approved production database/site deployment at 11:20:46 IST on 17 October. Installed production migration `20261017055113 / explicit_candidate_alert_choices`. All eight new/replaced function bodies match the reviewed migration, and retain SECURITY DEFINER. RLS is enabled on the private choice table; anonymous save and direct authenticated table writes are denied. Candidate/Application/Vacancy/outbound counts remain zero and automatic alerts remain OFF. Security advisor categories remain the expected RPC-only/no-policy, executable-definer and Free-plan leaked-password notices. No customer preference was modified and no WhatsApp send occurred. Site deployment was dispatched from reviewed source `bdb22dadfb50c598a225db95133f607a9a475ffa`; final outcome follows below.
