'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration044 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '044_vacancy_compensation_accommodation_lifecycle.sql'), 'utf8');
const migration045 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '045_fix_vacancy_lifecycle_rpc_ambiguity.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(root, 'supabase', 'tests', '045_vacancy_lifecycle_rpc_ambiguity_test.sql'), 'utf8');

const lifecycleFunctions = [
  'delete_company_portal_draft_vacancy', 'withdraw_company_portal_vacancy', 'close_company_portal_open_vacancy',
  'delete_contractor_portal_draft_vacancy', 'withdraw_contractor_portal_vacancy', 'close_contractor_portal_open_vacancy'
];

function functionBlock(sql, name) {
  const start = sql.indexOf(`function public.${name}`);
  assert.notEqual(start, -1, `${name} definition`);
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, `${name} terminator`);
  return sql.slice(start, end + 3);
}

test('Migration 045 replaces exactly the six M044 lifecycle signatures without schema changes', () => {
  assert.match(migration045, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(migration045, /\bcommit;\s*$/i);
  assert.doesNotMatch(migration045, /\b(?:alter|create|drop)\s+table\b/i);
  assert.doesNotMatch(migration045, /\b(?:create|drop)\s+policy\b/i);
  for (const name of lifecycleFunctions) {
    assert.match(migration045, new RegExp(`create or replace function public\\.${name}\\(p_requirement_id uuid\\)`, 'i'));
    assert.match(migration044, new RegExp(`create function public\\.${name}\\(p_requirement_id uuid\\)`, 'i'));
  }
  assert.equal((migration045.match(/create or replace function public\./gi) || []).length, 6);
});

test('all corrected functions use collision-proof locals and qualified ownership predicates', () => {
  for (const name of lifecycleFunctions) {
    const block = functionBlock(migration045, name);
    assert.match(block, /security definer set search_path=''/i);
    assert.match(block, /v_actor uuid/i);
    assert.match(block, /v_requirement public\.employer_requirements%rowtype/i);
    assert.doesNotMatch(block, /\bdeclare[^;]*\bcompany_id uuid\b/i);
    assert.doesNotMatch(block, /\bdeclare[^;]*\bcontractor_id uuid\b/i);
  }
  for (const name of lifecycleFunctions.slice(0, 3)) {
    const block = functionBlock(migration045, name);
    assert.match(block, /v_company_id/i);
    assert.match(block, /r\.company_id\s*=\s*v_company_id/i);
  }
  for (const name of lifecycleFunctions.slice(3)) {
    const block = functionBlock(migration045, name);
    assert.match(block, /v_contractor_id/i);
    assert.match(block, /rc\.contractor_id\s*=\s*v_contractor_id/i);
  }
});

test('Migration 045 preserves M044 authorization, dependency guards, transitions, and audit behavior', () => {
  for (const name of lifecycleFunctions) {
    const block = functionBlock(migration045, name);
    assert.match(block, /insert into public\.audit_logs/i, name);
  }
  for (const name of ['delete_company_portal_draft_vacancy', 'delete_contractor_portal_draft_vacancy']) {
    assert.match(functionBlock(migration045, name), /private\.vacancy_has_recruitment_dependencies/i, name);
  }
  assert.match(functionBlock(migration045, 'delete_company_portal_draft_vacancy'), /source_type='employer_portal'/);
  assert.match(functionBlock(migration045, 'delete_contractor_portal_draft_vacancy'), /source_type='contractor_portal'/);
  assert.match(functionBlock(migration045, 'withdraw_company_portal_vacancy'), /review_status='closed',requirement_stage='cancelled',requirement_visibility='private'/);
  assert.match(functionBlock(migration045, 'close_company_portal_open_vacancy'), /review_status='closed',requirement_stage='closed',requirement_visibility='private'/);
  assert.match(functionBlock(migration045, 'withdraw_contractor_portal_vacancy'), /submission_status='cancelled'/);
  assert.match(functionBlock(migration045, 'close_contractor_portal_open_vacancy'), /submission_status='closed',assignment_status='completed'/);
  assert.match(migration045, /revoke all on function[\s\S]*from public,anon;/i);
  assert.match(migration045, /grant execute on function[\s\S]*to authenticated;/i);
  assert.match(migration045, /Migration 045 vacancy lifecycle RPC security postcondition failed/);
});

test('focused checkpoint is rollback scoped and covers every lifecycle path, denial, and residue', () => {
  assert.match(checkpoint, /\\set ON_ERROR_STOP on[\s\S]*?\bbegin;/i);
  assert.match(checkpoint, /CHECKPOINT_045_VACANCY_LIFECYCLE_AMBIGUITY_PASS/);
  assert.match(checkpoint, /rollback;[\s\S]*CHECKPOINT_045_ZERO_RESIDUE_PASS/i);
  for (const marker of [
    'Company history-free draft delete failed', 'Company dependency-protected draft delete succeeded',
    'Company pending withdrawal failed', 'Company invalid withdrawal succeeded', 'Company open close failed',
    'Company invalid close succeeded', 'Cross-company lifecycle action succeeded',
    'Contractor history-free draft delete failed', 'Contractor dependency-protected draft delete succeeded',
    'Contractor pending withdrawal failed', 'Contractor invalid withdrawal succeeded',
    'Contractor open close failed', 'Cross-contractor lifecycle action succeeded'
  ]) assert.match(checkpoint, new RegExp(marker));
});
