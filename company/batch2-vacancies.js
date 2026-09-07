(function () {
  'use strict';
  if (document.body?.dataset.companyPage !== 'requirements-batch2') return;

  const client = window.aadhyantSupabase?.client;
  const optionApi = window.AadhyantRegistrationOptions;
  const fields = ['department','jobRole','jobLocation','requiredHeadcount','qualification','itiTrade','experienceRequirement','genderPreference','ageMin','ageMax','salaryMin','salaryMax','shiftDetails','workingHours','overtimeDetails','canteen','transport','accommodation','interviewLocation','interviewDate','expectedJoiningDate','additionalNotes'];
  const column = {department:'department',jobRole:'job_role',jobLocation:'job_location',requiredHeadcount:'required_headcount',qualification:'qualification',itiTrade:'iti_trade',experienceRequirement:'experience_requirement',genderPreference:'gender_preference',ageMin:'age_min',ageMax:'age_max',salaryMin:'salary_min',salaryMax:'salary_max',shiftDetails:'shift_details',workingHours:'working_hours',overtimeDetails:'overtime_details',canteen:'canteen',transport:'transport',accommodation:'accommodation',interviewLocation:'interview_location',interviewDate:'interview_date',expectedJoiningDate:'expected_joining_date',additionalNotes:'additional_notes'};
  const first = (value) => Array.isArray(value) ? value[0] : value;
  const display = (value, fallback = '—') => value === null || value === undefined || value === '' ? fallback : String(value);
  const call = async (name, args = {}) => { const { data, error } = await client.rpc(name, args); if (error) throw error; return data; };
  const statusFor = (row = {}) => {
    if (row.review_status === 'closed' || row.requirement_stage === 'closed') return 'Closed';
    if (row.review_status === 'rejected' || row.requirement_stage === 'cancelled') return 'Rejected';
    if (row.review_status === 'correction_required') return 'Correction Required';
    if (row.review_status === 'approved' && row.requirement_stage === 'open' && row.requirement_visibility === 'public') return 'Published / Open';
    if (row.review_status === 'pending_review') return 'Pending Review';
    return 'Draft';
  };
  const formatCtc = (row) => (row.salary_min ?? row.salary_max) !== null && (row.salary_min ?? row.salary_max) !== undefined
    ? `₹${row.salary_min ?? '—'} – ₹${row.salary_max ?? '—'}`
    : '—';
  const dateInput = (value, withTime = false) => value ? new Date(value).toISOString().slice(0, withTime ? 16 : 10) : '';

  async function start() {
    if (!client) return;
    const { data: sessionData } = await client.auth.getSession();
    if (!sessionData.session) { location.replace('login.html'); return; }
    let context;
    try { context = first(await call('get_company_portal_context')); } catch (_) { location.replace('login.html'); return; }
    if (!context || context.platform_status !== 'active' || context.company_status !== 'active' || context.membership_status !== 'active') { location.replace('index.html'); return; }
    document.querySelector('[data-portal-loading]')?.setAttribute('hidden','');document.querySelector('[data-portal]')?.removeAttribute('hidden');
    document.querySelectorAll('[data-user-email]').forEach((node) => { node.textContent = sessionData.session.user.email || ''; });
    document.querySelectorAll('[data-company-name]').forEach((node) => { node.textContent = context.company_name || 'your company'; });
    document.querySelectorAll('[data-logout]').forEach((button) => { button.onclick = async () => { await client.auth.signOut(); location.replace('login.html'); }; });

    const body = document.querySelector('[data-requirements-body]');
    const empty = document.querySelector('[data-requirements-empty]');
    const form = document.querySelector('[data-requirement-form]');
    const dialog = document.querySelector('[data-requirement-dialog]');
    const pageMessage = document.querySelector('[data-page-message]');
    let current = null;
    const message = (text, type = '') => { pageMessage.textContent = text; pageMessage.className = `company-message${type ? ` is-${type}` : ''}`; };
    const detailMessage = (text = '') => { const node = document.querySelector('[data-review-feedback]'); node.textContent = text; node.hidden = !text; };
    const params = () => {
      const value = (name) => String(form.elements[name].value || '').trim();
      const numeric = (name) => value(name) === '' ? null : Number(value(name));
      return { p_department:value('department'),p_job_role:value('jobRole'),p_job_location:value('jobLocation'),p_required_headcount:numeric('requiredHeadcount'),p_qualification:value('qualification')||null,p_iti_trade:value('itiTrade')||null,p_experience_requirement:value('experienceRequirement')||'Both',p_gender_preference:value('genderPreference')||'Any',p_age_min:numeric('ageMin'),p_age_max:numeric('ageMax'),p_salary_min:numeric('salaryMin'),p_salary_max:numeric('salaryMax'),p_shift_details:value('shiftDetails')||null,p_working_hours:value('workingHours')||null,p_overtime_details:value('overtimeDetails')||null,p_canteen:value('canteen')||'Not Applicable',p_transport:value('transport')||'Not Applicable',p_accommodation:value('accommodation')||'Not Applicable',p_interview_location:value('interviewLocation')||null,p_interview_date:value('interviewDate') ? new Date(value('interviewDate')).toISOString() : null,p_expected_joining_date:value('expectedJoiningDate')||null,p_additional_notes:value('additionalNotes')||null };
    };
    const valid = () => {
      const required = ['department','jobRole','jobLocation'].every((name) => form.elements[name].value.trim());
      const openings = Number(form.elements.requiredHeadcount.value);
      if (!required || !Number.isInteger(openings) || openings < 1) { message('Department, role, location, and a valid number of openings are required.','error'); return false; }
      return true;
    };
    const setEditable = () => {
      const editable = context.can_manage_requirements && (!current || ['draft','correction_required'].includes(current.review_status));
      form.querySelectorAll('input:not([type="hidden"]),select,textarea').forEach((input) => { input.disabled = !editable; });
      form.querySelector('[data-save-requirement]').hidden = !editable;
      form.querySelector('[data-submit-requirement]').hidden = !editable;
      form.querySelector('[data-submit-requirement]').textContent = current?.review_status === 'correction_required' ? 'Edit & Resubmit' : 'Submit Vacancy';
      form.querySelector('[data-close-requirement]').hidden = !context.can_manage_requirements || !current || ['closed','rejected'].includes(current.review_status);
    };
    const load = async () => {
      const filters = new FormData(document.querySelector('[data-requirement-filters]'));
      const rows = await call('list_company_portal_vacancy_reviews',{p_search:String(filters.get('search') || '').trim() || null,p_review_status:String(filters.get('status') || '').trim() || null,p_limit:50,p_offset:0}) || [];
      body.replaceChildren();empty.hidden = Boolean(rows.length);
      rows.forEach((row) => {
        const tr = document.createElement('tr');
        [ `${row.requirement_code} · ${row.job_role}`, display(row.job_location), row.required_headcount, formatCtc(row), statusFor(row), row.application_count || 0, row.interview_count || 0, row.joined_count || 0 ].forEach((value) => { const cell = document.createElement('td');cell.textContent = display(value);tr.append(cell); });
        const action = document.createElement('td');const view = document.createElement('button');view.className = 'table-action';view.type = 'button';view.textContent = 'View details';view.onclick = () => open(row);action.append(view);tr.append(action);body.append(tr);
      });
    };
    const open = async (row = null) => {
      form.reset(); optionApi?.initialize(form);current = row ? await call('get_company_portal_requirement',{p_requirement_id:row.requirement_id}) : null;
      form.elements.requirementId.value = row?.requirement_id || '';
      document.querySelector('[data-requirement-dialog-title]').textContent = row ? 'Vacancy Details' : 'Create Vacancy';
      document.querySelector('[data-requirement-code]').textContent = current ? `${current.requirement_code} · ${statusFor(current)}` : '';
      if (current) fields.forEach((name) => { const value = current[column[name]] ?? '';const control = form.elements[name];if (!control) return;if (control.tagName === 'SELECT') optionApi?.setValue(control,value);else control.value = name === 'interviewDate' ? dateInput(value,true) : name === 'expectedJoiningDate' ? dateInput(value) : value; });
      const feedback = current?.review_feedback ? `${statusFor(current)}: ${current.review_feedback}` : (current ? `Status: ${statusFor(current)}` : '');detailMessage(feedback);
      const pipeline = current?.pipeline || {};document.querySelector('[data-requirement-pipeline]').textContent = current ? `Applications ${pipeline.applications || 0} · Screening ${pipeline.screening || 0} · Shortlisted ${pipeline.shortlisted || 0} · Interviews ${pipeline.interviews || 0} · Selected ${pipeline.selected || 0} · Joined ${pipeline.joined || 0}` : '';
      setEditable();dialog.showModal();
    };
    const save = async () => {
      if (!valid()) return;const id = form.elements.requirementId.value;await call('manage_company_portal_requirement',{...params(),p_action:id ? 'update' : 'create',p_requirement_id:id || null});dialog.close();await load();message('Vacancy saved as Draft. Submit it when ready for Aadhyant review.','success');
    };
    const submit = async () => {
      if (!valid()) return;const id = form.elements.requirementId.value;
      if (!id) await call('manage_company_portal_requirement',{...params(),p_action:'create_and_submit',p_requirement_id:null});
      else { await call('manage_company_portal_requirement',{...params(),p_action:'update',p_requirement_id:id});await call('manage_company_portal_requirement',{p_action:current?.review_status === 'correction_required' ? 'resubmit' : 'submit',p_requirement_id:id}); }
      dialog.close();await load();message('Vacancy submitted successfully. It is pending Admin approval and is not visible to candidates yet.','success');
    };
    document.querySelector('[data-new-requirement]').onclick = () => open();
    document.querySelector('[data-requirement-filters]').onsubmit = (event) => { event.preventDefault();load().catch(() => message('Vacancies could not be loaded.','error')); };
    form.onsubmit = async (event) => { event.preventDefault();try { await save(); } catch (_) { message('The vacancy could not be saved. No changes were made.','error'); } };
    form.querySelector('[data-submit-requirement]').onclick = async () => { try { await submit(); } catch (_) { message('The vacancy could not be submitted. No changes were made.','error'); } };
    form.querySelector('[data-close-requirement]').onclick = async () => { try { await call('manage_company_portal_requirement',{p_action:'close',p_requirement_id:form.elements.requirementId.value});dialog.close();await load();message('Vacancy closed. Recruitment history remains available.','success'); } catch (_) { message('The vacancy could not be closed.','error'); } };
    dialog.querySelectorAll('[data-close-dialog]').forEach((button) => { button.onclick = () => dialog.close(); });
    await load();
  }
  window.aadhyantBatch2Company = Object.freeze({ statusFor });
  start().catch(() => { const node = document.querySelector('[data-page-message]');if (node) node.textContent = 'The vacancy workspace is temporarily unavailable.'; });
}());
