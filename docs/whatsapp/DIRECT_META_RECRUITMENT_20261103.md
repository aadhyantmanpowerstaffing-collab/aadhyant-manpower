# Direct Meta recruitment updates

Prepared; not deployed or activated.

The existing canonical recruitment outbox can send interview confirmations,
reminders and joining details directly through Meta Cloud API. Existing English
and Hindi Utility templates retain their six positional values. Interview messages
carry the exact Will attend / Cannot attend payloads handled by the direct webhook.
Joining messages add no interactive buttons. No WANotifier Notification URL/key
is required in direct mode. The existing worker URL is retained for compatibility;
there is no second outbox or duplicate notification preparation path.

## Delivery and verification

- Direct mode requires WHATSAPP_RECRUITMENT_UPDATES_ENABLED=true and refuses a
  simultaneously enabled WANOTIFIER_AUTOMATION_ENABLED switch.
- Auth accepts the existing scheduler worker secret or existing canonical single-use database
  wake key verified through its service-only RPC. Callers can supply only
  {"kind":"recruitment_updates"}; sender, recipient and template overrides fail.
- Each run verifies the configured phone's current WABA ownership, the Aadhyant
  app subscription/callback and all six approved Utility template contracts at
  Meta before refreshing readiness, preparing or claiming candidate messages.
- Template verification refresh never enables recruitment or legacy interview
  notifications. Browser roles cannot call it. It requires the exact configured
  sender and a server ownership verification within five minutes.
- Existing canonical claims, contact consent/suppression, schedule revision and
  final provider boundary remain authoritative. Batches contain at most ten
  messages and execute concurrently within their existing leases.
- A real provider message ID is persisted before reporting Sent. Sent is not
  Delivered. Uncertain network/receipt/persistence outcomes require reconciliation;
  there is no second provider fallback or automatic resend.
- The five-minute database scheduler generates a fresh one-time wake nonce and
  uses a separate recruitment verifier with the same five-minute single-use contract.
  No secret appears in cron command text. Separate recruitment wake timestamps
  avoid interfering with the registered-job publication timer. It remains dormant
  while recruitment_updates_enabled=false and never enables a feature itself.

## Release after explicit production approval

1. Merge the reviewed source and apply the two additive migrations in order:
   20261103064104_direct_meta_recruitment_readiness.sql and
   20261103064531_direct_recruitment_scheduler.sql, then the corrective
   20261103071137_direct_recruitment_one_time_wake_fix.sql and
   20261103073032_separate_recruitment_wake_credentials.sql.
2. Deploy wanotifier-outbox-worker and all reviewed runtime dependencies, retaining
   verify_jwt=false because the endpoint authenticates its server wake/worker key.
   Download the runtime and compare exact source. Verify an unauthenticated POST
   is rejected without a claim or real send.
3. For separately approved activation, keep all WANotifier sending switches off;
   set WHATSAPP_RECRUITMENT_UPDATES_ENABLED=true, and set the existing private
   recruitment_updates_enabled=true with interview_notifications_enabled=false.
   Retain the selected existing notification language. The scheduler will refresh
   verification and prepare only canonically eligible consented updates.
4. Inspect pending/eligible counts before activation. A real controlled test send
   needs explicit recipient/purpose approval; never replay historical inbound
   replies or mark synthetic statuses as real provider evidence.
5. Inspect delivery receipts and new signed interview replies for live closure.
   Local/synthetic checks alone do not prove a real Meta delivery.

Rollback: turn off WHATSAPP_RECRUITMENT_UPDATES_ENABLED and set the existing
recruitment_updates_enabled=false. The installed timer becomes dormant. Preserve
all canonical outbox/history; never automatically resend uncertain messages.

Authentication OTP remains a separate blocked activation: Meta rejected creation
of the Authentication template directly on 3 November. This release neither enables
OTP login nor changes candidate account ownership or marketing consent.

Live verification found that the current canonical verifier consumes each nonce
once and requires a fresh request timestamp. The corrective migration preserves
that contract; it does not revert to the historical static Vault key. Focused
checks prove real verifier-style consumption and reject a second use of the nonce.

Registered job alerts now check the current app subscription and callback before
syncing templates or claiming messages. Verified template identity rebinding runs
before complete sync. Recruitment has its own nonce hash and verifier in the
existing dispatch state, so simultaneous job/recruitment wakes cannot invalidate
each other. Both remain single-use and expire after five minutes.
