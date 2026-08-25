const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '033_job_lead_read_projections.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'tests', '034_job_lead_read_projections_test.sql'), 'utf8');
const doc = fs.readFileSync(path.join(__dirname, '..', 'RECRUITMENT_OPERATIONS_CORE_PHASE_B.md'), 'utf8');

test('Phase B migration is additive and defines only bounded Job Lead projections', () => {
  assert.match(migration, /create function public\.admin_list_job_leads/);
  assert.match(migration, /create function public\.admin_get_job_lead_detail/);
  assert.match(migration, /least\(greatest\(coalesce\(p_limit,25\),1\),100\)/);
  assert.doesNotMatch(migration, /create table public\.(?:job_leads|recruiter_tasks|crm)/i);
  assert.doesNotMatch(migration, /grant (?:select|update|insert|delete) on public\./i);
});

test('Phase B projections are security and privacy bounded', () => {
  assert.match(migration, /security definer set search_path = ''/i);
  assert.match(migration, /revoke all on function public\.admin_list_job_leads[\s\S]*grant execute on function public\.admin_list_job_leads[\s\S]*to authenticated/i);
  assert.match(migration, /revoke all on function public\.admin_get_job_lead_detail[\s\S]*grant execute on function public\.admin_get_job_lead_detail[\s\S]*to authenticated/i);
  assert.doesNotMatch(migration, /raw WhatsApp|aadhaar|bank|uan|esic|documents/i);
  assert.match(checkpoint, /CHECKPOINT_034_STATIC_PASS/);
});

test('Phase B documentation preserves canonical entities and defers UI/runtime application', () => {
  assert.match(doc, /canonical requirements/i);
  assert.match(doc, /No Phase B UI or NONPROD migration application is authorized/i);
  assert.match(doc, /unique canonical applications/i);
});
