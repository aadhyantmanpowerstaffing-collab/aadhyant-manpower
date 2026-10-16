# Readable mobile WhatsApp job layout — prepared, not deployed

The user requested readable spacing and formatting after viewing the v2 live Admin preview screenshots. The v2 section variables combine many labelled values into a long semicolon-separated paragraph. Changing browser CSS alone cannot change the recipient's actual WhatsApp message.

## Prepared change

The new reviewed draft `aadhyant_registered_job_alert_v3` puts all 68 scalar vacancy fields on their own fixed bullet lines, with bold section headings and one blank line between sections. Vacancy reference, additional closed-catalog benefits, and the complete description remain included. Buttons remain View Job & Apply and Stop alerts. All public vacancy information is preserved; optional missing scalar fields explicitly show Not supplied, because fixed template lines cannot be conditionally removed. Benefits remain one bounded value; a full description can naturally wrap across mobile lines.

The 72 text parameters stay individually single-line. Newlines live in the fixed template, not inside dynamic parameter values. This is an explicit new contract, not punctuation splitting or hidden Unicode/control-character workarounds. Semicolons in employer-supplied text are retained. The fixed body is 1018 characters. Sample values are synthetic, not production candidate/job edits.

Admin preview now renders supported whole-line WhatsApp bold headings as actual strong text, using safe text nodes, with a 380px maximum mobile-style bubble, 16px padding and 1.45 line height. No employer content is evaluated as HTML. Narrower screens wrap naturally. Template text and provider payload remain authoritative; the preview does not insert line breaks that would be absent in a delivered message.

## Upgrade and guards

New migration `20261016124516_readable_whatsapp_job_layout.sql` was created with the CLI; installed migrations remain unchanged. It retains existing canonical projection, campaigns, outbox, consent, publication dedupe, quota, sender checks and final job-snapshot comparison. Exact fresh approved v3 metadata is required for new automatic preparation/enablement. V1/v2 approval cannot activate v3. The setup function submits only static v3 and never edits/deletes previous templates. The worker supports the new ordered contract while retaining legacy payload parsing.

The v3 validator strictly allows only its named public line parameters plus existing correlation metadata, requires all parameters, rejects line breaks/tabs, runs of five spaces, unknown/protected keys, overlong fields and the existing 16 KiB JSON envelope limit. Older payloads continue through the unchanged prior validators. Private helpers retain empty search paths and revoked role grants; preview stays Admin-only.

## External verification and release boundary

This is **not Meta-approved or sent**. Local body length validation does not prove Meta acceptance: this complete per-field layout has 72 variables, and Meta can reject templates with excessive variable density. Meta's official error-code reference explicitly documents this restriction (https://developers.facebook.com/documentation/business-messaging/whatsapp/support/error-codes). The official components page was rate-limited during this review. No claim is made that every expanded message size is deliverable. Preserve the prior pending v2 template and OFF state until a production release and actual Meta review are separately authorized. If Meta rejects this complete layout, report its real error before choosing a shorter-summary/full-details-link design; do not silently drop saved job fields.

No production migration, deployment, Meta submission, real send, scheduler enablement, data or consent change was performed for v3. Review assets: `registered-job-alert-template-v3.json`, `readable-job-parameter-keys.json`, `readable-job-message-example.txt`.

Supabase changelog and current database-functions documentation were fetched on 16 October 2026. The September PostgreSQL extension/operator upgrade notice does not affect this plain JSON/text/function upgrade; no new extension or client API was introduced.

Validation: all 521 regression tests passed (zero failures/skips), JavaScript syntax and diff checks passed. Production build was rechecked after removing an offline HTML review fixture rejected by the strict runtime HTML allowlist; the guard was not weakened. No review fixture is shipped.
