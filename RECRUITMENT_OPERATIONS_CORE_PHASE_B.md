# Recruitment Operations Core — Phase B

Status: Migration 033 and checkpoint 034 are prepared locally only. No Phase B UI or NONPROD migration application is authorized by this document.

The Phase-A audit found that the existing `list_recruitment_requirements` RPC omitted operational metadata, origin, bounded filters, and funnel counts. Migration 033 adds only two read projections over canonical requirements and related canonical records: `admin_list_job_leads(...)` and `admin_get_job_lead_detail(uuid)`.

The list projection is paginated (maximum 100) and server-filters search, stage, source, owner, unassigned, company, contractor origin, attention, and creation date. Funnel semantics use unique canonical applications, linked interviews, selected-equivalent application stages, joined/left joining outcomes, authoritative filled positions, and `max(required_headcount-filled_positions,0)`. Fulfillment percentage is bounded to 0–100 using required headcount as denominator.

Both RPCs are `SECURITY DEFINER`, use `search_path=''`, authorize recruitment staff inside the function, expose no candidate PII or raw WhatsApp data, and grant EXECUTE only to `authenticated`. Detail history is built from a deterministic newest-first subquery capped at 50 events with an explicit summary allowlist. No base-table browser grants or entities are added. Existing Admin direct reads remain until the later UI replacement phase.

Checkpoint 034 is rollback-scoped and now declares the complete required runtime case matrix: search/filter combinations, pagination/order, company and contractor origin joins, funnel edge cases, history bounding, list/detail consistency, privacy allowlists, authorization denials, retained baselines, and post-rollback residue verification. The current executable section covers the deterministic smoke path and authorization/output checks; the remaining matrix cases are explicit closure cases for the separately authorized NONPROD run and are not overclaimed as executed locally. Migration 033 remains unapplied.

Legacy read coverage: the list projection supplies requirement identity, company, stage, headcount, funnel counts, source, owner, follow-up, age, origin, and operational state; the detail projection supplies the same fields plus safe history. No later UI field is approved to fall back to direct base-table reads.
