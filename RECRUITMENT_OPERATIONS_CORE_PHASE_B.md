# Recruitment Operations Core — Phase B

Status: Migration 033 and checkpoint 034 are prepared locally only. No Phase B UI or NONPROD migration application is authorized by this document.

The Phase-A audit found that the existing `list_recruitment_requirements` RPC omitted operational metadata, origin, bounded filters, and funnel counts. Migration 033 adds only two read projections over canonical requirements and related canonical records: `admin_list_job_leads(...)` and `admin_get_job_lead_detail(uuid)`.

The list projection is paginated (maximum 100) and server-filters search, stage, source, owner, unassigned, company, contractor origin, attention, and creation date. Funnel semantics use unique canonical applications, linked interviews, selected-equivalent application stages, joined/left joining outcomes, authoritative filled positions, and `max(required_headcount-filled_positions,0)`. Fulfillment percentage is bounded to 0–100 using required headcount as denominator.

Both RPCs are `SECURITY DEFINER`, use `search_path=''`, authorize recruitment staff inside the function, expose no candidate PII or raw WhatsApp data, and grant EXECUTE only to `authenticated`. No base-table browser grants or entities are added. Existing Admin direct reads remain until the later UI replacement phase.

Checkpoint 034 is static/rollback-scoped and verifies signatures, grants, security posture, pagination contract, and privacy safeguards. Runtime NONPROD application and full fixture validation require separate authorization.
