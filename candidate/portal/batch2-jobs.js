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
    return compensation?.legacySalary?.(row) || null;
  };
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
      ['Canteen', present(row.canteen) ? legacyFacilityDetails(row.canteen) : null],
      ['Transport', present(row.transport) ? legacyFacilityDetails(row.transport) : null],
      ['Accommodation', present(row.accommodation_status) || present(row.accommodation) ? accommodationDetails(row) : null]
    ].forEach(([label, detail]) => { const card = facilityCard(label, detail); if (card) cards.append(card); });
    node.append(heading, cards);
    return node;
  };

  window.aadhyantCandidateJobDetails = Object.freeze({ accommodationDetails, legacyFacilityDetails, salaryText });

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
    const notice = document.querySelector('[data-message]');
    if (requested) search.value = requested;
    const message = (text, type = '') => { notice.textContent = text; notice.className = `message ${type}`; };
    const load = async () => {
      const rows = await call('list_candidate_job_opportunities', { p_search: search.value.trim() || null, p_limit: 50, p_offset: 0 }) || [];
      list.replaceChildren(); document.querySelector('[data-empty]').hidden = Boolean(rows.length);
      rows.forEach((row) => {
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
          salary.textContent = pay; heading.append(salary);
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
        const breakup = salaryBreakdown(row); if (breakup) card.append(breakup);
        const eligibility = section('Eligibility', [
          ['Qualification', row.qualification], ['Trade / Specialization', row.iti_trade], ['Experience', row.experience_requirement],
          ['Age Preference', agePreference(row)], ['Gender Preference', row.gender_preference]
        ]);
        if (eligibility) card.append(eligibility);
        const facilitySection = facilities(row); if (facilitySection) card.append(facilitySection);
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
          try { await call('apply_candidate_job', { p_requirement_code: row.requirement_code }); apply.textContent = 'Applied'; message('Application submitted to Aadhyant.', 'success'); }
          catch (_) { apply.disabled = false; message('Your application could not be submitted. Please refresh and try again.', 'error'); }
        };
        card.append(apply); list.append(card);
      });
    };
    document.querySelector('[data-search]').onsubmit = (event) => { event.preventDefault(); load().catch(() => message('Opportunities could not be loaded.', 'error')); };
    await load();
  }
  start().catch(() => { const node = document.querySelector('[data-message]'); if (node) node.textContent = 'Opportunities are temporarily unavailable.'; });
}());
