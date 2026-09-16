const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const read = (file) => fs.readFileSync(file, 'utf8');
const migration = read('supabase/migrations/050_vacancy_candidate_terms_snapshot.sql');
const helperSource = read('assets/js/vacancy-candidate-terms.js');
const checkpoint = read('supabase/tests/050_vacancy_candidate_terms_snapshot_test.sql');
const candidate = read('candidate/portal/batch2-jobs.js');
const companyHtml = read('company/requirements.html');
const contractorHtml = read('contractor/vacancies.html');
const company = read('company/batch2-vacancies.js');
const contractor = read('contractor/batch2-vacancies.js');

test('M050 is additive, private, closed-catalog, and Candidate-safe', () => {
  for (const token of ['compensation_cadence','paid_leave_days_per_year','casual_leave_days_per_year','sick_leave_days_per_year','national_holiday_days_per_year','festival_holiday_days_per_year','working_days_per_week','weekly_off_count','overtime_rate_basis','canteen_status','transport_status','employment_type','payroll_type','private.vacancy_candidate_benefits','production_incentive','ppe','primary key(requirement_id,benefit_type)','enable row level security','revoke all on table private.vacancy_candidate_benefits']) assert.ok(migration.includes(token), token);
  assert.match(migration, /set search_path=''/);
  assert.match(migration, /private\.vacancy_is_application_eligible\(r\.id\)/);
  assert.doesNotMatch(migration, /(margin|service_charge|invoice_rate|private contacts)/i);
});

test('M050 validates controlled conditional terms and preserves legacy nulls', () => {
  for (const token of ["('monthly','annual')",'working_days_per_week+weekly_off_count=7',"('per_hour','per_day','multiplier')","('per_day','per_meal','per_month')","('per_day','per_month')",'contract_duration_months between 1 and 120','probation_period_months between 1 and 24','training_period_days between 1 and 365','notice_period_days between 1 and 180','leave_amount','leave_provision']) assert.ok(migration.includes(token), token);
  assert.match(migration, /canteen_status='chargeable' and canteen_charge_amount>0/);
  assert.match(migration, /transport_status='chargeable' and transport_charge_amount>0/);
  assert.match(migration, /compensation cadence is required/i);
  for (const field of ['paid_leave_days_per_year','casual_leave_days_per_year','sick_leave_days_per_year','national_holiday_days_per_year','festival_holiday_days_per_year']) assert.match(migration, new RegExp(`${field} is null or ${field} between 0 and 366`));
});

test('owner forms use controlled terms through owner RPCs and preserve M049 submit key', () => {
  for (const source of [company, contractor]) { assert.match(source, /p_candidate_terms/); assert.doesNotMatch(source, /\.from\s*\(/); }
  assert.match(contractor, /p_submission_idempotency_key: submissionKey/);
  assert.match(contractor, /submitInFlight/);
  for (const html of [companyHtml, contractorHtml]) for (const token of ['CTC Cadence','Paid / Earned Leave','Canteen terms','Transport terms','Employment Type','Payroll Type','Other Candidate Benefits','data-add-candidate-benefit']) assert.ok(html.includes(token), token);
});

test('Candidate detail is collapsed, truthful, and contains no private browser access', () => {
  for (const token of ['View Salary, Benefits & Employment Terms','Salary & CTC Breakdown','Deductions / Approx. In-Hand','Employer CTC Components','Leave & Holidays','Working Terms','Other Benefits','Employment Terms','candidate_benefits','salary_wage']) assert.ok(candidate.includes(token), token);
  assert.match(candidate, /candidate-terms-disclosure/);
  assert.doesNotMatch(candidate, /\.from\s*\(/);
  assert.doesNotMatch(candidate, /(margin|service_charge|invoice_rate|contractor_id|user_id)/i);
});

test('term helper rejects invalid conditional client payloads before RPC', () => {
  const window = {}; vm.runInNewContext(helperSource, { window });
  assert.ok(window.AadhyantVacancyCandidateTerms);
  assert.match(helperSource, /working days plus weekly off/i);
  assert.match(helperSource, /Cash benefits require/i);
  assert.match(helperSource, /Clear .* charge terms/i);
});

test('Company and Contractor annual leave and holiday controls enforce whole annual days from 0 through 366', () => {
  const window = {}; vm.runInNewContext(helperSource, { window });
  const control = (value = '') => ({ value, disabled: false });
  const api = window.AadhyantVacancyCandidateTerms;
  const fields = ['paidLeaveDaysPerYear','casualLeaveDaysPerYear','sickLeaveDaysPerYear','nationalHolidayDaysPerYear','festivalHolidayDaysPerYear'];
  for (const html of [companyHtml, contractorHtml]) for (const field of fields) assert.match(html, new RegExp(`name="${field}" type="number" min="0" max="366" step="1"`));
  for (const field of fields) {
    const form = { elements: Object.fromEntries(fields.map((name) => [name, control()])), querySelector: () => null, querySelectorAll: () => [] };
    for (const value of ['', '0', '12', '366']) {
      form.elements[field].value = value;
      assert.equal(api.validate(form), null, `${field} ${value || 'null'} should be valid`);
    }
    for (const value of ['-1', '367', '12.5']) {
      form.elements[field].value = value;
      assert.equal(api.validate(form), 'Annual leave and holiday values must be whole days from 0 through 366.', `${field} ${value} should fail`);
    }
  }
});

test('Company and Contractor clear hidden non-chargeable facility terms before RPC serialization', () => {
  const window = {}; vm.runInNewContext(helperSource, { window });
  const control = (value = '') => ({ value, disabled: false });
  const form = {
    elements: {
      canteenStatus: control('chargeable'), canteenChargeAmount: control('150'), canteenChargeBasis: control('per_day'),
      transportStatus: control('chargeable'), transportChargeAmount: control('900'), transportChargeBasis: control('per_month')
    }, querySelector: () => null, querySelectorAll: () => []
  };
  const api = window.AadhyantVacancyCandidateTerms;
  api.normalizeFacility(form, 'canteen'); api.normalizeFacility(form, 'transport');
  form.elements.canteenStatus.value = 'free'; form.elements.transportStatus.value = 'not_applicable';
  const payload = api.terms(form);
  assert.equal(form.elements.canteenChargeAmount.value, ''); assert.equal(form.elements.canteenChargeBasis.value, '');
  assert.equal(form.elements.transportChargeAmount.value, ''); assert.equal(form.elements.transportChargeBasis.value, '');
  assert.equal(payload.canteen_charge_amount, null); assert.equal(payload.canteen_charge_basis, null);
  assert.equal(payload.transport_charge_amount, null); assert.equal(payload.transport_charge_basis, null);
  form.elements.canteenStatus.value = 'chargeable'; api.normalizeFacility(form, 'canteen');
  assert.equal(form.elements.canteenChargeAmount.value, '');
  assert.equal(api.validate(form), 'Enter a positive canteen charge and valid basis.');
  for (const source of [company, contractor]) assert.match(source, /p_candidate_terms/);
});

test('every non-chargeable Company/Contractor facility state clears values and requires fresh values on return', () => {
  const window = {}; vm.runInNewContext(helperSource, { window });
  const control = (value = '') => ({ value, disabled: false });
  const api = window.AadhyantVacancyCandidateTerms;
  for (const portal of ['company', 'contractor']) {
    for (const [facility, states] of Object.entries({ canteen: ['free', 'not_available', 'not_applicable'], transport: ['free', 'not_available', 'not_applicable'] })) {
      for (const state of states) {
        const form = { elements: {
          canteenStatus: control(facility === 'canteen' ? 'chargeable' : 'free'), canteenChargeAmount: control('30'), canteenChargeBasis: control('per_day'),
          transportStatus: control(facility === 'transport' ? 'chargeable' : 'free'), transportChargeAmount: control('900'), transportChargeBasis: control('per_month')
        }, querySelector: () => null, querySelectorAll: () => [] };
        form.elements[`${facility}Status`].value = state;
        const payload = api.terms(form);
        assert.equal(payload[`${facility}_charge_amount`], null, `${portal} ${facility} ${state} amount`);
        assert.equal(payload[`${facility}_charge_basis`], null, `${portal} ${facility} ${state} basis`);
        assert.equal(form.elements[`${facility}ChargeAmount`].disabled, true);
        form.elements[`${facility}Status`].value = 'chargeable';
        api.normalizeFacility(form, facility);
        assert.equal(form.elements[`${facility}ChargeAmount`].value, '', `${portal} ${facility} restored a stale amount`);
        assert.match(api.validate(form), new RegExp(`positive ${facility} charge`, 'i'));
      }
    }
  }
});

test('M050 runtime checkpoint is rollback-scoped and covers owner, idempotency, review, projection, and legacy contracts', () => {
  for (const token of [
    'begin;', 'rollback;', 'CHECKPOINT_050_ZERO_RESIDUE_ROLLBACK_COMPLETE',
    'public.manage_company_portal_requirement', 'pg_temp.submit_m50',
    'CHECKPOINT_050_IDEMPOTENT_REPLAY', 'CHECKPOINT_050_CHANGED_BASE_REPLAY_ACCEPTED',
    'CHECKPOINT_050_CHANGED_SCALAR_REPLAY_ACCEPTED', 'CHECKPOINT_050_CHANGED_BENEFIT_REPLAY_ACCEPTED',
    'CHECKPOINT_050_CHANGED_BASE_AND_TERMS_REPLAY_ACCEPTED', 'CHECKPOINT_050_SCALAR_REREVIEW_GATE',
    'CHECKPOINT_050_BENEFIT_REREVIEW_GATE', 'CHECKPOINT_050_PENDING_REVIEW_EXPOSED',
    'CHECKPOINT_050_CANDIDATE_SAFE_PROJECTION', 'CHECKPOINT_050_LEGACY_FALLBACK',
    'CHECKPOINT_050_LEAVE_NULL_FAILED', 'CHECKPOINT_050_LEAVE_VALID_FAILED', 'CHECKPOINT_050_LEAVE_BOUND_ACCEPTED',
    'CHECKPOINT_050_CADENCE_MONTHLY_FAILED', 'CHECKPOINT_050_CADENCE_ANNUAL_FAILED',
    'CHECKPOINT_050_CADENCE_MISSING_ACCEPTED', 'CHECKPOINT_050_CADENCE_INVALID_ACCEPTED',
    'CHECKPOINT_050_FIXTURE_WAGE_TOTALS',
    'CHECKPOINT_050_CANTEEN_LEGACY_NULL', 'CHECKPOINT_050_CANTEEN_NONCHARGEABLE', 'CHECKPOINT_050_CANTEEN_CHARGEABLE',
    'CHECKPOINT_050_TRANSPORT_LEGACY_NULL', 'CHECKPOINT_050_TRANSPORT_NONCHARGEABLE', 'CHECKPOINT_050_TRANSPORT_CHARGEABLE',
    'private.vacancy_candidate_benefits', 'private.contractor_vacancy_submission_term_requests'
  ]) assert.ok(checkpoint.includes(token), token);
  for (const protectedCode of ['AAD-2026-000353', 'AAD-2026-000354', 'AAD-2026-000355', 'AAD-2026-000360', 'AAD-2026-000361']) assert.ok(!checkpoint.includes(protectedCode));
});

test('M050 structured-CTC checkpoint mutations retain cadence except dedicated cadence failures', () => {
  assert.match(checkpoint, /create function pg_temp\.m50_constraint_terms[\s\S]*pg_temp\.m50_terms\('\[\]'::jsonb\).*\|\|/);
  assert.match(checkpoint, /pg_temp\.m50_constraint_terms\(\)-'compensation_cadence'/);
  assert.match(checkpoint, /pg_temp\.m50_constraint_terms\('\{"compensation_cadence":"weekly"\}'::jsonb\)/);
  const structuredFixtureCalls = checkpoint.split(/\r?\n/).filter((line) => line.includes("apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001'"));
  assert.ok(structuredFixtureCalls.length > 0);
  for (const call of structuredFixtureCalls) assert.match(call, /pg_temp\.m50_constraint_terms\(/);
});

test('M050 replay composes with M049 base validation before additive terms validation', () => {
  const replay = migration.slice(migration.indexOf('select * into v_request from private.contractor_vacancy_submission_term_requests'));
  const baseReplay = replay.indexOf('select * into v_result from public.manage_contractor_portal_vacancy');
  const termsConflict = replay.indexOf('if v_request.terms_fingerprint<>v_fingerprint');
  assert.ok(baseReplay >= 0 && termsConflict > baseReplay, 'M049 base validation must occur before M050 terms replay success');
  assert.match(migration, /private\.canonical_vacancy_candidate_terms\(p_candidate_terms\)/);
  assert.match(migration, /jsonb_agg\(jsonb_strip_nulls\(value\) order by value->>'benefit_type',value::text\)/);
  assert.match(replay, /v_request\.requirement_id<>v_result\.id/);
});

test('material Candidate-facing edits are returned to review before publication', () => {
  assert.match(migration, /vacancy_candidate_terms_material_change_guard/);
  assert.match(migration, /requirement_visibility:='private'/);
  assert.match(migration, /requirement_stage:='draft'/);
  assert.match(migration, /submission_status='submitted'/);
});
