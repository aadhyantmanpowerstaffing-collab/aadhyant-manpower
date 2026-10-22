# Hindi job alerts in manual campaigns

The approved `aadhyant_registered_job_alert_hi_v1` was synced but incompatible: the selected-contact campaign path only built the legacy two-value payload. This change validates the exact Hindi body and URL/STOP buttons on each Meta sync, prepares the canonical ten-field summary for operator-selected campaigns, and supports that payload in the existing outbox worker. The UI obtains its Hindi preview from an Admin-only RPC and refreshes its script cache version.

Existing automatic regular-job alerts keep English v4; existing Same-Day Pay alerts keep their established Hindi contract. Installation creates no campaign, recipient or send. Campaign approval and queue actions remain separate operator actions. Current job terms, consent, STOP, template freshness, schedule and sender ownership are rechecked before delivery. Changes to public job terms invalidate a frozen Hindi payload.

Release order: deploy the worker with its current shared dependencies and existing JWT setting, apply `20261022090957_hindi_registered_manual_campaigns.sql`, sync actual Meta metadata, publish the frontend, and verify the fresh approved Hindi option and canonical preview. Do not use a real candidate send for validation.

Focused SQL/worker/UI tests cover exact template matching, repeated sync, unsupported components, ten ordered parameters, URL/STOP, permission checks, unapproved queue rejection, modified job terms and late STOP. The complete frontend regression and production artifact checks must pass before release.
