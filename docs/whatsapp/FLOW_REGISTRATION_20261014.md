# WhatsApp registration and alert consent — prepared 14 October 2026

Prepared for explicit production and Meta publication review. Nothing in this change has been deployed or published; no real message or candidate mutation was performed.

## User flow

Interested on a delivered job campaign opens the reviewed English WhatsApp form instead of a website link once the Meta Flow is published and verified. The two screens collect name, age, gender, state, district, village/city, qualification, trade/course, experience status and interview availability. The current WhatsApp sender determines the mobile; the form cannot supply another mobile.

Required consent: **I agree to registration and contact about this job.**

Optional, initially unchecked consent: **I want all Aadhyant job alerts on WhatsApp.** The form explains that all Aadhyant job alerts may include jobs that do not match the person, and STOP turns them off. Unchecked means no new alert consent; it does not revoke a previous independent subscription.

Submit creates or safely reuses a canonical basic Candidate and an `interested` Candidate Application for the original job. This is basic recruitment registration, not an authenticated Candidate Portal account or a complete document profile. No Aadhaar, bank detail, password or portal identity is collected or invented. New profiles remain `incomplete`; portal linking and document intake retain existing controls.

## Integrity and consent

- Reuse canonical contacts, inbound/outbound messages, Candidates and Applications. No second queue or identity store.
- Signed, exact sender identity checks happen before persistence. A random 64-hex token binds the published form to one registration outbox message, WhatsApp contact and original job.
- Require a confirmed delivered/sent/read form, exact token/contact, a valid timestamp within 24 hours of issue, current public job eligibility and no STOP/block/ambiguity.
- Store the immutable published form ID/hash, consent policy, provider timestamp and selected checkbox in the canonical audit trail. Do not coerce strings into boolean consent.
- One successful submission per token. Duplicate webhook delivery or another Submit cannot create another Candidate/Application or re-enable consent after STOP.
- Exact identity reuse checks name, age and mobile. Conflicts need review; existing private Candidate details are never overwritten. Preserve existing application stages.
- The all-job checkbox alone may record `opted_in` and `scope=all`; preserve a newer independent preference. False/missing/invalid consent never grants marketing permission.
- Invalid submissions become durable review attention. An uncertain committed success is never overwritten by a timeout recovery.
- No alert scheduler activation, historical webhook replay, bulk send or automatic portal account creation is part of this release.

## Meta setup and production sequence

After explicit approval:

1. Apply `20261014092316_whatsapp_registration_flow.sql` to Aadhyant `wsuctjhbqiedttfnwjvf`.
2. Deploy the reviewed signed webhook/shared dependencies and the new `whatsapp-flow-setup` with JWT plus verified Admin authorization.
3. Publish the reviewed Admin console through the existing Pages artifact process.
4. In Templates, publish the reviewed `aadhyant_registration_alerts_v1` form. The setup reads owned WABA Flows first, reuses only one deterministic name, validates the uploaded JSON before publishing, then checks PUBLISHED status and actual immutable asset content before enabling it. Publication sends no message.
5. Verify runtime, grants, published content and live UI. An operator-controlled new job test/Interested click is separate from publication.

Meta publication is irreversible: published assets cannot be edited. A future content change needs a new version/name and review. Draft or failed validation never enables the form. Until verified (or after verification expires), the existing site link remains the fallback. A verification button refreshes the published form without republishing it.

## Validation and limits

- Full regression: **454 tests passed**, zero failed/skipped. Two additional signed-submission tests were added and pass in the **31-test** focused webhook/Flow suite.
- SQL runtime tests cover canonical creation/reuse, no-consent registration, checkbox provenance, duplicate completion, wrong token/contact/policy, string consent, unsigned data, STOP, unavailable job, expiry, identity conflict, failure-recovery protection and changed form boundary rollback.
- Meta publication tests use fixtures, covering no sends, admin authorization, upload validation failure, read-only verification, immutable asset mismatch, native payload and exact parser booleans.
- Build and artifact verification pass; JSON review artifact and shipped server definition are identical; `git diff --check` passes.
- Meta's actual JSON validation/publication and a real WhatsApp form completion remain pending approval. Browser/WhatsApp visual QA is not claimed by local tests.

Primary API references: Meta's official `WhatsApp/WhatsApp-Flows-Tools` repository (contact/survey form examples and its `postman/v1/whatsapp-flows-api.postman_collection.json` for create, upload, publish, immutable assets and native Flow send payload), and Meta Flows developer documentation. This endpointless Flow uses the signed completion webhook; it does not need a data-exchange endpoint or an RSA encryption-key setup.

## Language review

At 15:19:32 IST the user requested English. All form titles, labels, choices, instructions, consent copy, Flow invitation and website-link fallback are now English. Optional alert consent remains unchecked. The 40 focused UI/Flow/webhook/reply tests and the rebuilt artifact verification pass after this wording change. No production or Meta publication occurred.
