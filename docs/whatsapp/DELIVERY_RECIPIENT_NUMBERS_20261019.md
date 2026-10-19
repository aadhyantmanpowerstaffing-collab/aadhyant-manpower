# Recipient numbers in delivery reports

User requested full recipient numbers in the WhatsApp delivery report and Excel export. The supplied summary workbook contains Campaign/Audience/Sent/Delivered/Read/Failed totals, without recipient rows.

The existing Admin-gated `admin_console_report` now adds `mobile` from the canonical contact provider address, retaining `mobile_masked` for compatibility and preserving canonical status/timestamps, offset bounds and access checks. Only this delivery projection exposes the full number as explicitly requested; other projections are unchanged.

Reports → View numbers & status opens recipient details. Export recipient report downloads campaign, WhatsApp Number (text), status, sent/delivered/read timestamps and failure category for the current page of up to 100 recipients. Existing pagination and generic displayed-table exports remain available. Read is a distinct latest status and also indicates delivery. No historical numbers can be reconstructed from the supplied aggregate spreadsheet.

Migration: `20261019152157_whatsapp_report_recipient_numbers.sql`.
No new tables, sends, templates, consent updates or queue changes.

Validation: focused database/UI/Excel tests 10/10, JS syntax, production artifact build and diff check passed. Initial concurrent large console runtime process terminated without an assertion failure; the new database test was isolated in its own process to avoid growing the existing embedded Postgres suite. Sequential full regression result is recorded below when complete.

Production remains unchanged pending explicit deployment approval under AGENTS.md.

Final validation: full regression run passed 611 individual cases; one unchanged candidate-preferences file was terminated without an assertion during overlap with the initial focused process. Its 8 cases passed on isolated rerun, together with the new database report case (9/9). The additional UI export case passed in the full suite. Combined coverage is 620 passing individual cases across the completed runs. Production artifact and syntax/diff checks passed. No production change or send occurred.
