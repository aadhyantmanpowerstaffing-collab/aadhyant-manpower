(function initializeAdmin() {
  const PAGE_SIZE = 25;
  const pageType = document.body.dataset.adminPage;
  const connection = window.aadhyantSupabase;
  const client = connection?.client;

  const employerStatuses = ['new', 'contacted', 'in_progress', 'fulfilled', 'closed'];
  const candidateStatuses = ['new', 'contacted', 'shortlisted', 'interview', 'selected', 'joined', 'inactive'];
  const pages = { employers: 0, candidates: 0, companies: 0 };
  const pageCounts = { employers: 0, candidates: 0, companies: 0 };
  const recordsById = new Map();

  const detailFields = {
    employers: [
      ['Submitted', 'created_at'], ['Company', 'company_name'], ['Contact Person', 'contact_person'],
      ['Mobile', 'mobile'], ['Email', 'email'], ['Company Location', 'company_location'],
      ['Job Role', 'job_role'], ['Required Headcount', 'required_headcount'],
      ['Qualification', 'qualification'], ['ITI Trade / Specialization', 'iti_trade'],
      ['Experience Requirement', 'experience_requirement'], ['Gender Preference', 'gender_preference'],
      ['Salary / Wage', 'salary_wage'], ['Shift Details', 'shift_details'],
      ['Working Hours', 'working_hours'], ['Expected Joining Date', 'expected_joining_date'],
      ['Accommodation', 'accommodation'], ['Canteen', 'canteen'], ['Transport', 'transport'],
      ['Additional Notes', 'additional_notes'], ['Consent', 'consent'], ['Status', 'status']
    ],
    candidates: [
      ['Submitted', 'created_at'], ['Full Name', 'full_name'], ['Age', 'age'], ['Gender', 'gender'],
      ['Mobile', 'mobile'], ['WhatsApp Number', 'whatsapp_number'],
      ['Village / City', 'current_location'], ['District', 'district'], ['State', 'state'],
      ['Highest Qualification', 'highest_qualification'], ['Trade / Specialization', 'specialization'],
      ['Candidate Type', 'candidate_type'], ['Total Experience', 'total_experience'],
      ['Previous Job Role', 'previous_job_role'], ['Can Attend Interview', 'interview_available'],
      ['Preferred Job Location', 'preferred_job_location'],
      ['Additional Information', 'additional_information'], ['Consent', 'consent'], ['Status', 'status']
    ]
  };

  const createElement = (tag, className, text) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  };

  const showMessage = (element, message, type = '') => {
    if (!element) return;
    element.textContent = message;
    element.classList.toggle('is-error', type === 'error');
    element.classList.toggle('is-success', type === 'success');
  };

  const readableStatus = (status) => status.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  const formatDate = (value) => value ? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—';
  const normalizeWhatsApp = (value) => {
    const digits = String(value || '').replace(/\D/g, '');
    return digits.length === 10 ? `91${digits}` : digits;
  };
  const safeFilterTerm = (value) => String(value || '').trim().slice(0, 100).replace(/[%_,().]/g, ' ');

  const isApprovedAdmin = async (userId) => {
    const { data, error } = await client.from('admin_users').select('user_id').eq('user_id', userId).maybeSingle();
    return !error && Boolean(data);
  };

  const initializeLogin = async () => {
    const form = document.querySelector('[data-login-form]');
    const message = document.querySelector('[data-auth-message]');
    if (!connection?.isConfigured) {
      showMessage(message, 'Supabase is not configured. Add the project URL and anon key in config.js before using admin login.', 'error');
      form.querySelector('button[type="submit"]').disabled = true;
      return;
    }

    const { data: sessionData } = await client.auth.getSession();
    if (sessionData.session && await isApprovedAdmin(sessionData.session.user.id)) {
      window.location.replace('./index.html');
      return;
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (!form.checkValidity()) {
        form.reportValidity();
        return;
      }
      const button = form.querySelector('button[type="submit"]');
      button.disabled = true;
      button.textContent = 'Signing In…';
      showMessage(message, '');
      const values = new FormData(form);
      const { data, error } = await client.auth.signInWithPassword({
        email: String(values.get('email')).trim(),
        password: String(values.get('password'))
      });
      if (error || !data.user) {
        showMessage(message, 'Unable to sign in. Check your credentials and try again.', 'error');
        button.disabled = false;
        button.textContent = 'Sign In';
        return;
      }
      if (!await isApprovedAdmin(data.user.id)) {
        await client.auth.signOut();
        showMessage(message, 'Your account is not authorized for Aadhyant administration.', 'error');
        button.disabled = false;
        button.textContent = 'Sign In';
        return;
      }
      window.location.replace('./index.html');
    });
  };

  const addCell = (row, value, strong = false) => {
    const cell = document.createElement('td');
    const content = strong ? createElement('strong', '', value || '—') : document.createTextNode(value || '—');
    cell.append(content);
    row.append(cell);
  };

  const statusBadge = (status) => {
    const badge = createElement('span', 'status-badge', readableStatus(status));
    badge.dataset.status = status;
    return badge;
  };

  const actionLink = (label, href) => {
    const link = createElement('a', 'table-action', label);
    link.href = href;
    if (href.startsWith('https://')) {
      link.target = '_blank';
      link.rel = 'noopener';
    }
    return link;
  };

  const actionButton = (label, type, id, focusStatus = false) => {
    const button = createElement('button', 'table-action', label);
    button.type = 'button';
    button.addEventListener('click', () => openDetails(type, recordsById.get(`${type}:${id}`), focusStatus));
    return button;
  };

  const renderEmployerRow = (record) => {
    const row = document.createElement('tr');
    addCell(row, formatDate(record.created_at)); addCell(row, record.company_name, true);
    addCell(row, record.contact_person); addCell(row, record.mobile); addCell(row, record.company_location);
    addCell(row, record.job_role); addCell(row, String(record.required_headcount));
    const statusCell = document.createElement('td'); statusCell.append(statusBadge(record.status)); row.append(statusCell);
    const actionsCell = document.createElement('td'); const actions = createElement('div', 'table-actions');
    actions.append(actionButton('View Details', 'employers', record.id));
    actions.append(actionLink('WhatsApp', `https://wa.me/${normalizeWhatsApp(record.mobile)}`));
    actions.append(actionLink('Call', `tel:${record.mobile}`));
    if (record.email) actions.append(actionLink('Email', `mailto:${record.email}`));
    actions.append(actionButton('Update Status', 'employers', record.id, true));
    actionsCell.append(actions); row.append(actionsCell); return row;
  };

  const renderCandidateRow = (record) => {
    const row = document.createElement('tr');
    addCell(row, formatDate(record.created_at)); addCell(row, record.full_name, true); addCell(row, record.mobile);
    addCell(row, [record.current_location, record.district, record.state].filter(Boolean).join(', '));
    addCell(row, record.highest_qualification); addCell(row, record.specialization);
    addCell(row, record.candidate_type);
    const statusCell = document.createElement('td'); statusCell.append(statusBadge(record.status)); row.append(statusCell);
    const actionsCell = document.createElement('td'); const actions = createElement('div', 'table-actions');
    actions.append(actionButton('View Details', 'candidates', record.id));
    actions.append(actionLink('WhatsApp', `https://wa.me/${normalizeWhatsApp(record.whatsapp_number || record.mobile)}`));
    actions.append(actionLink('Call', `tel:${record.mobile}`));
    actions.append(actionButton('Update Status', 'candidates', record.id, true));
    actionsCell.append(actions); row.append(actionsCell); return row;
  };

  const openCompanyReview = (record) => {
    if (!record) return;
    const dialog = document.querySelector('[data-company-dialog]');
    const list = document.querySelector('[data-company-detail-list]');
    const form = document.querySelector('[data-company-status-form]');
    const owner = record.owner || {};
    const details = [
      ['Registered', formatDate(record.created_at)], ['Company', record.legal_name],
      ['Account email', owner.email || record.main_email], ['Contact person', record.contact_person || owner.display_name],
      ['Mobile', record.main_phone || owner.mobile], ['Industry', record.industry],
      ['City / State', [record.city, record.state].filter(Boolean).join(', ')], ['GSTIN', record.gstin],
      ['Website', record.website], ['Workforce size', record.workforce_size],
      ['Address', record.address], ['Submitted requirement / notes', record.onboarding_notes],
      ['Owner membership', owner.membershipStatus], ['Account status', record.account_status]
    ];
    document.querySelector('[data-company-dialog-title]').textContent = record.legal_name;
    list.replaceChildren();
    details.filter(([, value]) => value).forEach(([label, value]) => {
      const item = createElement('div'); item.append(createElement('dt', '', label), createElement('dd', '', String(value))); list.append(item);
    });
    form.elements.companyId.value = record.id;
    form.elements.accountStatus.value = record.account_status;
    showMessage(document.querySelector('[data-company-dialog-message]'), '');
    dialog.showModal();
  };

  const renderCompanyRow = (record) => {
    const owner = record.owner || {};
    const row = document.createElement('tr');
    addCell(row, formatDate(record.created_at)); addCell(row, record.legal_name, true);
    addCell(row, owner.email || record.main_email); addCell(row, record.contact_person || owner.display_name);
    addCell(row, record.main_phone || owner.mobile); addCell(row, [record.city, record.state].filter(Boolean).join(', '));
    addCell(row, record.gstin);
    const statusCell = document.createElement('td'); statusCell.append(statusBadge(record.account_status)); row.append(statusCell);
    const actionsCell = document.createElement('td'); const actions = createElement('div', 'table-actions');
    const review = createElement('button', 'table-action', 'Review Account'); review.type = 'button'; review.addEventListener('click', () => openCompanyReview(record));
    actions.append(review);
    if (record.main_phone) actions.append(actionLink('Call', `tel:${record.main_phone}`));
    if (owner.email || record.main_email) actions.append(actionLink('Email', `mailto:${owner.email || record.main_email}`));
    actionsCell.append(actions); row.append(actionsCell); return row;
  };

  const buildQuery = (type) => {
    const form = document.querySelector(`[data-filter-form="${type}"]`);
    const filters = new FormData(form);
    const table = type === 'employers' ? 'employer_requirements' : type === 'candidates' ? 'candidates' : 'companies';
    let query = client.from(table).select('*', { count: 'exact' });
    const status = String(filters.get('status') || '');
    if (status) query = query.eq(type === 'companies' ? 'account_status' : 'status', status);
    if (type === 'employers') {
      const company = safeFilterTerm(filters.get('company'));
      const location = safeFilterTerm(filters.get('location'));
      const role = safeFilterTerm(filters.get('role'));
      if (company) query = query.ilike('company_name', `%${company}%`);
      if (location) query = query.ilike('company_location', `%${location}%`);
      if (role) query = query.ilike('job_role', `%${role}%`);
    } else if (type === 'candidates') {
      const search = safeFilterTerm(filters.get('search'));
      const state = safeFilterTerm(filters.get('state'));
      const district = safeFilterTerm(filters.get('district'));
      const qualification = String(filters.get('qualification') || '');
      const candidateType = String(filters.get('candidateType') || '');
      if (search) query = query.or(`full_name.ilike.%${search}%,mobile.ilike.%${search}%`);
      if (state) query = query.ilike('state', `%${state}%`);
      if (district) query = query.ilike('district', `%${district}%`);
      if (qualification) query = query.eq('highest_qualification', qualification);
      if (candidateType) query = query.eq('candidate_type', candidateType);
    } else {
      const search = safeFilterTerm(filters.get('search'));
      const location = safeFilterTerm(filters.get('location'));
      if (search) query = query.ilike('legal_name', `%${search}%`);
      if (location) query = query.or(`city.ilike.%${location}%,state.ilike.%${location}%`);
    }
    const from = pages[type] * PAGE_SIZE;
    return query.order('created_at', { ascending: false }).range(from, from + PAGE_SIZE - 1);
  };

  const loadRecords = async (type) => {
    const body = document.querySelector(`[data-table-body="${type}"]`);
    const empty = document.querySelector(`[data-empty="${type}"]`);
    body.replaceChildren();
    const { data, count, error } = await buildQuery(type);
    if (error) throw new Error('records');
    pageCounts[type] = count || 0;
    let records = data || [];
    if (type === 'companies' && records.length) {
      const { data: memberships, error: membershipError } = await client.from('company_users')
        .select('company_id, user_id, role, status, platform_users(display_name,email,mobile,account_status)')
        .in('company_id', records.map((record) => record.id)).eq('role', 'owner');
      if (membershipError) throw new Error('company-memberships');
      const owners = new Map((memberships || []).map((membership) => [membership.company_id, {
        ...(membership.platform_users || {}), userId: membership.user_id, membershipStatus: membership.status
      }]));
      records = records.map((record) => ({ ...record, owner: owners.get(record.id) || null }));
    }
    records.forEach((record) => {
      recordsById.set(`${type}:${record.id}`, record);
      body.append(type === 'employers' ? renderEmployerRow(record) : type === 'candidates' ? renderCandidateRow(record) : renderCompanyRow(record));
    });
    const filters = new FormData(document.querySelector(`[data-filter-form="${type}"]`));
    const hasFilters = [...filters.values()].some((value) => String(value).trim());
    const recordLabel = type === 'employers' ? 'employer requirements' : type === 'candidates' ? 'candidate registrations' : 'company accounts';
    empty.textContent = hasFilters ? `No ${recordLabel} match the selected filters.` : `No ${recordLabel} have been received yet.`;
    empty.hidden = Boolean(records.length);
    const label = document.querySelector(`[data-page-label="${type}"]`);
    const totalPages = Math.max(1, Math.ceil(pageCounts[type] / PAGE_SIZE));
    label.textContent = `Page ${pages[type] + 1} of ${totalPages}`;
    document.querySelector(`[data-page="${type}-prev"]`).disabled = pages[type] === 0;
    document.querySelector(`[data-page="${type}-next"]`).disabled = pages[type] + 1 >= totalPages;
  };

  const exactCount = async (table, status = '', statusColumn = 'status') => {
    let query = client.from(table).select('id', { count: 'exact', head: true });
    if (status) query = query.eq(statusColumn, status);
    const { count, error } = await query;
    if (error) throw new Error('count');
    return count || 0;
  };

  const loadCounts = async () => {
    const [employerTotal, employerNew, candidateTotal, candidateNew, companyTotal, companyPending] = await Promise.all([
      exactCount('employer_requirements'), exactCount('employer_requirements', 'new'),
      exactCount('candidates'), exactCount('candidates', 'new'),
      exactCount('companies'), exactCount('companies', 'pending', 'account_status')
    ]);
    document.querySelector('[data-count="employer-total"]').textContent = employerTotal;
    document.querySelector('[data-count="employer-new"]').textContent = employerNew;
    document.querySelector('[data-count="candidate-total"]').textContent = candidateTotal;
    document.querySelector('[data-count="candidate-new"]').textContent = candidateNew;
    document.querySelector('[data-count="company-total"]').textContent = companyTotal;
    document.querySelector('[data-count="company-pending"]').textContent = companyPending;
  };

  const openDetails = (type, record, focusStatus = false) => {
    if (!record) return;
    const dialog = document.querySelector('[data-detail-dialog]');
    const title = document.querySelector('[data-detail-title]');
    const list = document.querySelector('[data-detail-list]');
    const form = document.querySelector('[data-detail-form]');
    title.textContent = type === 'employers' ? record.company_name : record.full_name;
    list.replaceChildren();
    detailFields[type].forEach(([label, key]) => {
      let value = record[key];
      if (value === null || value === undefined || value === '') return;
      if (key === 'created_at') value = formatDate(value);
      if (key === 'consent') value = value ? 'Confirmed' : 'Not confirmed';
      if (key === 'status') value = readableStatus(value);
      const item = document.createElement('div');
      const term = createElement('dt', '', label); const description = createElement('dd', '', String(value));
      item.append(term, description); list.append(item);
    });
    form.elements.recordId.value = record.id;
    form.elements.recordType.value = type;
    form.elements.internalNotes.value = record.internal_notes || '';
    const statuses = type === 'employers' ? employerStatuses : candidateStatuses;
    form.elements.status.replaceChildren();
    statuses.forEach((status) => {
      const option = createElement('option', '', readableStatus(status));
      option.value = status; option.selected = status === record.status; form.elements.status.append(option);
    });
    showMessage(document.querySelector('[data-detail-message]'), '');
    dialog.showModal();
    if (focusStatus) form.elements.status.focus();
  };

  const initializeDashboard = async () => {
    const loading = document.querySelector('[data-admin-loading]');
    const dashboard = document.querySelector('[data-dashboard]');
    const dashboardMessage = document.querySelector('[data-dashboard-message]');
    if (!connection?.isConfigured) {
      loading.textContent = 'Supabase is not configured. Add the public project URL and anon key in config.js.';
      return;
    }
    const { data, error } = await client.auth.getSession();
    if (error || !data.session) {
      window.location.replace('./login.html');
      return;
    }
    if (!await isApprovedAdmin(data.session.user.id)) {
      await client.auth.signOut();
      window.location.replace('./login.html');
      return;
    }
    document.querySelector('[data-admin-email]').textContent = data.session.user.email || 'Approved administrator';
    loading.hidden = true; dashboard.hidden = false;

    const loadDashboard = async () => {
      showMessage(dashboardMessage, 'Loading dashboard data…');
      try {
        await Promise.all([loadCounts(), loadRecords('employers'), loadRecords('candidates'), loadRecords('companies')]);
        showMessage(dashboardMessage, '');
      } catch (_error) {
        showMessage(dashboardMessage, 'Dashboard data could not be loaded. Check the connection and try again.', 'error');
      }
    };

    document.querySelector('[data-logout]').addEventListener('click', async () => {
      await client.auth.signOut();
      window.location.replace('./login.html');
    });
    document.querySelector('[data-refresh]').addEventListener('click', loadDashboard);

    document.querySelectorAll('[data-tab]').forEach((tab) => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('[data-tab]').forEach((item) => item.setAttribute('aria-selected', String(item === tab)));
        document.querySelectorAll('[data-panel]').forEach((panel) => { panel.hidden = panel.dataset.panel !== tab.dataset.tab; });
      });
    });

    document.querySelectorAll('[data-filter-form]').forEach((form) => {
      const type = form.dataset.filterForm;
      form.addEventListener('submit', async (event) => {
        event.preventDefault(); pages[type] = 0;
        try { await loadRecords(type); } catch (_error) { showMessage(dashboardMessage, 'Filters could not be applied. Try again.', 'error'); }
      });
      form.addEventListener('reset', () => setTimeout(async () => {
        pages[type] = 0;
        try { await loadRecords(type); } catch (_error) { showMessage(dashboardMessage, 'Records could not be refreshed.', 'error'); }
      }, 0));
    });

    document.querySelectorAll('[data-page]').forEach((button) => {
      button.addEventListener('click', async () => {
        const [type, direction] = button.dataset.page.split('-');
        pages[type] += direction === 'next' ? 1 : -1;
        try { await loadRecords(type); } catch (_error) { pages[type] += direction === 'next' ? -1 : 1; showMessage(dashboardMessage, 'The requested page could not be loaded.', 'error'); }
      });
    });

    const dialog = document.querySelector('[data-detail-dialog]');
    document.querySelectorAll('[data-close-dialog]').forEach((button) => button.addEventListener('click', () => dialog.close()));
    dialog.addEventListener('click', (event) => { if (event.target === dialog) dialog.close(); });
    document.querySelector('[data-detail-form]').addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = event.currentTarget; const button = form.querySelector('button[type="submit"]');
      const type = form.elements.recordType.value; const table = type === 'employers' ? 'employer_requirements' : 'candidates';
      const detailMessage = document.querySelector('[data-detail-message]');
      button.disabled = true; button.textContent = 'Saving…'; showMessage(detailMessage, '');
      const { error: updateError } = await client.from(table).update({ status: form.elements.status.value, internal_notes: form.elements.internalNotes.value.trim() || null }).eq('id', form.elements.recordId.value);
      button.disabled = false; button.textContent = 'Save Status & Notes';
      if (updateError) { showMessage(detailMessage, 'The update could not be saved. Check your connection and try again.', 'error'); return; }
      showMessage(detailMessage, 'Status and internal notes saved.', 'success');
      try { await Promise.all([loadCounts(), loadRecords(type)]); } catch (_error) { showMessage(dashboardMessage, 'The update was saved, but the dashboard could not be refreshed.', 'error'); }
    });

    const companyDialog = document.querySelector('[data-company-dialog]');
    document.querySelectorAll('[data-close-company-dialog]').forEach((button) => button.addEventListener('click', () => companyDialog.close()));
    companyDialog.addEventListener('click', (event) => { if (event.target === companyDialog) companyDialog.close(); });
    document.querySelector('[data-company-status-form]').addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = event.currentTarget; const button = form.querySelector('button[type="submit"]');
      const companyMessage = document.querySelector('[data-company-dialog-message]');
      button.disabled = true; button.textContent = 'Saving…'; showMessage(companyMessage, '');
      const { error: statusError } = await client.rpc('set_company_account_status', {
        p_company_id: form.elements.companyId.value,
        p_account_status: form.elements.accountStatus.value
      });
      button.disabled = false; button.textContent = 'Save Account Status';
      if (statusError) { showMessage(companyMessage, 'The company status could not be updated. No access change was made.', 'error'); return; }
      showMessage(companyMessage, 'Company account status updated.', 'success');
      try { await Promise.all([loadCounts(), loadRecords('companies')]); } catch (_error) { showMessage(dashboardMessage, 'Status was updated, but company records could not be refreshed.', 'error'); }
    });

    client.auth.onAuthStateChange((event) => { if (event === 'SIGNED_OUT') window.location.replace('./login.html'); });
    await loadDashboard();
  };

  if (pageType === 'login') initializeLogin();
  if (pageType === 'dashboard') initializeDashboard();
}());
