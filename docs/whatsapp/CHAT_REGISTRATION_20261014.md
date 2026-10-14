# English WhatsApp chat registration — 14 October 2026

The user explicitly authorized starting this implementation and live setup at 16:16:36 IST after agreeing to registration entirely inside WhatsApp chat. No real test send or bulk campaign is included in this deployment.

## Behavior

An exact, signed Interested reply to a delivered console job campaign starts a durable chat for the same contact and job. Registered Candidates continue through the existing canonical Interested/Application processor. An unregistered contact is asked:

1. Permission to register and contact them about this job (Yes / No, current bound button required).
2. Full name.
3. Age, 16–75 (canonical profile range, not job matching).
4. Gender.
5. Highest qualification.
6. Course / trade / specialization (General is accepted).
7. State.
8. District.
9. Current village / city.
10. Fresher / Experienced.
11. Interview availability.
12. Separate optional all-job WhatsApp alert consent (Yes / No, current bound button required).

The last question explicitly includes jobs outside qualification, trade, age and preferred location, and allows sharing. Registration succeeds after either alert choice. A No answer never creates new alert permission; a prior independently established preference is preserved. Both permissions are evidenced by separately signed choices. No default Yes, bare-text Yes, Interested, import or campaign selection grants marketing consent.

The phone comes from authenticated Meta ingress, never from an editable answer. Successful intake creates/reuses the canonical basic Candidate and records this job's canonical interested Application. It does not create an Auth/portal login, advance recruitment stages or send other job campaigns. Profile completion remains incomplete. The existing approved job template remains unchanged.

## Boundaries

- Reuses canonical contacts, inbound events, outbox, candidates, applications and audit logs. The private chat table holds only temporary intake state, not parallel recruitment records.
- A private shared completion helper retains the reviewed native Flow's validation/identity/canonical commit logic. The existing Flow wrapper retains exact token, contact, job and expiry checks.
- A contact has at most one active chat. Another Interested/RESUME repeats that chat's current question and does not silently switch jobs.
- Current buttons/list replies bind session + step + exact delivered prompt. Stale/cross-contact replies cannot grant consent or shift questions. Unquoted text must be newer than the preceding accepted input and current sent prompt.
- Invalid answers repeat the current question. Every prompt uses a once-only canonical outbox row and a final sender/suppression/job/window boundary.
- Provider timeouts or missing receipts require reconciliation, never automatic re-send. An explicit new user RESUME can create a fresh prompt for the same unanswered step.
- STOP/UNSUBSCRIBE suppress contact messaging and cancel/clear active intake. CANCEL clears intake without changing existing alert preferences.
- Each intake expires 24 hours after the starting signed Interested. Expiry is enforced before processing and sending; partial answers are cleared when expiry is encountered. Completed/cancelled/review sessions clear temporary answers. At most 60 prompts per session.
- No arbitrary raw text is retained in canonical inbound rows, Admin reports or outbound prompts. Valid answers are held privately until the canonical commit. Admin Reports shows safe status/delivery/consent fields and masked phone.
- Private storage has RLS and no browser/service-role direct-table grants. Public orchestration RPCs execute only for service_role, with empty search paths. Browser Admin has only the established safe report/config projections.
- The sender remains authenticated by raw-body HMAC and exact WABA/phone identity. Chat messages use the normal customer-service window, without a Meta Flow asset. This does not publish the integrity-blocked native form or change the account identity.

## Release sequence

1. Validate local database behavior, signed ingress, sender boundary, failure/replay/STOP/consent cases and existing regressions.
2. Install the additive migration with chat disabled.
3. Deploy and compare the reviewed signed webhook including the new module.
4. Enable chat only after the runtime is verified, and publish the updated Admin status/report copy.
5. Verify live grants, enabled/readiness state and unsigned rejection. No historic Interested event is replayed; no real Candidate, consent or message is created as a deployment test.

Native form publication still depends on Meta resolving 139000 / 4233020. Chat registration is the explicitly authorized operational route; it is not a successful Meta review or published Flow.

Primary API references: https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/interactive-reply-buttons-messages and https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages .

## Verified release state

- Local regression: 480 passed, zero failed/skipped. The 12 new PGlite chat cases run in a separate test process using shared fixtures to keep memory bounded; the previous 37 console runtime tests remain intact.
- Installed production migration ledger: 20261014112829 / whatsapp_chat_registration on wsuctjhbqiedttfnwjvf.
- Signed webhook v22 ACTIVE; archive SHA-256 c7fec391b6f54fe9f52297eafc407d14135668bdd0841ec6dd79b31d3d6d9b5f. Downloaded entrypoint and all emitted runtime dependencies match the reviewed sources exactly.
- verify_jwt=false preserves the established raw-body HMAC and exact WABA/phone custom authentication. Unsigned live POST returns 403.
- Chat enabled after verified runtime deployment; sender verified. Private chat storage RLS=true, browser table access=false; orchestration RPC has anon/authenticated execute=false and service_role execute=true.
- Deployment verification found zero chat sessions/messages, and the existing Candidate/Application/outbound/marketing-opt-in counts were unchanged. No historical event replay or real test message was performed.
- Reviewed Admin artifact digest: 61ffca7e78ac9c98ce1ca9fcf1e4da8998008a212179acdc20adbeed5883ad76. Site publication verification is pending.
