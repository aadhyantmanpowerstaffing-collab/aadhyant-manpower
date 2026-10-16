# Readable mobile WhatsApp job layout — deployed; Meta submission blocked

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

Development validation performed no production changes. The separately authorized production release is recorded below. No Meta submission, real send, scheduler enablement, or consent change was performed for v3. Review assets: `registered-job-alert-template-v3.json`, `readable-job-parameter-keys.json`, `readable-job-message-example.txt`.

Supabase changelog and current database-functions documentation were fetched on 16 October 2026. The September PostgreSQL extension/operator upgrade notice does not affect this plain JSON/text/function upgrade; no new extension or client API was introduced.

Validation: all 521 regression tests passed (zero failures/skips), JavaScript syntax and diff checks passed. Production build was rechecked after removing an offline HTML review fixture rejected by the strict runtime HTML allowlist; the guard was not weakened. No review fixture is shipped.


## Production release under 18:21:17 IST approval

- Authorized source `e12f7533245e176d107a59cbb04436f38fc9b1ea`, exact reviewed tree `fb3e18dd9a0f4b31a45653098e3554bc602d97f5`; promoted by non-forced expected-SHA update of `web-platform-development` from `7a849cc12368745a076df8a6a82ae387f7cc47b9`.
- Production project `wsuctjhbqiedttfnwjvf`, Aadhyant connector. Migration applied as ledger `20261016125353 / readable_whatsapp_job_layout`; source SHA256 `9bccf99ec0589cc00c8e4867b76a027b7903b49200e82bdfacd90957b812d4e6`.
- `whatsapp-outbox-worker` v20 ACTIVE, verify_jwt=false retained custom authentication; archive `6a1be96c924ed74840a74d127b8166c0893bb7ec8296076ca61a03844863a02c`. All 3 downloaded runtime files exactly match local reviewed sources.
- `whatsapp-registered-template-setup` v3 ACTIVE, verify_jwt=true retained Admin checks; archive `09c9d35482eedde4e91b749587ed005f06ccb1241d70ff258ed5c94d8588176b`. Both downloaded runtime files exactly match reviewed sources.
- Existing manual Pages workflow run `38904029396`, source e12f753: build job `116983020326` and deploy job `116983436036` succeeded, including the full regression chain and artifact manifest verification. No new workflow or scheduled automation.
- Actual live versioned JS and CSS returned HTTP200 and exactly match source. JS SHA256 `1b836b502f16938158885ed85409b3beb8c1ba3af581056c3ded56b4cc5526f6`; CSS SHA256 `42e6b95299d6042fb14c23088715f149fb78143410811cb7e2a01acec8ec2b04`.
- Post-release SQL: template fixed body 1018 characters; all four currently application-eligible job payloads pass the local envelope validator; anonymous preview execution denied; automatic alerts still OFF. Counts unchanged: contacts 5, campaigns 10, outbox 39, applications 6.
- Meta submission was NOT attempted: native browser credential protection blocked Admin document observations after explicit fresh navigation. Stopped protected inspection and credential automation; no token extraction, impersonation, direct provider send, or alternate browser session workaround. Live visual QA/screenshot and actual v3 Meta submission/status remain unverified. V1/v2 metadata retained; no v3 catalog entry at final SQL read.
- Required operator continuation: in the signed-in Admin WhatsApp Manager, open Automatic Alerts and click **Submit Job Alert Template to Meta** once, then check the actual returned Meta result. Do not retry an ambiguous submission without looking up v3 by name. Automatic sending remains OFF while review/scheduler setup is incomplete.
