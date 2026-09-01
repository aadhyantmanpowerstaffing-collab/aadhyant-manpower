const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const migration039Path = path.join(root, 'supabase', 'migrations', '039_unified_vacancy_review_workflow.sql');
const migration040Path = path.join(root, 'supabase', 'migrations', '040_fix_contractor_vacancy_submit_ambiguity.sql');
const migration041Path = path.join(root, 'supabase', 'migrations', '041_fix_candidate_opportunity_ambiguity.sql');
const migration039 = fs.readFileSync(migration039Path, 'utf8');
const migration040 = fs.readFileSync(migration040Path, 'utf8');
const migration041 = fs.readFileSync(migration041Path, 'utf8');
const compact041 = migration041.replace(/\s+/g, ' ').toLowerCase();
const replacementStart = migration041.indexOf('create or replace function public.list_candidate_job_opportunities');
const replacementEnd = migration041.indexOf('revoke all on function public.list_candidate_job_opportunities', replacementStart);
const replacement = migration041.slice(replacementStart, replacementEnd);

test('Migration 041 is a narrow transactional Candidate opportunity correction', () => {
  assert.equal(path.basename(migration041Path), '041_fix_candidate_opportunity_ambiguity.sql');
  assert.match(migration041, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(migration041, /\bcommit;\s*$/i);
  assert.match(migration041, /create or replace function public\.list_candidate_job_opportunities\(/i);
  assert.doesNotMatch(migration041, /\balter table\b|\bcreate table\b|\bdrop table\b|\bcreate trigger\b/i);
  const later = fs.readdirSync(path.join(root, 'supabase', 'migrations'))
    .filter((name) => /^(?:042|0[5-9]\d|[1-9]\d{2,})_.*\.sql$/i.test(name));
  assert.deepEqual(later, ['042_fix_candidate_apply_ambiguity.sql']);
});

test('Migration 041 removes the Candidate identifier collision without changing the signature', () => {
  assert.match(replacement, /v_candidate_id uuid/i);
  assert.match(replacement, /a\.candidate_id=v_candidate_id/i);
  assert.doesNotMatch(replacement, /a\.candidate_id=candidate_id/i);
  assert.match(replacement, /a\.requirement_id=r\.id/i);
  assert.match(replacement, /v_term text/i);
});

test('Migration 041 keeps the exact approved/public/capacity eligibility boundary', () => {
  assert.match(compact041, /private\.vacancy_is_application_eligible\(r\.id\)/);
  assert.match(compact041, /greatest\(r\.required_headcount-r\.filled_positions,0\)/);
  assert.doesNotMatch(replacement, /review_feedback|audit_logs|internal_notes/i);
  assert.doesNotMatch(compact041, /dynamic\s+sql|execute\s+format/i);
});

test('Migration 041 preserves Candidate-only execution and fails closed on pre-state drift', () => {
  assert.match(compact041, /security definer set search_path=''/);
  assert.match(compact041, /migration 039 candidate opportunity security baseline drifted/);
  assert.match(compact041, /migration 041 expected pre-correction candidate opportunity function is not installed/);
  assert.match(compact041, /migration 040 contractor correction prerequisite is not installed/);
  assert.match(compact041, /revoke all on function public\.list_candidate_job_opportunities[\s\S]*from public,anon/);
  assert.match(compact041, /grant execute on function public\.list_candidate_job_opportunities[\s\S]*to authenticated/);
});

test('Migration 039 and Migration 040 remain immutable correction prerequisites', () => {
  assert.equal(crypto.createHash('sha256').update(migration039).digest('hex'), '95913e6fbdd16645eee9c769d8ec31ebd081cfeb167ce73c445c26ae4650deb1');
  assert.match(migration040, /rc\.contractor_id=v_contractor_id/);
  assert.match(migration039, /a\.candidate_id=candidate_id/);
});
