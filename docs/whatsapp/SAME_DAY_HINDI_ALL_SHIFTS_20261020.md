# Same-Day Pay Hindi for every shift

User explicitly requested Hindi for all Same-Day Pay alerts and accepted retaining the approved v1 wording “उसी शाम भुगतान”. Use `aadhyant_same_day_pay_hi_v1` for day and overnight shifts without editing the approved template or submitting a new Meta template.

Migration `20261020053644_same_day_hindi_all_shifts.sql` replaces only the existing private variables function. It removes the overnight English exception. Overnight date parameter includes both actual dates; shift duration uses full dated timestamps (20:00–04:00 is 8 hours); the payment parameter includes next-day date and existing immediate-completion wording/time/method. Regular jobs keep existing English v4 behavior. Canonical fingerprint, fresh Meta approval checks, audience consent, STOP, frozen-send validation, worker and outbox are unchanged. Previously frozen English jobs are not re-broadcast or silently rewritten.

Local focused tests: 16/16 passed, covering Hindi selection for day/night, dated payment, positive duration, privacy, cross-date overlap, sender contracts and regular English alerts. Full regression result follows when complete. No production database change or message send has occurred.

Full frontend/database/Edge regression: 620/620 passed, zero failures/skips. Diff check passed. Production remains unchanged, pending the repository's explicit production database approval boundary.
