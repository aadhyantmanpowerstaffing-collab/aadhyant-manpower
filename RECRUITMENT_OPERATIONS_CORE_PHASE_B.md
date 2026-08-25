# Recruitment Operations Core — Phase B

Status: Migration 033 and checkpoint 034 are prepared locally only. No Phase B UI or NONPROD migration application is authorized by this document.

The Phase-A audit found that the existing `list_recruitment_requirements` RPC omitted operational metadata, origin, bounded filters, and funnel counts. Migration 033 adds only two read projections over canonical requirements and related canonical records: `admin_list_job_leads(...)` and `admin_get_job_lead_detail(uuid)`.

The list projection is paginated (maximum 100) and server-filters search, stage, source, owner, unassigned, company, contractor origin, attention, and creation date. Funnel semantics use unique canonical applications, linked interviews, selected-equivalent application stages, joined/left joining outcomes, authoritative filled positions, and `max(required_headcount-filled_positions,0)`. Fulfillment percentage is bounded to 0–100 using required headcount as denominator.

Both RPCs are `SECURITY DEFINER`, use `search_path=''`, authorize recruitment staff inside the function, expose no candidate PII or raw WhatsApp data, and grant EXECUTE only to `authenticated`. Detail history is built from a deterministic newest-first subquery capped at 50 events with an explicit summary allowlist. No base-table browser grants or entities are added. Existing Admin direct reads remain until the later UI replacement phase.

Checkpoint 034 is rollback-scoped and verifies signatures, grants, internal authorization guards, bounded-history posture, pagination contract, and privacy safeguards. It remains a pre-application gate; runtime fixture validation and post-rollback residue verification require separate NONPROD authorization.
