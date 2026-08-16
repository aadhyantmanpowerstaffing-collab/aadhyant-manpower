# Reconstruction R12.1 — Production Defect Investigation and Safe Fix

## 1. Production symptoms

The operator reported that changing application `AAD-2026-000001` from `interested` to `screening` with an internal note did not appear to persist, and that four visually identical Candidate Interest rows appeared in the Admin list.

## 2. Root-cause findings

`candidate_applications` is the Admin query's primary row source. Its embedded Candidate and Requirement relations are many-to-one, and the query does not join `requirement_contractors` or another one-to-many relation. Each returned application therefore represents one `candidate_applications.id`.

The frontend did have a reproducible request race: `loadRecords()` cleared the table before awaiting its query, allowing multiple overlapping dashboard/filter/refresh responses to append after the clear. Stale responses could therefore duplicate a visible row and repaint an older status after a newer filter or refresh. The fix assigns a monotonically increasing load version per Admin dataset; only the latest response may clear and render the table.

The Save handler also treated the absence of a Supabase error as success without checking the RPC's expected `true` result or re-reading the updated application. It now permits one in-flight save, requires `data === true`, then performs an Admin-authorized fresh query by `candidate_applications.id` and compares the persisted status and normalized note before showing success.

These are frontend defects. Migration 013's RPC implementation and signature remain valid, so migration 014 is not required.

## 3. Physical duplicates versus UI duplication

The local reproduction proved UI duplication from overlapping responses and proved that the fixed list renders one row for one application. Partner assignments cannot multiply the query because they are not selected or joined.

The database constraint is `UNIQUE (candidate_id, requirement_id)`. It prevents the same Candidate master and Requirement pair from appearing twice, but visually identical Candidate masters with different Candidate UUIDs would still be separate physical pairs. Production was not accessed. The operator must run the SELECT-only diagnostics below to confirm the physical production state before considering any data remediation.

## 4. Files changed

- `admin/admin.js`: latest-request-wins rendering and verified, single-flight Admin save.
- `RECONSTRUCTION_R12_1_PRODUCTION_DEFECT_FIX.md`: investigation, testing, diagnostics, and rollback guidance.

No Company, Staffing Partner, public, configuration, legal, CNAME, migration, or RLS file changed.

## 5. RPC and database decision

The frontend continues to call only:

`public.admin_update_candidate_application(uuid,text,text)`

with named parameters `p_application_id`, `p_application_status`, and `p_admin_notes`. The identifier is the actual `candidate_applications.id`. Migration 013 updates exactly that row, validates the existing status allowlist and 4,000-character note bound, preserves `applied_at`, and relies on the existing `updated_at` trigger.

No migration 014 was created. Migration 013 was not edited.

## 6. R11 duplicate protection

Migration 012 serializes job-linked submissions by normalized mobile using a transaction advisory lock. Before Candidate creation it checks for an existing application for the same Requirement joined to a Candidate with that normalized mobile. It returns `already_registered`; the unique-violation fallback does the same. The transactional R11 test calls the function twice and asserts one application remains.

The M7 schema also retains `UNIQUE (candidate_id, requirement_id)`. Same Candidate plus a different eligible Requirement remains a legitimate distinct application.

## 7. Security boundaries

The correction adds no data route or permission. Anonymous, non-Admin authenticated, Company, and Staffing Partner access remain governed by existing RLS. Candidate and Requirement details remain read-only in the Admin dialog. Only application status and internal Admin note pass through the narrow Admin RPC.

## 8. Local validation

An isolated Chrome/Selenium harness used the real Admin HTML and JavaScript with a local mock Supabase client; it made no production requests. It deliberately completed two overlapping Candidate Interest requests out of order and confirmed exactly one rendered application. A double-dispatched Save produced exactly one RPC request. A fresh read confirmed `screening` and `R12 production verification`; Screening returned the application and Interested did not. Viewports 360, 390, 768, 1024, and 1440 had no page-level overflow. Unexplained console errors were zero.

The installed Supabase CLI was no longer available after the prior disposable stack cleanup, so database SQL was not rerun. Existing transactional tests 012 and 013 were reviewed: they cover repeated R11 submission, one application, Admin persistence, invalid status/ID/note rejection, immutable Candidate/Requirement/applied-at data, updated-at trigger, unique constraint, R10/R11 preservation, and role/grant boundaries.

## 9. SELECT-only production diagnostics

Run manually in the Supabase SQL Editor. These statements do not modify data.

```sql
-- A. Physical duplicate pairs by the canonical Candidate and Requirement IDs.
select
  candidate_id,
  requirement_id,
  count(*) as application_count,
  array_agg(id order by applied_at, id) as application_ids
from public.candidate_applications
group by candidate_id, requirement_id
having count(*) > 1
order by application_count desc, candidate_id, requirement_id;

-- B/C. Every physical application row displayed for AAD-2026-000001.
select
  a.id,
  a.candidate_id,
  a.requirement_id,
  r.requirement_code,
  c.full_name,
  c.mobile,
  a.application_status,
  a.admin_notes,
  a.applied_at,
  a.updated_at
from public.candidate_applications as a
join public.candidates as c on c.id = a.candidate_id
join public.employer_requirements as r on r.id = a.requirement_id
where r.requirement_code = 'AAD-2026-000001'
order by a.applied_at, a.id;

-- D. Confirm the Candidate/Requirement unique constraint and its definition.
select
  c.conname as constraint_name,
  c.contype as constraint_type,
  pg_get_constraintdef(c.oid, true) as constraint_definition,
  c.convalidated as is_validated
from pg_constraint as c
where c.conrelid = 'public.candidate_applications'::regclass
  and c.contype = 'u'
order by c.conname;

-- E. Prove the number of physical applications versus repeated display identity.
select
  r.requirement_code,
  c.mobile,
  lower(btrim(c.full_name)) as normalized_candidate_name,
  count(*) as physical_application_rows,
  count(distinct a.id) as distinct_application_ids,
  count(distinct a.candidate_id) as distinct_candidate_ids,
  array_agg(a.id order by a.applied_at, a.id) as application_ids,
  array_agg(distinct a.candidate_id) as candidate_ids
from public.candidate_applications as a
join public.candidates as c on c.id = a.candidate_id
join public.employer_requirements as r on r.id = a.requirement_id
where r.requirement_code = 'AAD-2026-000001'
group by r.requirement_code, c.mobile, lower(btrim(c.full_name))
order by c.mobile, normalized_candidate_name;
```

Expected: query A returns no rows; query B/C returns the actual physical rows; the unique constraint includes `(candidate_id, requirement_id)` and is validated; query E reports one distinct application ID for the affected Candidate identity if the production symptom was UI-only.

Stop and do not remediate data if query A returns rows, the unique constraint is missing/unvalidated, query B/C shows multiple Candidate IDs, or query E reports multiple physical application IDs. Preserve the returned IDs for separate operator review.

## 10. Manual production remediation guidance

No deletion or merge SQL is provided because production row identity has not been diagnosed. If diagnostics show one physical application, deploy only the reviewed frontend correction. If they show multiple physical applications with distinct Candidate IDs, first determine which Candidate masters are genuinely the same person and whether related interviews, joining, assignment, or audit records exist. Any merge/deletion requires a separately reviewed, backup-first, record-specific remediation plan and explicit operator approval.

## 11. Rollback

R12.1 is frontend-only. Roll back only the R12.1 changes in `admin/admin.js`: remove the per-dataset load-version guard and the enhanced save verification/single-flight handling. No SQL rollback applies, and migrations 012/013 must remain unchanged.

## 12. Known limitations and operator steps

- The production physical row count remains operator-verifiable only; Codex did not access production.
- The mock browser validates frontend ordering and persistence handling, while the prior transactional SQL suites validate the real RPC/database behavior.
- Browser caches/CDN propagation should be cleared or versioned during the eventual deployment so the corrected Admin JavaScript is loaded.

Recommended steps: review this diff, run the SELECT-only diagnostics, confirm one physical application or escalate any real duplicates, deploy the frontend correction through the normal reviewed process, then verify one Save and a fresh reload in production without creating additional applications.
