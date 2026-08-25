# Recruitment Operations Core — Phase A

Status: Phase A migration 030 is installed on approved NONPROD; migration 031 is prepared locally as the narrowly scoped RPC grant correction and is **not applied**. Checkpoint 033 remains pending successful rerun after migration 031.

Phase A adds bounded source vocabulary, ownership metadata, next-action/follow-up fields, and derived Admin attention around the canonical Requirements, Candidates, and Contractors. It does not create a recruiter-task table or duplicate any recruitment entity.

## Source and privacy contract

The approved source vocabulary is stored in `recruitment_source_vocabulary`. First-attribution timestamps are retained; source corrections are Admin-only, reason-required, and written to `audit_logs`. Source references/detail are bounded and must not contain raw phone numbers, WhatsApp text, payloads, or sensitive Candidate data. Existing Application source values remain backward-compatible, including `direct`, `contractor`, `admin`, `whatsapp`, `campus`, and `referral`.

## Ownership and attention

Requirements, Candidates, and Contractors receive staff-owner, assignment, next-action, and follow-up fields. Owner validation requires an active staff profile with a recruitment role; assignment and source corrections are audited with bounded old/new metadata. A follow-up due timestamp is optional, may be in the past, and requires a non-empty bounded next action when present. `lost_reason` is bounded and only valid on the existing terminal requirement stages; a trigger clears it when a requirement reopens. `admin_list_recruitment_attention` derives unassigned, incomplete, aging, approval, follow-up, interview, joining-pending, and contractor-participation attention without creating tasks or changing lifecycle state.

SLA defaults are centralized in `private.phase_a_sla()` (2-day application aging, 72-hour upcoming-interview window, 7-day contractor no-progress threshold). These are server-owned defaults, not frontend timing rules.

## Security

All mutation and projection functions are bounded `SECURITY DEFINER` functions with `search_path=''`, explicit authenticated EXECUTE grants, and server-side staff authorization. Browser metadata UPDATE grants are revoked. The source vocabulary table has RLS enabled and no browser table grants.

## Artifacts

- Migration: `supabase/migrations/030_recruitment_operations_core.sql`
- Checkpoint: `supabase/tests/033_recruitment_operations_core_test.sql`
- Migration SHA-256: `2f5c13fee45428d6034b6ed9ebfde46fb09f3c6776d0d6ce0e47fda27a0e7552`
- Checkpoint SHA-256: `42d3cabe26fda0ec6e6ce892fc4d7515e3188d72a8a4d98dc5bccf997e88c230`
- Schema plus migrations 007–030 aggregate SHA-256: `3b7ca82abed1e2d50129657b766c6f5c77ca7ac825d5ff7e62c2155b0d14628f`

The checkpoint is rollback-scoped and must be run only after a separately authorized NONPROD migration application. No production migration or deployment is implied.

Checkpoint 033 now creates deterministic Auth/staff, Requirement, Candidate, Application, Interview, Joining and Contractor fixtures inside one transaction and calls the Phase A source, owner, follow-up and attention RPCs with exact expected denials and audit assertions. It remains rollback-scoped; the file itself has not been executed against NONPROD, so runtime outcomes and post-rollback fingerprints are still pending separate migration-application authorization. Replay/idempotency is covered by repeated assignment expectations; true multi-session race testing is not claimed.
