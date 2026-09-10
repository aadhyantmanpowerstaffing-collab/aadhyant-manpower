const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '044_vacancy_compensation_accommodation_lifecycle.sql'), 'utf8');
const wageFields = ['basic_da','attendance_bonus','monthly_bonus','leave_amount','other_fixed_earning','gross_wages','employee_pf','employee_esic','canteen_deduction','other_deduction','employer_pf','employer_esic','gratuity_provision','bonus_provision','leave_provision','other_ctc_component','approx_in_hand','ctc'];

function validWage(v) {
  if (v.payable_days != null && (!Number.isInteger(v.payable_days) || v.payable_days < 1 || v.payable_days > 31)) return false;
  if (wageFields.some((name) => v[name] != null && (!Number.isFinite(v[name]) || v[name] < 0))) return false;
  const n = (name) => v[name] ?? 0;
  if (wageFields.every((name) => v[name] == null)) return true;
  const gross = n('basic_da') + n('attendance_bonus') + n('monthly_bonus') + n('leave_amount') + n('other_fixed_earning');
  const inHand = gross - n('employee_pf') - n('employee_esic') - n('canteen_deduction') - n('other_deduction');
  const ctc = gross + n('employer_pf') + n('employer_esic') + n('gratuity_provision') + n('bonus_provision') + n('leave_provision') + n('other_ctc_component');
  return v.gross_wages === gross && v.approx_in_hand === inHand && v.ctc === ctc && inHand >= 0;
}
function validAccommodation(status, amount = null, basis = null) {
  if (status == null) return amount == null && basis == null;
  if (status === 'chargeable') return Number.isFinite(amount) && amount > 0 && ['per_day', 'per_month'].includes(basis);
  return ['not_available', 'free'].includes(status) && amount == null && basis == null;
}

test('Migration 044 is additive and retains legacy salary/facility compatibility', () => {
  for (const name of ['payable_days', ...wageFields, 'accommodation_status', 'accommodation_charge_amount', 'accommodation_charge_basis']) assert.match(migration, new RegExp(`add column if not exists ${name}`));
  assert.match(migration, /Legacy salary_wage\/salary_min\/salary_max/);
  assert.doesNotMatch(migration, /drop column\s+(salary_wage|salary_min|salary_max)/i);
});

test('wage calculation contract accepts valid totals and rejects negative or malformed values', () => {
  const valid = { payable_days: 26,basic_da:10000,attendance_bonus:500,monthly_bonus:300,leave_amount:200,other_fixed_earning:0,gross_wages:11000,employee_pf:600,employee_esic:100,canteen_deduction:200,other_deduction:100,employer_pf:700,employer_esic:150,gratuity_provision:300,bonus_provision:250,leave_provision:100,other_ctc_component:0,approx_in_hand:10000,ctc:12500 };
  assert.equal(validWage(valid), true);
  assert.equal(validWage({...valid,gross_wages:1}), false);
  assert.equal(validWage({...valid,approx_in_hand:1}), false);
  assert.equal(validWage({...valid,ctc:1}), false);
  assert.equal(validWage({...valid,employee_pf:-1}), false);
  assert.equal(validWage({...valid,payable_days:32}), false);
  assert.match(migration, /employer_requirements_wage_totals_check/);
});

test('accommodation validates its canonical states separately from compensation', () => {
  assert.equal(validAccommodation('not_available'), true);
  assert.equal(validAccommodation('free'), true);
  assert.equal(validAccommodation('chargeable', 80, 'per_day'), true);
  assert.equal(validAccommodation('chargeable', 1500, 'per_month'), true);
  assert.equal(validAccommodation('chargeable', null, 'per_month'), false);
  assert.equal(validAccommodation('free', 1, null), false);
  assert.match(migration, /accommodation_status.*not_available.*free.*chargeable/s);
  assert.match(migration, /accommodation_charge_amount is not null and accommodation_charge_amount>0/);
  const wageConstraint = migration.slice(
    migration.indexOf('employer_requirements_wage_totals_check'),
    migration.indexOf('employer_requirements_accommodation_status_check')
  );
  assert.doesNotMatch(wageConstraint, /accommodation_charge_(amount|basis)/);
});

test('Company and Contractor share extended RPC semantics and protected lifecycle actions', () => {
  for (const rpc of ['manage_company_portal_vacancy','manage_company_portal_requirement','manage_contractor_portal_vacancy']) assert.match(migration, new RegExp(`create function public\\.${rpc}\\(`));
  for (const action of ['delete_company_portal_draft_vacancy','withdraw_company_portal_vacancy','close_company_portal_open_vacancy','delete_contractor_portal_draft_vacancy','withdraw_contractor_portal_vacancy','close_contractor_portal_open_vacancy']) assert.match(migration, new RegExp(`create function public\\.${action}`));
  assert.match(migration, /private\.vacancy_has_recruitment_dependencies/);
  assert.match(migration, /candidate_applications/);
  assert.match(migration, /interviews/);
  assert.match(migration, /candidate_joinings/);
  assert.doesNotMatch(migration, /on delete cascade/i);
  assert.match(migration, /extended vacancy management RPC security postcondition failed/);
  assert.match(migration, /vacancy lifecycle RPC security postcondition failed/);
  assert.match(migration, /Only a draft vacancy can be deleted/);
  assert.match(migration, /Only a pending-review vacancy can be withdrawn/);
  assert.match(migration, /Only a published open vacancy can be closed/);
});

test('safe projections include approved compensation and accommodation without contacts or commercial fields', () => {
  for (const projection of ['list_candidate_job_opportunities','get_public_job_requirements','get_company_portal_requirement','get_contractor_portal_vacancy','admin_get_vacancy_review_detail','admin_get_job_lead_detail']) assert.match(migration, new RegExp(`function public\\.${projection}`));
  for (const ownerProjection of ['list_company_portal_requirements','list_contractor_portal_vacancies']) assert.match(migration, new RegExp(`function public\\.${ownerProjection}`));
  assert.match(migration, /company_worksite_name text/);
  assert.match(migration, /private\.vacancy_compensation_projection/);
  const candidateProjection = migration.slice(
    migration.indexOf('create function public.list_candidate_job_opportunities'),
    migration.indexOf('drop function if exists public.get_public_job_requirements')
  );
  assert.match(candidateProjection, /private\.vacancy_is_application_eligible/);
  assert.match(candidateProjection, /private\.current_candidate_portal_id/);
  assert.doesNotMatch(candidateProjection, /r\.(contact_person|mobile|email|company_phone|billing|margin|service_charge)/i);
});
