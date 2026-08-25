# Recruitment Operations Core — Phase A

Status: repository implementation complete locally; migration 030 and checkpoint 033 are prepared but **not applied** to NONPROD.

Phase A adds bounded source vocabulary, ownership metadata, next-action/follow-up fields, and derived Admin attention around the canonical Requirements, Candidates, and Contractors. It does not create a recruiter-task table or duplicate any recruitment entity.

## Source and privacy contract

The approved source vocabulary is stored in `recruitment_source_vocabulary`. First-attribution timestamps are retained; source corrections are Admin-only, reason-required, and written to `audit_logs`. Source references/detail are bounded and must not contain raw phone numbers, WhatsApp text, payloads, or sensitive Candidate data. Existing Application source values remain backward-compatible, including `direct`, `contractor`, `admin`, `whatsapp`, `campus`, and `referral`.

## Ownership and attention

Requirements, Candidates, and Contractors receive staff-owner, assignment, next-action, and follow-up fields. Owner validation requires an active staff profile with a recruitment role. `admin_list_recruitment_attention` derives unassigned, incomplete, aging, approval, follow-up, and joining-pending attention without creating tasks or changing lifecycle state.

## Security

All mutation and projection functions are bounded `SECURITY DEFINER` functions with `search_path=''`, explicit authenticated EXECUTE grants, and server-side staff authorization. Browser metadata UPDATE grants are revoked. The source vocabulary table has RLS enabled and no browser table grants.

## Artifacts

- Migration: `supabase/migrations/030_recruitment_operations_core.sql`
- Checkpoint: `supabase/tests/033_recruitment_operations_core_test.sql`
- Migration SHA-256: `6bad0ad8601ab99ab3662b2467526474f2230795ccbf8c6f10c60ba2ce954d03`
- Checkpoint SHA-256: `7ea6e9f6f394419876989164a261ec88ed32dfc54718bc9bf7685c447d57cfaa`
- Schema plus migrations 007–030 aggregate SHA-256: `4cd6ae97a160f36d543f989de64f54a8df9d9c00fb9336dbb41535161fdde722`

The checkpoint is rollback-scoped and must be run only after a separately authorized NONPROD migration application. No production migration or deployment is implied.
