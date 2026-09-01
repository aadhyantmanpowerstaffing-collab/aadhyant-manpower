const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migrationPath = path.join(root, 'supabase', 'migrations', '039_unified_vacancy_review_workflow.sql');
const checkpointPath = path.join(root, 'supabase', 'tests', '038_unified_vacancy_review_workflow_test.sql');
const sql = fs.readFileSync(migrationPath, 'utf8');
const checkpoint = fs.readFileSync(checkpointPath, 'utf8');
const compact = sql.replace(/\s+/g, ' ').toLowerCase();

test('Migration 039 is the next migration and has a transactional checkpoint', () => {
  assert.equal(fs.existsSync(migrationPath), true);
  assert.equal(fs.existsSync(checkpointPath), true);
  assert.match(sql, /^-- Batch 2:[\s\S]*?\bbegin;/);
  assert.match(sql, /\bcommit;\s*$/);
  assert.match(checkpoint, /\\set ON_ERROR_STOP on[\s\S]*?\bbegin;/);
  assert.match(checkpoint, /\brollback;\s*$/);
  const later = fs.readdirSync(path.join(root, 'supabase', 'migrations')).filter((name) => /^(?:04\d|0[5-9]\d|[1-9]\d{2,})_.*\.sql$/i.test(name));
  // 039 remains immutable; the reviewed follow-ups only correct its
  // Contractor and Candidate Portal RPC implementations.
  assert.deepEqual(later, [
    '040_fix_contractor_vacancy_submit_ambiguity.sql',
    '041_fix_candidate_opportunity_ambiguity.sql',
    '042_fix_candidate_apply_ambiguity.sql',
  ]);
});

test('Migration 039 has a constrained Company review model and exact source vocabulary', () => {
  for (const column of ['review_status text', 'review_feedback text', 'submitted_at timestamptz', 'reviewed_at timestamptz', 'reviewed_by uuid']) {
    assert.match(compact, new RegExp(column));
  }
  assert.match(compact, /\('draft','pending_review','correction_required','approved','rejected','closed'\)/);
  assert.match(compact, /source_type='employer_portal'/);
  assert.match(compact, /source_type='contractor_portal'/);
  assert.match(compact, /source_type='admin_manual'/);
});

test('Migration 039 normalizes only the five reviewed retained requirements', () => {
  for (const id of [
    '33d8c291-850c-4533-96c1-f2a97543813e',
    '81fa702d-0b02-4417-bc3d-4307ee719858',
    '69e6b28e-3815-47a6-9c0f-ab17868139af',
    '82a877fd-86aa-4853-9b2c-ac1fde9dc98a',
    '89800000-0000-0000-0001-000000000001',
  ]) assert.match(sql, new RegExp(id, 'i'));
  assert.doesNotMatch(compact, /update public\.employer_requirements set source_type='employer_portal'\s*;/);
  assert.match(compact, /retained requirement inventory changed after migration 039 reconciliation/);
  assert.match(compact, /retained synthetic w7c validation fixture/);
});

test('Migration 039 keeps review and lifecycle transitions authoritative', () => {
  for (const rpc of [
    'manage_company_portal_vacancy',
    'list_company_portal_vacancy_reviews',
    'manage_contractor_portal_vacancy',
    'admin_list_vacancy_reviews',
    'admin_get_vacancy_review_detail',
    'admin_approve_and_publish_vacancy',
    'admin_request_vacancy_correction',
    'admin_reject_vacancy',
  ]) assert.match(sql, new RegExp(`(?:create|replace)[\\s\\S]{0,80}function public\\.${rpc}`, 'i'));
  assert.match(compact, /review_status='approved'.*requirement_stage='open'.*requirement_visibility='public'/);
  assert.match(compact, /review_status='correction_required'/);
  assert.match(compact, /review_status='rejected'/);
  assert.match(compact, /only an approved vacancy can be published/);
  assert.match(compact, /only a pending company vacancy can be approved/);
});

test('Migration 039 preserves 037/038 boundaries and gates matching/application creation', () => {
  assert.doesNotMatch(sql, /alter table public\.candidate_joinings/i);
  assert.doesNotMatch(sql, /grant\s+(?:insert|update)\s+on\s+(?:table\s+)?public\.(?:candidate_applications|candidate_joinings)/i);
  assert.match(compact, /private\.vacancy_is_application_eligible/);
  assert.match(compact, /candidate_applications_require_approved_public_vacancy/);
  assert.match(compact, /whatsapp_campaigns_require_approved_public_vacancy/);
  assert.match(compact, /revoke update\(status,internal_notes\) on public\.employer_requirements from authenticated/);
  assert.match(compact, /security definer set search_path=''/);
  assert.match(compact, /revoke all on function private\.normalized_vacancy_review_status/);
});

test('Checkpoint 038 covers Company, Contractor, review, publication, rejection and rollback', () => {
  for (const marker of [
    'Company draft contract failed', 'Company submit contract failed', 'Correction contract failed',
    'Company resubmit contract failed', 'Approve and full-detail contract failed',
    'Contractor submit contract failed', 'Reject contract failed', 'Rejected vacancy was republished',
    'Cross-tenant Company edit succeeded', 'CHECKPOINT_038_UNIFIED_VACANCY_REVIEW_PASS',
  ]) assert.match(checkpoint, new RegExp(marker));
});
