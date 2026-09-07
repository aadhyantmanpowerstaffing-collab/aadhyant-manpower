const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const migrationPath = path.join(root, 'supabase', 'migrations', '038_recruitment_direct_write_hardening.sql');
const checkpointPath = path.join(root, 'supabase', 'tests', '037_recruitment_direct_write_hardening_test.sql');
const migration = fs.readFileSync(migrationPath, 'utf8');
const checkpoint = fs.readFileSync(checkpointPath, 'utf8');
const checkpoint018 = fs.readFileSync(path.join(root, 'supabase', 'tests', '018_recruitment_operations_foundation_test.sql'), 'utf8');
const checkpoint036 = fs.readFileSync(path.join(root, 'supabase', 'tests', '036_joining_fulfillment_hardening_test.sql'), 'utf8');

test('migration 038 has the approved number, name, and transaction boundary', () => {
  assert.equal(path.basename(migrationPath), '038_recruitment_direct_write_hardening.sql');
  assert.match(migration, /^-- Batch D:[\s\S]*\nbegin;/i);
  assert.match(migration, /commit;\s*$/i);
  const later = fs.readdirSync(path.join(root, 'supabase', 'migrations'))
    .filter((name) => /^(?:039|0[4-9]\d|[1-9]\d{2,})_/.test(name));
  // 038 remains frozen; the reviewed Batch 2 migration and its narrowly scoped
  // Contractor/Candidate Portal RPC corrections are the only later migrations.
  assert.deepEqual(later, [
    '039_unified_vacancy_review_workflow.sql',
    '040_fix_contractor_vacancy_submit_ambiguity.sql',
    '041_fix_candidate_opportunity_ambiguity.sql',
    '042_fix_candidate_apply_ambiguity.sql',
    '043_extend_company_vacancy_fields.sql',
  ]);
});

test('migration contains only the exact approved table and column revocations', () => {
  assert.match(migration, /revoke insert, update on table public\.candidate_applications from authenticated;/i);
  assert.match(migration, /revoke update\(source_reference, correlation_id\) on public\.candidate_applications from authenticated;/i);
  assert.match(migration, /revoke insert, update on table public\.candidate_joinings from authenticated;/i);
  assert.doesNotMatch(migration, /revoke\s+select\b/i);
  assert.match(migration, /has_table_privilege\('authenticated','public\.candidate_applications','select'\)/i);
  assert.match(migration, /has_table_privilege\('authenticated','public\.candidate_joinings','select'\)/i);
});

test('migration drops exactly the four approved legacy write policies fail closed', () => {
  const drops = [...migration.matchAll(/drop policy\s+(?:if exists\s+)?"([^"]+)"\s+on\s+public\.(candidate_applications|candidate_joinings);/gi)]
    .map((match) => `${match[1]} on ${match[2]}`);
  assert.deepEqual(drops, [
    'M7 admins create applications on candidate_applications',
    'M7 admins update applications on candidate_applications',
    'M7 admins create joinings on candidate_joinings',
    'M7 admins update joinings on candidate_joinings',
  ]);
  assert.doesNotMatch(migration, /drop policy\s+if exists/i);
  assert.match(migration, /target policy count drifted/i);
  assert.match(migration, /exact M7 policy contracts drifted/i);
  assert.match(migration, /unexpected target write policy exists/i);
});

test('compatibility wrapper is retained for owner control but browser execute is revoked', () => {
  assert.match(migration, /revoke execute on function public\.upsert_recruitment_joining\(uuid,date,date,text,text,text,uuid\) from public, anon, authenticated;/i);
  assert.doesNotMatch(migration, /drop function[\s\S]*upsert_recruitment_joining/i);
  assert.doesNotMatch(migration, /create(?: or replace)? function[\s\S]*upsert_recruitment_joining/i);
  assert.match(migration, /admin_update_candidate_application\(uuid,text,text\)/);
});

test('migration is privilege and policy only with no retained-data or structural mutation', () => {
  assert.doesNotMatch(migration, /\b(?:insert\s+into|delete\s+from|truncate\s+(?:table\s+)?|merge\s+into)\s+public\./i);
  assert.doesNotMatch(migration, /\bupdate\s+public\./i);
  assert.doesNotMatch(migration, /\balter\s+table\b|\bcreate\s+table\b|\bdrop\s+table\b/i);
  assert.doesNotMatch(migration, /\bcreate(?:\s+or\s+replace)?\s+function\b|\bdrop\s+function\b/i);
  assert.doesNotMatch(migration, /\bcreate\s+(?:constraint|trigger|index)\b|\bdrop\s+(?:constraint|trigger|index)\b/i);
  assert.doesNotMatch(migration, /\bcreate\s+policy\b/i);
});

test('migration preflight and postconditions cover grants, policies, RPCs, and private helpers', () => {
  ['target table RLS is disabled', 'application column UPDATE grants drifted', 'anonymous or PUBLIC target mutation privilege exists',
    'compatibility wrapper pre-state drifted', 'application privilege boundary is invalid', 'joining privilege boundary is invalid',
    'target policy boundary is invalid', 'private helper'].forEach((message) => assert.match(migration, new RegExp(message, 'i')));
  ['create_recruitment_joining', 'transition_recruitment_joining', 'update_recruitment_joining_details',
    'correct_recruitment_joining', 'admin_update_candidate_application', 'can_manage_joinings', 'can_correct_joinings',
    'joining_application_status', 'validate_candidate_joining_dates'].forEach((name) => assert.match(migration, new RegExp(name)));
});

test('checkpoint 037 is rollback scoped and covers catalog, denial, RPC continuity, and residue', () => {
  assert.match(checkpoint, /^-- Batch D checkpoint:[\s\S]*\nbegin;/i);
  assert.match(checkpoint, /CHECKPOINT_037_BATCH_D_DIRECT_WRITE_HARDENING_PASS/);
  assert.match(checkpoint, /rollback;[\s\S]+CHECKPOINT_037_ZERO_RESIDUE_PASS/i);
  ['Candidate', 'Company', 'Contractor', 'Recruiter', 'Operations', 'Admin'].forEach((role) => assert.match(checkpoint, new RegExp(role, 'i')));
  assert.match(checkpoint, /Direct application UPDATE succeeded/);
  assert.match(checkpoint, /Direct application INSERT succeeded/);
  assert.match(checkpoint, /Direct joining INSERT succeeded/);
  assert.match(checkpoint, /Anonymous direct application INSERT succeeded/);
  assert.match(checkpoint, /Recruiter canonical application creation failed/);
  assert.match(checkpoint, /Company safe requirement projection failed/);
  assert.match(checkpoint, /Company safe application projection failed/);
  assert.match(checkpoint, /Operations canonical joining lifecycle failed/);
  assert.match(checkpoint, /Admin canonical application creation failed/);
  assert.match(checkpoint, /Admin canonical correction failed/);
  assert.match(checkpoint, /private helper is browser-accessible/);
  assert.match(checkpoint, /fixture residue remains after rollback/);
});

test('checkpoint 018 and 036 compatibility edits use canonical browser RPCs and owner-only wrapper coverage', () => {
  const operations018 = checkpoint018.slice(checkpoint018.indexOf('-- Operations:'), checkpoint018.indexOf('-- Viewer:'));
  assert.match(operations018, /create_recruitment_joining/);
  assert.match(operations018, /transition_recruitment_joining/g);
  assert.doesNotMatch(operations018, /upsert_recruitment_joining/);
  assert.match(checkpoint018, /Recruiter managed joining/);

  assert.match(checkpoint036, /retained wrapper remains owner-controlled compatibility only/i);
  assert.match(checkpoint036, /has_function_privilege\('authenticated','public\.upsert_recruitment_joining[^\n]+\n\s+or has_function_privilege/i);
  const authenticatedLifecycle036 = checkpoint036.slice(checkpoint036.indexOf('set local role authenticated;'));
  assert.doesNotMatch(authenticatedLifecycle036, /perform public\.upsert_recruitment_joining/);
  assert.match(checkpoint036, /create_recruitment_joining/);
  assert.match(checkpoint036, /transition_recruitment_joining/);
});
