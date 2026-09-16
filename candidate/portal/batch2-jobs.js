(function () {
  'use strict';
  if (document.body?.dataset.candidatePage !== 'jobs-batch2') return;

  const client = window.aadhyantSupabase?.client;
  const compensation = window.AadhyantVacancyCompensation;
  const requested = String(new URLSearchParams(location.search).get('requirement') || '').trim().toUpperCase().match(/^[A-Z0-9_-]{1,64}$/)?.[0] || '';
  const call = async (name, args = {}) => { const { data, error } = await client.rpc(name, args); if (error) throw error; return data; };
  const date = (value) => value ? new Date(value).toLocaleDateString('en-IN', { dateStyle: 'medium' }) : null;
  const present = (value) => value !== null && value !== undefined && value !== '';
  const money = (value) => compensation?.money?.(value) || (Number.isFinite(Number(value)) ? `₹${Number(value).toLocaleString('en-IN', { maximumFractionDigits: 2 })}` : null);
  const words = (value) => String(value || '').trim().replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  const pair = (list, label, value) => {
    if (!present(value)) return;
    const item = document.createElement('div');
    const term = document.createElement('dt');
    const description = document.createElement('dd');
    term.textContent = label; description.textContent = String(value);
    item.append(term, description); list.append(item);
  };
  const section = (title, entries, className = '') => {
    const values = entries.filter(([, value]) => present(value));
    if (!values.length) return null;
    const node = document.createElement('section'); node.className = `job-detail-section ${className}`.trim();
    const heading = document.createElement('h3'); heading.textContent = title;
    const list = document.createElement('dl'); list.className = 'job-detail-grid';
    values.forEach(([label, value]) => pair(list, label, value));
    node.append(heading, list);
    return node;
  };
  const accommodationDetails = (row) => {
    const status = String(row.accommodation_status || '').trim().toLowerCase();
    if (status === 'free') return { status: 'Free', terms: null };
    if (status === 'not_available') return { status: 'Not Available', terms: null };
    if (status === 'chargeable') {
      const amount = money(row.accommodation_charge_amount);
      const basis = { per_day: 'day', per_month: 'month' }[String(row.accommodation_charge_basis || '').trim().toLowerCase()] || words(row.accommodation_charge_basis);
      return { status: 'Chargeable', terms: amount && basis ? `${amount} / ${basis}` : amount || basis || null };
    }
    return { status: compensation?.facility?.(row.accommodation) || words(row.accommodation), terms: null };
  };
  const legacyFacilityDetails = (value) => ({ status: compensation?.facility?.(value) || words(value), terms: null });
  const structuredFacilityDetails = (status, amount, chargeBasis, legacy) => {
    if (!status) return legacyFacilityDetails(legacy);
    if (status === 'chargeable') { const basis = { per_day: 'day', per_meal: 'meal', per_month: 'month' }[chargeBasis] || words(chargeBasis); return { status: 'Chargeable', terms: amount != null && basis ? `${money(amount)} / ${basis}` : null }; }
    return { status: words(status), terms: null };
  };
  const agePreference = (row) => {
    const min = present(row.age_min) ? row.age_min : null;
    const max = present(row.age_max) ? row.age_max : null;
    if (min && max) return `${min}–${max} years`;
    if (min) return `${min}+ years`;
    if (max) return `Up to ${max} years`;
    return null;
  };
  const salaryText = (row) => {
    if (compensation?.hasStructuredSalary?.(row)) return money(row.ctc) || money(row.gross_wages) || null;
    return compensation?.legacySalary?.(row) || (present(row.salary_wage) ? row.salary_wage : null);
  };
  const selectorLabel = (row) => [row.requirement_code, row.job_role || 'Vacancy', row.job_location, salaryText(row)].filter(present).join(' — ');
  const filterOpportunities = (rows, searchTerm) => {
    const term = String(searchTerm || '').trim().toLowerCase();
    if (!term) return rows;
    return rows.filter((row) => [row.requirement_code, row.job_role, row.company_worksite_name, row.job_location]
      .some((value) => String(value || '').toLowerCase().includes(term)));
  };
  const selectedOpportunity = (rows, requirementCode) => rows.find((row) => row.requirement_code === requirementCode) || null;
  const reconcileSelectedCode = (rows, requirementCode) => selectedOpportunity(rows, requirementCode)?.requirement_code || rows[0]?.requirement_code || '';
  const applyTarget = (row) => row?.requirement_code || null;
  const facilityCard = (label, detail) => {
    if (!detail?.status) return null;
    const item = document.createElement('article'); item.className = 'facility-card';
    const title = document.createElement('h4'); title.textContent = label;
    const status = document.createElement('p'); status.className = 'facility-status'; status.textContent = detail.status;
    item.append(title, status);
    if (detail.terms) {
      const terms = document.createElement('p'); terms.className = 'facility-terms'; terms.textContent = detail.terms;
      item.append(terms);
    }
    return item;
  };
  const salaryBreakdown = (row) => {
    if (!compensation?.hasStructuredSalary(row)) return null;
    const section = document.createElement('section'); section.className = 'salary-breakdown';
    const heading = document.createElement('h3'); heading.textContent = 'Salary Breakup'; section.append(heading);
    const groups = [
      ['Earnings', ['basicDa', 'attendanceBonus', 'monthlyBonus', 'leaveAmount', 'otherFixedEarning']],
      ['Deductions', ['employeePf', 'employeeEsic', 'canteenDeduction', 'otherDeduction']],
      ['Employer / CTC', ['employerPf', 'employerEsic', 'gratuityProvision', 'bonusProvision', 'leaveProvision', 'otherCtcComponent']]
    ];
    groups.forEach(([title, names]) => {
      const entries = names.map((name) => [compensation.columns[name], row[compensation.columns[name]]]).filter(([, value]) => present(value));
      if (!entries.length) return;
      const group = document.createElement('div'); group.className = 'salary-breakdown-group';
      const label = document.createElement('h4'); label.textContent = title;
      const list = document.createElement('dl');
      entries.forEach(([column, value]) => pair(list, compensation.labels?.[column] || column.replaceAll('_', ' '), compensation.money(value)));
      group.append(label, list); section.append(group);
    });
    return section;
  };
  const salarySummary = (row) => {
    if (!compensation?.hasStructuredSalary(row)) return null;
    const section = document.createElement('section'); section.className = 'vacancy-detail-summary';
    const heading = document.createElement('h4'); heading.textContent = 'Salary Summary';
    const list = document.createElement('dl');
    pair(list, 'Gross Salary', compensation.money(row.gross_wages));
    pair(list, 'Approx. In-Hand', compensation.money(row.approx_in_hand));
    pair(list, 'CTC', compensation.money(row.ctc));
    section.append(heading, list);
    return section;
  };
  const facilities = (row) => {
    if (!present(row.canteen) && !present(row.transport) && !present(row.accommodation_status) && !present(row.accommodation)) return null;
    const node = document.createElement('section'); node.className = 'job-detail-section facility-list';
    const heading = document.createElement('h3'); heading.textContent = 'Facilities & Benefits';
    const cards = document.createElement('div'); cards.className = 'facility-cards';
    [
      ['Canteen', structuredFacilityDetails(row.canteen_status, row.canteen_charge_amount, row.canteen_charge_basis, row.canteen)],
      ['Transport', structuredFacilityDetails(row.transport_status, row.transport_charge_amount, row.transport_charge_basis, row.transport)],
      ['Accommodation', present(row.accommodation_status) || present(row.accommodation) ? accommodationDetails(row) : null]
    ].forEach(([label, detail]) => { const card = facilityCard(label, detail); if (card) cards.append(card); });
    node.append(heading, cards);
    return node;
  };
  const termsDisclosure = (row) => {
    const details = document.createElement('details'); details.className = 'candidate-terms-disclosure';
    const summary = document.createElement('summary'); summary.textContent = 'View Salary, Benefits & Employment Terms'; details.append(summary);
    const cadence = row.compensation_cadence === 'monthly' ? 'Monthly CTC' : row.compensation_cadence === 'annual' ? 'Annual CTC' : 'CTC';
    const ctc = section('Salary & CTC Breakdown', [['Basic + DA', money(row.basic_da)], ['Attendance Bonus', money(row.attendance_bonus)], ['Monthly Bonus', money(row.monthly_bonus)], ['EL / Leave Amount', money(row.leave_amount)], ['Other Fixed Earning', money(row.other_fixed_earning)], ['Gross Salary — Before listed employee deductions', money(row.gross_wages)], [cadence, money(row.ctc)]]);
    const deductions = section('Deductions / Approx. In-Hand', [['Employee PF', money(row.employee_pf)], ['Employee ESIC', money(row.employee_esic)], ['Canteen Deduction', money(row.canteen_deduction)], ['Other Deduction', money(row.other_deduction)], ['Approx. In-Hand — Approximate amount after listed employee deductions', money(row.approx_in_hand)]]);
    const employer = section('Employer CTC Components', [['Employer PF', money(row.employer_pf)], ['Employer ESIC', money(row.employer_esic)], ['Gratuity Provision', money(row.gratuity_provision)], ['Bonus Provision', money(row.bonus_provision)], ['Leave Provision', money(row.leave_provision)], ['Other CTC Component', money(row.other_ctc_component)]]);
    const leave = section('Leave & Holidays', [['Paid / Earned Leave (days/year)', row.paid_leave_days_per_year], ['Casual Leave (days/year)', row.casual_leave_days_per_year], ['Sick Leave (days/year)', row.sick_leave_days_per_year], ['National Holidays (days/year)', row.national_holiday_days_per_year], ['Festival Holidays (days/year)', row.festival_holiday_days_per_year]]);
    const work = section('Working Terms', [['Duty Hours', row.working_hours], ['Working Days / Week', row.working_days_per_week], ['Weekly Offs / Week', row.weekly_off_count], ['Shift', row.shift_details], ['Overtime', row.overtime_details], ['OT Rate', present(row.overtime_rate) ? `${money(row.overtime_rate)} / ${words(row.overtime_rate_basis)}` : null]]);
    const facility = facilities(row);
    const benefits = Array.isArray(row.candidate_benefits) && row.candidate_benefits.length ? section('Other Benefits', row.candidate_benefits.map((benefit) => [words(benefit.benefit_type), benefit.benefit_value_type === 'cash' ? `${money(benefit.amount)} / ${words(benefit.amount_basis)}` : 'Provided'])) : null;
    const employment = section('Employment Terms', [['Employment Type', words(row.employment_type)], ['Payroll', row.payroll_type ? ({ company: 'Company Payroll', contractor: 'Contractor Payroll', third_party: 'Third-party Payroll' }[row.payroll_type] || words(row.payroll_type)) : null], ['Contract Duration', present(row.contract_duration_months) ? `${row.contract_duration_months} months` : null], ['Probation', present(row.probation_period_months) ? `${row.probation_period_months} months` : null], ['Training', present(row.training_period_days) ? `${row.training_period_days} days` : null], ['Notice Period', present(row.notice_period_days) ? `${row.notice_period_days} days` : null]]);
    [ctc, deductions, employer, leave, work, facility, benefits, employment].filter(Boolean).forEach((node) => details.append(node));
    return details.childElementCount > 1 ? details : null;
  };

  window.aadhyantCandidateJobDetails = Object.freeze({
    accommodationDetails, legacyFacilityDetails, structuredFacilityDetails, salaryText, selectorLabel, filterOpportunities, selectedOpportunity, reconcileSelectedCode, applyTarget
  });

  async function start() {
    if (!client) return;
    const { data: sessionData } = await client.auth.getSession();
    if (!sessionData.session) { location.replace('login.html'); return; }
    try { await call('get_candidate_portal_context'); } catch (_) { location.replace('login.html'); return; }
    document.querySelector('[data-loading]')?.setAttribute('hidden', '');
    document.querySelector('[data-portal]')?.removeAttribute('hidden');
    document.querySelectorAll('[data-logout]').forEach((button) => { button.onclick = async () => { await client.auth.signOut(); location.replace('login.html'); }; });
    const list = document.querySelector('[data-job-list]');
    const search = document.querySelector('[name=search]');
    const selector = document.querySelector('[data-job-select]');
    const notice = document.querySelector('[data-message]');
    const empty = document.querySelector('[data-empty]');
    const noResults = document.querySelector('[data-no-results]');
    let allRows = [];
    let selectedCode = requested;
    if (requested) search.value = requested;
    const message = (text, type = '') => { notice.textContent = text; notice.className = `message ${type}`; };
    const detailCard = (row) => {
        const card = document.createElement('article'); card.className = 'job job-detail-card';
        const heading = document.createElement('header'); heading.className = 'job-detail-hero';
        heading.append(
          Object.assign(document.createElement('p'), { className: 'eyebrow', textContent: row.requirement_code }),
          Object.assign(document.createElement('h2'), { textContent: row.job_role || 'Vacancy' }),
          Object.assign(document.createElement('p'), { textContent: `${row.job_location || 'Location not specified'} · ${row.open_positions} openings` })
        );
        const pay = salaryText(row);
        if (pay) {
          const salary = document.createElement('p'); salary.className = 'job-detail-pay';
          salary.textContent = `${row.compensation_cadence === 'monthly' ? 'Monthly CTC ' : row.compensation_cadence === 'annual' ? 'Annual CTC ' : ''}${pay}`; heading.append(salary);
          if (present(row.approx_in_hand)) heading.append(Object.assign(document.createElement('p'), { className: 'job-detail-in-hand', textContent: `Approx. In-Hand ${money(row.approx_in_hand)}` }));
        }
        card.append(heading);
        const summary = section('Job Summary', [
          ['Vacancy Code', row.requirement_code], ['Role', row.job_role], ['Company / Worksite', row.company_worksite_name],
          ['Department', row.department], ['Location', row.job_location], ['Openings', row.open_positions]
        ]);
        if (summary) card.append(summary);
        const work = section('Salary & Work Details', [
          ['Salary / CTC', pay], ['Duty Hours', row.working_hours], ['Shift', row.shift_details], ['Overtime', row.overtime_details]
        ], 'salary-work-section');
        if (work) card.append(work);
        const structuredSummary = salarySummary(row); if (structuredSummary) work?.append(structuredSummary);
        const eligibility = section('Eligibility', [
          ['Qualification', row.qualification], ['Trade / Specialization', row.iti_trade], ['Experience', row.experience_requirement],
          ['Age Preference', agePreference(row)], ['Gender Preference', row.gender_preference]
        ]);
        if (eligibility) card.append(eligibility);
        const disclosure = termsDisclosure(row); if (disclosure) card.append(disclosure);
        const interview = section('Interview & Joining', [
          ['Interview Location', row.interview_location], ['Interview Date', date(row.interview_date)], ['Expected Joining', date(row.expected_joining_date)]
        ]);
        if (interview) card.append(interview);
        const description = section('Job Description / Remarks', [['Description', row.safe_description]], 'job-description-section');
        if (description) card.append(description);
        const apply = document.createElement('button');
        apply.className = 'button job-detail-apply'; apply.type = 'button'; apply.textContent = row.already_applied ? 'Applied' : 'Apply Now'; apply.disabled = Boolean(row.already_applied);
        apply.onclick = async () => {
          apply.disabled = true;
          try {
            await call('apply_candidate_job', { p_requirement_code: applyTarget(row) });
            row.already_applied = true; message('Application submitted to Aadhyant.', 'success'); render();
          }
          catch (_) { apply.disabled = false; message('Your application could not be submitted. Please refresh and try again.', 'error'); }
        };
        card.append(apply);
        return card;
    };
    const render = () => {
      const rows = filterOpportunities(allRows, search.value);
      selectedCode = reconcileSelectedCode(rows, selectedCode);
      const selected = selectedOpportunity(rows, selectedCode);
      selector.replaceChildren();
      rows.forEach((row) => {
        const option = document.createElement('option'); option.value = row.requirement_code; option.textContent = selectorLabel(row);
        selector.append(option);
      });
      selector.disabled = !rows.length;
      if (selected) selector.value = selected.requirement_code;
      list.replaceChildren();
      if (selected) list.append(detailCard(selected));
      empty.hidden = Boolean(allRows.length);
      noResults.hidden = !allRows.length || Boolean(rows.length);
    };
    const load = async () => {
      const pageSize = 50;
      let offset = 0;
      let rows = [];
      do {
        const page = await call('list_candidate_job_opportunities', { p_search: null, p_limit: pageSize, p_offset: offset }) || [];
        rows = rows.concat(page); offset += page.length;
        if (page.length < pageSize) break;
      } while (offset <= 5000);
      allRows = rows;
      render();
    };
    document.querySelector('[data-search]').onsubmit = (event) => { event.preventDefault(); render(); };
    search.oninput = () => render();
    selector.onchange = () => { selectedCode = selector.value; render(); };
    await load();
  }
  start().catch(() => { const node = document.querySelector('[data-message]'); if (node) node.textContent = 'Opportunities are temporarily unavailable.'; });
}());
