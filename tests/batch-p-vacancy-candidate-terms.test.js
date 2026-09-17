const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
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
const localSupabaseConfig = read('supabase/config.toml');
const localRuntimeHarness = read('scripts/ci/run-m050-local-validation.sh');
const localRuntimeWorkflow = read('.github/workflows/m050-local-runtime-validation.yml');
const reviewWorkflow = read('supabase/migrations/039_unified_vacancy_review_workflow.sql');
const checkpointDiagnosticPhases = [
  'COMPENSATION_CADENCE', 'LEAVE_HOLIDAY', 'WORKING_WEEK', 'OVERTIME', 'CANTEEN', 'TRANSPORT',
  'BENEFITS_SECURITY', 'EMPLOYMENT_TERMS', 'ACCOMMODATION_REGRESSION', 'COMPANY_OWNER_RPC',
  'CONTRACTOR_OWNER_RPC', 'REPLAY_IDENTICAL', 'REPLAY_CHANGED_BASE', 'REPLAY_CHANGED_SCALAR',
  'REPLAY_CHANGED_BENEFITS', 'REPLAY_CHANGED_BASE_AND_TERMS', 'MATERIAL_REVIEW_INITIAL_APPROVAL',
  'MATERIAL_REVIEW_SCALAR_EDIT', 'MATERIAL_REVIEW_SCALAR_REAPPROVAL', 'MATERIAL_REVIEW_BENEFIT_EDIT',
  'MATERIAL_REVIEW_BENEFIT_REAPPROVAL', 'CANDIDATE_PROJECTION', 'PENDING_REVIEW_EXCLUSION',
  'LEGACY_COMPATIBILITY', 'FINAL_RESIDUE_PRE_ROLLBACK'
];

test('M050 is additive, private, closed-catalog, and Candidate-safe', () => {
  for (const token of ['compensation_cadence','paid_leave_days_per_year','casual_leave_days_per_year','sick_leave_days_per_year','national_holiday_days_per_year','festival_holiday_days_per_year','working_days_per_week','weekly_off_count','overtime_rate_basis','canteen_status','transport_status','employment_type','payroll_type','private.vacancy_candidate_benefits','production_incentive','ppe','primary key(requirement_id,benefit_type)','enable row level security','revoke all on table private.vacancy_candidate_benefits']) assert.ok(migration.includes(token), token);
  assert.match(migration, /set search_path=''/);
  assert.match(migration, /private\.vacancy_is_application_eligible\(r\.id\)/);
  assert.doesNotMatch(migration, /(margin|service_charge|invoice_rate|private contacts)/i);
});

test('M050 validates controlled conditional terms and preserves legacy nulls', () => {
  for (const token of ["('monthly','annual')",'working_days_per_week+weekly_off_count=7',"('per_hour','per_day','multiplier')","('per_day','per_meal','per_month')","('per_day','per_month')",'contract_duration_months between 1 and 120','probation_period_months between 1 and 24','training_period_days between 1 and 365','notice_period_days between 1 and 180','leave_amount','leave_provision']) assert.ok(migration.includes(token), token);
  assert.match(migration, /compensation cadence is required/i);
  for (const field of ['paid_leave_days_per_year','casual_leave_days_per_year','sick_leave_days_per_year','national_holiday_days_per_year','festival_holiday_days_per_year']) assert.match(migration, new RegExp(`${field} is null or ${field} between 0 and 366`));
});

test('M050 conditional checks reject invalid NULL pairings rather than allowing SQL UNKNOWN', () => {
  const sql = migration.toLowerCase().replace(/\s+/g, ' ');
  for (const contract of [
    "when overtime_rate is null then overtime_rate_basis is null",
    "when overtime_rate_basis is null then false",
    "when canteen_status is null then canteen_charge_amount is null and canteen_charge_basis is null",
    "when canteen_status='chargeable' then canteen_charge_amount is not null and canteen_charge_amount>0 and canteen_charge_basis is not null",
    "when transport_status is null then transport_charge_amount is null and transport_charge_basis is null",
    "when transport_status='chargeable' then transport_charge_amount is not null and transport_charge_amount>0 and transport_charge_basis is not null",
    "contract_duration_months is null or (employment_type is not null and employment_type='contract')",
    "when benefit_value_type='cash' then amount is not null and amount>0 and amount_basis is not null",
    "when benefit_value_type='provided' then amount is null and amount_basis is null"
  ]) assert.ok(sql.includes(contract), contract);
  assert.match(checkpoint, /CHECKPOINT_050_OVERTIME_NULL_PAIR/);
  assert.match(checkpoint, /\{"canteen_status":"chargeable","canteen_charge_amount":null,"canteen_charge_basis":null\}/);
  assert.match(checkpoint, /\{"transport_status":"chargeable","transport_charge_amount":null,"transport_charge_basis":null\}/);
  assert.match(checkpoint, /"benefit_value_type":"cash","amount":null/);
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

test('M050 Company owner fixture follows the authoritative legacy facility vocabulary', () => {
  const companyFixture = checkpoint.slice(checkpoint.indexOf('select * into v_company'), checkpoint.indexOf('-- Contractor submission'));
  for (const token of ["p_canteen=>'Yes'", "p_transport=>'Yes'", "p_accommodation=>'Yes'"]) assert.ok(companyFixture.includes(token), token);
  assert.doesNotMatch(companyFixture, /p_(canteen|transport|accommodation)=>'Available'/);
});

test('M050 Contractor replay fixture follows the authoritative legacy facility vocabulary', () => {
  const contractorFixture = checkpoint.slice(checkpoint.indexOf('create function pg_temp.submit_m50'), checkpoint.indexOf("set local role authenticated;", checkpoint.indexOf('create function pg_temp.submit_m50')));
  for (const token of ["p_canteen=>'Yes'", "p_transport=>'Yes'", "p_accommodation=>'Yes'"]) assert.ok(contractorFixture.includes(token), token);
  assert.doesNotMatch(contractorFixture, /p_(canteen|transport|accommodation)=>'Available'/);
  const legacyFixture = checkpoint.slice(checkpoint.indexOf('-- Legacy compatibility'), checkpoint.indexOf('-- The transaction boundary'));
  assert.match(legacyFixture, /'15000','Yes','No','Yes'/);
  assert.doesNotMatch(legacyFixture, /'Available'|'Not Available'/);
});

test('M050 checkpoint restores privileged context before private owner postconditions', () => {
  const security = checkpoint.slice(checkpoint.indexOf('-- Browser-role execution'), checkpoint.indexOf('-- Company owner uses'));
  assert.match(security, /set local role anon;[\s\S]*CHECKPOINT_050_ANON_PRIVATE_BENEFITS_READ[\s\S]*reset role;/);
  assert.match(security, /set local role authenticated;[\s\S]*CHECKPOINT_050_AUTHENTICATED_PRIVATE_BENEFITS_READ[\s\S]*reset role;/);
  const company = checkpoint.slice(checkpoint.indexOf('-- Company owner uses'), checkpoint.indexOf('-- Contractor submission'));
  const reset = company.indexOf('reset role;');
  const privatePostcondition = company.indexOf('private.vacancy_candidate_benefits');
  assert.ok(reset >= 0 && privatePostcondition > reset, 'Company private verification must follow RESET ROLE');
  assert.match(company, /current_setting\('m50\.company_requirement'\)::uuid/);
  const contractor = checkpoint.slice(checkpoint.indexOf('-- Contractor submission'), checkpoint.indexOf('-- Admin approval'));
  assert.match(contractor, /set local role authenticated;[\s\S]*m50\.contractor_requirement[\s\S]*reset role;[\s\S]*private\.contractor_vacancy_submission_requests/);
  assert.match(contractor, /CHECKPOINT_050_CHANGED_BASE_REPLAY_ACCEPTED[\s\S]*reset role;[\s\S]*CHECKPOINT_050_CONFLICT_RESIDUE/);
});

test('M050 material review resets from Admin actions before private eligibility verification', () => {
  const material = checkpoint.slice(checkpoint.indexOf('-- Admin approval'), checkpoint.indexOf('-- Legacy compatibility'));
  const approval = material.indexOf('public.admin_approve_and_publish_vacancy');
  const initialPrivateCheck = material.indexOf('CHECKPOINT_050_APPROVAL_PRECONDITION');
  assert.ok(approval >= 0 && initialPrivateCheck > approval);
  assert.match(material.slice(approval, initialPrivateCheck), /reset role;[\s\S]*private\.vacancy_is_application_eligible/);
  assert.match(material, /CHECKPOINT_050_SCALAR_REREVIEW_GATE[\s\S]*set local role authenticated;[\s\S]*admin_approve_and_publish_vacancy[\s\S]*reset role;[\s\S]*CHECKPOINT_050_SCALAR_REAPPROVAL_GATE/);
  assert.match(material, /CHECKPOINT_050_BENEFIT_REREVIEW_GATE[\s\S]*set local role authenticated;[\s\S]*admin_approve_and_publish_vacancy[\s\S]*reset role;[\s\S]*CHECKPOINT_050_BENEFIT_REAPPROVAL_GATE/);
  const candidate = checkpoint.slice(checkpoint.indexOf('-- Pending Review'), checkpoint.indexOf('-- Legacy compatibility'));
  assert.match(candidate, /set local role authenticated;[\s\S]*50000000-0000-0000-0000-000000000004[\s\S]*list_candidate_job_opportunities[\s\S]*reset role;/);
  assert.match(candidate, /admin_approve_and_publish_vacancy[\s\S]*reset role;[\s\S]*set local role authenticated;[\s\S]*50000000-0000-0000-0000-000000000004/);
  const legacy = checkpoint.slice(checkpoint.indexOf('-- Legacy compatibility'), checkpoint.indexOf('-- The transaction boundary'));
  assert.match(legacy, /set local role authenticated;[\s\S]*50000000-0000-0000-0000-000000000004[\s\S]*list_candidate_job_opportunities[\s\S]*reset role;/);
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

test('M050 scalar Contractor material edits restore the M039 rereview transition without changing non-material replay', () => {
  const rereview = migration.slice(
    migration.indexOf('create or replace function private.require_vacancy_candidate_terms_rereview'),
    migration.indexOf('create or replace function private.vacancy_candidate_terms_material_change')
  );
  const materialTrigger = migration.slice(
    migration.indexOf('create or replace function private.vacancy_candidate_terms_material_change'),
    migration.indexOf('create or replace function private.vacancy_candidate_benefit_material_change')
  );
  const contractorReset = "update public.requirement_contractors set submission_status='submitted',submitted_at=clock_timestamp(),reviewed_at=null";
  const normalizeSql = (sql) => sql.replace(/\s+/g, ' ');
  const normalizedRereview = normalizeSql(rereview);
  const normalizedTrigger = normalizeSql(materialTrigger);
  assert.ok(normalizedRereview.includes(`${contractorReset} where requirement_id=p_requirement_id and origin_type='contractor_submission'`));
  const resetStart = normalizedTrigger.indexOf(contractorReset);
  const resetBranch = normalizedTrigger.slice(resetStart, normalizedTrigger.indexOf('else', resetStart));
  assert.ok(resetStart > normalizedTrigger.indexOf('private.vacancy_is_application_eligible(old.id)'), 'Contractor link reset must stay inside the material-change gate');
  assert.ok(normalizedTrigger.includes(`if old.source_type='contractor_portal' then ${contractorReset} where requirement_id=old.id and origin_type='contractor_submission'`));
  assert.doesNotMatch(resetBranch, /reviewed_by/);
  assert.match(reviewWorkflow, /rc\.submission_status not in \('submitted','under_review'\)/);
  assert.match(reviewWorkflow, /submission_status='approved',assignment_status='active',reviewed_at=now_at,reviewed_by=actor/);
  const scalarPath = checkpoint.slice(checkpoint.indexOf('CHECKPOINT_050_PHASE=MATERIAL_REVIEW_SCALAR_EDIT'), checkpoint.indexOf('CHECKPOINT_050_PHASE=MATERIAL_REVIEW_BENEFIT_EDIT'));
  assert.match(scalarPath, /jsonb_set\(pg_temp\.m50_terms\(\),'\{canteen_charge_amount\}','35'::jsonb\)/);
  assert.match(scalarPath, /admin_approve_and_publish_vacancy[\s\S]*CHECKPOINT_050_SCALAR_REAPPROVAL_GATE/);
});

test('M050 rereview logic does not depend on an approval timestamp outside the vacancy review contract', () => {
  assert.doesNotMatch(migration, /\bapproved_at\b/);
});

test('M050 disposable local runtime harness is unlinked, exact-source, and fail-closed', () => {
  assert.match(localSupabaseConfig, /project_id\s*=\s*"aadhyant-m050-local-validation"/);
  assert.match(localSupabaseConfig, /\[auth\][\s\S]*enabled\s*=\s*true/);
  assert.match(localSupabaseConfig, /\[storage\][\s\S]*enabled\s*=\s*true/);
  assert.doesNotMatch(localSupabaseConfig, /zrluniaccvcdrvfwgrmj|wsuctjhbqiedttfnwjvf|\.supabase\.co|postgres(?:ql)?:\/\//i);

  for (const token of [
    'set -euo pipefail', 'SUPABASE_TELEMETRY_DISABLED=1', 'SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'SUPABASE_SERVICE_ROLE_KEY',
    'zrluniaccvcdrvfwgrmj', 'wsuctjhbqiedttfnwjvf', 'LOCAL_DB_HOST_REFUSED',
    'LOCAL_WORKDIR', 'prepare_local_workdir', 'supabase --workdir "$LOCAL_WORKDIR" start',
    'supabase --workdir "$LOCAL_WORKDIR" stop --no-backup',
    'supabase/schema.sql', 'MIGRATION_SEQUENCE_AMBIGUOUS_OR_MISSING',
    'seq 7 49', 'private.contractor_vacancy_submission_requests',
    'EXPECTED_M050_SHA256', 'EXPECTED_CHECKPOINT_SHA256',
    'supabase/migrations/050_vacancy_candidate_terms_snapshot.sql',
    'supabase/tests/050_vacancy_candidate_terms_snapshot_test.sql',
    'CHECKPOINT_SYNTHETIC_RESIDUE_ZERO', 'public.requirement_contractors',
    'public.candidate_applications', 'public.application_stage_history',
    'public.audit_logs', 'private.vacancy_candidate_benefits',
    'M050_LOCAL_RUNTIME_RESULT=PASS'
  ]) assert.ok(localRuntimeHarness.includes(token), token);
  assert.match(localRuntimeHarness, /EXPECTED_M050_SHA256="3d3ad4e03fd6b57699a6e0c73db1838040062917fb394526a441862d66a0ad44"/);
  assert.match(localRuntimeHarness, /EXPECTED_CHECKPOINT_SHA256="78881deb7e7d528052e216555e2ba779892d131bca1bffe9df96527569aef645"/);
  assert.doesNotMatch(localRuntimeHarness, /supabase\s+link\b|supabase\s+db\s+push\b|supabase\s+migration\s+up\b/i);
  assert.doesNotMatch(localRuntimeHarness, /supabase\s+stop\s+--all\b|supabase\s+--workdir\s+[^\n]+\s+stop\s+--all\b|\b(?:curl|wget)\b/i);
  assert.match(localRuntimeHarness, /psql\s+"\$LOCAL_DB_URL"\s+-X\s+-q\s+-v\s+ON_ERROR_STOP=1/);
  assert.match(localRuntimeHarness, /supabase --workdir "\$LOCAL_WORKDIR" status -o env[\s\S]*LOCAL_DB_URL=/);
  assert.match(localRuntimeHarness, /mkdir -p "\$LOCAL_WORKDIR\/supabase"[\s\S]*cp "\$REPOSITORY_ROOT\/supabase\/config\.toml" "\$LOCAL_WORKDIR\/supabase\/config\.toml"/);
  assert.match(localRuntimeHarness, /rm -f "\$RAW_OUTPUT" "\$STATUS_ENV"[\s\S]*supabase --workdir "\$LOCAL_WORKDIR" stop --no-backup[\s\S]*rm -rf "\$LOCAL_WORKDIR"/);

  assert.match(localRuntimeWorkflow, /^on:\s*\n\s+workflow_dispatch:/m);
  assert.doesNotMatch(localRuntimeWorkflow, /^\s*(push|pull_request|schedule):/m);
  assert.match(localRuntimeWorkflow, /runs-on:\s*ubuntu-24\.04/);
  assert.match(localRuntimeWorkflow, /timeout-minutes:\s*45/);
  assert.match(localRuntimeWorkflow, /permissions:\s*\n\s+contents:\s*read/m);
  assert.match(localRuntimeWorkflow, /actions\/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd/);
  assert.match(localRuntimeWorkflow, /supabase\/setup-cli@3c2f5e2ae34c34e428e8e206e2c4d21fa2d20fbf/);
  assert.match(localRuntimeWorkflow, /version:\s*2\.111\.0/);
  assert.match(localRuntimeWorkflow, /bash scripts\/ci\/run-m050-local-validation\.sh/);
  assert.doesNotMatch(localRuntimeWorkflow, /secrets\.|SUPABASE_ACCESS_TOKEN|SUPABASE_DB_PASSWORD|STAGING_SUPABASE|CLOUDFLARE|environment:/i);
});

test('M050 checkpoint failure diagnostics are closed-catalog and redact raw psql output', () => {
  const allowlist = localRuntimeHarness.match(/is_allowed_checkpoint_phase\(\) \{[\s\S]*?case "\$\{1:-\}" in([\s\S]*?)esac/);
  assert.ok(allowlist);
  for (const phase of checkpointDiagnosticPhases) {
    assert.match(checkpoint, new RegExp(`CHECKPOINT_050_PHASE=${phase}`));
    assert.match(allowlist[1], new RegExp(`\\b${phase}\\b`));
  }
  assert.match(localRuntimeHarness, /-v VERBOSITY=verbose -v SHOW_CONTEXT=errors/);
  assert.match(localRuntimeHarness, /\^\[0-9A-Z\]\{5\}\$/);
  assert.match(localRuntimeHarness, /M050_LOCAL_RUNTIME_CHECKPOINT_PHASE=/);
  assert.match(localRuntimeHarness, /M050_LOCAL_RUNTIME_SQLSTATE=/);
  assert.match(localRuntimeHarness, /M050_LOCAL_RUNTIME_SQL_ERROR=/);
  assert.match(localRuntimeHarness, /M050_LOCAL_RUNTIME_SQL_CONTEXT=/);
  assert.match(localRuntimeHarness, /M050_LOCAL_RUNTIME_UNDEFINED_IDENTIFIER=/);
  assert.match(localRuntimeHarness, /M050_LOCAL_RUNTIME_CHECKPOINT=PASS/);
  assert.match(localRuntimeHarness, /checkpoint_undefined_identifier\(\)/);
  assert.match(localRuntimeHarness, /\[A-Za-z_\]\[A-Za-z0-9_\$\]\*/);
  assert.doesNotMatch(localRuntimeHarness, /\b(?:cat|tee)\b[^\n]*RAW_OUTPUT/);
});

test('M050 SQLSTATE 42703 diagnostic exposes only a whitelisted identifier', (t) => {
  if (process.platform === 'win32') {
    t.skip('Ubuntu CI executes the Bash diagnostic extraction test.');
    return;
  }
  const harnessPath = path.join('scripts', 'ci', 'run-m050-local-validation.sh');
  const program = [
    'source "$1"',
    "printf 'psql: ERROR:  42703: record \"old\" has no field \"candidate_terms_status\"\\n' > \"$RAW_OUTPUT\"",
    'checkpoint_undefined_identifier 42703',
    "printf 'psql: ERROR:  42703: column \"unsafe;payload\" does not exist\\n' > \"$RAW_OUTPUT\"",
    'checkpoint_undefined_identifier 42703',
    "printf 'psql: ERROR:  42501: column \"candidate_terms_status\" does not exist\\n' > \"$RAW_OUTPUT\"",
    'checkpoint_undefined_identifier 42501',
    'checkpoint_sql_error',
    'checkpoint_sql_context'
  ].join('; ');
  const result = spawnSync('bash', ['-c', program, 'bash', harnessPath], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.stdout.trim().split(/\r?\n/), [
    'candidate_terms_status',
    'UNAVAILABLE',
    'UNAVAILABLE',
    'REDACTED',
    'REDACTED'
  ]);
});

test('M050 disposable local runtime harness is valid Bash on Linux CI', (t) => {
  if (process.platform === 'win32') {
    t.skip('Ubuntu CI executes the Bash parser check; this workstation routes bash through unavailable WSL.');
    return;
  }
  const result = spawnSync('bash', ['-n', path.join('scripts', 'ci', 'run-m050-local-validation.sh')], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
});
