(function initializeCompanyPortal() {
  const pageType = document.body.dataset.companyPage;
  const connection = window.aadhyantSupabase;
  const client = connection?.client;

  const messageElement = () => document.querySelector('[data-page-message]');
  const showMessage = (message, type = '') => {
    const element = messageElement();
    if (!element) return;
    element.textContent = message;
    element.className = 'company-message';
    if (type) element.classList.add(`is-${type}`);
  };

  const fieldError = (form, name, message) => {
    const field = form.elements[name];
    const error = form.querySelector(`[data-error-for="${name}"]`);
    if (field) field.setAttribute('aria-invalid', String(Boolean(message)));
    if (error) error.textContent = message;
    return !message;
  };

  const validateRegistration = (form) => {
    const values = new FormData(form);
    const email = String(values.get('email') || '').trim();
    const password = String(values.get('password') || '');
    const confirmPassword = String(values.get('confirmPassword') || '');
    const mobile = String(values.get('mobile') || '').trim();
    const gstin = String(values.get('gstin') || '').trim().toUpperCase();
    const website = String(values.get('website') || '').trim();
    let valid = true;
    const required = ['companyName', 'contactPerson', 'industry', 'city', 'state'];
    required.forEach((name) => { valid = fieldError(form, name, String(values.get(name) || '').trim() ? '' : 'This field is required.') && valid; });
    valid = fieldError(form, 'email', /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? '' : 'Enter a valid work email address.') && valid;
    valid = fieldError(form, 'password', /^(?=.*[A-Za-z])(?=.*\d).{8,}$/.test(password) ? '' : 'Use at least 8 characters including a letter and a number.') && valid;
    valid = fieldError(form, 'confirmPassword', confirmPassword === password && confirmPassword ? '' : 'Passwords do not match.') && valid;
    valid = fieldError(form, 'mobile', /^[6-9][0-9]{9}$/.test(mobile) ? '' : 'Enter a valid 10-digit Indian mobile number.') && valid;
    valid = fieldError(form, 'gstin', !gstin || /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(gstin) ? '' : 'Enter a valid 15-character GSTIN.') && valid;
    let websiteValid = true;
    if (website) { try { const url = new URL(website); websiteValid = ['http:', 'https:'].includes(url.protocol); } catch (_error) { websiteValid = false; } }
    valid = fieldError(form, 'website', websiteValid ? '' : 'Enter a complete website URL beginning with http:// or https://.') && valid;
    valid = fieldError(form, 'consent', values.get('consent') === 'on' ? '' : 'Your acknowledgement is required for account review.') && valid;
    return valid;
  };

  const getCompanyAccount = async () => {
    const { data: sessionData, error: sessionError } = await client.auth.getSession();
    if (sessionError || !sessionData.session) return { session: null };
    const session = sessionData.session;
    const { data: platformUser, error: platformError } = await client.from('platform_users')
      .select('user_id, account_type, display_name, email, mobile, account_status')
      .eq('user_id', session.user.id).maybeSingle();
    if (platformError) throw platformError;
    if (!platformUser || platformUser.account_type !== 'company') return { session, platformUser: null };
    const { data: membership, error: membershipError } = await client.from('company_users')
      .select('company_id, user_id, role, status').eq('user_id', session.user.id).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership) return { session, platformUser, membership: null };
    const { data: company, error: companyError } = await client.from('companies')
      .select('id, legal_name, contact_person, industry, main_email, main_phone, city, state, gstin, workforce_size, account_status, verification_status, created_at')
      .eq('id', membership.company_id).maybeSingle();
    if (companyError) throw companyError;
    return { session, platformUser, membership, company };
  };

  const initializeRegistration = async () => {
    const form = document.querySelector('[data-registration-form]');
    if (!connection?.isConfigured || !client) {
      showMessage('Company registration is temporarily unavailable. Please contact Aadhyant.', 'error');
      form.querySelector('button[type="submit"]').disabled = true;
      return;
    }
    const existing = await getCompanyAccount();
    if (existing.session && existing.platformUser) { window.location.replace('index.html'); return; }
    if (existing.session) {
      showMessage('A different account is already signed in. Log out of that portal or use a separate browser session before registering a company.', 'warning');
      form.querySelector('button[type="submit"]').disabled = true;
      return;
    }
    form.addEventListener('input', (event) => {
      if (event.target.matches('input, select, textarea') && event.target.getAttribute('aria-invalid') === 'true') validateRegistration(form);
    });
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      showMessage('');
      if (!validateRegistration(form)) {
        showMessage('Please correct the highlighted fields before continuing.', 'error');
        form.querySelector('[aria-invalid="true"]')?.focus();
        return;
      }
      const values = new FormData(form);
      const button = form.querySelector('button[type="submit"]');
      button.disabled = true; button.textContent = 'Creating account…';
      const email = String(values.get('email')).trim().toLowerCase();
      const { data: signupData, error } = await client.auth.signUp({
        email,
        password: String(values.get('password')),
        options: {
          emailRedirectTo: new URL('login.html', window.location.href).href,
          data: {
            onboarding_type: 'company', company_name: String(values.get('companyName')).trim(),
            contact_person: String(values.get('contactPerson')).trim(), mobile: String(values.get('mobile')).trim(),
            industry: String(values.get('industry')).trim(), city: String(values.get('city')).trim(), state: String(values.get('state')).trim(),
            gstin: String(values.get('gstin')).trim().toUpperCase(), website: String(values.get('website')).trim(),
            address: String(values.get('address')).trim(), workforce_size: String(values.get('workforceSize')).trim(),
            onboarding_notes: String(values.get('notes')).trim(), consent: true
          }
        }
      });
      if (error || !signupData.user) {
        showMessage('We could not create the company account. The email may already be registered, or the submitted details could not be accepted. Please review the form or contact Aadhyant.', 'error');
        button.disabled = false; button.textContent = 'Create Company Account';
        return;
      }
      form.reset();
      if (!signupData.session) {
        showMessage('Check your email to continue. After confirming your address, sign in to view your company approval status.', 'success');
        button.textContent = 'Email Confirmation Required';
        return;
      }
      showMessage('Your company account was created and is now under review by Aadhyant.', 'success');
      setTimeout(() => window.location.replace('index.html'), 900);
    });
  };

  const statusContent = {
    pending: ['Your company account is under review by Aadhyant.', 'Account under review'],
    suspended: ['Access to this company account has been suspended. Contact Aadhyant for assistance.', 'Company access suspended'],
    rejected: ['This company registration was not approved. Contact Aadhyant if you need clarification.', 'Registration not approved']
  };

  const initializeLogin = async () => {
    const form = document.querySelector('[data-login-form]');
    if (!connection?.isConfigured || !client) { showMessage('Company login is temporarily unavailable. Please contact Aadhyant.', 'error'); form.querySelector('button').disabled = true; return; }
    try {
      const existing = await getCompanyAccount();
      if (existing.session && existing.platformUser?.account_status === 'active') { window.location.replace('index.html'); return; }
      if (existing.session && existing.platformUser) showMessage(statusContent[existing.platformUser.account_status]?.[0] || 'Your company account is not available.', existing.platformUser.account_status === 'pending' ? 'warning' : 'error');
    } catch (_error) { showMessage('We could not verify the current session. Please sign in again.', 'error'); }
    form.addEventListener('submit', async (event) => {
      event.preventDefault(); showMessage('');
      const values = new FormData(form); const email = String(values.get('email')).trim(); const password = String(values.get('password'));
      let valid = fieldError(form, 'email', email ? '' : 'Enter your work email.'); valid = fieldError(form, 'password', password ? '' : 'Enter your password.') && valid;
      if (!valid) return;
      const button = form.querySelector('button[type="submit"]'); button.disabled = true; button.textContent = 'Signing in…';
      const { error } = await client.auth.signInWithPassword({ email, password });
      if (error) { showMessage('Unable to sign in. Check your credentials and confirm your email if required.', 'error'); button.disabled = false; button.textContent = 'Sign In'; return; }
      try {
        const account = await getCompanyAccount();
        if (!account.platformUser) { await client.auth.signOut(); showMessage('This login is not linked to a company account.', 'error'); button.disabled = false; button.textContent = 'Sign In'; return; }
        if (account.platformUser.account_status === 'active') { window.location.replace('index.html'); return; }
        showMessage(statusContent[account.platformUser.account_status]?.[0] || 'Your company account is unavailable.', account.platformUser.account_status === 'pending' ? 'warning' : 'error');
      } catch (_error) { showMessage('Your account could not be verified. Please try again.', 'error'); }
      button.disabled = false; button.textContent = 'Sign In';
    });
    document.querySelector('[data-reset-password]').addEventListener('click', async () => {
      const email = String(form.elements.email.value).trim();
      if (!email) { fieldError(form, 'email', 'Enter your work email first.'); form.elements.email.focus(); return; }
      const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo: new URL('login.html', window.location.href).href });
      showMessage(error ? 'The reset email could not be sent. Please try again or contact Aadhyant.' : 'If the email is registered, password reset instructions have been sent.', error ? 'error' : 'success');
    });
  };

  const initializeDashboard = async () => {
    const loading = document.querySelector('[data-portal-loading]'); const portal = document.querySelector('[data-portal]');
    if (!connection?.isConfigured || !client) { loading.textContent = 'Company Portal is temporarily unavailable.'; return; }
    try {
      const account = await getCompanyAccount();
      if (!account.session) { window.location.replace('login.html'); return; }
      if (!account.platformUser || !account.membership) { window.location.replace('login.html'); return; }
      document.querySelector('[data-user-email]').textContent = account.session.user.email || account.platformUser.email;
      document.querySelectorAll('[data-logout]').forEach((button) => button.addEventListener('click', async () => { await client.auth.signOut(); window.location.replace('login.html'); }));
      loading.hidden = true; portal.hidden = false;
      if (account.platformUser.account_status !== 'active') {
        const status = account.platformUser.account_status; const content = statusContent[status] || ['Your company account is unavailable.', 'Account unavailable'];
        const gate = document.querySelector('[data-status-gate]'); gate.hidden = false;
        document.querySelector('[data-status-title]').textContent = content[1]; document.querySelector('[data-status-copy]').textContent = content[0];
        document.querySelector('[data-gate-company]').textContent = account.company?.legal_name
          || account.session.user.user_metadata?.company_name || 'Registered company';
        const badge = document.querySelector('[data-account-status]'); badge.textContent = status; badge.dataset.status = status;
        return;
      }
      if (!account.company) { throw new Error('Active company profile is unavailable'); }
      document.querySelector('[data-active-dashboard]').hidden = false;
      document.querySelector('[data-company-name]').textContent = account.company.legal_name;
      document.querySelector('[data-active-badge]').dataset.status = 'active';
      const values = { ...account.company, location: [account.company.city, account.company.state].filter(Boolean).join(', ') };
      document.querySelectorAll('[data-profile]').forEach((element) => { element.textContent = values[element.dataset.profile] || 'Not provided'; });
    } catch (_error) { loading.textContent = 'Company access could not be verified. Please return to login and try again.'; }
    client.auth.onAuthStateChange((event) => { if (event === 'SIGNED_OUT') window.location.replace('login.html'); });
  };

  const requirementFields = ['department', 'jobRole', 'jobLocation', 'requiredHeadcount', 'qualification', 'experienceRequirement', 'genderPreference', 'ageMin', 'ageMax', 'salaryMin', 'salaryMax', 'shiftDetails', 'workingHours', 'overtimeDetails', 'canteen', 'transport', 'accommodation', 'interviewLocation', 'interviewDate', 'additionalNotes'];
  const requirementColumns = 'id,requirement_code,department,job_role,job_location,required_headcount,filled_positions,qualification,experience_requirement,gender_preference,age_min,age_max,salary_min,salary_max,shift_details,working_hours,overtime_details,canteen,transport,accommodation,interview_location,interview_date,additional_notes,requirement_stage,requirement_visibility,created_at,updated_at';
  const requirementMap = {
    department: 'department', jobRole: 'job_role', jobLocation: 'job_location', requiredHeadcount: 'required_headcount', qualification: 'qualification',
    experienceRequirement: 'experience_requirement', genderPreference: 'gender_preference', ageMin: 'age_min', ageMax: 'age_max', salaryMin: 'salary_min', salaryMax: 'salary_max',
    shiftDetails: 'shift_details', workingHours: 'working_hours', overtimeDetails: 'overtime_details', canteen: 'canteen', transport: 'transport', accommodation: 'accommodation',
    interviewLocation: 'interview_location', interviewDate: 'interview_date', additionalNotes: 'additional_notes'
  };
  const requirementParams = (form) => {
    const value = (name) => String(form.elements[name].value || '').trim();
    const nullableNumber = (name) => value(name) === '' ? null : Number(value(name));
    return {
      p_department: value('department'), p_job_role: value('jobRole'), p_job_location: value('jobLocation'), p_required_headcount: Number(value('requiredHeadcount')),
      p_qualification: value('qualification') || null, p_experience_requirement: value('experienceRequirement'), p_gender_preference: value('genderPreference'),
      p_age_min: nullableNumber('ageMin'), p_age_max: nullableNumber('ageMax'), p_salary_min: nullableNumber('salaryMin'), p_salary_max: nullableNumber('salaryMax'),
      p_shift_details: value('shiftDetails') || null, p_working_hours: value('workingHours') || null, p_overtime_details: value('overtimeDetails') || null,
      p_canteen: value('canteen'), p_transport: value('transport'), p_accommodation: value('accommodation'), p_interview_location: value('interviewLocation') || null,
      p_interview_date: value('interviewDate') ? new Date(value('interviewDate')).toISOString() : null, p_additional_notes: value('additionalNotes') || null
    };
  };
  const validateRequirement = (form) => {
    let valid = true;
    ['department', 'jobRole', 'jobLocation'].forEach((name) => { valid = fieldError(form, name, form.elements[name].value.trim() ? '' : 'This field is required.') && valid; });
    const headcount = Number(form.elements.requiredHeadcount.value);
    valid = fieldError(form, 'requiredHeadcount', Number.isInteger(headcount) && headcount > 0 && headcount <= 100000 ? '' : 'Enter a whole number between 1 and 100000.') && valid;
    const ageMin = form.elements.ageMin.value === '' ? null : Number(form.elements.ageMin.value); const ageMax = form.elements.ageMax.value === '' ? null : Number(form.elements.ageMax.value);
    valid = fieldError(form, 'ageRange', ageMin !== null && ageMax !== null && ageMin > ageMax ? 'Minimum age cannot exceed maximum age.' : '') && valid;
    const salaryMin = form.elements.salaryMin.value === '' ? null : Number(form.elements.salaryMin.value); const salaryMax = form.elements.salaryMax.value === '' ? null : Number(form.elements.salaryMax.value);
    valid = fieldError(form, 'salaryRange', (salaryMin !== null && salaryMin < 0) || (salaryMax !== null && salaryMax < 0) || (salaryMin !== null && salaryMax !== null && salaryMin > salaryMax) ? 'Enter a valid non-negative salary range.' : '') && valid;
    valid = fieldError(form, 'interviewDate', form.elements.interviewDate.value && Number.isNaN(new Date(form.elements.interviewDate.value).getTime()) ? 'Enter a valid interview date.' : '') && valid;
    return valid;
  };
  const readable = (value) => String(value || '').replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  const money = (value) => value === null || value === undefined ? '—' : `₹${Number(value).toLocaleString('en-IN')}`;

  const initializeRequirements = async () => {
    const loading = document.querySelector('[data-portal-loading]'); const portal = document.querySelector('[data-portal]');
    if (!connection?.isConfigured || !client) { loading.textContent = 'Company Portal is temporarily unavailable.'; return; }
    let account;
    try { account = await getCompanyAccount(); } catch (_error) { loading.textContent = 'Company access could not be verified.'; return; }
    if (!account.session) { window.location.replace('login.html'); return; }
    if (!account.platformUser || account.platformUser.account_status !== 'active' || !account.company || account.membership?.status !== 'active') { window.location.replace('index.html'); return; }
    loading.hidden = true; portal.hidden = false;
    document.querySelector('[data-user-email]').textContent = account.session.user.email || account.platformUser.email;
    document.querySelector('[data-company-name]').textContent = account.company.legal_name;
    document.querySelectorAll('[data-logout]').forEach((button) => button.addEventListener('click', async () => { await client.auth.signOut(); window.location.replace('login.html'); }));
    const body = document.querySelector('[data-requirements-body]'); const empty = document.querySelector('[data-requirements-empty]'); const dialog = document.querySelector('[data-requirement-dialog]'); const form = document.querySelector('[data-requirement-form]');
    let records = [];
    const load = async () => {
      const { data, error } = await client.from('employer_requirements').select(requirementColumns).order('created_at', { ascending: false });
      if (error) throw error; records = data || [];
      const filters = new FormData(document.querySelector('[data-requirement-filters]')); const search = String(filters.get('search') || '').trim().toLowerCase(); const stage = String(filters.get('stage') || '');
      const visible = records.filter((record) => (!stage || record.requirement_stage === stage) && (!search || [record.requirement_code, record.job_role, record.job_location].some((item) => String(item || '').toLowerCase().includes(search))));
      body.replaceChildren(); empty.hidden = Boolean(visible.length);
      visible.forEach((record) => {
        const row = document.createElement('tr'); const open = Math.max(0, record.required_headcount - record.filled_positions);
        const values = [`${record.requirement_code}\n${record.department} · ${record.job_role}`, record.job_location, String(record.required_headcount), `${record.filled_positions} filled · ${open} open`, `${money(record.salary_min)} – ${money(record.salary_max)}`, `${readable(record.requirement_stage)} / ${readable(record.requirement_visibility)}`, new Date(record.created_at).toLocaleDateString('en-IN')];
        values.forEach((value, index) => { const cell = document.createElement('td'); cell.textContent = value; if (index === 0) cell.className = 'requirement-primary'; row.append(cell); });
        const action = document.createElement('td'); const button = document.createElement('button'); button.type = 'button'; button.className = 'table-action'; button.textContent = 'View'; button.addEventListener('click', () => openDialog(record)); action.append(button); row.append(action); body.append(row);
      });
    };
    const openDialog = (record = null) => {
      form.reset(); form.elements.requirementId.value = record?.id || '';
      document.querySelector('[data-requirement-dialog-title]').textContent = record ? 'Requirement Details' : 'Create Requirement';
      const code = document.querySelector('[data-requirement-code]'); code.hidden = !record; code.textContent = record ? `${record.requirement_code} · ${readable(record.requirement_stage)} · ${readable(record.requirement_visibility)}` : '';
      if (record) requirementFields.forEach((name) => { const source = requirementMap[name]; let value = record[source] ?? ''; if (name === 'interviewDate' && value) value = new Date(value).toISOString().slice(0, 16); form.elements[name].value = value; });
      const editable = !record || record.requirement_stage === 'draft'; form.querySelectorAll('input:not([type="hidden"]),select,textarea').forEach((control) => { control.disabled = !editable; });
      form.querySelector('button[type="submit"]').hidden = !editable; const closeButton = form.querySelector('[data-close-requirement]'); closeButton.hidden = !record || !['draft', 'open', 'on_hold'].includes(record.requirement_stage); closeButton.textContent = record?.requirement_stage === 'draft' ? 'Cancel Requirement' : 'Close Requirement';
      const detailMessage = document.querySelector('[data-requirement-message]'); detailMessage.textContent = ''; detailMessage.className = 'company-message'; dialog.showModal();
    };
    document.querySelector('[data-new-requirement]').addEventListener('click', () => openDialog());
    document.querySelector('[data-requirement-filters]').addEventListener('submit', (event) => { event.preventDefault(); load(); });
    document.querySelector('[data-requirement-filters]').addEventListener('reset', () => setTimeout(load, 0));
    form.addEventListener('submit', async (event) => {
      event.preventDefault(); if (!validateRequirement(form)) { showMessage('Please correct the highlighted requirement fields.', 'error'); form.querySelector('[aria-invalid="true"]')?.focus(); return; }
      const button = form.querySelector('button[type="submit"]'); button.disabled = true; const id = form.elements.requirementId.value; const params = requirementParams(form); if (id) params.p_requirement_id = id;
      const { data, error } = await client.rpc(id ? 'update_company_requirement' : 'create_company_requirement', params);
      button.disabled = false; if (error) { const message = document.querySelector('[data-requirement-message]'); message.textContent = 'The requirement could not be saved. No completion was recorded.'; message.className = 'company-message is-error'; return; }
      dialog.close(); await load(); showMessage(`Requirement ${data.requirement_code} saved successfully.`, 'success');
    });
    form.querySelector('[data-close-requirement]').addEventListener('click', async () => {
      const button = form.querySelector('[data-close-requirement]'); button.disabled = true; const { error } = await client.rpc('close_company_requirement', { p_requirement_id: form.elements.requirementId.value }); button.disabled = false;
      if (error) { const message = document.querySelector('[data-requirement-message]'); message.textContent = 'This requirement could not be closed. Its status was not changed.'; message.className = 'company-message is-error'; return; }
      dialog.close(); await load(); showMessage('Requirement lifecycle updated. History has been preserved.', 'success');
    });
    dialog.addEventListener('close', () => form.reset());
    client.auth.onAuthStateChange((event) => { if (event === 'SIGNED_OUT') window.location.replace('login.html'); });
    try { await load(); } catch (_error) { showMessage('Requirements could not be loaded. Please refresh or contact Aadhyant.', 'error'); }
  };

  if (pageType === 'register') initializeRegistration();
  if (pageType === 'login') initializeLogin();
  if (pageType === 'dashboard') initializeDashboard();
  if (pageType === 'requirements') initializeRequirements();
}());
