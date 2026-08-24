# Aadhyant Web Platform — Autonomous Continuation Guide

## Scope and precedence

This file governs autonomous work in the repository root and all descendant paths unless a more specific `AGENTS.md` exists below them. Continue the existing Aadhyant Web Platform; do not treat this repository as a greenfield project.

## Project continuity

- Continue from the current repository, verified Git history, migrations, tests, and documentation.
- Never recreate the platform from scratch, rewrite established architecture, or invent a parallel implementation.
- Never replace canonical tables, workflows, security boundaries, or messaging systems with duplicates.
- Before feature work, read the relevant current documentation, migrations, tests, and Git history (including the commits in the current ahead range).
- Preserve compatibility with completed work and retained live data.

## Verified continuation point

- Branch: `web-platform-development`
- Verified remote-closed W7B HEAD at the W7C handoff: `ff2d436c321a7d2cde5dac1bd11b2b85fe4a041a`
- At the W7C handoff, local and `origin/web-platform-development` were even.
- At handoff, the tracked worktree and index are clean.
- `supabase/.temp/` is expected untracked local Supabase CLI metadata. Never commit it.
- Docker Desktop, Supabase CLI, and Codex CLI are available.

Treat the branch, HEAD, ahead/behind state, and cleanliness above as a handoff checkpoint, not an instruction to discard later authorized commits. If current state differs, inspect history and establish why; fail closed before any NONPROD mutation when the required approved state cannot be proven.

## Current milestone state

- W2–W6 were completed previously.
- W7A practical closure was completed and deployed to NONPROD.
- W7B implementation and dedicated NONPROD database/runtime validation are complete.
- Migration 028 is installed on NONPROD. At the start of the closure run its objects were already present and empty, so the migration's fail-closed preflight correctly prevented replay.
- Corrected checkpoint 031 and W7A regressions 029/030 pass with client exit 0; W7A Edge tests pass 20/20 and the frontend baseline passes 138/138.
- W7C implementation and dedicated NONPROD runtime validation are complete. It preserves W7A/W7B and creates or reuses only canonical Candidate Applications.
- Migration 029 is installed; checkpoint 032 and W7A/W7B regressions pass with zero checkpoint residue.
- The reviewed `whatsapp-webhook` source from W7C closure HEAD `eed8fe73ceadcad3f7669193441005466737c17e` is deployed only to approved NONPROD as version 5, ACTIVE, with `verify_jwt=false`; the downloaded runtime source matches the authorized files exactly.
- Signed deployed-endpoint validation proves W7A durable ingress/orchestration, exact W7B correlation, W7C canonical Application creation, safe audit/history, and exact replay idempotency without a Graph API call or WhatsApp send.
- Full real Meta inbound validation remains deferred: the single final operator-controlled test-number message at `2026-08-24 13:25:42 IST` produced no observable Meta-to-Edge invocation, webhook row, or inbound row through `13:32:47 IST`. This reproduces the documented Meta test-number ingress limitation and is not evidence of an application defect.
- The separately authorized Post-W7C Admin Product Phase is implemented and locally regression-validated. It adds a grouped responsive Admin shell, composite safe-projection dashboard, stronger canonical recruitment workspaces, polished W7B campaigns, and W7A Incoming/Replies plus Failed/Attention views without changing schema, Edge, Meta, messaging, or production state. Focused Admin tests pass 90/90, the complete frontend suite passes 153/153, and the unchanged Edge suite passes 21/21. See `POST_W7C_ADMIN_PRODUCT_PHASE.md`.

## Canonical architecture

Reuse the existing canonical systems and tables:

- `employer_requirements`
- `candidates`
- `candidate_applications`
- `interviews`
- `joinings`
- `whatsapp_contacts`
- `whatsapp_webhook_events`
- `whatsapp_inbound_messages`
- `whatsapp_outbound_messages`
- `whatsapp_message_events`
- existing W7A RPC, outbox, and security contracts

Do not create duplicate recruitment, contact, application, campaign-delivery, or outbox systems. Extend the established architecture with upgrade-safe changes only.

## Autonomous permissions

Within an already authorized milestone or task, the agent may autonomously:

- inspect the repository and Git history;
- edit project files;
- run local focused and regression tests;
- run static, SQL, and security scans;
- use Docker, Supabase CLI, and Codex CLI;
- independently self-review and fix discovered defects;
- rerun tests until passing;
- create focused commits; and
- operate against the approved dedicated NONPROD environment only when every guard and identity gate passes.

For an authorized task, work through inspect, implement, test, self-review, fix, retest, and commit without seeking approval for every minor technical decision. These permissions do not override the hard approval boundaries below.

## Hard approval boundaries

Stop and request explicit human approval before:

- any production deployment;
- any production database mutation;
- force push, rebase, reset, or any operation that rewrites shared history;
- any destructive database operation;
- any real bulk WhatsApp campaign or send;
- contacting real candidates;
- changing real Meta production configuration;
- deleting real or live data; or
- beginning a materially new milestone that has not already been authorized.

Also stop for a missing credential, manual login or OTP, an ambiguous business decision, a production or real-user action, a destructive action, or materially new scope.

## NONPROD safety gate

Before every NONPROD database mutation, complete all of the following in order:

1. Verify the current branch.
2. Verify the current HEAD.
3. Verify the tracked worktree and index state.
4. Run the repository's staging guard.
5. Verify the guard's approved HEAD.
6. Verify the approved migration aggregate.
7. Verify the exact identity of the dedicated approved NONPROD project/database.
8. Run and pass the TLS/read-only identity gate before any write-capable action.
9. Confirm the production denylist is clear and the target cannot be production.

Fail closed on any mismatch, ambiguity, missing evidence, or guard failure. Do not substitute a project name, URL, cached CLI linkage, or assumption for the exact identity checks. Never mutate an environment other than the approved dedicated NONPROD target.

## Migration rules

- Never edit an already-installed migration.
- Use upgrade-safe corrective migrations for fixes to installed behavior.
- Preserve exact migration numbering and ordering.
- The current authorized migration range is through 029 for W7C.
- Do not create migration 030 or later unless an upgrade-safe W7C correction is required or a later milestone is explicitly authorized.
- Recalculate and verify hashes after any authorized migration or checkpoint change.
- Extend the staging guard only after independent static review.

## Testing and validation

For meaningful changes, run the checks relevant to the changed surface:

- focused tests;
- full frontend regression;
- relevant W7A and W7B tests;
- SQL, static, and security scans;
- `git diff --check`;
- the applicable runtime checkpoint; and
- rollback and zero-residue verification for synthetic NONPROD fixtures.

Do not weaken, remove, bypass, or rewrite assertions merely to obtain a PASS. Diagnose failures, fix the underlying defect within authorized scope, and rerun the appropriate chain.

## Security and privacy invariants

- RLS and RPC boundaries are authoritative.
- Do not add browser direct-table writes unless the existing architecture explicitly permits them.
- Every `SECURITY DEFINER` function must set `search_path = ''`.
- Do not use dynamic SQL unless it has been explicitly reviewed for the authorized change.
- Never log, print, expose, or commit secrets, access tokens, Meta App Secrets, verify tokens, service-role keys, credentials, or sensitive connection material.
- Do not expose raw Aadhaar, bank, UAN, ESIC, document, or other private candidate data in WhatsApp messages or Admin projections.
- Mask phone and contact data in Admin views.

## WhatsApp invariants and milestone boundary

- Reuse the W7A outbox; never bypass it with a direct Graph API send.
- Recheck consent and suppression server-side at the time required by the established contracts.
- Keep marketing consent and transactional consent distinct.
- W7B owns campaign, matching, and queue behavior.
- W7C owns exact `INTERESTED` response correlation and canonical application creation/reuse.
- Do not expand W7C into Candidate creation, application-stage advancement, interview/reminder automation, live sending, or a later chatbot/inbox milestone.
- A validation fixture must not become a real candidate contact or real bulk send.

## Git workflow

- Prefer small, focused commits that preserve a reviewable history.
- Never force push unless separately and explicitly authorized.
- Before a normal push, review the full local-ahead range and confirm it contains only intended commits.
- After a push, verify the remote HEAD explicitly.
- Never commit `supabase/.temp/`.
- Do not reset or overwrite unrelated user work. Investigate unexpected worktree changes before proceeding.

## Current verified W7B facts

- Migration 028: `supabase/migrations/028_whatsapp_vacancy_campaigns.sql`
- Migration 028 SHA-256: `54c7e66a45703a95261aa9fee96f92474255a54de20d3a48ae6fc4efff2454ec`
- Checkpoint 031: `supabase/tests/031_whatsapp_vacancy_campaigns_test.sql`
- Checkpoint 031 SHA-256: `3c72239de0d9941e9115f1297fd841073a3c5857b441e87d777d94f673e3cfda`
- Aggregate schema plus migrations 007–028 SHA-256: `a8c7f62cd9c0bec2a0a77556d5d1b635edd54379b6f6e12caec39daf4738b965`
- The staging guard has been extended through migration 028.
- Migration 028 is installed in approved NONPROD. Its verified tables are present with RLS and zero browser grants.
- W7B campaign and recipient tables contained zero rows after the dedicated W7B/W7C database runtime checkpoints. The later controlled W7C Edge validation retained exactly one completed synthetic campaign/recipient correlation fixture; it has no queued/sending campaign and no queued/claimed/sending outbound row.
- Retained W7A live data must not be deleted, truncated, overwritten, or treated as disposable test data.

## Current verified W7C facts

- Migration 029: `supabase/migrations/029_whatsapp_interested_applications.sql`
- Migration 029 SHA-256: `a1214b6beea3e575d4594edef8adacbf34b53ee2da20e52761fdefd3a50ecd1e`
- Checkpoint 032: `supabase/tests/032_whatsapp_interested_applications_test.sql`
- Checkpoint 032 SHA-256: `4fddf27c4246737c80bf5fc3243d0b0052b37a67b65ce98c844eb63027b3989f`
- Aggregate schema plus migrations 007–029 SHA-256: `7429888214faca7524c1e119674684ab8765052bb36701dd82b22353de07ac46`
- The staging guard is extended through exactly migration 029.
- Migration 029 is installed on approved NONPROD with the reviewed catalog, RLS, and service-role-only RPC posture.
- Checkpoint 032 passes with `ON_ERROR_STOP=1`, rollback, client exit 0, and zero residue.
- W7A checkpoints 029/030 and W7B checkpoint 031 pass unchanged; Edge tests pass 21/21, focused W7B tests 17/17, and frontend tests 138/138.
- Before Edge validation, Candidate, Application, Requirement, and retained W7A count/digests matched the captured pre-state; W7B tables and retained W7C links were empty.
- Controlled deployed-endpoint validation retained one explicitly synthetic auth/Admin, Requirement, Candidate, resolved contact, completed campaign, queued recipient linked to an already-delivered synthetic outbox row, webhook, processed inbound, canonical Application, stage-history, and safe audit chain. Exact replay retained one logical row at every W7A/W7C boundary. Existing W7A fingerprints remain unchanged, interviews/joinings remain empty, and all sendable campaign/outbound counts remain zero.
- The final real Meta test-number action produced no observable ingress. No retry was performed, no real Candidate was contacted, no automated or Graph message was sent, Meta configuration was unchanged, and production was not contacted.

Any hash mismatch must fail closed. Determine whether the file changed through an authorized, reviewed commit before updating any recorded or guarded hash.

## Post-W7C Admin Product closure and next approval boundary

W7C remains technically and operationally closed on dedicated NONPROD with the Meta test-number ingress limitation above. The authorized Admin Product Phase is complete locally and changes no backend or runtime architecture. Its exact W7C trace/conversion and Audit views remain deferred because current safe Admin projections do not expose those links. Full real Meta inbound proof remains deferred and must not be inferred from signed endpoint validation. Stop before any deployment, Edge or Meta change, another real-message test, production mutation, real-candidate contact, synthetic-residue deletion, or new backend milestone without explicit human authorization.
