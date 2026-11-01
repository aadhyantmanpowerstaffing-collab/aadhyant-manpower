# Selected vacancy delivery through WANotifier

The existing Campaigns workspace selects the published vacancy, freezes eligible
recipients, and snapshots the message through canonical RPCs. No separate Job
Message form is used. Manual delivery now calls `wanotifier-campaign`, never a
Graph API fallback. Automatic publication/scheduler activation is separate.

The Admin-JWT worker reads the saved campaign identity server-side, selects an
exact template endpoint before claiming, and reuses `console_claim_campaign`,
`console_provider_boundary`, the canonical receipt ledger and failure handling.
Ten variables are taken from the saved requirement snapshot: vacancy reference,
company, role, location, qualification, salary, take-home, overtime, duty and
benefits. A URL button uses the same vacancy reference. This route does not
accept editable message fields, recipient lists, contact attributes or consent.

Supported server-side endpoint names:

- `WANOTIFIER_SELECTED_VACANCY_EN_V4_URL`: registered job alert v4.
- `WANOTIFIER_SELECTED_VACANCY_HI_V1_URL`: Hindi registered alert v1.
- `WANOTIFIER_SELECTED_VACANCY_EN_V5_URL`: registered job alert v5.
- `WANOTIFIER_SELECTED_VACANCY_HI_V2_URL`: Hindi registered alert v2.

These names do not make retired/unapproved templates selectable. Existing
catalog compatibility, approval, freshness, consent and job-change guards stay
authoritative. Unsupported video/other templates fail before taking a lease.

Sending requires both `WANOTIFIER_SELECTED_VACANCIES_ENABLED=true` and
`WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED=true`, the pinned WANotifier sender
identity, a verified canonical sender and the exact private endpoint. Leave both
gates disabled until a supported per-recipient genuine WhatsApp message ID is
proven for Notification API, rather than Messaging API alone. Never expose the
provider key/URL in frontend source, examples, screenshots or logs.

Missing or conflicting receipts require reconciliation. No automatic retry or
Meta fallback is performed. Provider-managed retry settings must be reviewed
separately before activation. A response without a genuine message ID is not
proof of failed delivery and must not cause another send.

Interested registration continues through the existing signed webhook and exact
original-message correlation. Templates must actually include an approved
Interested button before claiming this path is available. Fixed `Interested`
and `Stop alerts` button payloads are normalised only for button messages; a
STOP suppresses before any registration action. Never infer the vacancy from a
phone number's latest campaign or from uncorrelated free text.

Validation uses synthetic provider/database fixtures. A controlled real test
must separately prove delivery, receipt correlation, exact-job private form,
registration replay and STOP. Passing unit tests does not prove that live flow.
