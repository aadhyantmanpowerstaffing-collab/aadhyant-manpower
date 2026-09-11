'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration044 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '044_vacancy_compensation_accommodation_lifecycle.sql'), 'utf8');
const migration047 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '047_fix_candidate_opportunity_projection_ambiguity.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(root, 'supabase', 'tests', '047_candidate_opportunity_projection_ambiguity_test.sql'), 'utf8');

function functionBlock(sql, name) {
  const start = sql.indexOf(`function public.${name}`);
  assert.notEqual(start, -1, `${name} definition`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} terminator`);
  return sql.slice(start, end + 3);
}

test('Migration 047 replaces only the M044 Candidate opportunity signature without schema changes', () => {
  assert.match(migration047, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(migration047, /\bcommit;\s*$/i);
  assert.equal((migration047.match(/create or replace function public\./gi) || []).length, 1);
  assert.match(migration044, /create function public\.list_candidate_job_opportunities\(p_search text default null,p_limit integer default 25,p_offset integer default 0\)/i);
  assert.match(migration047, /create or replace function public\.list_candidate_job_opportunities\(p_search text default null,p_limit integer default 25,p_offset integer default 0\)/i);
  assert.doesNotMatch(migration047, /\b(?:alter|create|drop)\s+table\b|\b(?:create|drop)\s+policy\b/i);
});

test('Candidate list uses server-derived collision-proof identity and preserves approved opportunity filtering', () => {
  const block = functionBlock(migration047, 'list_candidate_job_opportunities');
  assert.match(block, /security definer set search_path=''/i);
  assert.match(block, /v_candidate_id uuid := \(select private\.current_candidate_portal_id\(\)\)/i);
  assert.match(block, /a\.candidate_id\s*=\s*v_candidate_id/i);
  assert.match(block, /private\.vacancy_is_application_eligible\(r\.id\)/i);
  assert.match(block, /greatest\(r\.required_headcount-r\.filled_positions,0\)/i);
  assert.match(block, /r\.payable_days.*r\.ctc/s);
  assert.match(block, /r\.accommodation_status.*r\.accommodation_charge_basis/s);
  assert.doesNotMatch(block, /\bdeclare[^;]*\bcandidate_id uuid\b/i);
  assert.doesNotMatch(block, /get_public_job_requirements|admin_get_|list_company_portal|list_contractor_portal/i);
});

test('M047 retains the Candidate-only execution boundary and focused rollback checkpoint', () => {
  assert.match(migration047, /revoke all on function public\.list_candidate_job_opportunities\(text,integer,integer\) from public,anon/i);
  assert.match(migration047, /grant execute on function public\.list_candidate_job_opportunities\(text,integer,integer\) to authenticated/i);
  assert.match(migration047, /Migration 047 Candidate opportunity projection security postcondition failed/);
  assert.match(checkpoint, /\\ir 025_candidate_portal_foundation_test\.sql/);
  assert.match(checkpoint, /CHECKPOINT_047_CANDIDATE_OPPORTUNITY_PROJECTION_AMBIGUITY_PASS/);
});
