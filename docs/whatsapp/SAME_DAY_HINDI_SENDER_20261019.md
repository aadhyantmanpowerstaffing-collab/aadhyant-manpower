# Same-Day Pay Hindi sender — 19 October 2026

Prepared, not deployed. User requested wiring the already approved Hindi template into automatic Same-Day Pay alerts. Regular vacancies retain English v4. No provider send or production mutation is part of preparation.

## Behavior

The existing publication capture, frozen audience, canonical outbox, rolling cap, final consent/STOP/location/capacity guards and one-attempt provider boundary remain authoritative. Future Same-Day Pay publications select `aadhyant_same_day_pay_hi_v1` / `hi`; regular publications select v4 / `en`. Missing, changed, stale or unapproved Hindi metadata waits without falling back to English. Existing disabled publications are not replayed. Already frozen old snapshots fail closed after the contract upgrade.

Hindi body parameters: location, role, date, shift time and hours, headcount, whole-shift pay, payment time and method. URL suffix is the canonical vacancy code on the approved Same-Day Pay URL; STOP quick reply binds literal STOP. Supervisor contact details are never parameters. Payment equal to shift end is described as immediate completion payment; legacy agreed times are preserved.

The approved heading still says “उसी शाम भुगतान”; its exact approved body is intentionally preserved. A future wording change requires a new Meta review, separate from this integration.

Migration replaces publication preparation from the latest explicit-choice baseline, retaining `job_alert_choice_allows` as well as `same_day_alert_eligible`. New/renamed helpers are revoked from browser and service roles; only the service sync RPC remains service-callable. Fresh actual Meta synchronization is required before the Hindi catalog becomes compatible.

## Release

After production release authorization: compare live prerequisites, verify no pending sendable queue, deploy the reviewed worker with its existing shared dependencies and JWT setting, apply the upgrade migration, run the canonical scheduler for actual Meta sync, compare function bodies/grants and verify Hindi compatibility without inventing recipients or sending tests. Keep existing enabled configuration and cap intact. No old jobs or dummy records are broadcast.
