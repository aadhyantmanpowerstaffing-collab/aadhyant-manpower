# Immediate registered-alert dispatch — 19 October 2026

Live: user approved production database/worker release at 17:58:08 IST on 19 October 2026. User requested immediate dispatch after AAD-2026-000007 remained queued despite one eligible subscriber. GitHub schedule was last observed at 15:49 IST; vacancy published17:45 IST. The public GitHub timer is unsuitable as the only low-latency dispatch source.

## Change

Reuse the existing worker and outbox. A private publication trigger queues pg_net HTTP POST after the canonical publication transaction commits. Payload is only `{automatic:true}`, with no contact, destination, job override or applicant data. Requests go only to the fixed production worker URL. A five-second coalescing lock avoids bursts; pg_cron checks pending work each minute for missed wake requests and bounded batch draining. No polling request occurs while alerts are paused or no work is pending. Ten-attempt worker bound, rolling daily cap, current Meta sync, job fingerprint, consent/STOP/location/capacity and ambiguous-outcome rules remain unchanged.

Wake authentication uses a dedicated randomly generated64-hex token in Supabase Vault, generated inside the migration without returning it. Private state stores only SHA-256 digest and safe request metadata. Service-only verification RPC checks this credential; worker accepts it only for automatic requests and rejects campaigns or payload overrides. Existing GitHub scheduler credential remains valid for backup. No frontend secrets, credential extraction, direct Graph sends or browser table writes.

pg_net and pg_cron are available but not currently enabled. Migration enables them, installs private state, guarded helpers/trigger and one named minute cron. Publication errors in enqueue are sanitized and retain the job; the timer retries the wake. A DB wake request is not proof of delivery. Existing queued campaigns can be processed by the first minute drain after deployment; specifically AAD-2026-000007 currently has one queued registered recipient. No historical empty/disabled publications are re-enrolled or rebroadcast. Real subscriber consent is never modified.

## Validation and release

Isolated runtime substitutes only the unavailable external extension/Vault network interfaces, executing the actual migration functions and publication trigger. Tests cover fixed payload/endpoint, digest verification, no draft/disabled wake, rollback, coalescing, minute recovery and narrow privileges. Edge tests cover allowed DB wake, denied/invalid keys, automatic-only mode and no recipient/template override. These tests use no external network or real contacts. The hosted extension and post-commit transport require live verification after approval.

After explicit production database/worker release approval: verify source/current queue; save reviewed GitHub source without rewriting unrelated history; deploy worker preserving own authentication and verify_jwt=false; apply migration; verify installed definitions, Vault/queue privileges without reading secrets, cron and safe response status; observe the already-authorized canonical queued alert and its actual outcome. Do not simulate a vacancy or create a test candidate. Confirm delivery separately from provider acceptance.

## Production verification

Worker25 ACTIVE, own authentication and verify_jwt=false retained. Migration immediate_registered_alert_dispatch installed, pg_net/pg_cron enabled, named minute job active. HTTP requests1/2 returned200; canonical AAD-2026-000007 outbox state DELIVERED, attempt_count1, no error. Worker heartbeat12:29:18Z. No new vacancy/recipient/consent created. Full614/614 passed; latest single-use auth/runtime focused12/12 passed.

Hosted pg_net queue is owned by supabase_admin and has PUBLIC ACL. Broad schema ACL revocation was rejected by automatic review; narrower SELECT revoke was permitted but could not remove owner grants. No broad revoke was executed. Corrective migration one_time_automatic_wake_credentials instead replaces persistent transport credentials with random per-request five-minute single-use capabilities: DB verifies then consumes the digest, so no reusable sender credential is placed in transport. Vault secret remains private and is no longer used for requests. Subsequent minute wakes retain the normal consent and send boundaries.
