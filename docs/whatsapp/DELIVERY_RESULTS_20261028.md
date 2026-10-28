# Clear campaign delivery results and bounded dispatch claim

Production evidence: the SNAND GIDC worker received one HTTP 502; its database `console_claim_campaign` request returned HTTP 500 with PostgREST SQLSTATE `57014` after about 8.2 seconds. Thirty-nine other worker requests succeeded. The campaign had 383 outbound rows and zero queued/sending rows, but its canonical campaign/recipient status remained queued. Failed webhook records contained provider error codes while the report read only empty outbox error fields.

## Changes

- Optimize the internal `console_claim_campaign_before_registered` function with a cheap work check before template/eligibility expansion and a materialized per-campaign template check. Preserve the public manual wrapper, automatic quota separation, consent, suppression, ownership, lease, attempt and final-provider guards. Completed dispatches never re-enter claim or resend terminal messages.
- Add restricted read-only full-campaign delivery aggregation. Keep Delivered inclusive of Read; Sent is explicitly Awaiting delivery. Pending, not sent and outcomes needing review are separate. Derive the user-facing campaign stage from actual outbound evidence without rewriting the canonical campaign lifecycle.
- Read the latest failed provider webhook event when outbox error fields are empty. Display English failure explanations and codes, including Meta recipient, quality/spam and marketing restrictions. Preserve the established Admin-only number report and bounded pagination.
- Refresh report totals and current-page receipts every 10 seconds while visible. Refresh after tab visibility resumes, and stop read polling when leaving Reports. Read refresh never claims or sends a message.
- Reload durable campaign state even when sending returns an error. Do not leave a stale Send Now action or Process Pending button when no work remains. Return a specific preparation-pause error for a failed claim, without automatic retry or raw database details.

Delivery cannot be guaranteed for every recipient: Meta may reject or withhold messages, and Sent remains unconfirmed until a delivery receipt arrives. This release does not retry failed messages, bypass Meta restrictions, change consent, grant new send permission, or contact real recipients as a test.

## Release order

Apply `20261028072609_campaign_delivery_results_and_claim_guard.sql`, deploy the matching `whatsapp-outbox-worker` with its existing authentication settings and unchanged dependencies, then publish the matching Admin artifact. Verify function bodies and the public manual/automatic separation against production first. Keep real sends paused during validation. Production read checks must not invoke a send-capable worker. The user requested these corrections to the existing sending/reporting flow; use only that scope.

Validation: isolated PGlite tests cover receipt accounting, provider-event error projection, fast no-work return with an expensive-validation sentinel, lease-safe claims, access grants and manual/automatic separation. UI tests cover stale-state recovery after worker failure and read-only report polling. Edge tests cover the claim timeout and retain ambiguous-outcome no-retry behavior. Complete regression, artifact checks and exact deployed-source verification are required before closure.
