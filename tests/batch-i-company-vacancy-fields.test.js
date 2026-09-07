const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration039 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '039_unified_vacancy_review_workflow.sql'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'supabase', 'migrations', '043_extend_company_vacancy_fields.sql'), 'utf8');
const compact = sql.replace(/\s+/g, ' ').toLowerCase();

test('Migration 043 is a transactional RPC-only extension over existing canonical fields', () => {
  assert.match(sql, /^-- Batch 2 corrective migration:[\s\S]*?\bbegin;/i);
  assert.match(sql, /\bcommit;\s*$/i);
  assert.match(sql, /column_name='iti_trade'/);
  assert.match(sql, /column_name='expected_joining_date'/);
  assert.doesNotMatch(sql, /\balter table\b|\badd column\b|\bcreate table\b|\bcreate trigger\b/i);
});

test('Migration 043 forwards iti_trade and expected_joining_date to the canonical Company implementation', () => {
  assert.match(sql, /p_iti_trade text,p_experience_requirement text/);
  assert.match(sql, /p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text/);
  assert.match(sql, /p_qualification,p_iti_trade,p_experience_requirement/);
  assert.match(sql, /p_interview_date,p_expected_joining_date,p_additional_notes/);
  assert.match(migration039, /iti_trade=nullif\(btrim\(p_iti_trade\),''\)/);
  assert.match(migration039, /expected_joining_date=p_expected_joining_date/);
});

test('Migration 043 keeps old callers on the legacy wrapper without overload ambiguity', () => {
  assert.match(sql, /This overload deliberately has no defaults/);
  assert.match(sql, /create or replace function public\.manage_company_portal_requirement/);
  assert.match(sql, /p_qualification,null,p_experience_requirement/);
  assert.match(sql, /p_interview_location,p_interview_date,null,p_additional_notes/);
  assert.match(compact, /extended company vacancy rpc already exists/);
});

test('Migration 043 retains the protected authenticated-only execution boundary', () => {
  assert.match(compact, /security definer set search_path=''/);
  assert.match(sql, /revoke all on function public\.manage_company_portal_requirement[\s\S]*from public,anon/);
  assert.match(sql, /grant execute on function public\.manage_company_portal_requirement[\s\S]*to authenticated/);
  assert.match(compact, /company vacancy rpc security postcondition failed/);
  assert.doesNotMatch(compact, /dynamic\s+sql|execute\s+format/);
});

test('Migration 039 remains immutable and continues to provide safe Company/Admin projections', () => {
  assert.equal(crypto.createHash('sha256').update(migration039).digest('hex'), '95913e6fbdd16645eee9c769d8ec31ebd081cfeb167ce73c445c26ae4650deb1');
  assert.match(migration039, /'iti_trade',r\.iti_trade/);
  assert.match(migration039, /'expected_joining_date',r\.expected_joining_date/);
});
