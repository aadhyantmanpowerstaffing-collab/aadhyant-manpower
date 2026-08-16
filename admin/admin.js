(function initializeAdmin() {
  const PAGE_SIZE = 25;
  const pageType = document.body.dataset.adminPage;
  const connection = window.aadhyantSupabase;
  const client = connection?.client;

  const employerStatuses = ['new', 'contacted', 'in_progress', 'fulfilled', 'closed'];
  const candidateStatuses = ['new', 'contacted', 'shortlisted', 'interview', 'selected', 'joined', 'inactive'];
  const pages = { employers: 0, candidates: 0, candidateInterests: 0, companies: 0, companyRequirements: 0, contractors: 0 };
  const pageCounts = { employers: 0, candidates: 0, candidateInterests: 0, companies: 0, companyRequirements: 0, contractors: 0 };
  const loadVersions = { employers: 0, candidates: 0, candidateInterests: 0, companies: 0, companyRequirements: 0, contractors: 0 };
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

  const renderCandidateInterestRow = (record) => {
    const candidate = record.candidates || {};
    const requirement = record.employer_requirements || {};
    const row = document.createElement('tr');
    [formatDate(record.applied_at), requirement.requirement_code, requirement.job_role,
      candidate.full_name, candidate.mobile,
      [candidate.current_location, candidate.district, candidate.state].filter(Boolean).join(', '),
      candidate.highest_qualification, candidate.specialization,
      [candidate.candidate_type, candidate.total_experience].filter(Boolean).join(' / ')
    ].forEach((value) => addCell(row, value));
    const statusCell = document.createElement('td'); statusCell.append(statusBadge(record.application_status)); row.append(statusCell);
    const actionCell = document.createElement('td'); const manage = createElement('button', 'table-action', 'View / Manage'); manage.type = 'button'; manage.addEventListener('click', () => openCandidateApplication(record, manage)); actionCell.append(manage); row.append(actionCell);
    return row;
  };

  let applicationReturnFocus = null;
  let interviewLoadVersion = 0;
  let activeInterviewApplicationId = null;
  let activeInterviewMutation = null;
  let interviewIntegrityFailure = false;
  const interviewRecords = new Map();
  const appendDetails = (list, details) => {
    list.replaceChildren();
    details.filter(([, value]) => value !== null && value !== undefined && value !== '').forEach(([label, value]) => {
      const item = createElement('div'); item.append(createElement('dt', '', label), createElement('dd', '', String(value))); list.append(item);
    });
  };
  const toDatetimeLocal = (value) => {
    if (!value) return '';
    const date = new Date(value); const offset = date.getTimezoneOffset() * 60000;
    return new Date(date.getTime() - offset).toISOString().slice(0, 16);
  };
  const resetInterviewForm = (applicationId) => {
    const form = document.querySelector('[data-interview-form]');
    form.reset(); form.elements.applicationId.value = applicationId; form.elements.interviewId.value = '';
    form.querySelector('button[type="submit"]').textContent = 'Schedule Interview';
    document.querySelector('[data-cancel-reschedule]').hidden = true;
    showMessage(document.querySelector('[data-interview-form-message]'), '');
  };
  const editInterviewSchedule = (record) => {
    const form = document.querySelector('[data-interview-form]');
    form.elements.interviewId.value = record.id; form.elements.scheduledAt.value = toDatetimeLocal(record.scheduled_at);
    form.elements.mode.value = record.mode || ''; form.elements.location.value = record.location || '';
    form.elements.meetingLink.value = record.meeting_link || ''; form.elements.contactPerson.value = record.contact_person || '';
    form.elements.contactPhone.value = record.contact_phone || ''; form.elements.instructions.value = record.instructions || '';
    form.querySelector('button[type="submit"]').textContent = 'Reschedule Interview';
    document.querySelector('[data-cancel-reschedule]').hidden = false; form.elements.scheduledAt.focus();
  };
  const editInterviewOutcome = (record) => {
    const form = document.querySelector('[data-interview-outcome-form]');
    form.hidden = false; form.elements.interviewId.value = record.id;
    form.elements.status.value = record.status === 'attended' ? 'completed' : 'attended';
    form.elements.result.value = record.result || ''; form.elements.resultNotes.value = record.result_notes || '';
    showMessage(document.querySelector('[data-interview-outcome-message]'), ''); form.elements.status.focus();
  };
  const setInterviewMutationControls = (disabled) => {
    document.querySelectorAll('[data-interview-form] button, [data-interview-outcome-form] button, [data-new-interview], [data-interview-history] button').forEach((control) => { control.disabled = disabled || interviewIntegrityFailure; });
  };
  const beginInterviewMutation = (applicationId) => {
    if (activeInterviewMutation) return false;
    activeInterviewMutation = applicationId; setInterviewMutationControls(true); return true;
  };
  const endInterviewMutation = (applicationId) => {
    if (activeInterviewMutation === applicationId) activeInterviewMutation = null;
    setInterviewMutationControls(false);
  };
  const interviewErrorMessage = (error, action) => {
    const detail = String(error?.message || '').toLowerCase();
    if (detail.includes('already scheduled')) return 'An interview is already scheduled for this application.';
    if (detail.includes('not eligible')) return 'This application is no longer eligible for interview scheduling.';
    return action === 'update' ? 'Interview status could not be updated. Refresh and try again.' : 'The interview could not be scheduled. Refresh and try again.';
  };
  const sameOptionalText = (persisted, requested) => (persisted || null) === (requested || null);
  const loadInterviewHistory = async (applicationId) => {
    const loadVersion = ++interviewLoadVersion; const message = document.querySelector('[data-interview-load-message]');
    showMessage(message, 'Loading interview history…');
    const { data, error } = await client.from('interviews')
      .select('id,application_id,interview_round,supersedes_interview_id,scheduled_at,mode,location,meeting_link,contact_person,contact_phone,instructions,status,result,result_notes,created_at,updated_at')
      .eq('application_id', applicationId).order('created_at', { ascending: false }).limit(50);
    if (loadVersion !== interviewLoadVersion || applicationId !== activeInterviewApplicationId) return { ok: false, stale: true, records: [] };
    if (error) { showMessage(message, 'Interview history could not be loaded. Please try again.', 'error'); return { ok: false, records: [] }; }
    const records = data || []; const body = document.querySelector('[data-interview-history]'); body.replaceChildren(); interviewRecords.clear();
    records.forEach((record) => {
      interviewRecords.set(record.id, record); const row = document.createElement('tr');
      [String(record.interview_round), formatDate(record.scheduled_at), readableStatus(record.mode || ''), readableStatus(record.status), readableStatus(record.result || 'pending'), formatDate(record.updated_at)].forEach((value) => addCell(row, value));
      const actionCell = document.createElement('td'); const actions = createElement('div', 'table-actions');
      if (record.status === 'scheduled') {
        const reschedule = createElement('button', 'table-action', 'Reschedule'); reschedule.type = 'button'; reschedule.addEventListener('click', () => editInterviewSchedule(record)); actions.append(reschedule);
        const outcome = createElement('button', 'table-action', 'Update Status'); outcome.type = 'button'; outcome.addEventListener('click', () => editInterviewOutcome(record)); actions.append(outcome);
      } else if (record.status === 'attended') {
        const outcome = createElement('button', 'table-action', 'Complete'); outcome.type = 'button'; outcome.addEventListener('click', () => editInterviewOutcome(record)); actions.append(outcome);
      }
      actionCell.append(actions); row.append(actionCell); body.append(row);
    });
    document.querySelector('[data-interview-empty]').hidden = Boolean(records.length);
    const scheduled = records.filter((record) => record.status === 'scheduled');
    const integrityFailure = scheduled.length > 1; interviewIntegrityFailure = integrityFailure;
    const current = scheduled[0] || records[0]; const summary = document.querySelector('[data-interview-summary]');
    setInterviewMutationControls(Boolean(activeInterviewMutation));
    if (integrityFailure) showMessage(message, 'Interview records require review before another schedule change can be made.', 'error');
    else if (!current) { appendDetails(summary, [['Status', 'No interview scheduled yet.']]); }
    else appendDetails(summary, [
      ['Interview round', current.interview_round], ['Scheduled', formatDate(current.scheduled_at)], ['Mode', readableStatus(current.mode || '')],
      ['Status', readableStatus(current.status)], ['Result', readableStatus(current.result || 'pending')], ['Location', current.location || '—'],
      ['Meeting link', current.meeting_link || '—'], ['Contact person', current.contact_person || '—'], ['Contact phone', current.contact_phone || '—'],
      ['Last updated', formatDate(current.updated_at)]
    ]);
    if (!integrityFailure) showMessage(message, '');
    return { ok: !integrityFailure, integrityFailure, records, current: scheduled[0] || null };
  };
  const openCandidateApplication = (record, trigger) => {
    if (!record) return;
    const candidate = record.candidates || {}; const requirement = record.employer_requirements || {};
    const dialog = document.querySelector('[data-application-dialog]'); const form = document.querySelector('[data-application-form]');
    applicationReturnFocus = trigger; activeInterviewApplicationId = record.id; interviewIntegrityFailure = false;
    document.querySelector('[data-application-title]').textContent = `${requirement.requirement_code || 'Requirement'} · ${candidate.full_name || 'Candidate'}`;
    appendDetails(document.querySelector('[data-application-requirement]'), [
      ['Requirement code', requirement.requirement_code], ['Job role', requirement.job_role], ['Department', requirement.department],
      ['Job location', requirement.job_location], ['Open positions', Math.max(0, Number(requirement.required_headcount || 0) - Number(requirement.filled_positions || 0))],
      ['Salary', [requirement.salary_min, requirement.salary_max].filter((value) => value !== null).join(' – ')],
      ['Qualification', requirement.qualification], ['Experience', requirement.experience_requirement], ['Shift', requirement.shift_details],
      ['Facilities', [['Canteen', requirement.canteen], ['Transport', requirement.transport], ['Accommodation', requirement.accommodation]].filter(([, value]) => value === 'Yes').map(([label]) => label).join(', ')],
      ['Stage', readableStatus(requirement.requirement_stage || '')], ['Visibility', readableStatus(requirement.requirement_visibility || '')]
    ]);
    appendDetails(document.querySelector('[data-application-candidate]'), [
      ['Full name', candidate.full_name], ['Age', candidate.age], ['Gender', candidate.gender], ['Mobile', candidate.mobile],
      ['WhatsApp', candidate.whatsapp_number], ['Village / City', candidate.current_location], ['District', candidate.district], ['State', candidate.state],
      ['Qualification', candidate.highest_qualification], ['Specialization', candidate.specialization], ['Candidate type', candidate.candidate_type],
      ['Experience', candidate.total_experience], ['Previous role', candidate.previous_job_role], ['Interview availability', candidate.interview_available],
      ['Preferred job location', candidate.preferred_job_location], ['Additional information', candidate.additional_information], ['Registered', formatDate(candidate.created_at)],
      ['Interest source', readableStatus(record.source_type || '')], ['Interested', formatDate(record.applied_at)], ['Last updated', formatDate(record.updated_at)]
    ]);
    form.elements.applicationId.value = record.id; form.elements.applicationStatus.value = record.application_status; form.elements.adminNotes.value = record.admin_notes || '';
    resetInterviewForm(record.id); document.querySelector('[data-interview-outcome-form]').hidden = true;
    showMessage(document.querySelector('[data-application-message]'), ''); dialog.showModal();
    loadInterviewHistory(record.id); form.elements.applicationStatus.focus();
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

  const openContractorReview = (record) => {
    const dialog=document.querySelector('[data-contractor-dialog]'),list=document.querySelector('[data-contractor-details]'),form=document.querySelector('[data-contractor-status-form]'),owner=record.owner||{};
    document.querySelector('[data-contractor-title]').textContent=record.agency_name;list.replaceChildren();[['Registered',formatDate(record.created_at)],['Agency',record.agency_name],['Contact',record.owner_name||owner.display_name],['Email',owner.email||record.main_email],['Mobile',record.main_phone||owner.mobile],['Location',[record.city,record.district,record.state].filter(Boolean).join(', ')],['GSTIN',record.gstin],['Labour licence',record.labour_license_number],['EPFO',record.epfo_code],['ESIC',record.esic_code],['Capacity',record.workforce_capacity],['Service areas',(record.operating_locations||[]).join(', ')],['Categories',(record.manpower_categories||[]).join(', ')],['Notes',record.onboarding_notes]].filter(([,v])=>v!==null&&v!=='').forEach(([k,v])=>{const d=createElement('div');d.append(createElement('dt','',k),createElement('dd','',String(v)));list.append(d)});form.elements.contractorId.value=record.id;form.elements.status.value=record.account_status;showMessage(document.querySelector('[data-contractor-message]'),'');dialog.showModal();
  };
  const renderContractorRow = record => {const row=document.createElement('tr'),owner=record.owner||{};[formatDate(record.created_at),record.agency_name,record.owner_name||owner.display_name,owner.email||record.main_email,record.main_phone||owner.mobile,[record.city,record.state].filter(Boolean).join(', '),record.gstin].forEach(v=>addCell(row,v));const s=document.createElement('td');s.append(statusBadge(record.account_status));row.append(s);const a=document.createElement('td'),b=createElement('button','table-action','Review');b.type='button';b.onclick=()=>openContractorReview(record);a.append(b);row.append(a);return row};

  const loadRequirementAssignments = async (record) => {
    const {data:assignments,error}=await client.from('requirement_contractors').select('id,contractor_id,assigned_headcount,assignment_status,assigned_at,accepted_at,declined_at,closed_at,contractors(agency_name)').eq('requirement_id',record.id).order('assigned_at');if(error)throw error;
    const counted=(assignments||[]).filter(x=>['assigned','accepted','active'].includes(x.assignment_status)).reduce((sum,x)=>sum+x.assigned_headcount,0),open=Math.max(0,record.required_headcount-record.filled_positions),remaining=Math.max(0,open-counted);
    document.querySelector('[data-assignment-summary=open]').textContent=open;document.querySelector('[data-assignment-summary=allocated]').textContent=counted;document.querySelector('[data-assignment-summary=remaining]').textContent=remaining;
    const form=document.querySelector('[data-assignment-form]');form.elements.requirementId.value=record.id;form.elements.headcount.max=remaining;form.hidden=record.requirement_stage!=='open'||remaining===0;
    const {data:contractors,error:ce}=await client.from('contractors').select('id,agency_name').eq('account_status','active').order('agency_name');if(ce)throw ce;form.elements.contractorId.replaceChildren(new Option('Select active partner',''));(contractors||[]).filter(c=>!(assignments||[]).some(a=>a.contractor_id===c.id)).forEach(c=>form.elements.contractorId.add(new Option(c.agency_name,c.id)));
    const body=document.querySelector('[data-assignment-list]');body.replaceChildren();(assignments||[]).forEach(a=>{const row=document.createElement('tr');[a.contractors?.agency_name||'Partner',a.assigned_headcount,readableStatus(a.assignment_status),formatDate(a.assigned_at),formatDate(a.accepted_at||a.declined_at)].forEach(v=>addCell(row,String(v)));const cell=document.createElement('td');if(['assigned','accepted','active'].includes(a.assignment_status)){const cancel=createElement('button','table-action','Cancel');cancel.type='button';cancel.onclick=async()=>{const {error:e}=await client.rpc('set_requirement_assignment_status',{p_assignment_id:a.id,p_assignment_status:'cancelled'});if(e){showMessage(document.querySelector('[data-assignment-message]'),'Could not cancel assignment.','error');return}await loadRequirementAssignments(record)};cell.append(cancel)}if(a.assignment_status==='accepted'){const start=createElement('button','table-action','Start');start.type='button';start.onclick=async()=>{const {error:e}=await client.rpc('set_requirement_assignment_status',{p_assignment_id:a.id,p_assignment_status:'active'});if(e){showMessage(document.querySelector('[data-assignment-message]'),'Could not start assignment.','error');return}await loadRequirementAssignments(record)};cell.append(start)}row.append(cell);body.append(row)});
  };
  const openCompanyRequirement = async (record) => {
    const dialog = document.querySelector('[data-requirement-admin-dialog]'); const list = document.querySelector('[data-requirement-admin-list]'); const form = document.querySelector('[data-requirement-admin-form]');
    document.querySelector('[data-requirement-admin-title]').textContent = `${record.requirement_code} · ${record.job_role}`; list.replaceChildren();
    const open = Math.max(0, record.required_headcount - record.filled_positions); const details = [['Company', record.company_name], ['Contact', `${record.contact_person || '—'} · ${record.mobile || '—'}`], ['Department / role', `${record.department} / ${record.job_role}`], ['Location', record.job_location], ['Headcount', record.required_headcount], ['Filled / open', `${record.filled_positions} / ${open}`], ['Salary', `${record.salary_min ?? '—'} - ${record.salary_max ?? '—'}`], ['Interview', record.interview_date ? formatDate(record.interview_date) : 'Not scheduled'], ['Notes', record.additional_notes]];
    details.filter(([, value]) => value !== null && value !== '').forEach(([label, value]) => { const item = createElement('div'); item.append(createElement('dt', '', label), createElement('dd', '', String(value))); list.append(item); });
    form.elements.requirementId.value = record.id; form.elements.stage.value = record.requirement_stage; form.elements.visibility.value = record.requirement_visibility; showMessage(document.querySelector('[data-requirement-admin-message]'), ''); dialog.showModal();await loadRequirementAssignments(record);
  };

  const renderCompanyRequirementRow = (record) => {
    const row = document.createElement('tr'); const open = Math.max(0, record.required_headcount - record.filled_positions);
    [formatDate(record.created_at), record.requirement_code, `${record.company_name}\n${record.contact_person || ''}`, `${record.department} / ${record.job_role}`, record.job_location, String(record.required_headcount), `${record.filled_positions} filled / ${open} open`, `${record.salary_min ?? '—'} - ${record.salary_max ?? '—'}`, readableStatus(record.requirement_stage), readableStatus(record.requirement_visibility)].forEach((value) => addCell(row, value));
    const cell = document.createElement('td'); const button = createElement('button', 'table-action', 'Review'); button.type = 'button'; button.addEventListener('click', () => openCompanyRequirement(record)); cell.append(button); row.append(cell); return row;
  };

  const buildQuery = (type) => {
    const form = document.querySelector(`[data-filter-form="${type}"]`);
    const filters = new FormData(form);
    if (type === 'candidateInterests') {
      const code = safeFilterTerm(filters.get('code')); const role = safeFilterTerm(filters.get('role'));
      const candidate = safeFilterTerm(filters.get('candidate')); const status = String(filters.get('status') || '');
      const location = safeFilterTerm(filters.get('location')); const qualification = safeFilterTerm(filters.get('qualification')); const since = String(filters.get('since') || '');
      let query = client.from('candidate_applications').select('id,source_type,application_status,admin_notes,applied_at,updated_at,candidates!inner(full_name,age,gender,mobile,whatsapp_number,current_location,district,state,highest_qualification,specialization,candidate_type,total_experience,previous_job_role,interview_available,preferred_job_location,additional_information,created_at),employer_requirements!inner(requirement_code,job_role,department,job_location,required_headcount,filled_positions,salary_min,salary_max,qualification,experience_requirement,shift_details,canteen,transport,accommodation,requirement_stage,requirement_visibility)', { count: 'exact' });
      if (code) query = query.ilike('employer_requirements.requirement_code', `%${code}%`);
      if (role) query = query.ilike('employer_requirements.job_role', `%${role}%`);
      if (candidate) query = /^[0-9]+$/.test(candidate) ? query.ilike('candidates.mobile', `%${candidate}%`) : query.ilike('candidates.full_name', `%${candidate}%`);
      if (status) query = query.eq('application_status', status);
      if (location) query = query.or(`current_location.ilike.%${location}%,district.ilike.%${location}%,state.ilike.%${location}%`, { referencedTable: 'candidates' });
      if (qualification) query = query.ilike('candidates.highest_qualification', `%${qualification}%`);
      if (since) query = query.gte('applied_at', `${since}T00:00:00.000Z`);
      const from = pages[type] * PAGE_SIZE;
      return query.order('applied_at', { ascending: false }).range(from, from + PAGE_SIZE - 1);
    }
    const table = type === 'employers' || type === 'companyRequirements' ? 'employer_requirements' : type === 'candidates' ? 'candidates' : type === 'contractors' ? 'contractors' : 'companies';
    let query = client.from(table).select('*', { count: 'exact' });
    const status = String(filters.get('status') || '');
    if (status) query = query.eq(type === 'companies' || type === 'contractors' ? 'account_status' : 'status', status);
    if (type === 'employers') {
      const company = safeFilterTerm(filters.get('company'));
      const location = safeFilterTerm(filters.get('location'));
      const role = safeFilterTerm(filters.get('role'));
      if (company) query = query.ilike('company_name', `%${company}%`);
      if (location) query = query.ilike('company_location', `%${location}%`);
      if (role) query = query.ilike('job_role', `%${role}%`);
    } else if (type === 'companyRequirements') {
      query = query.not('company_id', 'is', null);
      const stage = String(filters.get('stage') || ''); const company = safeFilterTerm(filters.get('company')); const code = safeFilterTerm(filters.get('code')); const location = safeFilterTerm(filters.get('location'));
      if (stage) query = query.eq('requirement_stage', stage); if (company) query = query.ilike('company_name', `%${company}%`); if (code) query = query.ilike('requirement_code', `%${code}%`); if (location) query = query.ilike('job_location', `%${location}%`);
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
    } else if(type==='companies'||type==='contractors') {
      const search = safeFilterTerm(filters.get('search'));
      const location = safeFilterTerm(filters.get('location'));
      if (search) query = query.ilike(type==='contractors'?'agency_name':'legal_name', `%${search}%`);
      if (location) query = query.or(`city.ilike.%${location}%,state.ilike.%${location}%`);
    }
    const from = pages[type] * PAGE_SIZE;
    return query.order('created_at', { ascending: false }).range(from, from + PAGE_SIZE - 1);
  };

  const loadRecords = async (type) => {
    const body = document.querySelector(`[data-table-body="${type}"]`);
    const empty = document.querySelector(`[data-empty="${type}"]`);
    const loadVersion = ++loadVersions[type];
    const { data, count, error } = await buildQuery(type);
    if (loadVersion !== loadVersions[type]) return false;
    if (error) throw new Error('records');
    pageCounts[type] = count || 0;
    let records = data || [];
    if ((type === 'companies'||type==='contractors') && records.length) {
      const membershipTable=type==='contractors'?'contractor_users':'company_users', idColumn=type==='contractors'?'contractor_id':'company_id';
      const { data: memberships, error: membershipError } = await client.from(membershipTable)
        .select(`${idColumn}, user_id, role, status, platform_users(display_name,email,mobile,account_status)`)
        .in(idColumn, records.map((record) => record.id)).eq('role', 'owner');
      if (membershipError) throw new Error('company-memberships');
      const owners = new Map((memberships || []).map((membership) => [membership[idColumn], {
        ...(membership.platform_users || {}), userId: membership.user_id, membershipStatus: membership.status
      }]));
      records = records.map((record) => ({ ...record, owner: owners.get(record.id) || null }));
    }
    if (loadVersion !== loadVersions[type]) return false;
    body.replaceChildren();
    records.forEach((record) => {
      recordsById.set(`${type}:${record.id}`, record);
      body.append(type === 'employers' ? renderEmployerRow(record) : type === 'candidates' ? renderCandidateRow(record) : type === 'candidateInterests' ? renderCandidateInterestRow(record) : type === 'companyRequirements' ? renderCompanyRequirementRow(record) : type==='contractors'?renderContractorRow(record):renderCompanyRow(record));
    });
    const filters = new FormData(document.querySelector(`[data-filter-form="${type}"]`));
    const hasFilters = [...filters.values()].some((value) => String(value).trim());
    const recordLabel = type === 'employers' ? 'employer requirements' : type === 'candidates' ? 'candidate registrations' : type === 'candidateInterests' ? 'Candidate job interests' : type === 'companyRequirements' ? 'company requirements' : type==='contractors'?'staffing partners':'company accounts';
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
        await Promise.all([loadCounts(), loadRecords('employers'), loadRecords('candidates'), loadRecords('candidateInterests'), loadRecords('companies'), loadRecords('companyRequirements'),loadRecords('contractors')]);
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

    const applicationDialog = document.querySelector('[data-application-dialog]');
    const closeApplicationDialog = () => {
      activeInterviewApplicationId = null; interviewLoadVersion += 1; activeInterviewMutation = null; interviewIntegrityFailure = false; setInterviewMutationControls(false);
      applicationDialog.close(); applicationReturnFocus?.focus(); applicationReturnFocus = null;
    };
    document.querySelectorAll('[data-close-application]').forEach((button) => button.addEventListener('click', closeApplicationDialog));
    applicationDialog.addEventListener('click', (event) => { if (event.target === applicationDialog) closeApplicationDialog(); });
    applicationDialog.addEventListener('close', () => {
      activeInterviewApplicationId = null; interviewLoadVersion += 1; activeInterviewMutation = null; interviewIntegrityFailure = false; setInterviewMutationControls(false);
      if (applicationReturnFocus) { applicationReturnFocus.focus(); applicationReturnFocus = null; }
    });
    document.querySelector('[data-application-form]').addEventListener('submit', async (event) => {
      event.preventDefault(); const form = event.currentTarget; const button = form.querySelector('button[type="submit"]'); const message = document.querySelector('[data-application-message]');
      if (!form.checkValidity()) { form.reportValidity(); return; }
      if (form.dataset.saving === 'true') return;
      const applicationId = form.elements.applicationId.value;
      const requestedStatus = form.elements.applicationStatus.value;
      const requestedNotes = form.elements.adminNotes.value.trim() || null;
      form.dataset.saving = 'true'; button.disabled = true; button.textContent = 'Saving…'; showMessage(message, '');
      try {
        const { data: saved, error } = await client.rpc('admin_update_candidate_application', {
          p_application_id: applicationId,
          p_application_status: requestedStatus,
          p_admin_notes: requestedNotes
        });
        if (error || saved !== true) {
          showMessage(message, 'The application could not be updated. Check your access and connection, then try again.', 'error');
          return;
        }
        const { data: persisted, error: verifyError } = await client.from('candidate_applications')
          .select('id,application_status,admin_notes,updated_at')
          .eq('id', applicationId)
          .maybeSingle();
        if (verifyError || !persisted || persisted.application_status !== requestedStatus || (persisted.admin_notes || null) !== requestedNotes) {
          showMessage(message, 'The update could not be confirmed. Reload the application before trying again.', 'error');
          return;
        }
        form.elements.applicationStatus.value = persisted.application_status;
        form.elements.adminNotes.value = persisted.admin_notes || '';
        const cached = recordsById.get(`candidateInterests:${applicationId}`);
        if (cached) recordsById.set(`candidateInterests:${applicationId}`, { ...cached, ...persisted });
        showMessage(message, 'Application status and internal note saved.', 'success');
        try { await loadRecords('candidateInterests'); } catch (_error) { showMessage(message, 'The update was saved, but the filtered list could not be refreshed.', 'error'); }
      } catch (_error) {
        showMessage(message, 'The application could not be updated. Check your access and connection, then try again.', 'error');
      } finally {
        delete form.dataset.saving; button.disabled = false; button.textContent = 'Save Application';
      }
    });

    document.querySelector('[data-new-interview]').addEventListener('click', () => {
      const applicationId = document.querySelector('[data-application-form]').elements.applicationId.value;
      resetInterviewForm(applicationId); document.querySelector('[data-interview-form]').elements.scheduledAt.focus();
    });
    document.querySelector('[data-cancel-reschedule]').addEventListener('click', () => {
      resetInterviewForm(document.querySelector('[data-interview-form]').elements.applicationId.value);
    });
    document.querySelector('[data-cancel-interview-outcome]').addEventListener('click', () => {
      document.querySelector('[data-interview-outcome-form]').hidden = true;
    });
    document.querySelector('[data-interview-form]').addEventListener('submit', async (event) => {
      event.preventDefault(); const form = event.currentTarget; const button = form.querySelector('button[type="submit"]'); const message = document.querySelector('[data-interview-form-message]');
      if (!form.checkValidity()) { form.reportValidity(); return; }
      if (form.dataset.saving === 'true' || activeInterviewMutation) return;
      const applicationId = form.elements.applicationId.value; const interviewId = form.elements.interviewId.value;
      const scheduledDate = new Date(form.elements.scheduledAt.value);
      if (!Number.isFinite(scheduledDate.getTime()) || scheduledDate <= new Date()) { showMessage(message, 'Choose a future interview date and time.', 'error'); return; }
      const details = {
        p_scheduled_at: scheduledDate.toISOString(), p_mode: form.elements.mode.value,
        p_location: form.elements.location.value.trim() || null, p_meeting_link: form.elements.meetingLink.value.trim() || null,
        p_contact_person: form.elements.contactPerson.value.trim() || null, p_contact_phone: form.elements.contactPhone.value.trim() || null,
        p_instructions: form.elements.instructions.value.trim() || null
      };
      if (![details.p_location, details.p_meeting_link, details.p_contact_person, details.p_contact_phone, details.p_instructions]
        .every((value, index) => !value || value.length <= [500, 1000, 200, 30, 4000][index])) {
        showMessage(message, 'One or more interview details exceed the allowed length.', 'error'); return;
      }
      const rpcName = interviewId ? 'admin_reschedule_candidate_interview' : 'admin_schedule_candidate_interview';
      const rpcArgs = interviewId ? { p_interview_id: interviewId, ...details } : { p_application_id: applicationId, ...details };
      if (!beginInterviewMutation(applicationId)) return;
      form.dataset.saving = 'true'; button.textContent = interviewId ? 'Rescheduling…' : 'Scheduling…'; showMessage(message, '');
      try {
        const { data: savedId, error } = await client.rpc(rpcName, rpcArgs);
        if (applicationId !== activeInterviewApplicationId) return;
        if (error || typeof savedId !== 'string') { showMessage(message, interviewErrorMessage(error, 'schedule'), 'error'); return; }
        const refreshed = await loadInterviewHistory(applicationId);
        if (!refreshed.ok || applicationId !== activeInterviewApplicationId) {
          if (!refreshed.stale) showMessage(message, 'Interview details changed before confirmation. Refresh and try again.', 'error');
          return;
        }
        const scheduled = refreshed.records.filter((record) => record.status === 'scheduled');
        const persisted = scheduled[0]; const predecessor = interviewId ? refreshed.records.find((record) => record.id === interviewId) : null;
        if (scheduled.length !== 1 || !persisted || persisted.id !== savedId || persisted.application_id !== applicationId
            || persisted.mode !== details.p_mode || new Date(persisted.scheduled_at).getTime() !== scheduledDate.getTime()
            || !sameOptionalText(persisted.location, details.p_location) || !sameOptionalText(persisted.meeting_link, details.p_meeting_link)
            || !sameOptionalText(persisted.contact_person, details.p_contact_person) || !sameOptionalText(persisted.contact_phone, details.p_contact_phone)
            || !sameOptionalText(persisted.instructions, details.p_instructions)
            || (interviewId && (!predecessor || predecessor.status !== 'rescheduled' || persisted.supersedes_interview_id !== interviewId))) {
          showMessage(message, 'Interview details changed before confirmation. Refresh and try again.', 'error'); return;
        }
        const { data: application, error: applicationError } = await client.from('candidate_applications')
          .select('application_status').eq('id', applicationId).maybeSingle();
        if (applicationId !== activeInterviewApplicationId) return;
        if (applicationError || !application) { showMessage(message, 'Interview was saved, but the application status could not be refreshed.', 'error'); return; }
        document.querySelector('[data-application-form]').elements.applicationStatus.value = application.application_status;
        resetInterviewForm(applicationId);
        showMessage(message, interviewId ? 'Interview rescheduled and history preserved.' : 'Interview scheduled.', 'success');
        try { await loadRecords('candidateInterests'); } catch (_error) { showMessage(message, 'Interview was saved, but the application list could not be refreshed.', 'error'); }
      } catch (_error) {
        if (applicationId === activeInterviewApplicationId) showMessage(message, 'The interview could not be scheduled. Refresh and try again.', 'error');
      } finally {
        delete form.dataset.saving; endInterviewMutation(applicationId);
        if (form.elements.interviewId.value) button.textContent = 'Reschedule Interview'; else button.textContent = 'Schedule Interview';
      }
    });
    document.querySelector('[data-interview-outcome-form]').addEventListener('submit', async (event) => {
      event.preventDefault(); const form = event.currentTarget; const button = form.querySelector('button[type="submit"]'); const message = document.querySelector('[data-interview-outcome-message]');
      if (!form.checkValidity()) { form.reportValidity(); return; }
      if (form.dataset.saving === 'true' || activeInterviewMutation) return;
      const interviewId = form.elements.interviewId.value; const requestedStatus = form.elements.status.value;
      const requestedResult = form.elements.result.value || null; const requestedNotes = form.elements.resultNotes.value.trim() || null;
      const source = interviewRecords.get(interviewId); const applicationId = source?.application_id || activeInterviewApplicationId;
      if (!applicationId || !beginInterviewMutation(applicationId)) return;
      form.dataset.saving = 'true'; button.textContent = 'Saving…'; showMessage(message, '');
      try {
        const { data: saved, error } = await client.rpc('admin_update_candidate_interview', {
          p_interview_id: interviewId, p_status: requestedStatus, p_result: requestedResult, p_result_notes: requestedNotes
        });
        if (applicationId !== activeInterviewApplicationId) return;
        if (error || saved !== true) { showMessage(message, interviewErrorMessage(error, 'update'), 'error'); return; }
        const refreshed = await loadInterviewHistory(applicationId);
        if (!refreshed.ok || applicationId !== activeInterviewApplicationId) {
          if (!refreshed.stale) showMessage(message, 'Interview details changed before confirmation. Refresh and try again.', 'error');
          return;
        }
        const persisted = refreshed.records.find((record) => record.id === interviewId);
        if (!persisted || persisted.status !== requestedStatus || (persisted.result || null) !== requestedResult || (persisted.result_notes || null) !== requestedNotes) {
          showMessage(message, 'Interview details changed before confirmation. Refresh and try again.', 'error'); return;
        }
        form.hidden = true;
        showMessage(document.querySelector('[data-interview-load-message]'), 'Interview status and result notes saved.', 'success');
      } catch (_error) {
        if (applicationId === activeInterviewApplicationId) showMessage(message, 'Interview status could not be updated. Refresh and try again.', 'error');
      } finally {
        delete form.dataset.saving; endInterviewMutation(applicationId); button.textContent = 'Save Interview Status';
      }
    });

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

    const contractorDialog=document.querySelector('[data-contractor-dialog]');document.querySelectorAll('[data-close-contractor]').forEach(b=>b.addEventListener('click',()=>contractorDialog.close()));document.querySelector('[data-contractor-status-form]').addEventListener('submit',async event=>{event.preventDefault();const form=event.currentTarget,button=form.querySelector('button[type=submit]');button.disabled=true;const {error}=await client.rpc('set_contractor_account_status',{p_contractor_id:form.elements.contractorId.value,p_account_status:form.elements.status.value});button.disabled=false;if(error){showMessage(document.querySelector('[data-contractor-message]'),'Partner status could not be updated.','error');return}showMessage(document.querySelector('[data-contractor-message]'),'Partner status updated.','success');await loadRecords('contractors')});

    const requirementDialog = document.querySelector('[data-requirement-admin-dialog]');
    document.querySelectorAll('[data-close-requirement-admin]').forEach((button) => button.addEventListener('click', () => requirementDialog.close()));
    requirementDialog.addEventListener('click', (event) => { if (event.target === requirementDialog) requirementDialog.close(); });
    document.querySelector('[data-requirement-admin-form]').addEventListener('submit', async (event) => {
      event.preventDefault(); const form = event.currentTarget; const button = form.querySelector('button[type="submit"]'); const message = document.querySelector('[data-requirement-admin-message]'); button.disabled = true; button.textContent = 'Saving…'; showMessage(message, '');
      const { error } = await client.rpc('set_company_requirement_stage', { p_requirement_id: form.elements.requirementId.value, p_requirement_stage: form.elements.stage.value, p_requirement_visibility: form.elements.visibility.value });
      button.disabled = false; button.textContent = 'Save Requirement Stage'; if (error) { showMessage(message, 'The operational stage could not be changed.', 'error'); return; } showMessage(message, 'Requirement stage updated.', 'success');
      try { await loadRecords('companyRequirements'); } catch (_error) { showMessage(dashboardMessage, 'Stage saved, but Company Requirements could not be refreshed.', 'error'); }
    });
    document.querySelector('[data-assignment-form]').addEventListener('submit',async event=>{event.preventDefault();const form=event.currentTarget,requirement=recordsById.get(`companyRequirements:${form.elements.requirementId.value}`),button=form.querySelector('button[type=submit]');button.disabled=true;showMessage(document.querySelector('[data-assignment-message]'),'');const {error}=await client.rpc('assign_requirement_contractor',{p_requirement_id:form.elements.requirementId.value,p_contractor_id:form.elements.contractorId.value,p_assigned_headcount:Number(form.elements.headcount.value),p_internal_notes:form.elements.notes.value.trim()||null});button.disabled=false;if(error){showMessage(document.querySelector('[data-assignment-message]'),'Assignment could not be saved. Check partner status and remaining allocation.','error');return}form.reset();showMessage(document.querySelector('[data-assignment-message]'),'Staffing partner assigned.','success');await loadRequirementAssignments(requirement)});

    client.auth.onAuthStateChange((event) => { if (event === 'SIGNED_OUT') window.location.replace('./login.html'); });
    await loadDashboard();
  };

  if (pageType === 'login') initializeLogin();
  if (pageType === 'dashboard') initializeDashboard();
}());
