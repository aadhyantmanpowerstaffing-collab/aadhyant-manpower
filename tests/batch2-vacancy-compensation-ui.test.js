const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const read = (file) => fs.readFileSync(file, 'utf8');
const sharedSource = read('assets/js/vacancy-compensation.js');
const companyHtml = read('company/requirements.html');
const company = read('company/batch2-vacancies.js');
const contractorHtml = read('contractor/vacancies.html');
const contractor = read('contractor/batch2-vacancies.js');
const candidate = read('candidate/portal/batch2-jobs.js');
const candidateHtml = read('candidate/portal/jobs.html');
const admin = read('admin/vacancy-review.js');

function helper() {
  const window = {};
  vm.runInNewContext(sharedSource, { window });
  return window.AadhyantVacancyCompensation;
}

test('shared wage helper calculates the approved deterministic salary contract', () => {
  const result = helper().calculate({ basicDa: 10000, attendanceBonus: 500, monthlyBonus: 300, leaveAmount: 200, otherFixedEarning: 0, employeePf: 600, employeeEsic: 100, canteenDeduction: 200, otherDeduction: 100, employerPf: 700, employerEsic: 150, gratuityProvision: 300, bonusProvision: 250, leaveProvision: 100, otherCtcComponent: 0 });
  assert.equal(result.grossWages, 11000);
  assert.equal(result.approxInHand, 10000);
  assert.equal(result.ctc, 12500);
});

test('Company and Contractor use the same compensation inputs, accommodation model, and canonical lifecycle RPCs', () => {
  for (const label of ['Payable Days', 'Basic + DA', 'Attendance Bonus', 'Monthly Bonus', 'EL / Leave Amount', 'Other Fixed Earning', 'Employee PF', 'Employee ESIC', 'Canteen Deduction', 'Other Deduction', 'Employer PF', 'Employer ESIC', 'Gratuity Provision', 'Bonus Provision', 'Leave Provision', 'Other CTC Component', 'Gross Wages', 'Approx In-Hand', 'CTC', 'Not Available', 'Free', 'Chargeable', 'Per Day', 'Per Month']) {
    assert.ok(companyHtml.includes(label), `Company is missing ${label}`);
    assert.ok(contractorHtml.includes(label), `Contractor is missing ${label}`);
  }
  for (const rpc of ['delete_company_portal_draft_vacancy', 'withdraw_company_portal_vacancy', 'close_company_portal_open_vacancy']) assert.match(company, new RegExp(rpc));
  for (const rpc of ['delete_contractor_portal_draft_vacancy', 'withdraw_contractor_portal_vacancy', 'close_contractor_portal_open_vacancy']) assert.match(contractor, new RegExp(rpc));
  assert.match(contractor, /requirement_visibility === undefined/);
  assert.doesNotMatch(`${company}\n${contractor}`, /\.from\s*\(/);
});

test('Candidate job cards render candidate-safe labelled salary and facilities, with legacy fallback', () => {
  for (const token of ['company_worksite_name', 'Salary Summary', 'Salary Breakup', 'Salary / CTC', 'Canteen', 'Transport', 'Accommodation', 'compensation?.accommodation', 'safe_description']) assert.ok(candidate.includes(token), `Candidate card is missing ${token}`);
  assert.match(candidateHtml, /vacancy-compensation\.js/);
  assert.doesNotMatch(candidate, /join\(['"] .*['"]\)/);
  assert.doesNotMatch(candidate, /(contact_person|company_phone|billing|margin|service_charge|internal_note)/i);
});

test('Admin review displays compensation, accommodation and labelled facilities without changing review actions', () => {
  for (const token of ['compensationSection', 'Salary / Wage Details', 'Basic + DA', 'Approx. In-Hand', 'displayHelper?.facility', 'displayHelper?.accommodation', 'admin_approve_and_publish_vacancy', 'admin_request_vacancy_correction', 'admin_reject_vacancy']) assert.ok(admin.includes(token), `Admin detail is missing ${token}`);
  assert.doesNotMatch(admin, /\.from\s*\(/);
});
