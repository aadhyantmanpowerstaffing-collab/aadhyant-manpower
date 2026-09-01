const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const migration039 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '039_unified_vacancy_review_workflow.sql'), 'utf8');
const migration040 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '040_fix_contractor_vacancy_submit_ambiguity.sql'), 'utf8');
const migration041 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '041_fix_candidate_opportunity_ambiguity.sql'), 'utf8');
const migration042Path = path.join(root, 'supabase', 'migrations', '042_fix_candidate_apply_ambiguity.sql');
const migration042 = fs.readFileSync(migration042Path, 'utf8');
const compact042 = migration042.replace(/\s+/g, ' ').toLowerCase();
const replacementStart = migration042.indexOf('create or replace function public.apply_candidate_job');
const replacementEnd = migration042.indexOf('revoke all on function public.apply_candidate_job', replacementStart);
const replacement = migration042.slice(replacementStart, replacementEnd);

test('Migration 042 is a narrow transactional Candidate Apply correction', () => {
  assert.equal(path.basename(migration042Path), '042_fix_candidate_apply_ambiguity.sql');
  assert.match(migration042, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(migration042, /\bcommit;\s*$/i);
  assert.match(migration042, /create or replace function public\.apply_candidate_job\(p_requirement_code text\)/i);
  assert.doesNotMatch(migration042, /\balter table\b|\bcreate table\b|\bdrop table\b|\bcreate trigger\b/i);
  const later = fs.readdirSync(path.join(root, 'supabase', 'migrations'))
    .filter((name) => /^(?:043|0[5-9]\d|[1-9]\d{2,})_.*\.sql$/i.test(name));
  assert.deepEqual(later, []);
});

test('Migration 042 removes Candidate Apply ambiguity with its public signature intact', () => {
  assert.match(replacement, /v_candidate_id uuid/i);
  assert.match(replacement, /v_application_id uuid/i);
  assert.match(replacement, /d\.candidate_id=v_candidate_id/i);
  assert.doesNotMatch(replacement, /d\.candidate_id=candidate_id/i);
  assert.match(replacement, /c\.id=v_candidate_id/i);
  assert.match(replacement, /values\(v_candidate_id,v_requirement\.id,'direct','applied'/i);
});

test('Migration 042 retains Candidate ownership, eligibility, duplicate, and audit contracts', () => {
  assert.match(compact042, /private\.current_candidate_portal_id\(\)/);
  assert.match(compact042, /private\.vacancy_is_application_eligible\(r\.id\)/);
  assert.match(compact042, /for share/);
  assert.match(compact042, /you already have an application for this opportunity/);
  assert.match(compact042, /candidate\.application_created/);
  assert.match(compact042, /candidate_portal/);
  assert.doesNotMatch(replacement, /review_feedback|internal_notes|dynamic\s+sql|execute\s+format/i);
});

test('Migration 042 keeps the exact security and fail-closed prerequisites', () => {
  assert.match(compact042, /security definer set search_path=''/);
  assert.match(compact042, /migration 039 candidate apply security baseline drifted/);
  assert.match(compact042, /migration 042 expected pre-correction candidate apply function is not installed/);
  assert.match(compact042, /migration 041 candidate opportunity correction prerequisite is not installed/);
  assert.match(compact042, /revoke all on function public\.apply_candidate_job\(text\) from public,anon/);
  assert.match(compact042, /grant execute on function public\.apply_candidate_job\(text\) to authenticated/);
});

test('Migration 039, 040, and 041 remain immutable prerequisites', () => {
  assert.equal(crypto.createHash('sha256').update(migration039).digest('hex'), '95913e6fbdd16645eee9c769d8ec31ebd081cfeb167ce73c445c26ae4650deb1');
  assert.match(migration040, /rc\.contractor_id=v_contractor_id/);
  assert.match(migration041, /a\.candidate_id=v_candidate_id/);
  assert.match(migration039, /d\.candidate_id=candidate_id/);
});
