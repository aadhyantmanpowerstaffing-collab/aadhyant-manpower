'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration044 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '044_vacancy_compensation_accommodation_lifecycle.sql'), 'utf8');
const migration046 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '046_fix_owner_vacancy_projection_ambiguity.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(root, 'supabase', 'tests', '046_owner_vacancy_projection_ambiguity_test.sql'), 'utf8');

const ownerFunctions = [
  ['list_company_portal_requirements', 'text,text,integer,integer', 'v_company_id', 'r\\.company_id\\s*=\\s*v_company_id'],
  ['get_company_portal_requirement', 'uuid', 'v_company_id', 'r\\.company_id\\s*=\\s*v_company_id'],
  ['list_contractor_portal_vacancies', 'text,text,integer,integer', 'v_contractor_id', 'rc\\.contractor_id\\s*=\\s*v_contractor_id'],
  ['get_contractor_portal_vacancy', 'uuid', 'v_contractor_id', 'rc\\.contractor_id\\s*=\\s*v_contractor_id']
];

function functionBlock(sql, name) {
  const start = sql.indexOf(`function public.${name}`);
  assert.notEqual(start, -1, `${name} definition`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} terminator`);
  return sql.slice(start, end + 3);
}

test('Migration 046 replaces only the four M044 owner projection/list/detail signatures', () => {
  assert.match(migration046, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(migration046, /\bcommit;\s*$/i);
  assert.equal((migration046.match(/create or replace function public\./gi) || []).length, 4);
  assert.doesNotMatch(migration046, /\b(?:alter|create|drop)\s+table\b/i);
  assert.doesNotMatch(migration046, /\b(?:create|drop)\s+policy\b/i);
  for (const [name, signature] of ownerFunctions) {
    assert.match(migration044, new RegExp(`(?:create|create or replace) function public\\.${name}\\(`, 'i'));
    assert.match(migration046, new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
    assert.match(migration046, new RegExp(`public\\.${name}\\(${signature}\\)`, 'i'));
  }
});

test('all corrected owner projections use collision-proof locals and qualified tenant predicates', () => {
  for (const [name, , ownerLocal, predicate] of ownerFunctions) {
    const block = functionBlock(migration046, name);
    assert.match(block, /security definer set search_path=''/i);
    assert.match(block, new RegExp(`\\b${ownerLocal}\\b`));
    assert.match(block, new RegExp(predicate, 'i'));
    assert.doesNotMatch(block, /\bdeclare[^;]*\bcompany_id uuid\b/i);
    assert.doesNotMatch(block, /\bdeclare[^;]*\bcontractor_id uuid\b/i);
  }
  assert.match(functionBlock(migration046, 'list_company_portal_requirements'), /v_needle|v_stage/i);
  assert.match(functionBlock(migration046, 'list_contractor_portal_vacancies'), /v_needle|v_filter_status/i);
});

test('Migration 046 preserves compensation, accommodation, owner projections, and browser execution boundaries', () => {
  for (const [name] of ownerFunctions) {
    const block = functionBlock(migration046, name);
    assert.match(block, /payable_days|vacancy_compensation_projection/i, name);
    assert.match(block, /accommodation_status|vacancy_accommodation_projection/i, name);
  }
  assert.match(migration046, /revoke all on function[\s\S]*from public,anon;/i);
  assert.match(migration046, /grant execute on function[\s\S]*to authenticated;/i);
  assert.match(migration046, /Migration 046 owner vacancy projection security postcondition failed/);
  assert.doesNotMatch(migration046, /list_candidate_job_opportunities|get_public_job_requirements|admin_get_/i);
});

test('focused M046 runtime checkpoint reuses rollback-scoped Company and Contractor tenant fixtures', () => {
  assert.match(checkpoint, /\\ir 019_company_portal_foundation_test\.sql/);
  assert.match(checkpoint, /\\ir 022_contractor_portal_foundation_test\.sql/);
  assert.match(checkpoint, /CHECKPOINT_046_OWNER_VACANCY_PROJECTION_AMBIGUITY_PASS/);
  assert.match(checkpoint, /M046 owner vacancy projection anon execution granted/);
});
