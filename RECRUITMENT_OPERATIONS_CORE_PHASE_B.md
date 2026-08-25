# Recruitment Operations Core — Phase B

Status: Migrations 033 and 034 are installed on approved NONPROD; checkpoint 034 completed its current executable authorization/smoke gate and rolled back fixtures. The installed read contract is ready for the Phase-B Admin UI; broader funnel/history analytics remain deferred. No production or deployment action is authorized by this document.

The Phase-A audit found that the existing `list_recruitment_requirements` RPC omitted operational metadata, origin, bounded filters, and funnel counts. Migration 033 adds only two read projections over canonical requirements and related canonical records: `admin_list_job_leads(...)` and `admin_get_job_lead_detail(uuid)`.

The list projection is paginated (maximum 100) and server-filters search, stage, source, owner, unassigned, company, contractor origin, attention, and creation date. Funnel semantics use unique canonical applications, linked interviews, selected-equivalent application stages, joined/left joining outcomes, authoritative filled positions, and `max(required_headcount-filled_positions,0)`. Fulfillment percentage is bounded to 0–100 using required headcount as denominator.

Both RPCs are `SECURITY DEFINER`, use `search_path=''`, authorize recruitment staff inside the function, expose no candidate PII or raw WhatsApp data, and grant EXECUTE only to `authenticated`. Detail history is built from a deterministic newest-first subquery capped at 50 events with an explicit summary allowlist. No base-table browser grants or entities are added. Existing Admin direct reads remain until the later UI replacement phase.

Checkpoint 034 is rollback-scoped and covers the deterministic authorization/output smoke path, with separate residue verification completed for its fixtures. It does not claim to be a full analytics/funnel conformance suite; those broader cases are deferred from the frontend-readiness gate. Migration 033 and 034 are installed only on approved NONPROD.

Legacy read coverage: the list projection supplies requirement identity, company, stage, headcount, funnel counts, source, owner, follow-up, age, origin, and operational state; the detail projection supplies the same fields plus safe history. No later UI field is approved to fall back to direct base-table reads.
