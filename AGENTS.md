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
- Verified HEAD at handoff: `ff87bf3706306181bc4b9587e7b5216d80dfadd8`
- At handoff, the local branch is ahead of `origin/web-platform-development` by 4 and behind by 0.
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
- W7C has not started. Do not start or implement W7C without separate milestone authorization.

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
- The current migration range is through 028.
- Do not create migration 029 or later unless the authorized milestone explicitly requires it.
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
- W7C will own the `INTERESTED` response and application workflow later.
- Do not implement W7C while finishing or validating W7B.
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
- W7B campaign and recipient tables contain zero rows after runtime validation.
- Retained W7A live data must not be deleted, truncated, overwritten, or treated as disposable test data.

Any hash mismatch must fail closed. Determine whether the file changed through an authorized, reviewed commit before updating any recorded or guarded hash.

## Next approval boundary

W7B is technically ready for final closure review. The next action is human review of the complete local-ahead range and, only if separately authorized, a normal non-force push followed by remote-HEAD verification. Do not deploy, contact real users, enable a real WhatsApp send, or begin W7C/a materially new milestone without explicit authorization.
