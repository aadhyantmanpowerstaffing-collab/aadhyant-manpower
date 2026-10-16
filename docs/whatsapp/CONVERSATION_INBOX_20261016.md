# WhatsApp Inbox and Sent — prepared design and implementation

## Live release — 16 October 2026

Explicit production approval received at 20:30:47 IST. Reviewed native source `769effb08db99e97793a20df66066eae030ac7dc`, tree `8d872acee875edcb08d0a5043542623d7ff0787c`, promoted without force. Migration installed as `20261016150132 / whatsapp_conversation_inbox`; source SHA256 `b84eac6639376d1927928073d44a2675745c5447d18fc7a228a8ae06e3c1cab0`.

Pages run `38920707845` succeeded: build `117039601945`, deploy `117040451742`; CI 553/553 tests passed, zero failures/skips, artifact boundary and manifest passed. Live Admin console JS matches SHA256 `6923372c77ca49deb5c2800e37f2fd34e72795040526c340c60f299ba45c1b6c`. Signed-in Admin verified default Inbox, incoming contact list/unread counts, combined contact history, Sent folder and delivery-status filters using retained records. Private read table RLS, zero direct browser/service grants and all three Admin RPC ACLs/search paths verified. Advisors show expected private RLS/no-policy and three additional guarded authenticated-definer endpoints; no anonymous grants added. Official remediation references remain https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy and https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable .

Counts unchanged: contacts=5, outbound=39, applications=6, personal read markers=0. No real message sent or existing unread state cleared. Employer Post Job replies remain enabled; candidate automatic alerts remain disabled. No Edge or Meta configuration changed. Verified Admin URL: `https://aadhyantmanpower.in/admin/?release=20261016-conversation-inbox#whatsappConsole`. Earlier prepared/not-live statements below are historical and superseded by this release entry.

User authorized the operator Inbox/Sent design on 16 October 2026 at 20:22 IST. This is a new prepared release; it has **not** been applied to production.

WhatsApp Manager opens Inbox by default. Inbox shows contacts with incoming messages; Sent shows contacts with outgoing messages, including pending and failed deliveries. Select a masked contact to open the combined incoming/outgoing history. Search uses up to the last four mobile digits. Both folders support Unread and Needs Attention; Sent also filters queued/sending/sent/delivered/read/failed. List pages contain 50 contacts; history pages contain 100 events, ordered by canonical record creation time and ID. Sent ordering uses outgoing activity only. Manual Refresh updates history; there is no background polling or new scheduler.

Unread is personal to the signed-in Admin. Only an explicit “Mark Visible Messages as Read” action records the selected incoming IDs. A new message arriving afterwards remains unread, and one operator does not clear another operator's unread state. These markers never change WhatsApp provider delivery/read receipts, processing results, consent or subscriptions. Needs Attention is derived from failed records, processing errors or unclassified unprocessed inbound records; it is not an assignment/resolution workflow.

## Canonical data and privacy

The existing inbound/outbound/contact tables remain authoritative. No duplicate message store or provider API exists here. The sole new private table stores operator/message read markers, with RLS and all browser/service grants revoked. Three bounded SECURITY DEFINER RPCs validate existing `admin_console_access() IS TRUE`, empty search paths, offsets/filter values, message ownership and current auth.uid(). Only authenticated role execute is granted; Company, Contractor and Candidate users fail the Admin guard. No direct client table access is introduced.

History intentionally displays **activity summaries**, not an invented exact transcript. Current ingress deliberately does not persist raw incoming text. Unknown messages display that original text is unavailable. Registration answers, arbitrary action payloads, private form tokens/URLs, raw provider IDs, template variable objects and sensitive error payloads are not projected. Outgoing rows show purpose summary, template name, canonical job code, delivery state/times and a fixed safe failure explanation. The full public Post Job URL can be shown. All text renders through DOM text nodes. Contact names/numbers remain masked.

This release does not add a compose/send box, provider read receipts, attachments, automatic replies, message retention, contact permissions, Meta configuration or outbound retries. Existing Templates/Campaigns/Automatic Alerts/Reports remain available. Campaign Reports retain their existing detailed workflow.

## Verification and release

Focused PostgreSQL runtime tests verify multi-operator markers, idempotence, late-arriving unread records, cross-contact rejection, bounded stable history pagination, private-data exclusions, all-folder filters and Admin/ACL denials. DOM behavior tests verify Inbox/Sent navigation, combined history, safe text rendering, exact visible-ID read mutations, error rendering and no sending RPCs. Existing console tests remain unchanged.

A standalone synthetic preview is included as `tests/fixtures/inbox-design-preview.html`; it runs the actual console JS/CSS against fixed in-memory demonstration records, uses no network or credentials and performs no real send. This preview is not included in the production artifact allowlist.

Production requires explicit approval under root AGENTS.md (“Stop and request explicit human approval before … any production deployment; any production database mutation”). After approval: confirm current shared source, promote reviewed tree without forcing, apply `20261016145231_whatsapp_conversation_inbox.sql`, publish the existing Pages workflow, verify authenticated access/ACLs, source hashes and Inbox/Sent with retained records. Do not enable candidate alerts, change employer Post Job flags or send a real message. No webhook deployment is required.

Official reviewed reference: https://supabase.com/docs/guides/database/functions and https://supabase.com/docs/guides/database/postgres/row-level-security . Privileged RPCs are needed to preserve canonical tables' browser-denied access while serving only bounded Admin projections.

Final validation: full regression **553/553 passed**, zero failures/skips. After the final fail-closed Admin guard refinement, all six new runtime/DOM tests passed again. JS syntax and git diff checks passed. Production packaging excludes the synthetic preview through the existing test-fixture boundary. No live mutation, publication or send occurred. Managed graphical browser QA was unavailable; no local browser server was started.
