# Selected Job Alerts — reviewed implementation

## Agreed behavior

Company, Contractor and Aadhyant continue posting jobs through their existing
canonical workspaces and approval lifecycle. Only published, open, application-
eligible jobs appear in this campaign wizard.

The Admin workflow has four stages: Choose Job, Choose Audience, Preview,
Approve and Queue. Suggested Matches is an advisory subset. All Registered
Candidates permits manual inclusion of a candidate whose qualification, trade,
experience or location differs; mismatch reasons are displayed. Imported Contacts
permits manual outreach without site registration or a separate subscription,
but requires existing, attributed marketing opt-in. Import never grants consent.
Explicit filtered subscriber choices, STOP, ambiguous identity, inactive candidate,
existing application, job closure and cancellation remain authoritative.

All data uses canonical WhatsApp contacts, campaigns, recipients and W7A outbox.
Legacy campaign modules/history remain available via Previous Campaigns. Their
sidebar entries are hidden only after the new RPCs successfully load. An absent
database upgrade leaves the legacy UI accessible and the new workflow disabled.

## Message and sending boundaries

Preview shows the actual job code, role, location, public job link and the masked
selected audience. It deliberately does not invent the wording of the approved
Meta template. Template name, language and version remain an expandable setup
section; these values must match the reviewed sender's actual configuration.
Existing INTERESTED/STOP/provider metadata is preserved. Public View/Apply and
Share behavior remains canonical. No template or provider contract is changed.

Save freezes the exact audience. Approval and Queue require separate clicks.
Retries retain one operation identity and reject changed frozen payloads.
No browser calls Meta. Existing send-time eligibility now recognizes the new
selected_contacts audience mode and still validates campaign/outbox linkage.
The production sender/scheduler remains unchanged and disabled. Neither code
review nor a successful Queue implies delivery.

## Migration and validation

Forward migration: `20261013091247_selected_job_campaigns.sql`.
It refuses a changed send-guard baseline or queued/sending outbound rows, adds one
canonical audience mode and Admin-only RPCs, and updates the existing guard.
It does not delete contacts, history or jobs, and does not edit installed migrations.
All SECURITY DEFINER functions have an empty search_path and authenticated Admin
checks; private functions and anonymous RPC execution are revoked.

Local validation includes an executed four-stage UI flow, advisory nonmatch
selection, unknown-consent denial, filtered-preference suppression, STOP before
approval and at send time, closed jobs, cancellation, existing applications,
operation conflicts, queue idempotency, bounded reads and anonymous privilege
denial. PGlite executes the migration and lifecycle against canonical table
contracts with a stub outbox provider; no real provider call occurs.

Browser visual QA was not performed: the supported control-browser capability is
unavailable. The production upgrade and deployment were explicitly authorized at
2026-10-13 14:59:30 IST. Migration ledger version `20261013093109` is installed
on Aadhyant `wsuctjhbqiedttfnwjvf`; source remains the reviewed migration above.
Pages run `38377334432` completed every build/test/upload/deployment step.
No real campaign was created or sent.

## Production and rollback

Before installation, recheck Aadhyant project wsuctjhbqiedttfnwjvf, current schema,
exact guard hash, backup/recovery and zero queued/sending rows. Require the
repository's explicit production-release authorization for this new migration.
Install the migration then publish the matching allowlisted frontend artifact;
verify deployed digest and anonymous/Admin privilege gates. Sender activation and
any actual test/campaign delivery require separately reviewed scope and recipients.

Rollback the frontend to the preceding release if necessary; keep the additive
schema and existing rows. Do not remove selected_contacts while campaigns of that
mode exist. Use a reviewed forward correction for database issues.

## Production postflight — 13 October 2026

- Published source: `b53ca60da18758093fdf79c017f8f6f27b2e5019`.
- Artifact digest: `876e1c39db717a1fbe38f63701c8ec8c8819b510f37621855dc60d1186a325bc`.
- Live HTML, controller, stylesheet, Admin bootstrap and digest match local dist.
- Read-only Admin RPC validation returned 4 registered candidates, 3 imported
  contacts and no new selected-audience campaigns. Non-admin execution is denied.
- Contacts, candidates, campaigns and outbound row fingerprints match preflight;
  queued/sending remains zero. Existing hard-disabled scheduler is preserved.
- Security advisor flags authenticated SECURITY DEFINER RPCs by design; Admin
  checks, empty search_path and anonymous execute denial were verified live.
- Initial CI attempt lacked the PGlite dependency; corrected publication installed
  locked dependencies before 361 tests. Manual production/staging workflows now
  install the same pinned test dependencies. The one-shot publisher is retired.
