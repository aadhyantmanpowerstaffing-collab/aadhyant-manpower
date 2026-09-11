'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration044 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '044_vacancy_compensation_accommodation_lifecycle.sql'), 'utf8');
const migration048 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '048_fix_vacancy_submit_managed_record_shape.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(root, 'supabase', 'tests', '048_contractor_managed_record_shape_test.sql'), 'utf8');

const signature = 'text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text';

function functionBlock(sql) {
  const start = sql.indexOf('function public.manage_contractor_portal_vacancy(');
  assert.notEqual(start, -1, 'extended Contractor management definition');
  const end = sql.indexOf('$$;', start);
  assert.notEqual(end, -1, 'extended Contractor management terminator');
  return sql.slice(start, end + 3);
}

test('Migration 048 replaces only the M044 extended Contractor management overload', () => {
  assert.match(migration048, /^-- Correct the M044 Contractor compensation wrapper record-shape regression\.[\s\S]*?\bbegin;/i);
  assert.match(migration048, /\bcommit;\s*$/i);
  assert.equal((migration048.match(/create or replace function public\./gi) || []).length, 1);
  assert.match(migration044, /create function public\.manage_contractor_portal_vacancy\(/i);
  assert.match(migration048, /create or replace function public\.manage_contractor_portal_vacancy\(/i);
  assert.match(migration048, new RegExp(`manage_contractor_portal_vacancy\\(${signature.replaceAll(',', '\\s*,\\s*')}\\)`, 'i'));
  assert.doesNotMatch(migration048, /\b(?:alter|create|drop)\s+table\b|\b(?:create|drop)\s+policy\b/i);
  assert.doesNotMatch(migration048, /manage_company_portal_requirement|manage_company_portal_vacancy/i);
});

test('M048 keeps the managed RPC result and updated requirement row as distinct record shapes', () => {
  const block = functionBlock(migration048);
  assert.match(block, /security definer set search_path=''/i);
  assert.match(block, /managed record;/i);
  assert.match(block, /updated_requirement public\.employer_requirements%rowtype;/i);
  assert.match(block, /select \* into managed from public\.manage_contractor_portal_vacancy\(/i);
  assert.match(block, /where r\.id\s*=\s*managed\.id returning r\.\* into updated_requirement;/i);
  assert.match(block, /managed\.submission_status/i);
  assert.match(block, /coalesce\(updated_requirement\.updated_at,managed\.updated_at\)/i);
  assert.doesNotMatch(block, /returning \* into managed/i);
  assert.doesNotMatch(block, /returning r\.\* into managed/i);
});

test('M048 preserves the M044 structured-field actions and authenticated-only boundary', () => {
  const block = functionBlock(migration048);
  assert.match(block, /action in \('create','create_draft','create_and_submit','update','update_draft'\)/i);
  assert.match(block, /payable_days=p_payable_days[\s\S]*?accommodation_charge_basis=p_accommodation_charge_basis/i);
  assert.match(migration048, new RegExp(`revoke all on function public\\.manage_contractor_portal_vacancy\\(${signature.replaceAll(',', '\\s*,\\s*')}\\) from public,anon`, 'i'));
  assert.match(migration048, new RegExp(`grant execute on function public\\.manage_contractor_portal_vacancy\\(${signature.replaceAll(',', '\\s*,\\s*')}\\) to authenticated`, 'i'));
  assert.match(migration048, /Migration 048 Contractor management RPC security or record-shape postcondition failed/);
});

test('the focused M048 checkpoint is rollback scoped and names every affected action path', () => {
  assert.match(checkpoint, /\\set ON_ERROR_STOP on[\s\S]*?\bbegin;/i);
  assert.match(checkpoint, /rollback;/i);
  for (const marker of [
    'CHECKPOINT_048_CONTRACTOR_CREATE_PASS',
    'CHECKPOINT_048_CONTRACTOR_CREATE_AND_SUBMIT_PASS',
    'CHECKPOINT_048_CONTRACTOR_UPDATE_PASS',
    'CHECKPOINT_048_CONTRACTOR_SUBMIT_PASS',
    'CHECKPOINT_048_CONTRACTOR_RESUBMIT_PASS',
    'CHECKPOINT_048_ZERO_RESIDUE_PASS'
  ]) assert.match(checkpoint, new RegExp(marker));
});
