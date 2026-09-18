const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const sql = fs.readFileSync(path.join(root, 'supabase', 'production', 'pre_m050_production_reconciliation.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(root, 'supabase', 'tests', 'pre_m050_production_reconciliation_test.sql'), 'utf8');
const model = fs.readFileSync(path.join(root, 'supabase', 'tests', 'pre_m050_production_reconciliation_model.sql'), 'utf8');
const runbook = fs.readFileSync(path.join(root, 'PRODUCTION_PRE_M050_RECONCILIATION_RUNBOOK.md'), 'utf8');

test('pre-M050 reconciler is a guarded manual transaction, not a numbered migration', () => {
  assert.match(sql, /^-- Manual, production-specific reconciliation/m);
  assert.match(sql, /\bbegin;[\s\S]*\bcommit;\s*$/i);
  assert.match(sql, /app\.pre_m050_reconciliation_approved/);
  assert.match(sql, /coalesce\(current_setting\('app\.pre_m050_reconciliation_approved', true\), ''\) <> 'yes'/);
  assert.match(sql, /M049 or M050 evidence is already present/);
  assert.doesNotMatch(sql, /\b[a-z0-9]{20}\b/i, 'manual artifact must not embed a project reference');
});

test('pre-M050 reconciler encodes only the approved generic two-row mapping', () => {
  assert.match(sql, /count\(\*\) from public\.employer_requirements\) <> 2/);
  assert.match(sql, /status='in_progress' and requirement_stage='open'/);
  assert.match(sql, /status='new' and requirement_stage='draft'/);
  assert.match(sql, /set review_status='approved', review_feedback=null/);
  assert.match(sql, /set review_status='draft', review_feedback=null/);
  assert.match(sql, /M039 or M044 collision: expected schema additions are not wholly absent/);
  assert.match(sql, /Contractor predecessor collision: expected audited detail\/review contracts are unavailable/);
  assert.doesNotMatch(sql, new RegExp(['AAD', '2026'].join('-'), 'i'));
});

test('pre-M050 reconciler retains joining validation and removes only audited direct writes', () => {
  assert.match(sql, /private\.validate_candidate_joining_dates\(\)/);
  assert.match(sql, /Actual joining date requires Joined or Left status/);
  assert.match(sql, /candidate_joinings_validate_dates/);
  assert.match(sql, /revoke insert, update on public\.candidate_applications from authenticated/);
  assert.match(sql, /revoke insert, update on public\.candidate_joinings from authenticated/);
  assert.match(sql, /drop policy "M7 admins create applications"/);
  assert.match(sql, /drop policy "M7 admins update joinings"/);
  assert.doesNotMatch(sql, /grant (all|insert|update) on (table )?public\.candidate_(applications|joinings) to authenticated/i);
});

test('review, Company, compensation, projection, and M049 prerequisite contracts are guarded', () => {
  for (const marker of [
    'private.vacancy_is_application_eligible',
    'candidate_applications_require_approved_public_vacancy',
    'public.admin_approve_and_publish_vacancy',
    'public.admin_list_vacancy_reviews',
    'public.admin_get_vacancy_review_detail',
    'public.list_company_portal_vacancy_reviews',
    'public.review_contractor_vacancy',
    'public.admin_request_vacancy_correction',
    'public.admin_reject_vacancy',
    'public.manage_company_portal_requirement',
    'private.vacancy_compensation_projection',
    'private.vacancy_accommodation_projection',
    'public.list_company_portal_requirements',
    'public.get_company_portal_requirement',
    'public.get_contractor_portal_vacancy',
    'public.list_candidate_job_opportunities',
    'public.delete_company_portal_draft_vacancy',
    'public.close_contractor_portal_open_vacancy',
    'contractor_vacancy_submission_requests',
    'vacancy_candidate_benefits',
  ]) assert.match(sql, new RegExp(marker.replace(/[.()]/g, '\\$&')));
  assert.match(sql, /revoke all on function private\.vacancy_compensation_projection/);
  assert.match(sql, /has_table_privilege\('authenticated','public\.candidate_applications','insert,update'\)/);
  assert.match(sql, /M049\/M050 must remain absent/);
});

test('M045 audit and the audited Contractor predecessor upgrade are exact and fail closed', () => {
  for (const action of [
    'company_vacancy_draft_deleted', 'company_vacancy_withdrawn', 'company_vacancy_closed',
    'contractor_vacancy_draft_deleted', 'contractor_vacancy_withdrawn', 'contractor_vacancy_closed',
  ]) assert.match(sql, new RegExp(`'${action}'`));
  assert.match(sql, /insert into public\.audit_logs/);
  assert.match(sql, /Contractor list collision: expected audited predecessor fingerprint is unavailable/);
  assert.match(sql, /md5\(pg_get_function_result\(p\.oid\)\)='ba95d431fdb82d0ecf6f301e194d3fd3'/);
  assert.match(sql, /drop function public\.list_contractor_portal_vacancies\(text,text,integer,integer\)/);
  assert.match(sql, /accommodation_charge_basis text,submission_status text/);
  assert.match(sql, /not has_function_privilege\('anon',p\.oid,'execute'\)/);
  for (const semantic of ['rc\\.contractor_id\\s*=\\s*v_contractor_id', 'contractor_submission', 'r\\.payable_days', 'r\\.accommodation_charge_basis']) {
    assert.match(sql, new RegExp(semantic));
  }
  assert.match(checkpoint, /CHECKPOINT_PRE_M050_M045_AUDIT/);
});

test('M039 reviewer and M046 owner projections retain their reviewed callable shapes', () => {
  assert.match(sql, /admin_list_vacancy_reviews\(p_review_status text default 'pending_review',p_source_type text default null,p_limit integer default 50,p_offset integer default 0\)/);
  assert.match(sql, /requirement_id uuid,requirement_code text,source_type text,normalized_review_status text,contractor_submission_status text/);
  assert.match(sql, /admin_get_vacancy_review_detail\(p_requirement_id uuid\)[\s\S]*returns jsonb/);
  assert.match(sql, /list_company_portal_vacancy_reviews\(p_search text default null,p_review_status text default null,p_limit integer default 25,p_offset integer default 0\)/);
  assert.match(sql, /get_company_portal_requirement\(p_requirement_id uuid\)[\s\S]*returns jsonb/);
  assert.match(sql, /get_contractor_portal_vacancy\(p_requirement_id uuid\)[\s\S]*returns jsonb/);
  for (const name of ['admin_list_vacancy_reviews', 'admin_get_vacancy_review_detail', 'list_company_portal_vacancy_reviews', 'get_company_portal_requirement', 'get_contractor_portal_vacancy']) {
    assert.match(sql, new RegExp(`revoke all on function [^;]*${name}|revoke all on function ${name}`));
  }
  assert.doesNotMatch(sql, /grant execute on function private\.[^\n]+ to authenticated/i);
});

test('checkpoint and runbook keep reconciliation controlled and separate from M049/M050', () => {
  assert.match(checkpoint, /\bbegin;[\s\S]*rollback;\s*$/i);
  assert.match(checkpoint, /\\ir \.\.\/production\/pre_m050_production_reconciliation\.sql/);
  assert.match(checkpoint, /CHECKPOINT_PRE_M050_M049_PRECONDITION/);
  assert.match(runbook, /not an automatic\s+migration/i);
  assert.match(runbook, /apply M049 unchanged/i);
  assert.match(runbook, /apply M050 unchanged/i);
  assert.doesNotMatch(runbook, /\b[a-z0-9]{20}\b/i, 'runbook must not embed a project reference');
});

test('disposable model is synthetic, pre-M049/M050, and reproduces the audited predecessor posture', () => {
  assert.match(model, /Disposable-only model/);
  assert.match(model, /create policy "M7 admins create applications"/);
  assert.match(model, /grant select, insert, update on public\.candidate_applications/);
  assert.match(model, /create function public\.list_contractor_portal_vacancies/);
  assert.doesNotMatch(model, /create function private\.current_candidate_portal_id/);
  assert.match(model, /returns table\(id uuid,requirement_code text,client_name text,job_role text,job_location text,required_headcount integer,submission_status text/);
  assert.match(model, /create function public\.get_contractor_portal_vacancy/);
  assert.match(model, /create function public\.review_contractor_vacancy/);
  assert.match(model, /create table public\.audit_logs/);
  assert.match(model, /grant execute on function public\.register_candidate_requirement_interest[\s\S]* to anon/);
  assert.doesNotMatch(model, /contractor_vacancy_submission_requests|vacancy_candidate_benefits/);
  assert.doesNotMatch(model, /\b[a-z0-9]{20}\b/i, 'model must not embed a hosted project reference');
});

test('reconciler accepts only the audited absent Candidate helper and exact Contractor predecessors', () => {
  assert.match(sql, /Candidate identity collision: expected canonical helper is absent/);
  assert.match(sql, /Candidate identity prerequisite columns are unavailable/);
  assert.match(sql, /create function private\.current_candidate_portal_id\(\)/);
  assert.match(sql, /md5\(pg_get_function_result\(p\.oid\)\)='cd8a1292080b231b3e9a85d440b02023'/);
  assert.match(sql, /md5\(pg_get_function_result\(p\.oid\)\)='d3f5ca5331c9a9e2169965e5c7da7bda'/);
  assert.match(sql, /coalesce\(array_to_string\(p\.proconfig, ','\),''\) = 'search_path=""'/);
  assert.doesNotMatch(sql, /proconfig, ','\),'?'\) like '%search_path=%'/);
  assert.match(sql, /create or replace function public\.get_contractor_portal_vacancy/);
  assert.match(sql, /create or replace function public\.review_contractor_vacancy/);
  assert.match(checkpoint, /CHECKPOINT_PRE_M050_CANDIDATE_IDENTITY_OR_CONTRACTOR_LIST_UPGRADE/);
});
