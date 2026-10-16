# Concise WhatsApp job summary v4

Authorized by the user at 18:40:31 IST, 16 October 2026, after Meta rejected the 72-parameter v3 draft with code 100 / subcode 2388293. The user accepted the proposed WhatsApp summary with complete information and application on View Job & Apply.

The reusable English marketing template has ten ordered parameters: vacancy reference, company, role, location, qualification, CTC/salary, approximate take-home, overtime, duty and benefits. Fixed bold headings and newlines keep the main facts readable. Salary amounts retain their supplied pay cadence; missing amounts/terms link to full job details. Facilities with charges are not presented as free. No salary figures, benefits or default entitlements are invented. A synthetic example is retained in `summary-job-message-example.txt`.

All full public vacancy fields, description, structured benefits, salary breakup, deductions and conditions stay on the existing job page. Summary benefits intentionally cover the principal listed statutory contributions/facilities/attendance bonus, not every saved benefit. A longer benefits summary explicitly directs the reader to full conditions, rather than truncating text. The existing URL action stays bound to the exact vacancy and Stop alerts remains a quick reply. No Interested or repeated registration action is added for registered alerts.

The fixed body is 541 characters with ten parameters; the expanded sample is 685 characters. Database and worker independently enforce 1024 expanded Unicode characters for this button-bearing template, single-line parameters of at most 300 characters, a strict key allowlist, a 16 KiB envelope and a valid vacancy reference. Oversized actual summaries fail closed for Admin review. Local limits do not guarantee Meta approval or delivery.

A SHA256 fingerprint of the complete existing candidate-facing v2 projection is stored with the summary. Thus a change to an omitted leave, deduction, description or structured benefit still pauses an already frozen publication; omission from the WhatsApp summary does not weaken the full-job snapshot comparison. The fingerprint is correlation metadata, never a provider body parameter.

A new corrective migration `20261016131116_concise_registered_job_alerts.sql` preserves installed migrations and canonical candidates/applications/campaigns/recipients/outbox. Exact approved and freshly synced v4 is required for enablement/preparation; v1/v2/v3 approval is insufficient. Earlier Meta templates are not overwritten/deleted. Private helpers retain empty search paths and revoked role grants, and preview remains Admin-only. Full existing consent, STOP, sender, scheduler, quotas, publication dedupe and no-historical-replay gates remain.

The current task authorizes implementation, deployment and Meta submission of this format. It does not activate a scheduler, automatic bulk sending, candidate test send, consent changes or historical job replay. Those remain OFF.

Validation before release: 525/525 tests passed with no skips/failures in the serial full regression run. The initially interrupted console database suite passed separately with the summary suite (39/39); the runner now uses one concurrent file to avoid overlapping embedded PostgreSQL runtimes. No test assertions were weakened. Node syntax and diff checks passed.


## Production release and Meta submission

- User approval: 16 October 2026, 18:40:31 IST. Native source commit `a5654310030dacf9ccd3342b52d9ae7906d01f43`, tree `5eb296e670dff7d9a8e7f3703a1b0d541a21ef92`, fast-forwarded by expected-SHA update from `0a73a5f88072eeece91992646826e637a0823a16` on `web-platform-development`.
- Production project `wsuctjhbqiedttfnwjvf`, Aadhyant connector. Migration ledger `20261016131802 / concise_registered_job_alerts`; source SHA256 `2857e29f93c1347d93e4b25855c9fa354628535af465fec8434fc20656fc4829`.
- Worker v21 ACTIVE; existing custom-auth verify_jwt=false retained. Archive `af568d26aad5567cb56f1571990ede9fc3f0a1f9df6dade879fbbd1a6826d6cc`; all three downloaded runtime files exactly match reviewed sources.
- Fixed setup endpoint v5 ACTIVE, verify_jwt=true with existing Admin/account binding. Archive `6dc4d799eea24208910506c632942de6034d9bd601f4f2a1bd2d68aa562458d6`; both downloaded runtime files exactly match source.
- Existing manual Pages production run `38906947892` succeeded from a565431; build job `116992793400`, deploy job `116993341111`, including complete regression and artifact manifest checks. No new deployment or messaging automation.
- Actual live Admin HTML and versioned console JS match the rebuilt production artifact: HTML SHA256 `805c14abb13b7ec932c7dbf66295987ac9f03bf84838589ce2d3786fac97b95a`, JS `bd00db5f35a7a18b82349bb5a6f4d1156ddd86475f93c2cc8ad91f27f9ca2947`. A local stale artifact fixture initially lacked version query strings; rebuilding after regression restored exact byte matches without source changes.
- Submitted static v4 exactly once through the actual signed-in Admin button, then synced provider status. Meta name `aadhyant_registered_job_alert_v4`, language en, ID `1740952410349653`, **PENDING**, compatible=true; sync `2026-10-16T13:20:21.084415Z` (18:50:21 IST). The v3 density rejection did not recur for v4. This is submission acceptance, not approval or delivery.
- Live browser preview of actual stored `AAD-2026-000003 / Associate` renders separate bullets, bold section headings, mobile-width bubble, CTC range/pay cadence, take-home, OT and duty. The benefits summary correctly distinguishes free transport from charged canteen/accommodation. Saved figures were not edited. Whole-line bold headings render in preview; the inline business-name asterisks remain literal in this simple preview renderer, while the provider template retains WhatsApp bold syntax.
- Existing four application-eligible vacancies produce 733, 682, 741 and 695-character summaries respectively; all pass local limits. Anonymous preview execution remains denied.
- Frozen OFF state and counts unchanged: contacts 5, campaigns 10, outbox 39, applications 6. No candidate/test/bulk message, publication, consent change, historical replay or scheduler activation.
- Verified live URL: https://aadhyantmanpower.in/admin/?release=20261016-summary-job-v4#whatsappConsole . Automatic Alerts → choose a vacancy → Preview Job Summary. No second Meta submission was used to restore a status label after loading the new site.

Outstanding: actual Meta approval, eligible all-job subscribers and scheduler/sender readiness before any separately authorized automatic activation. Do not promise a fixed approval time or treat submission as proof of a delivered WhatsApp message.
