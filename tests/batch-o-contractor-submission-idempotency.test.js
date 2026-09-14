'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '049_contractor_submission_idempotency_and_joining_date.sql'), 'utf8');
const checkpoint = fs.readFileSync(path.join(root, 'supabase', 'tests', '049_contractor_submission_idempotency_test.sql'), 'utf8');
const contractor = fs.readFileSync(path.join(root, 'contractor', 'batch2-vacancies.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'contractor', 'vacancies.html'), 'utf8');

const legacy = 'text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text';

test('M049 provides an opaque private ledger with a unique idempotency boundary', () => {
  assert.match(migration, /^-- Contractor submission idempotency and operational expected-joining-date enforcement\.[\s\S]*?\bbegin;/i);
  assert.match(migration, /create table private\.contractor_vacancy_submission_requests/i);
  assert.match(migration, /idempotency_key uuid not null unique/i);
  assert.match(migration, /contractor_id uuid not null references public\.contractors/i);
  assert.match(migration, /actor_user_id uuid not null references auth\.users/i);
  assert.match(migration, /payload_fingerprint text not null check/i);
  assert.match(migration, /requirement_id uuid unique references public\.employer_requirements/i);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /revoke all on table private\.contractor_vacancy_submission_requests from public,anon,authenticated/i);
  assert.match(migration, /\bcommit;\s*$/i);
});

test('M049 preserves the reviewed overload and adds an authenticated idempotent overload', () => {
  assert.match(migration, new RegExp(`manage_contractor_portal_vacancy\\(${legacy.replaceAll(',', '\\s*,\\s*')}\\)`, 'i'));
  assert.match(migration, new RegExp(`manage_contractor_portal_vacancy\\(${legacy.replaceAll(',', '\\s*,\\s*')},uuid\\)`, 'i'));
  assert.match(migration, /create function public\.manage_contractor_portal_vacancy\([\s\S]*?p_submission_idempotency_key uuid\)/i);
  assert.match(migration, /language plpgsql security definer set search_path=''/i);
  assert.match(migration, /on conflict \(idempotency_key\) do nothing/i);
  assert.match(migration, /where idempotency_key=p_submission_idempotency_key for update/i);
  assert.match(migration, /payload_fingerprint<>v_payload_fingerprint/i);
  assert.match(migration, /v_request\.contractor_id<>v_contractor_id or v_request\.actor_user_id<>v_actor/i);
  assert.match(migration, /grant execute on function public\.manage_contractor_portal_vacancy[\s\S]*?uuid\) to authenticated/i);
  assert.doesNotMatch(migration, /manage_company_portal_(?:requirement|vacancy)/i);
});

test('M049 enforces optional Contractor joining dates with the India operational date', () => {
  assert.match(migration, /clock_timestamp\(\) at time zone 'Asia\/Kolkata'/i);
  assert.match(migration, /Expected joining date must be today or a future date/i);
  assert.match(migration, /create trigger contractor_expected_joining_date_guard/i);
  assert.match(migration, /new\.source_type='contractor_portal'/i);
  assert.match(migration, /new\.expected_joining_date is distinct from old\.expected_joining_date/i);
});

test('Contractor UI creates one opaque key, latches before await, and keeps validation inside the dialog', () => {
  assert.match(contractor, /Intl\.DateTimeFormat\('en-CA', \{ timeZone: 'Asia\/Kolkata'/);
  assert.match(contractor, /window\.crypto\?\.randomUUID/);
  assert.match(contractor, /let submitInFlight = false;/);
  assert.match(contractor, /if \(submitInFlight \|\| !valid\(\)\) return;/);
  assert.match(contractor, /if \(!id && !submissionKey\) submissionKey = newSubmissionKey\(\);/);
  assert.match(contractor, /setSubmitInFlight\(true\);[\s\S]*?await call\('manage_contractor_portal_vacancy'/);
  assert.match(contractor, /p_submission_idempotency_key: submissionKey/);
  assert.match(contractor, /finally \{ setSubmitInFlight\(false\); \}/);
  assert.match(contractor, /Minimum CTC cannot exceed Maximum CTC\./);
  assert.match(contractor, /Expected joining date must be today or a future date\./);
  assert.match(contractor, /editingHistoricalDate/);
  assert.match(contractor, /expectedJoiningDate\.min = current \? '' : indiaToday\(\)/);
  assert.match(contractor, /data-vacancy-form-message/);
  assert.match(html, /data-vacancy-form-message/);
  assert.doesNotMatch(contractor, /\.from\s*\(/);
});

test('focused M049 checkpoint is rollback scoped and exercises every synchronous idempotency and date boundary', () => {
  assert.match(checkpoint, /\\set ON_ERROR_STOP on[\s\S]*?\bbegin;/i);
  assert.match(checkpoint, /rollback;/i);
  assert.match(checkpoint, /v_first\.id<>v_replay\.id/);
  assert.match(checkpoint, /M49 Conflict/);
  assert.match(checkpoint, /M49 Cross Contractor/);
  assert.match(checkpoint, /M49 Null/);
  assert.match(checkpoint, /M49 Future/);
  assert.match(checkpoint, /M49 Past/);
  assert.match(checkpoint, /v_today date := \(clock_timestamp\(\) at time zone 'Asia\/Kolkata'\)::date/);
  assert.match(checkpoint, /private\.vacancy_is_application_eligible/);
  assert.match(checkpoint, /count\(\*\) from private\.contractor_vacancy_submission_requests/);
  assert.match(checkpoint, /contractor_vacancy_create_and_submit/);
});

test('M044 through M048 remain immutable', () => {
  const expected = {
    '044_vacancy_compensation_accommodation_lifecycle.sql': 'abc79fb9ec456c70f80fefc93804d618bc3fba489c26f54526cad626feb43184',
    '045_fix_vacancy_lifecycle_rpc_ambiguity.sql': 'e3cba9aab60983f40afbc41f1e4ade4937a1eca742df5d41fa1391138d8a1bea',
    '046_fix_owner_vacancy_projection_ambiguity.sql': 'baee5ef5870ee36307e3a4b2de687c705a2bc0113cdb8e0aec578ae8190618f9',
    '047_fix_candidate_opportunity_projection_ambiguity.sql': 'abeca57bb3c514d67aca02e28b1770c937829186c2c8cac48e44afe227645ffe',
    '048_fix_vacancy_submit_managed_record_shape.sql': 'a39137259c9b9ee1ce02ba58deb220e9705c9a9c9771b4475138cecb984520ba'
  };
  for (const [file, hash] of Object.entries(expected)) {
    const content = fs.readFileSync(path.join(root, 'supabase', 'migrations', file));
    assert.equal(crypto.createHash('sha256').update(content).digest('hex'), hash, file);
  }
});
