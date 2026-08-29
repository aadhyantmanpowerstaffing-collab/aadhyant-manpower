const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '037_joining_fulfillment_hardening.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'tests', '036_joining_fulfillment_hardening_test.sql'), 'utf8');

test('migration 037 is transactional and fails closed on reconciled-data invariants', () => {
  assert.match(migration,/^-- Batch D:[\s\S]*\nbegin;/i);
  assert.match(migration,/commit;\s*$/i);
  [
    'fulfillment counter mismatch','over headcount','application and joining state mismatch',
    'lacks an actual joining date','lacks an expected joining date','future actual joining date','incompatible full or terminal requirement state'
  ].forEach((message)=>assert.match(migration,new RegExp(message,'i')));
  assert.doesNotMatch(migration,/update public\.employer_requirements\s+set filled_positions\s*=\s*\(\s*select count/i);
});

test('strict joining RPCs use authorization, correlation, stale tokens, and fixed lock order', () => {
  ['create_recruitment_joining','transition_recruitment_joining','update_recruitment_joining_details','correct_recruitment_joining'].forEach((name)=>{
    assert.match(migration,new RegExp(`create function public\\.${name}`));
  });
  assert.match(migration,/select \* into app from public\.candidate_applications[^;]+for update;[\s\S]+select \* into req from public\.employer_requirements[^;]+for update;[\s\S]+select \* into current_joining from public\.candidate_joinings[^;]+for update;/);
  assert.match(migration,/p_expected_status text/);
  assert.match(migration,/p_expected_updated_at timestamptz/);
  assert.match(migration,/p_correlation_id is null/);
  assert.match(migration,/action='recruitment\.joining_created'[\s\S]+correlation_id=p_correlation_id/);
  assert.match(migration,/action='recruitment\.joining_details_updated'[\s\S]+correlation_id=p_correlation_id/);
  assert.match(migration,/action='recruitment\.joining_corrected'[\s\S]+correlation_id=p_correlation_id/);
  assert.match(migration,/Joining state changed; refresh and try again/);
  assert.match(migration,/security definer\s+set search_path = ''/g);
});

test('joining lifecycle and application synchronization match the approved matrix', () => {
  [
    "('pending','confirmed')","('pending','deferred')","('pending','joined')","('pending','no_show')","('pending','cancelled')",
    "('confirmed','deferred')","('confirmed','joined')","('confirmed','no_show')","('confirmed','cancelled')",
    "('deferred','confirmed')","('deferred','joined')","('deferred','no_show')","('deferred','cancelled')","('joined','left')"
  ].forEach((edge)=>assert.match(migration,new RegExp(edge.replace(/[()]/g,'\\$&'))));
  assert.doesNotMatch(migration,/\('deferred','pending'\)/);
  assert.match(migration,/when 'confirmed' then 'joining_pending'/);
  assert.match(migration,/when 'deferred' then 'joining_pending'/);
  assert.match(migration,/when 'no_show' then 'cancelled'/);
  assert.match(migration,/when 'left' then 'left'/);
  assert.doesNotMatch(migration,/update public\.candidates\s+set/i);
});

test('date and fulfillment enforcement use India date and guarded counters', () => {
  assert.match(migration,/clock_timestamp\(\) at time zone 'Asia\/Kolkata'/g);
  assert.match(migration,/candidate_joinings_actual_date_state_check/);
  assert.match(migration,/create trigger candidate_joinings_validate_dates/);
  assert.match(migration,/update of joining_status, expected_joining_date, actual_joining_date/);
  assert.doesNotMatch(migration,/check\s*\([^)]*clock_timestamp|check\s*\([^)]*current_date/i);
  assert.match(migration,/set filled_positions=filled_positions\+1/);
  assert.match(migration,/where id=req\.id and filled_positions<required_headcount/);
  assert.match(migration,/set filled_positions=filled_positions-1/);
  assert.match(migration,/where id=req\.id and filled_positions>0/);
  assert.match(migration,/requirement_stage=case when filled_positions\+1=required_headcount then 'filled'/);
  assert.match(migration,/requirement_visibility=case when filled_positions\+1=required_headcount then 'private'/);
});

test('correction and audit contracts are narrow and rich', () => {
  assert.match(migration,/create function private\.can_correct_joinings[\s\S]+is_bootstrap_recruitment_admin[\s\S]+has_staff_role\('super_admin'\)[\s\S]+has_staff_role\('admin'\)/);
  const correction = migration.slice(migration.indexOf('create function public.correct_recruitment_joining'), migration.indexOf('create or replace function public.upsert_recruitment_joining'));
  assert.doesNotMatch(correction,/has_staff_role\('operations'\)|has_staff_role\('recruiter'\)/);
  assert.match(correction,/Joining correction reason is required/);
  assert.match(correction,/counter_delta :=/);
  ['joining_created','joining_transitioned','joining_details_updated','joining_corrected','joining_application_synchronized','joining_fulfillment_changed','requirement_lifecycle_changed'].forEach((action)=>assert.match(migration,new RegExp(action)));
  ['old_filled_positions','new_filled_positions','old_requirement_stage','new_requirement_stage','employee_code','actual_joining_date','reason'].forEach((field)=>assert.match(migration,new RegExp(field)));
});

test('migration 038 write revocations and policy removals are absent', () => {
  assert.doesNotMatch(migration,/revoke\s+(?:insert|update)[\s\S]+candidate_(?:applications|joinings)/i);
  assert.doesNotMatch(migration,/drop policy[\s\S]+M7 admins (?:create|update) (?:applications|joinings)/i);
  assert.doesNotMatch(migration,/revoke\s+update\s*\(\s*source_reference/i);
  assert.match(migration,/Migration 038 will separately revoke legacy direct table writes/);
});

test('checkpoint is rollback scoped and covers lifecycle, security, audit, and zero residue', () => {
  assert.match(checkpoint,/^-- Batch D[\s\S]*\nbegin;/i);
  assert.match(checkpoint,/rollback;[\s\S]+select 'CHECKPOINT_036_BATCH_D_PASS'/i);
  ['pending','confirmed','deferred','joined','no_show','cancelled','left'].forEach((state)=>assert.match(checkpoint,new RegExp(`'${state}'`)));
  ['Operations correction bypassed','Recruiter correction bypassed','Candidate correction bypassed','Company correction bypassed','Contractor correction bypassed'].forEach((message)=>assert.match(checkpoint,new RegExp(message)));
  assert.match(checkpoint,/joining_fulfillment_changed/);
  assert.match(checkpoint,/requirement_lifecycle_changed/);
  assert.match(checkpoint,/Joining creation retry was not idempotent/);
  assert.match(checkpoint,/Detail-update retry duplicated audit/);
  assert.match(checkpoint,/Joined correction synchronization\/retry failed/);
  assert.match(checkpoint,/Left without reason succeeded/);
  assert.match(checkpoint,/Cancelled without reason succeeded/);
  assert.match(checkpoint,/Filled requirement creation succeeded/);
  assert.match(checkpoint,/Full requirement remained in the public opportunity projection/);
  assert.match(checkpoint,/application_stage_history/);
});
