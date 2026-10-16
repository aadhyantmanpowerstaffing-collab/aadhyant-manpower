# Concise WhatsApp job summary v4

Authorized by the user at 18:40:31 IST, 16 October 2026, after Meta rejected the 72-parameter v3 draft with code 100 / subcode 2388293. The user accepted the proposed WhatsApp summary with complete information and application on View Job & Apply.

The reusable English marketing template has ten ordered parameters: vacancy reference, company, role, location, qualification, CTC/salary, approximate take-home, overtime, duty and benefits. Fixed bold headings and newlines keep the main facts readable. Salary amounts retain their supplied pay cadence; missing amounts/terms link to full job details. Facilities with charges are not presented as free. No salary figures, benefits or default entitlements are invented. A synthetic example is retained in `summary-job-message-example.txt`.

All full public vacancy fields, description, structured benefits, salary breakup, deductions and conditions stay on the existing job page. Summary benefits intentionally cover the principal listed statutory contributions/facilities/attendance bonus, not every saved benefit. A longer benefits summary explicitly directs the reader to full conditions, rather than truncating text. The existing URL action stays bound to the exact vacancy and Stop alerts remains a quick reply. No Interested or repeated registration action is added for registered alerts.

The fixed body is 541 characters with ten parameters; the expanded sample is 685 characters. Database and worker independently enforce 1024 expanded Unicode characters for this button-bearing template, single-line parameters of at most 300 characters, a strict key allowlist, a 16 KiB envelope and a valid vacancy reference. Oversized actual summaries fail closed for Admin review. Local limits do not guarantee Meta approval or delivery.

A SHA256 fingerprint of the complete existing candidate-facing v2 projection is stored with the summary. Thus a change to an omitted leave, deduction, description or structured benefit still pauses an already frozen publication; omission from the WhatsApp summary does not weaken the full-job snapshot comparison. The fingerprint is correlation metadata, never a provider body parameter.

A new corrective migration `20261016131116_concise_registered_job_alerts.sql` preserves installed migrations and canonical candidates/applications/campaigns/recipients/outbox. Exact approved and freshly synced v4 is required for enablement/preparation; v1/v2/v3 approval is insufficient. Earlier Meta templates are not overwritten/deleted. Private helpers retain empty search paths and revoked role grants, and preview remains Admin-only. Full existing consent, STOP, sender, scheduler, quotas, publication dedupe and no-historical-replay gates remain.

The current task authorizes implementation, deployment and Meta submission of this format. It does not activate a scheduler, automatic bulk sending, candidate test send, consent changes or historical job replay. Those remain OFF.

Validation before release: 525/525 tests passed with no skips/failures in the serial full regression run. The initially interrupted console database suite passed separately with the summary suite (39/39); the runner now uses one concurrent file to avoid overlapping embedded PostgreSQL runtimes. No test assertions were weakened. Node syntax and diff checks passed.
