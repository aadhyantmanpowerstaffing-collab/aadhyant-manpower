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

function candidateDetails() {
  const window = { AadhyantVacancyCompensation: helper() };
  const document = { body: { dataset: { candidatePage: 'jobs-batch2' } } };
  vm.runInNewContext(candidate, { window, document, location: { search: '' }, URLSearchParams });
  return window.aadhyantCandidateJobDetails;
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
  for (const token of ['Job Summary', 'Salary & Work Details', 'Eligibility', 'Facilities & Benefits', 'Interview & Joining', 'Job Description / Remarks', 'Salary Summary', 'Salary Breakup', 'Salary / CTC', 'Canteen', 'Transport', 'Accommodation', 'Department', 'Age Preference', 'Gender Preference', 'Interview Date', 'safe_description', 'Apply Now']) assert.ok(candidate.includes(token), `Candidate card is missing ${token}`);
  assert.match(candidateHtml, /vacancy-compensation\.js/);
  assert.match(candidate, /facilityCard/);
  assert.doesNotMatch(candidate, /compensation\?\.facility\([^)]*\)\s*\.join\(/);
  assert.doesNotMatch(candidate, /(contact_person|company_phone|billing|margin|service_charge|internal_note)/i);
});

test('Candidate job detail formats structured and legacy salary truthfully', () => {
  const details = candidateDetails();
  assert.equal(details.salaryText({ ctc: 25000, basic_da: 15000 }), '₹25,000');
  assert.equal(details.salaryText({ salary_min: 15000, salary_max: 25000 }), '₹15,000 – ₹25,000');
  assert.equal(details.salaryText({ salary_max: 15000 }), 'Up to ₹15,000');
});

test('Candidate facility detail shows only supported terms without inventing charges', () => {
  const details = candidateDetails();
  const normalize = (value) => JSON.parse(JSON.stringify(value));
  assert.deepEqual(normalize(details.accommodationDetails({ accommodation_status: 'free' })), { status: 'Free', terms: null });
  assert.deepEqual(normalize(details.accommodationDetails({ accommodation_status: 'chargeable', accommodation_charge_amount: 1500, accommodation_charge_basis: 'per_month' })), { status: 'Chargeable', terms: '₹1,500 / month' });
  assert.deepEqual(normalize(details.accommodationDetails({ accommodation_status: 'chargeable', accommodation_charge_amount: 30, accommodation_charge_basis: 'per_day' })), { status: 'Chargeable', terms: '₹30 / day' });
  assert.deepEqual(normalize(details.accommodationDetails({ accommodation_status: 'not_available' })), { status: 'Not Available', terms: null });
  assert.deepEqual(normalize(details.legacyFacilityDetails('Yes')), { status: 'Available', terms: null });
  assert.deepEqual(normalize(details.legacyFacilityDetails('No')), { status: 'Not Available', terms: null });
  assert.deepEqual(normalize(details.legacyFacilityDetails('Not Applicable')), { status: 'Not Applicable', terms: null });
});

test('Candidate job detail remains responsive and preserves candidate-safe Apply flow', () => {
  for (const token of ['@media(max-width:900px)', '@media(max-width:620px)', 'facility-cards', 'job-detail-apply', 'job-selector']) assert.ok(fs.readFileSync('candidate/portal/batch2-jobs.css', 'utf8').includes(token), `Missing responsive detail rule ${token}`);
  assert.match(candidate, /apply_candidate_job/);
  assert.match(candidate, /already_applied/);
  assert.doesNotMatch(candidate, /\.from\s*\(/);
});

test('Candidate job selector filters safe result fields and cannot retain a stale Apply target', () => {
  const details = candidateDetails();
  const rows = [
    { requirement_code: 'AAD-2026-000269', job_role: 'Helper', company_worksite_name: 'Mandal Mother Son', job_location: 'Mandal', salary_min: 15000, salary_max: 25000 },
    { requirement_code: 'AAD-2026-000270', job_role: 'Fitter', company_worksite_name: 'Sanand Works', job_location: 'Sanand', salary_max: 18000 }
  ];
  assert.equal(details.selectorLabel(rows[0]), 'AAD-2026-000269 — Helper — Mandal — ₹15,000 – ₹25,000');
  assert.deepEqual(JSON.parse(JSON.stringify(details.filterOpportunities(rows, 'helper').map((row) => row.requirement_code))), ['AAD-2026-000269']);
  assert.deepEqual(JSON.parse(JSON.stringify(details.filterOpportunities(rows, '000270').map((row) => row.requirement_code))), ['AAD-2026-000270']);
  assert.deepEqual(JSON.parse(JSON.stringify(details.filterOpportunities(rows, 'mother son').map((row) => row.requirement_code))), ['AAD-2026-000269']);
  assert.deepEqual(JSON.parse(JSON.stringify(details.filterOpportunities(rows, 'sanand').map((row) => row.requirement_code))), ['AAD-2026-000270']);
  assert.equal(details.reconcileSelectedCode(rows, 'AAD-2026-000270'), 'AAD-2026-000270');
  const filtered = details.filterOpportunities(rows, 'helper');
  const noResults = details.filterOpportunities(rows, 'no such opportunity');
  assert.equal(details.reconcileSelectedCode(filtered, 'AAD-2026-000270'), 'AAD-2026-000269');
  assert.equal(details.selectedOpportunity(filtered, 'AAD-2026-000270'), null);
  assert.equal(noResults.length, 0);
  assert.equal(details.reconcileSelectedCode(noResults, 'AAD-2026-000269'), '');
  assert.equal(details.filterOpportunities(rows, '').length, 2);
  assert.equal(details.selectedOpportunity(rows, 'AAD-2026-000270').requirement_code, 'AAD-2026-000270');
  assert.equal(details.applyTarget(details.selectedOpportunity(rows, 'AAD-2026-000270')), 'AAD-2026-000270');
  assert.equal(details.applyTarget(details.selectedOpportunity(filtered, 'AAD-2026-000270')), null);
});

test('Candidate selector renders one active detail view from existing Candidate-safe RPC results', () => {
  for (const token of ['data-job-select', 'data-no-results', 'selectorLabel', 'filterOpportunities', 'reconcileSelectedCode', 'applyTarget', 'list.append(detailCard(selected))', 'p_search: null', 'p_limit: pageSize', 'p_offset: offset']) assert.ok(`${candidate}\n${candidateHtml}`.includes(token), `Candidate selector is missing ${token}`);
  assert.doesNotMatch(candidate, /rows\.forEach\(\(row\)\s*=>\s*\{\s*const card = document\.createElement\('article'\)/);
});

test('Admin review displays compensation, accommodation and labelled facilities without changing review actions', () => {
  for (const token of ['compensationSection', 'Salary / Wage Details', 'Basic + DA', 'Approx. In-Hand', 'displayHelper?.facility', 'displayHelper?.accommodation', 'admin_approve_and_publish_vacancy', 'admin_request_vacancy_correction', 'admin_reject_vacancy']) assert.ok(admin.includes(token), `Admin detail is missing ${token}`);
  assert.doesNotMatch(admin, /\.from\s*\(/);
});
