const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const migration039Path = path.join(root, 'supabase', 'migrations', '039_unified_vacancy_review_workflow.sql');
const migration040Path = path.join(root, 'supabase', 'migrations', '040_fix_contractor_vacancy_submit_ambiguity.sql');
const migration039 = fs.readFileSync(migration039Path, 'utf8');
const migration040 = fs.readFileSync(migration040Path, 'utf8');
const compact040 = migration040.replace(/\s+/g, ' ').toLowerCase();
const replacementStart = migration040.indexOf('create or replace function public.manage_contractor_portal_vacancy');
const replacementEnd = migration040.indexOf('revoke all on function public.manage_contractor_portal_vacancy', replacementStart);
const replacement = migration040.slice(replacementStart, replacementEnd);
const reviewReplacementStart = migration040.indexOf('create or replace function public.review_contractor_vacancy');
const reviewReplacementEnd = migration040.indexOf('revoke all on function public.review_contractor_vacancy', reviewReplacementStart);
const reviewReplacement = migration040.slice(reviewReplacementStart, reviewReplacementEnd);

test('Migration 040 is a narrow transactional replacement of the Contractor vacancy RPC', () => {
  assert.equal(path.basename(migration040Path), '040_fix_contractor_vacancy_submit_ambiguity.sql');
  assert.match(migration040, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(migration040, /\bcommit;\s*$/i);
  assert.match(migration040, /create or replace function public\.manage_contractor_portal_vacancy\(/i);
  assert.doesNotMatch(migration040, /\balter table\b|\bcreate table\b|\bdrop table\b/i);
  assert.match(migration040, /create or replace function public\.review_contractor_vacancy\(/i);
  const later = fs.readdirSync(path.join(root, 'supabase', 'migrations'))
    .filter((name) => /^(?:041|042|0[5-9]\d|[1-9]\d{2,})_.*\.sql$/i.test(name));
  assert.deepEqual(later, [
    '041_fix_candidate_opportunity_ambiguity.sql',
    '042_fix_candidate_apply_ambiguity.sql',
  ]);
});

test('Migration 040 removes the ambiguous identifier while keeping the public signature stable', () => {
  const signature = 'manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)';
  assert.match(migration040, new RegExp(signature.replace(/[()]/g, '\\$&')));
  assert.match(replacement, /v_contractor_id uuid/i);
  assert.match(replacement, /rc\.contractor_id=v_contractor_id/i);
  assert.doesNotMatch(replacement, /rc\.contractor_id=contractor_id/i);
  assert.match(replacement, /where r\.id=v_requirement\.id/i);
  assert.match(replacement, /where rc\.id=v_link\.id/i);
  assert.doesNotMatch(replacement, /if v_action in \('create','create_draft','create_and_submit','update','update_draft','resubmit'\) then/i);
  assert.match(replacement, /elsif v_action in \('submit','resubmit'\) then/i);
  assert.match(reviewReplacement, /rc\.requirement_id=v_requirement\.id/i);
  assert.doesNotMatch(reviewReplacement, /where requirement_id=r\.id/i);
  assert.match(reviewReplacement, /where rc\.id=v_link\.id/i);
});

test('Migration 040 preserves the Contractor review and publication boundary', () => {
  for (const marker of [
    "'create','create_draft','create_and_submit'",
    "'submit','resubmit'",
    "'draft','correction_required'",
    "submission_status='submitted'",
    "requirement_stage='draft',requirement_visibility='private'",
    "'contractor_portal'",
    "'contractor_vacancy_'||v_action",
  ]) assert.match(compact040, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(compact040, /requirement_visibility='public'/);
  assert.doesNotMatch(compact040, /dynamic\s+sql|execute\s+format/i);
});

test('Migration 040 retains the security-definer grant boundary and fails closed on unexpected pre-state', () => {
  assert.match(compact040, /security definer set search_path=''/);
  assert.match(compact040, /migration 039 contractor vacancy security baseline drifted/);
  assert.match(compact040, /migration 040 expected pre-correction contractor function is not installed/);
  assert.match(compact040, /revoke all on function public\.manage_contractor_portal_vacancy[\s\S]*from public,anon/);
  assert.match(compact040, /grant execute on function public\.manage_contractor_portal_vacancy[\s\S]*to authenticated/);
  assert.match(compact040, /revoke all on function public\.review_contractor_vacancy[\s\S]*from public,anon/);
  assert.match(compact040, /grant execute on function public\.review_contractor_vacancy[\s\S]*to authenticated/);
  assert.match(compact040, /has_function_privilege\('anon'/);
});

test('Migration 039 remains immutable while Migration 040 contains the corrective replacement', () => {
  const sha256 = crypto.createHash('sha256').update(migration039).digest('hex');
  assert.equal(sha256, '95913e6fbdd16645eee9c769d8ec31ebd081cfeb167ce73c445c26ae4650deb1');
  assert.match(migration039, /rc\.contractor_id=contractor_id/);
});
