(function () {
  'use strict';
  if (document.body?.dataset.contractorPage !== 'vacancies-batch2') return;

  const client = window.aadhyantSupabase?.client;
  const options = window.AadhyantRegistrationOptions;
  const compensation = window.AadhyantVacancyCompensation;
  const candidateTerms = window.AadhyantVacancyCandidateTerms;
  const fields = ['clientName', 'department', 'jobRole', 'jobLocation', 'requiredHeadcount', 'qualification', 'itiTrade', 'experienceRequirement', 'genderPreference', 'ageMin', 'ageMax', 'salaryMin', 'salaryMax', 'shiftDetails', 'workingHours', 'overtimeDetails', 'canteen', 'transport', 'interviewLocation', 'expectedJoiningDate', 'additionalNotes'];
  const map = { clientName: 'client_name', department: 'department', jobRole: 'job_role', jobLocation: 'job_location', requiredHeadcount: 'required_headcount', qualification: 'qualification', itiTrade: 'iti_trade', experienceRequirement: 'experience_requirement', genderPreference: 'gender_preference', ageMin: 'age_min', ageMax: 'age_max', salaryMin: 'salary_min', salaryMax: 'salary_max', shiftDetails: 'shift_details', workingHours: 'working_hours', overtimeDetails: 'overtime_details', canteen: 'canteen', transport: 'transport', interviewLocation: 'interview_location', expectedJoiningDate: 'expected_joining_date', additionalNotes: 'additional_notes' };
  const numericFields = new Set(['requiredHeadcount', 'ageMin', 'ageMax', 'salaryMin', 'salaryMax']);
  const call = async (name, args = {}) => { const { data, error } = await client.rpc(name, args); if (error) throw error; return data; };
  const first = (value) => Array.isArray(value) ? value[0] : value;
  const indiaToday = () => {
    const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date());
    return `${parts.find((part) => part.type === 'year').value}-${parts.find((part) => part.type === 'month').value}-${parts.find((part) => part.type === 'day').value}`;
  };
  const newSubmissionKey = () => {
    if (!window.crypto?.randomUUID) throw new Error('Secure submission identifiers are unavailable. Refresh and try again.');
    return window.crypto.randomUUID();
  };
  const statusFor = (row = {}) => {
    const review = row.normalized_review_status || row.submission_status;
    if (['closed', 'cancelled'].includes(row.requirement_stage) || review === 'cancelled') return 'Closed';
    if (review === 'rejected') return 'Rejected';
    if (review === 'correction_required') return 'Correction Required';
    if (review === 'approved' && row.requirement_stage === 'open' && (row.requirement_visibility === undefined || row.requirement_visibility === 'public')) return 'Published / Open';
    if (['submitted', 'under_review', 'pending_review'].includes(review)) return 'Pending Review';
    return 'Draft';
  };

  async function start() {
    if (!client) return;
    const { data: sessionData } = await client.auth.getSession();
    if (!sessionData.session) { location.replace('login.html'); return; }
    let context;
    try { context = first(await call('get_contractor_portal_context')); } catch (_) { location.replace('login.html'); return; }
    if (!context?.can_manage_vacancies && context?.platform_status !== 'active') { location.replace('index.html'); return; }

    document.querySelector('[data-loading]')?.setAttribute('hidden', '');
    document.querySelector('[data-portal]')?.removeAttribute('hidden');
    document.querySelectorAll('[data-user-email]').forEach((node) => { node.textContent = sessionData.session.user.email || ''; });
    document.querySelectorAll('[data-logout]').forEach((button) => { button.onclick = async () => { await client.auth.signOut(); location.replace('login.html'); }; });

    const body = document.querySelector('[data-vacancies-body]');
    const dialog = document.querySelector('[data-vacancy-dialog]');
    const form = document.querySelector('[data-vacancy-form]');
    const pageMessage = document.querySelector('[data-page-message]');
    const formMessage = document.querySelector('[data-vacancy-form-message]');
    let current = null;
    let submitInFlight = false;
    let submissionKey = null;
    let originalExpectedJoiningDate = '';
    const message = (text, type = '', inForm = false) => {
      pageMessage.textContent = text; pageMessage.className = `message ${type}`;
      if (formMessage) { formMessage.textContent = inForm ? text : ''; formMessage.hidden = !inForm; }
    };
    const setSubmitInFlight = (value) => {
      submitInFlight = value;
      form.querySelectorAll('[data-submit],[data-save]').forEach((button) => { button.disabled = value; });
    };
    const valid = () => {
      if (!['clientName', 'jobRole', 'jobLocation'].every((name) => form.elements[name].value.trim()) || Number(form.elements.requiredHeadcount.value) <= 0) {
        message('Client/worksite, role, location, and openings are required.', 'error', true);
        return false;
      }
      const error = compensation?.validate(form);
      if (error) { message(error, 'error', true); return false; }
      const termsError = candidateTerms?.validate(form);
      if (termsError) { message(termsError, 'error', true); return false; }
      const minimum = form.elements.salaryMin.value === '' ? null : Number(form.elements.salaryMin.value);
      const maximum = form.elements.salaryMax.value === '' ? null : Number(form.elements.salaryMax.value);
      if (minimum !== null && maximum !== null && minimum > maximum) {
        message('Minimum CTC cannot exceed Maximum CTC.', 'error', true); return false;
      }
      const expectedJoining = form.elements.expectedJoiningDate.value;
      const editingHistoricalDate = Boolean(form.elements.requirementId.value) && expectedJoining === originalExpectedJoiningDate;
      if (expectedJoining && expectedJoining < indiaToday() && !editingHistoricalDate) {
        message('Expected joining date must be today or a future date.', 'error', true); return false;
      }
      if (!form.checkValidity()) { form.reportValidity(); return false; }
      return true;
    };
    const params = () => {
      const data = new FormData(form), result = {};
      fields.forEach((name) => {
        let value = String(data.get(name) || '').trim();
        if (numericFields.has(name)) value = value === '' ? null : Number(value);
        result[`p_${name.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)}`] = value === '' ? null : value;
      });
      return { ...result, p_accommodation: null, ...(compensation?.rpcParams(form) || {}), p_candidate_terms: candidateTerms?.terms(form) || {} };
    };
    const load = async () => {
      const values = new FormData(document.querySelector('[data-vacancy-filters]'));
      const rows = await call('list_contractor_portal_vacancies', { p_search: String(values.get('search') || '') || null, p_status: String(values.get('status') || '') || null, p_limit: 50, p_offset: 0 }) || [];
      body.replaceChildren();
      document.querySelector('[data-empty]').hidden = Boolean(rows.length);
      rows.forEach((row) => {
        const tr = document.createElement('tr');
        const ctc = compensation?.hasStructuredSalary(row) ? `CTC ${compensation.money(row.ctc)}` : (compensation?.legacySalary(row) || '—');
        [`${row.requirement_code} · ${row.job_role}`, row.client_name, row.job_location, row.required_headcount, ctc, statusFor(row), row.application_count || 0, row.interview_count || 0, row.joined_count || 0].forEach((value) => {
          const cell = document.createElement('td'); cell.textContent = value ?? '—'; tr.append(cell);
        });
        const action = document.createElement('td');
        const view = document.createElement('button');
        view.className = 'table-action'; view.type = 'button'; view.textContent = 'View details'; view.onclick = () => open(row);
        action.append(view); tr.append(action); body.append(tr);
      });
    };
    const open = async (row = null) => {
      form.reset(); options?.initialize(form);
      submissionKey = null;
      setSubmitInFlight(false);
      if (formMessage) { formMessage.textContent = ''; formMessage.hidden = true; }
      current = row ? await call('get_contractor_portal_vacancy', { p_requirement_id: row.id }) : null;
      originalExpectedJoiningDate = current?.expected_joining_date || '';
      form.elements.requirementId.value = row?.id || '';
      document.querySelector('#vacancy-title').textContent = row ? 'Vacancy Details' : 'Create Vacancy';
      if (current) fields.forEach((name) => {
        const control = form.elements[name], value = current[map[name]] ?? '';
        if (control?.tagName === 'SELECT') options?.setValue(control, value); else if (control) control.value = value;
      });
      form.elements.expectedJoiningDate.min = current ? '' : indiaToday();
      compensation?.hydrate(form, current || {});
      candidateTerms?.hydrate(form, current || {}); candidateTerms?.wire(form);
      const feedback = document.querySelector('[data-review-feedback]'), state = current ? statusFor(current) : '';
      feedback.textContent = current?.review_feedback ? `${state}: ${current.review_feedback}` : (state ? `Status: ${state}` : '');
      feedback.hidden = !feedback.textContent;
      const editable = context.can_manage_vacancies && (!current || ['draft', 'correction_required'].includes(current.submission_status));
      form.querySelectorAll('input:not([type=hidden]),select,textarea').forEach((control) => { control.disabled = !editable; });
      form.querySelector('[data-save]').hidden = !editable;
      form.querySelector('[data-submit]').hidden = !editable;
      form.querySelector('[data-submit]').textContent = current?.submission_status === 'correction_required' ? 'Edit & Resubmit' : 'Submit Vacancy';
      form.querySelector('[data-delete-vacancy]').hidden = !current || current.submission_status !== 'draft';
      form.querySelector('[data-withdraw-vacancy]').hidden = !current || !['submitted', 'under_review', 'pending_review'].includes(current.submission_status);
      form.querySelector('[data-cancel-vacancy]').hidden = !current || !(current.normalized_review_status === 'approved' && current.requirement_stage === 'open' && current.requirement_visibility === 'public');
      dialog.showModal();
    };
    const save = async () => {
      if (!valid()) return;
      const id = form.elements.requirementId.value;
      await call('manage_contractor_portal_vacancy', { ...params(), p_action: id ? 'update' : 'create', p_requirement_id: id || null });
      dialog.close(); await load(); message('Vacancy saved as Draft. Submit it when ready for Aadhyant review.', 'success');
    };
    const submit = async () => {
      if (submitInFlight || !valid()) return;
      const id = form.elements.requirementId.value;
      if (!id && !submissionKey) submissionKey = newSubmissionKey();
      setSubmitInFlight(true);
      try {
        if (!id) await call('manage_contractor_portal_vacancy', { ...params(), p_action: 'create_and_submit', p_requirement_id: null, p_submission_idempotency_key: submissionKey });
        else if (current?.submission_status === 'correction_required') {
          await call('manage_contractor_portal_vacancy', { ...params(), p_action: 'update', p_requirement_id: id });
          await call('manage_contractor_portal_vacancy', { p_action: 'resubmit', p_requirement_id: id });
        } else {
          await call('manage_contractor_portal_vacancy', { ...params(), p_action: 'update', p_requirement_id: id });
          await call('manage_contractor_portal_vacancy', { p_action: 'submit', p_requirement_id: id });
        }
        submissionKey = null;
        dialog.close(); await load(); message('Vacancy submitted successfully. It is pending Admin approval and is not visible to candidates yet.', 'success');
      } finally { setSubmitInFlight(false); }
    };
    const lifecycle = async (rpc, confirmation, success) => {
      if (!current || !window.confirm(confirmation)) return;
      form.querySelectorAll('button').forEach((button) => { button.disabled = true; });
      try {
        await call(rpc, { p_requirement_id: form.elements.requirementId.value });
        dialog.close(); await load(); message(success, 'success');
      } catch (_) {
        message('This vacancy action could not be completed because its current state or recruitment history does not allow it.', 'error');
      } finally { form.querySelectorAll('button').forEach((button) => { button.disabled = false; }); }
    };

    compensation?.wireForm(form);
    candidateTerms?.wire(form);
    document.querySelector('[data-new-vacancy]').onclick = () => open();
    document.querySelector('[data-vacancy-filters]').onsubmit = (event) => { event.preventDefault(); load().catch(() => message('Vacancies could not be loaded.', 'error')); };
    form.onsubmit = async (event) => {
      event.preventDefault();
      try { await submit(); }
      catch (error) {
        const text = String(error?.message || '');
        const safe = /Expected joining date/.test(text) ? 'Expected joining date must be today or a future date.'
          : /Vacancy criteria are invalid/.test(text) ? 'Check the salary range and vacancy criteria.'
          : /accommodation/i.test(text) ? 'Enter a valid accommodation charge and basis.'
          : 'The vacancy could not be submitted right now. Please try again or contact Aadhyant.';
        message(safe, 'error', true);
      }
    };
    form.querySelector('[data-save]').onclick = async () => { try { await save(); } catch (_) { message('The vacancy could not be saved. No changes were made.', 'error'); } };
    form.querySelector('[data-delete-vacancy]').onclick = () => lifecycle('delete_contractor_portal_draft_vacancy', 'Delete this draft vacancy? This action cannot be undone.', 'Draft vacancy deleted.');
    form.querySelector('[data-withdraw-vacancy]').onclick = () => lifecycle('withdraw_contractor_portal_vacancy', 'Withdraw this vacancy from review?', 'Vacancy withdrawn from review.');
    form.querySelector('[data-cancel-vacancy]').onclick = () => lifecycle('close_contractor_portal_open_vacancy', 'Close this vacancy? Existing recruitment history will remain available.', 'Vacancy closed. Recruitment history remains available.');
    dialog.querySelectorAll('[data-close-dialog]').forEach((button) => { button.onclick = () => dialog.close(); });
    await load();
  }

  window.aadhyantBatch2Contractor = Object.freeze({ statusFor });
  start().catch(() => { const node = document.querySelector('[data-page-message]'); if (node) node.textContent = 'The vacancy workspace is temporarily unavailable.'; });
}());
