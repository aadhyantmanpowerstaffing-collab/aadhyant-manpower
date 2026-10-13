# WhatsApp retirement — 13 October 2026

User explicitly requested removal of the whole WhatsApp area, including its data,
after clarification at 15:35–15:36 IST.

## Completed runtime retirement

- Worker version 15 and webhook version 16 now contain only the retired endpoint
  response; both require JWT. No database or Meta call is possible in their code.
- `retire_whatsapp_access` revokes 39 public RPCs and all seven WhatsApp tables from
  PUBLIC, anon, authenticated and service_role. Scheduler remains hard-disabled.
- Candidate profile preference controls and public job subscription/share controls
  are removed. Old subscription URLs show a removal notice and Browse Jobs.
- Admin WhatsApp navigation, campaigns, imports, inbound/replies, attention screens,
  dashboard WhatsApp metrics and shortcuts are removed from the active site.
- Campaign, subscription, preference and import assets are excluded from dist.
  Historical source/tests and canonical empty-capable schema are retained in Git.

## Data purge not completed

Two full-migration attempts and one separate DML request returned
`INVALID_ARGUMENT: Invalid or expired requestState`. Read-only checks confirmed
that the deletion did not run. Access revocation succeeded separately.

Remaining records before purge: 3 contacts, 2 campaigns, 2 recipients, 2 outbound
messages (one queued), 2 inbound messages, 3 delivery events, 8 webhook records and
20 WhatsApp audit records. These records are inactive and cannot be accessed via
the revoked application RPCs. No real message was sent by retirement.

`supabase/production/retire_whatsapp_20261013/purge.sql` is the exact reviewed,
user-authorized transactional deletion. It uses explicit foreign-key order,
rejects an in-flight sender, and does not use CASCADE or delete recruitment rows.
Execute it once through an authorized SQL session after confirming project
`wsuctjhbqiedttfnwjvf`; then verify all seven WhatsApp tables and WhatsApp audit
rows are empty. Connector session/confirmation failure must be resolved before
claiming deletion complete. Do not disguise the DELETE statements to bypass it.

Local regression: 364 tests pass, including actual isolated database deletion,
in-flight refusal, retained Candidate/Requirement/Application records, revoked
RPCs and absence of active frontend controls. Browser QA is unavailable.

## Published frontend verification

- Reviewed source `b17d3925eb437c5163e3344b7401a4740d3c37bd` deployed by Pages
  run `38384004625`; every build/test/upload/deploy step succeeded.
- Deployed artifact digest `760d57c8f3adcf6e1e296e35e70068127381edd9e3dc515dcad53e6c5d6ab59e`.
- Eight live files/digest match local dist, including Admin navigation/bootstrap,
  dashboard, Candidate profile and both jobs/subscription pages.
- Access migration ledger is `20261013102344`, name `retire_whatsapp_access`.
  Candidate enrollment, campaign preparation and service worker claim execution
  are all revoked. Read-only postflight still finds 3 contacts and one queued
  message: deletion remains explicitly incomplete.
- Candidate, Requirement and Application fingerprints matched before the
  attempted purge. Neither blocked purge request deleted recruitment records.
- One-shot publishing workflow is removed after successful publication.

## Follow-up verification — 13 October 2026

The separately authorized pending purge succeeded using the native execute_sql tool. Read-only postcheck confirms all seven WhatsApp tables and WhatsApp audit rows are empty. The new console migration was then installed and template-sync Edge v1 deployed with JWT verification. The worker/webhook remain retired and sender_ready=false. Frontend console release was blocked by automatic approval review pending explicit release approval; production branch remains unchanged. This supersedes the earlier pending-purge status without changing the historical error record.
