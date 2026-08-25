# Recruitment Operations Core — Phase C

Status: Candidate Lead backend migration 035 is installed and runtime-validated on approved NONPROD. The read-only Candidate Leads frontend is implemented locally; no production action, deployment, push, or database mutation is part of this slice.

Candidate Leads reuse `candidates`, `candidate_applications`, `interviews`, `candidate_joinings`, existing Phase-A source/owner/follow-up metadata, and the W7C canonical Application path. Candidate acquisition source is distinct from Application source: acquisition remains immutable on the Candidate, while each Application retains its own canonical source.

Operational state is derived: `inactive`, `joining_pending`, `joined`, `interview`, `applied`, `profile_incomplete`, `awaiting_match`, or `profile_ready`. Profile readiness uses the existing `profile_completion_status`; sensitive Aadhaar, bank, UAN, ESIC, and document fields are not required or exposed.

Migration 035 adds bounded, role-gated `admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)` and `admin_get_candidate_lead_detail(uuid)` projections. List filters are search, acquisition source, owner/unassigned, readiness, derived state, Application stage, attention, creation date range, and bounded limit/offset (maximum 100). Detail returns safe identity/profile fields, acquisition and owner/follow-up metadata, Application/Interview/Joining summaries, attention, and a newest-first history capped at 50 events.

Both functions raise exactly `Recruitment access is required` for unauthorized callers, use `SECURITY DEFINER` with `search_path=''`, and grant EXECUTE only to `authenticated`. No base-table browser grants, duplicate lifecycle, Candidate contact data, sensitive intake, raw WhatsApp payload, or unrestricted notes are added.

## Candidate Leads frontend

Candidate Leads is integrated into the existing Recruitment Operations workspace and quick actions. It uses only the validated RPC contracts: `admin_list_candidate_leads(...)` for server-filtered bounded list data and `admin_get_candidate_lead_detail(uuid)` for on-demand detail data.

The UI supports search, acquisition source, profile readiness, derived operational state, Application stage, unassigned, attention, creation date range, and bounded pagination. Source options use the approved acquisition vocabulary. An owner selector is intentionally deferred because no approved safe owner-options RPC exists; the frontend performs no direct staff-table read and does not invent owner labels.

The list is read-only and privacy-safe. Detail is fetched only when opened and renders approved profile, source, owner/follow-up, application/interview/joining summaries, attention, and bounded history fields. Candidate phone/email, Aadhaar, bank, UAN, ESIC, documents, Auth data, raw WhatsApp content, and unrestricted notes are not rendered. No direct base-table reads or writes were added.

Existing loading, empty, authorization-error, retry, pagination, responsive table/card, keyboard, and modal-focus behavior is reused. Mutation controls are not added; matching/application mutation remains outside this frontend slice.

Phase-C frontend contract tests cover RPC-only access, exact filter argument mapping, bounded pagination, privacy-safe detail rendering, and the deferred owner-options limitation. Human authenticated NONPROD browser review of Candidate Leads is the next approval boundary; deployment, production action, and any Candidate mutation require separate authorization.

Checkpoint 035 verifies signatures, authorization, grants, privacy text, bounded history, retained canonical baselines, and deterministic authorized/unauthorized list/detail RPC calls inside a rollback scope. Independent post-rollback residue verification remains required before NONPROD application. W7C campaign → recipient → INTERESTED → Candidate → Application attribution remains unchanged.
