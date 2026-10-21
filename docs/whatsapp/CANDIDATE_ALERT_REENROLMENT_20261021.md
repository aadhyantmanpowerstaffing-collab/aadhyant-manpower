# Candidate WhatsApp alert re-enrolment

A Candidate with a resolved contact suppressed by an inbound `user_stop` can give fresh consent from My Profile. Ordinary Save Profile still cannot clear STOP.

Choose Yes for at least one of Job Alerts / Same-Day Pay Alerts, click Restart WhatsApp Alerts, review the frozen choices and location, check the initially unchecked permission box, then Confirm and Restart Alerts. Cancel does not write anything. Other profile changes still require Save Profile.

The new authenticated-only `restart_candidate_whatsapp_alerts` RPC derives its Candidate from the existing active portal access helper. It locks the Candidate, mobile advisory lock and canonical contact, checks unique identity and exact ownership, and only clears `user_stop` attributed to `whatsapp_inbound`. Administrative suppression and ambiguous/blocked/mismatched contacts remain blocked. It returns transactional status to unknown, without granting transactional permission. It uses the canonical preference writer for independent alert choices and stamps fresh policy-versioned marketing consent.

A safe audit event retains the previous STOP reason, confirmed choices, operation/contact IDs and a location digest. Replaying the same confirmed operation makes no additional consent change. A later STOP prevents that operation from being replayed to restart messages; a new confirmation is required. Ordinary STOP and all sender consent, matching, template and quota checks remain in place. No sender or webhook changes, no messages sent by deployment, and no historical outbox replay.

The existing preferences RPC now adds `can_restart_alerts` without changing its existing fields. The UI checks the same Candidate session before the restart and after it before displaying fresh preference state. A failed request can be retried with the same operation, or the Candidate can reopen My Profile to inspect state.

Validation: isolated PGlite tests cover explicit consent, independent choices, missing confirmation, malformed inputs, idempotent replay, subsequent STOP, administrative suppression, identity mismatch, missing Candidate access and narrow grants. VM UI tests cover unchecked confirmation, cancellation, frozen choices and changed-session rejection. Synthetic fixtures do not use live users or provider sends.
