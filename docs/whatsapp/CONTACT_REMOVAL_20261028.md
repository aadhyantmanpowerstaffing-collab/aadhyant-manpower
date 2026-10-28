# Contact removal from manual bulk selection

Problem: Delete Selected only permanently removed unused imports. Subscribed contacts were kept, so an administrator could not clear old contacts from a new manual campaign's audience.

The existing confirmation now calls `admin_console_archive_contacts(uuid[])`. It marks exactly the reviewed selection (1–500 IDs, deduplicated) with `console_archived_at`. Contacts and manual campaign audiences filter this marker before pagination. The selected-contact eligibility guard rejects archived IDs, including stale selections. The result scrolls into view and reports how many contacts were removed.

Contact identity, candidate links, permission and STOP state, inbound/outbound messages, campaign history, and automatic subscription choices are retained. No automatic subscription, existing queued campaign, or outbox state is modified. Imports do not automatically clear the marker. No contact is removed until the administrator confirms their selection in the updated UI.

Security: existing Admin permission check plus non-null authenticated identity; empty search path; explicit authenticated RPC grant, no anonymous/public/service-role grant; count-only audit metadata. Existing permanent-delete RPC remains unchanged for compatibility. No direct browser table writes, new sends, or provider changes.

## Release boundary

Production release explicitly approved by the user on 28 October 2026. PR #19 merged as `5b8eb46cf2a847d73651926729f9f0b41c3d7666`. Production migration installed as `20261028055943 / archive_console_contacts` in verified Aadhyant project `wsuctjhbqiedttfnwjvf`. Pages run `40641425474` succeeded (build `122660223166`, deploy `122661136411`), including full regression. Published Admin JavaScript matches the reviewed source byte-for-byte, SHA-256 `0d08f15616cc8efc52e8de070c16922ca1c414135bc564eb79517046f47e4612`. Local regression: 723/723 passed; focused checks: 11/11 passed. Production read-only verification retained 491 contacts, 14 inbound and 498 outbound records, with zero contacts archived; RLS remains enabled, authenticated RPC grant is present, anonymous execution is denied. Security advisor's authenticated SECURITY DEFINER warning is expected for this Admin-guarded RPC. No real contact was archived and no message was sent during release. Authenticated UI confirmation by the operator remains pending; no real contacts were used as smoke-test fixtures.

Deployment order: Apply `20261028055133_archive_console_contacts.sql` before deploying the updated frontend. Use the normal verified production release process; do not replay earlier migrations. Smoke-test with an explicitly disposable contact, cancel confirmation first, then confirm and verify its absence from Contacts and manual audiences and the retention of history. Do not delete or archive real contacts as a deployment smoke test.

Rollback: redeploy the previous frontend first. The old RPC remains available. Leave the additional column and RPC installed while preparing a reviewed corrective migration if rollback of filtering is required. Do not delete retained contact identities or history. A future explicit restore action can clear the archive marker after Admin authorization; this release provides no automatic restoration or consent changes.
