(function () {
  'use strict';
  if (document.body?.dataset.candidatePage !== 'jobs-batch2') return;

  const client = window.aadhyantSupabase?.client;
  const compensation = window.AadhyantVacancyCompensation;
  const requested = String(new URLSearchParams(location.search).get('requirement') || '').trim().toUpperCase().match(/^[A-Z0-9_-]{1,64}$/)?.[0] || '';
  const call = async (name, args = {}) => { const { data, error } = await client.rpc(name, args); if (error) throw error; return data; };
  const date = (value) => value ? new Date(value).toLocaleDateString('en-IN', { dateStyle: 'medium' }) : null;
  const present = (value) => value !== null && value !== undefined && value !== '';
  const pair = (list, label, value) => {
    if (!present(value)) return;
    const item = document.createElement('div');
    const term = document.createElement('dt');
    const description = document.createElement('dd');
    term.textContent = label; description.textContent = String(value);
    item.append(term, description); list.append(item);
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
    const heading = document.createElement('h3'); heading.textContent = 'Salary Summary';
    const list = document.createElement('dl');
    pair(list, 'Gross Salary', compensation.money(row.gross_wages));
    pair(list, 'Approx. In-Hand', compensation.money(row.approx_in_hand));
    pair(list, 'CTC', compensation.money(row.ctc));
    section.append(heading, list);
    return section;
  };
  const facilities = (row) => {
    if (!present(row.canteen) && !present(row.transport) && !present(row.accommodation_status) && !present(row.accommodation)) return null;
    const section = document.createElement('section'); section.className = 'facility-list';
    const heading = document.createElement('h3'); heading.textContent = 'Facilities';
    const list = document.createElement('dl');
    if (present(row.canteen)) pair(list, 'Canteen', compensation?.facility(row.canteen) || row.canteen);
    if (present(row.transport)) pair(list, 'Transport', compensation?.facility(row.transport) || row.transport);
    if (present(row.accommodation_status) || present(row.accommodation)) pair(list, 'Accommodation', compensation?.accommodation(row) || row.accommodation);
    section.append(heading, list);
    return section;
  };

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
        const card = document.createElement('article'); card.className = 'job';
        const heading = document.createElement('div');
        heading.append(
          Object.assign(document.createElement('p'), { className: 'eyebrow', textContent: row.requirement_code }),
          Object.assign(document.createElement('h2'), { textContent: row.job_role || 'Vacancy' }),
          Object.assign(document.createElement('p'), { textContent: `${row.job_location || 'Location not specified'} · ${row.open_positions} openings` })
        );
        card.append(heading);
        const detail = document.createElement('dl'); detail.className = 'grid';
        pair(detail, 'Vacancy Code', row.requirement_code);
        pair(detail, 'Role', row.job_role);
        pair(detail, 'Company / Worksite', row.company_worksite_name);
        pair(detail, 'Location', row.job_location);
        pair(detail, 'Openings', row.open_positions);
        pair(detail, 'Qualification', row.qualification);
        pair(detail, 'Trade / Specialization', row.iti_trade);
        pair(detail, 'Experience', row.experience_requirement);
        pair(detail, 'Shift', row.shift_details);
        pair(detail, 'Duty Hours', row.working_hours);
        pair(detail, 'OT Details', row.overtime_details);
        pair(detail, 'Interview Location', row.interview_location);
        pair(detail, 'Expected Joining', date(row.expected_joining_date));
        pair(detail, 'Description', row.safe_description);
        if (!compensation?.hasStructuredSalary(row)) pair(detail, 'Salary / CTC', compensation?.legacySalary(row) || null);
        card.append(detail);
        const summary = salarySummary(row); if (summary) card.append(summary);
        const breakup = salaryBreakdown(row); if (breakup) card.append(breakup);
        const facilitySection = facilities(row); if (facilitySection) card.append(facilitySection);
        const apply = document.createElement('button');
        apply.className = 'button'; apply.type = 'button'; apply.textContent = row.already_applied ? 'Applied' : 'Apply'; apply.disabled = Boolean(row.already_applied);
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
