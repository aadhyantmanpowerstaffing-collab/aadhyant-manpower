# Recruitment Operations Core — Phase C

Status: Candidate Lead backend foundation prepared locally; migration 035 is not applied. No frontend implementation, NONPROD mutation, production action, or push is included.

Candidate Leads reuse `candidates`, `candidate_applications`, `interviews`, `candidate_joinings`, existing Phase-A source/owner/follow-up metadata, and the W7C canonical Application path. Candidate acquisition source is distinct from Application source: acquisition remains immutable on the Candidate, while each Application retains its own canonical source.

Operational state is derived: `inactive`, `joining_pending`, `joined`, `interview`, `applied`, `profile_incomplete`, `awaiting_match`, or `profile_ready`. Profile readiness uses the existing `profile_completion_status`; sensitive Aadhaar, bank, UAN, ESIC, and document fields are not required or exposed.

Migration 035 adds bounded, role-gated `admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)` and `admin_get_candidate_lead_detail(uuid)` projections. List filters are search, acquisition source, owner/unassigned, readiness, derived state, Application stage, attention, creation date range, and bounded limit/offset (maximum 100). Detail returns safe identity/profile fields, acquisition and owner/follow-up metadata, Application/Interview/Joining summaries, attention, and a newest-first history capped at 50 events.

Both functions raise exactly `Recruitment access is required` for unauthorized callers, use `SECURITY DEFINER` with `search_path=''`, and grant EXECUTE only to `authenticated`. No base-table browser grants, duplicate lifecycle, Candidate contact data, sensitive intake, raw WhatsApp payload, or unrestricted notes are added.

Checkpoint 035 verifies signatures, authorization, grants, privacy text, bounded history, retained canonical baselines, and deterministic authorized/unauthorized list/detail RPC calls inside a rollback scope. Independent post-rollback residue verification remains required before NONPROD application. W7C campaign → recipient → INTERESTED → Candidate → Application attribution remains unchanged.
