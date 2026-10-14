# English WhatsApp registration release — 14 October 2026

The user explicitly authorized Meta publication and live deployment at 15:25:47 IST.

## Verified production state

- Reviewed English source: d305fe4585fabf76121c11b2f5e05f0c977c6797.
- Migration ledger: 20261014095632 / whatsapp_registration_flow on Aadhyant wsuctjhbqiedttfnwjvf.
- Signed webhook v21 ACTIVE, verify_jwt=false, archive hash 84a853ff4cf3a9c3ed376d814f6d4383feed8f243e95bf132cde6a8458105413.
- Flow setup v8 ACTIVE, verify_jwt=true plus actual Admin authorization, archive hash eb7b1266c9385c9365ba8dd21fdf20b1e1b363b9c6b2a68aa520e881f29a5a35.
- Downloaded runtime entrypoints and all runtime dependencies exactly match current reviewed local corrections.
- Registration handler executes for service_role only; anon and authenticated direct execution are denied.
- Successful Pages run 38546302193, job 115793100532, trigger 65a840e61a2b6ed04dae8d9d1ef4fb37eb94fe52.
- CI at publication: 456 passed, zero failed. Final local correction regression: 458 passed, zero failed/skipped.
- Verified artifact digest d0bc22934d24716a6f2df8fcd0632e6f3f00c63a290dcf9aaa6ae8adeb6c3e2d.
- Live Admin console SHA-256 00d16c29d4f538b1228943ed657e002ff3adb0940d2435f545131c9414711b11 matches the deployed source.
- Unsigned live webhook requests return 403. No new real send, registration, marketing opt-in, account creation or historical replay was performed.
- Native Flow message count is zero; the test contact remains unknown consent; scheduling stays disabled.

## Meta publication boundary

A single deterministic draft named aadhyant_registration_alerts_v1 was created/reused through the authenticated Admin setup. Meta rejected JSON version 3.1, unsupported OptIn init-value, and the string type for numeric Age navigation. Corrective source uses supported version 7.2, Form-level init-values=false for both consent fields, and numeric Age navigation. The signed parser converts only valid integer age values into the canonical age field.

Meta's read-only draft verification now reports no JSON validation errors or additional health error codes. Actual publication fails with **139000 / 4233020 — Blocked by Integrity**. This is an account integrity restriction; no further publish attempts were made after identifying this block. Native form activation is false and no published ID/hash is saved. The reviewed English website-link fallback remains live.

Primary Meta error reference: https://developers.facebook.com/documentation/business-messaging/whatsapp/flows/reference/error-codes .
Meta's official Flows changelog identifies supported 7.2; its official WhatsApp-Flows-Tools Postman reference documents read-only validation_errors/health_status inspection. Safe diagnostics expose static form validation messages and numeric provider codes only, never tokens, signed preview URLs or candidate submissions.

Next boundary: the account owner should request Meta account/Flows integrity review for code 139000 / subcode 4233020. Do not assume missing business verification, promise a 24-hour resolution, rename the Flow, rotate numbers or bypass the restriction. After Meta resolves it, verify the existing draft and publish that same reviewed form once; confirm immutable asset equality and the saved ready flag before a separately authorized real test.

This release supersedes the prepared/not-deployed statement in FLOW_REGISTRATION_20261014.md. The code and English form are deployed and validated, but native WhatsApp registration is not yet operational because publication is blocked. Remove the temporary Pages publisher after its confirmed success; removal does not publish another artifact.
