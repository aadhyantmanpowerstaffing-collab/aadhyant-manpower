(function initializeRecruitmentOperationsModule() {
  const definitions = [
    ['recruitmentDashboard', 'Dashboard', 'get_recruitment_dashboard'],
    ['recruitmentCandidates', 'Candidates', 'list_recruitment_candidates'],
    ['recruitmentRequirements', 'Requirements', 'list_recruitment_requirements'],
    ['recruitmentApplications', 'Applications', 'list_recruitment_applications'],
    ['recruitmentInterviews', 'Interviews', 'list_recruitment_interviews'],
    ['recruitmentJoinings', 'Joining / Placement', 'list_recruitment_joinings']
  ];
  const columns = {
    recruitmentCandidates: [['Name','full_name'],['Location','current_location'],['District','district'],['Qualification','highest_qualification'],['Trade','specialization'],['Type','candidate_type'],['Status','status'],['Applications','application_count']],
    recruitmentRequirements: [['Code','requirement_code'],['Company','company_name'],['Role','job_role'],['Location','job_location'],['Headcount','required_headcount'],['Filled','filled_positions'],['Stage','requirement_stage'],['Applications','application_count']],
    recruitmentApplications: [['Candidate','candidate_name'],['Requirement','requirement_code'],['Company','company_name'],['Role','job_role'],['Stage','application_status'],['Applied','applied_at']],
    recruitmentInterviews: [['Candidate','candidate_name'],['Requirement','requirement_code'],['Round','interview_round'],['Scheduled','scheduled_at'],['Mode','mode'],['Status','status'],['Result','result']],
    recruitmentJoinings: [['Candidate','candidate_name'],['Requirement','requirement_code'],['Company','company_name'],['Expected','expected_joining_date'],['Actual','actual_joining_date'],['Status','joining_status'],['Employee Code','employee_code']]
  };
  const readable = (value) => String(value ?? '—').replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  const make = (tag, className = '', text = '') => { const node = document.createElement(tag); node.className = className; node.textContent = text; return node; };
  const call = async (client, name, args = {}) => { const { data, error } = await client.rpc(name, args); if (error) throw error; return data; };
  const argsFor = (key, search = '') => ({
    recruitmentCandidates: { p_search: search || null, p_limit: 50, p_offset: 0 },
    recruitmentRequirements: { p_search: search || null, p_limit: 50, p_offset: 0 },
    recruitmentApplications: { p_search: search || null, p_limit: 50, p_offset: 0 },
    recruitmentInterviews: { p_upcoming_only: false, p_limit: 100 },
    recruitmentJoinings: { p_status: null, p_limit: 100 }
  }[key] || {});
  const setMessage = (panel, message, failed = false) => { const node = panel.querySelector('[data-w3-message]'); node.textContent = message; node.classList.toggle('is-error', failed); };
  const canMutate = (key, permissions) => ({ recruitmentCandidates: permissions.candidate_mutation, recruitmentApplications: permissions.application_mutation, recruitmentInterviews: permissions.interview_mutation, recruitmentJoinings: permissions.joining_mutation }[key] ?? false);
  const isRequirementMatchable = (requirement) => requirement?.requirement_stage === 'open';
  const isCandidateMatchable = (candidate) => candidate?.status !== 'inactive';
  const canMatchRequirement = (requirement, permissions) => Boolean(permissions?.application_mutation && isRequirementMatchable(requirement));
  const candidateSearchArgs = (search = '') => ({ p_search: search.trim() || null, p_status: null, p_limit: 50, p_offset: 0 });
  const friendlyMatchError = (error) => {
    const message = String(error?.message || '');
    if (/already has an application/i.test(message)) return 'This candidate is already matched to the requirement.';
    if (/active candidate was not found/i.test(message)) return 'This candidate is no longer eligible for matching. Refresh the candidate results.';
    if (/open requirement was not found/i.test(message)) return 'This requirement is no longer open for matching. Refresh the requirements list.';
    if (/application management access is required|permission|not authorized/i.test(message)) return 'You are not authorized to match candidates to requirements.';
    return 'The application could not be created. Check the connection and try again.';
  };
  const openCandidatePicker = (client, requirement) => new Promise((resolve) => {
    const dialog=make('dialog','detail-dialog candidate-picker-dialog');dialog.setAttribute('aria-labelledby','candidate-picker-title');
    const heading=make('div','dialog-heading');const headingCopy=make('div');headingCopy.append(make('p','admin-eyebrow','Candidate matching'),make('h2','','Match Candidate'));headingCopy.querySelector('h2').id='candidate-picker-title';
    const close=make('button','dialog-close','×');close.type='button';close.setAttribute('aria-label','Close candidate picker');heading.append(headingCopy,close);
    const context=make('dl','match-requirement-context');[['Company',requirement.company_name],['Role',requirement.job_role],['Location',requirement.job_location],['Status',readable(requirement.requirement_stage)]].forEach(([label,value])=>{const item=make('div');item.append(make('dt','',label),make('dd','',value||'—'));context.append(item);});
    const searchForm=make('form','candidate-picker-search');const field=make('div','admin-field');const search=make('input');search.type='search';search.name='candidateSearch';search.autocomplete='off';search.placeholder='Search candidate name or profile text';field.append(make('label','','Search candidates'),search);const searchButton=make('button','admin-button admin-button-primary','Search');searchButton.type='submit';searchForm.append(field,searchButton);
    const message=make('div','admin-message');message.dataset.candidatePickerMessage='';message.setAttribute('role','status');message.setAttribute('aria-live','polite');
    const wrap=make('div','table-wrap candidate-picker-results');wrap.tabIndex=0;const table=make('table');const head=make('thead');const headRow=make('tr');['Name','Location','District','Qualification','Trade','Type','Status','Applications','Action'].forEach((label)=>headRow.append(make('th','',label)));head.append(headRow);const body=make('tbody');table.append(head,body);wrap.append(table);
    const confirmation=make('section','candidate-match-confirmation');confirmation.hidden=true;const confirmationCopy=make('p');const actions=make('div','dialog-actions');const confirm=make('button','admin-button admin-button-primary','Confirm Match');confirm.type='button';const cancel=make('button','admin-button admin-button-quiet','Cancel');cancel.type='button';actions.append(confirm,cancel);confirmation.append(make('h3','','Confirm candidate match'),confirmationCopy,actions);
    dialog.append(heading,context,searchForm,message,wrap,confirmation);document.body.append(dialog);
    let selected=null;let settled=false;
    const finish=(matched)=>{if(settled)return;settled=true;dialog.close();dialog.remove();resolve(matched);};
    const setPickerMessage=(text,failed=false)=>{message.textContent=text;message.classList.toggle('is-error',failed);message.classList.toggle('is-success',!failed&&Boolean(text));};
    const load=async()=>{body.replaceChildren();confirmation.hidden=true;selected=null;setPickerMessage('Loading candidates…');try{const rows=await call(client,'list_recruitment_candidates',candidateSearchArgs(search.value));(rows||[]).forEach((candidate)=>{const tr=make('tr');['full_name','current_location','district','highest_qualification','specialization','candidate_type','status','application_count'].forEach((property)=>tr.append(make('td','',property==='status'?readable(candidate[property]):candidate[property]??'—')));const action=make('td');const choose=make('button','table-action',isCandidateMatchable(candidate)?'Select':'Not eligible');choose.type='button';choose.disabled=!isCandidateMatchable(candidate);choose.addEventListener('click',()=>{selected=candidate;confirmationCopy.textContent=`Candidate: ${candidate.full_name}. Requirement: ${requirement.job_role} at ${requirement.company_name}.`;confirmation.hidden=false;confirm.focus();});action.append(choose);tr.append(action);body.append(tr);});setPickerMessage(rows?.length?'Select an eligible candidate.':'No candidates matched your search.');}catch(_error){setPickerMessage('Candidates could not be loaded. Check the connection and try again.',true);}};
    searchForm.addEventListener('submit',(event)=>{event.preventDefault();load();});
    confirm.addEventListener('click',async()=>{if(!selected)return;confirm.disabled=true;cancel.disabled=true;setPickerMessage('Creating application…');try{await call(client,'create_recruitment_application',{p_candidate_id:selected.id,p_requirement_id:requirement.id,p_source_reference:'W3 portal',p_correlation_id:crypto.randomUUID()});finish(true);}catch(error){confirm.disabled=false;cancel.disabled=false;setPickerMessage(friendlyMatchError(error),true);}});
    close.addEventListener('click',()=>finish(false));cancel.addEventListener('click',()=>finish(false));dialog.addEventListener('cancel',(event)=>{event.preventDefault();finish(false);});
    dialog.showModal();search.focus();load();
  });
  const renderDashboard = async (client, panel) => {
    const metrics = await call(client, 'get_recruitment_dashboard'); const grid = make('div', 'summary-grid w3-summary');
    [['Active Requirements','active_requirements'],['New Candidates','new_candidates'],['Applications','applications'],['Upcoming Interviews','upcoming_interviews'],['Selected','selected'],['Joining Pending','joining_pending'],['Joined','joined']]
      .forEach(([label,key]) => { const card=make('article'); card.append(make('span','',label),make('strong','',metrics[key] ?? 0)); grid.append(card); }); panel.append(grid);
  };
  const viewRecord = async (client, key, row) => {
    if (key === 'recruitmentCandidates') { const detail=await call(client,'get_recruitment_candidate',{p_candidate_id:row.id}); window.alert(`${detail.full_name}\n${detail.mobile ? `Mobile: ${detail.mobile}` : 'Contact PII restricted'}\nApplications: ${detail.applications?.length || 0}\nInterviews: ${detail.interviews?.length || 0}`); }
    if (key === 'recruitmentApplications') { const detail=await call(client,'get_recruitment_application',{p_application_id:row.id}); window.alert(`${detail.candidate_name}\n${readable(detail.application_status)}\nHistory: ${detail.stage_history?.length || 0}`); }
  };
  const mutateRecord = async (client, key, row) => {
    const correlation = crypto.randomUUID();
    if (key === 'recruitmentCandidates') {
      const status=window.prompt('Candidate status',row.status);if(!status)return;
      const availability=window.prompt('Interview available: Yes or No',row.interview_available||'Yes');if(!availability)return;
      await call(client,'update_recruitment_candidate',{p_candidate_id:row.id,p_status:status,p_interview_available:availability,p_internal_notes:null,p_correlation_id:correlation});
    } else if (key === 'recruitmentApplications') {
      const target=window.prompt(`Current: ${readable(row.application_status)}. Enter validated next stage`);if(!target)return;
      await call(client,'transition_recruitment_application',{p_application_id:row.id,p_to_stage:target,p_reason:'W3 portal transition',p_internal_notes:null,p_correlation_id:correlation});
    } else if (key === 'recruitmentInterviews') {
      const status=window.prompt('Interview status: attended, absent, completed, cancelled',row.status);if(!status)return;
      const result=window.prompt('Result: pending, selected, rejected, on_hold (optional)',row.result||'');
      await call(client,'update_recruitment_interview',{p_interview_id:row.id,p_status:status,p_result:result||null,p_result_notes:null,p_correlation_id:correlation});
    } else if (key === 'recruitmentJoinings') {
      const status=window.prompt('Joining status: pending, confirmed, joined, no_show, deferred, left, cancelled',row.joining_status);if(!status)return;
      await call(client,'upsert_recruitment_joining',{p_application_id:row.application_id,p_expected_date:row.expected_joining_date,p_actual_date:['joined','left'].includes(status)?(row.actual_joining_date||new Date().toISOString().slice(0,10)):null,p_joining_status:status,p_employee_code:row.employee_code||null,p_remarks:row.remarks||null,p_correlation_id:correlation});
    }
  };
  const scheduleFromApplication = async (client, row) => {
    const scheduled=window.prompt('Interview date/time (ISO 8601)');if(!scheduled)return;
    const mode=window.prompt('Mode: onsite, phone, video, other','onsite');if(!mode)return;
    await call(client,'schedule_recruitment_interview',{p_application_id:row.id,p_scheduled_at:scheduled,p_mode:mode,p_location:null,p_instructions:null,p_correlation_id:crypto.randomUUID()});
  };
  const startJoiningFromApplication = async (client, row) => {
    const expected=window.prompt('Expected joining date (YYYY-MM-DD)');if(!expected)return;
    await call(client,'upsert_recruitment_joining',{p_application_id:row.id,p_expected_date:expected,p_actual_date:null,p_joining_status:'pending',p_employee_code:null,p_remarks:null,p_correlation_id:crypto.randomUUID()});
  };
  const renderList = async (client, panel, key, rpcName, permissions) => {
    const content=make('div'); content.dataset.w3Content=''; const form=make('form','filter-grid w3-filter'); const field=make('div','admin-field'); const input=make('input'); input.type='search'; input.name='search'; field.append(make('label','','Search'),input); const submit=make('button','admin-button admin-button-primary','Apply Filter'); submit.type='submit'; form.append(field,submit);
    const wrap=make('div','table-wrap'); wrap.tabIndex=0; const table=make('table'); const head=make('thead'); const headRow=make('tr'); columns[key].forEach(([label])=>headRow.append(make('th','',label)));headRow.append(make('th','','Action'));head.append(headRow); const body=make('tbody'); table.append(head,body); wrap.append(table); content.append(form,wrap); panel.append(content);
    const load=async()=>{body.replaceChildren();setMessage(panel,'Loading…');try{const rows=await call(client,rpcName,argsFor(key,input.value.trim()));(rows||[]).forEach((row)=>{const tr=make('tr');columns[key].forEach(([,property])=>{let value=row[property];if(property.endsWith('_at')&&value)value=new Date(value).toLocaleString();if(property.includes('status')||property==='result'||property==='mode')value=readable(value);tr.append(make('td','',value));});const action=make('td');if(['recruitmentCandidates','recruitmentApplications'].includes(key)){const view=make('button','table-action','View');view.type='button';view.addEventListener('click',()=>viewRecord(client,key,row).catch((error)=>setMessage(panel,error.message,true)));action.append(view);}if(key==='recruitmentRequirements'&&canMatchRequirement(row,permissions)){const match=make('button','table-action','Match Candidate');match.type='button';match.addEventListener('click',async()=>{const matched=await openCandidatePicker(client,row);if(matched){await load();setMessage(panel,'Application created. Requirement counts refreshed; Applications and Dashboard will refresh when opened.');}});action.append(match);}else if(canMutate(key,permissions)){const manage=make('button','table-action','Update');manage.type='button';manage.addEventListener('click',async()=>{try{await mutateRecord(client,key,row);await load();}catch(error){setMessage(panel,error.message||'Mutation denied.',true);}});action.append(manage);}if(key==='recruitmentApplications'&&permissions.interview_mutation&&['interested','applied','screening','shortlisted','interview'].includes(row.application_status)){const schedule=make('button','table-action','Schedule Interview');schedule.type='button';schedule.addEventListener('click',()=>scheduleFromApplication(client,row).then(load).catch((error)=>setMessage(panel,error.message||'Interview scheduling denied.',true)));action.append(schedule);}if(key==='recruitmentApplications'&&permissions.joining_mutation&&row.application_status==='selected'){const joining=make('button','table-action','Start Joining');joining.type='button';joining.addEventListener('click',()=>startJoiningFromApplication(client,row).then(load).catch((error)=>setMessage(panel,error.message||'Joining creation denied.',true)));action.append(joining);}tr.append(action);body.append(tr);});setMessage(panel,'');}catch(error){setMessage(panel,error.message||'Records could not be loaded.',true);}};
    form.addEventListener('submit',(event)=>{event.preventDefault();load();}); if(!canMutate(key,permissions))panel.dataset.readOnly='true'; await load();
  };
  const initialize = async ({ client, authorization }) => {
    let permissions; try { const data=await call(client,'get_recruitment_permissions');permissions=Array.isArray(data)?data[0]:data; } catch (_error) { return false; }
    if(!permissions?.view_access)return false; const tabs=document.querySelector('.admin-tabs'); const main=tabs.parentElement; const created=[];
    definitions.forEach(([key,title,rpcName])=>{const tab=make('button','',title);tab.type='button';tab.dataset.w3Tab=key;tab.setAttribute('role','tab');tab.setAttribute('aria-selected','false');const panel=make('section','record-panel w3-panel');panel.dataset.panel=key;panel.hidden=true;const heading=make('div','panel-heading');const copy=make('div');copy.append(make('h2','',title),make('p','','Server-authorized internal recruitment operations.'));heading.append(copy);const message=make('div','admin-message');message.dataset.w3Message='';message.setAttribute('role','status');panel.append(heading,message);tabs.insertBefore(tab,tabs.querySelector('[data-tab="staff"]'));main.insertBefore(panel,document.querySelector('[data-panel="staff"]'));created.push({tab,panel,key,rpcName});});
    const activate=async(key)=>{created.forEach((item)=>{const active=item.key===key;item.tab.setAttribute('aria-selected',String(active));item.panel.hidden=!active;});const item=created.find((entry)=>entry.key===key);item.panel.querySelector('[data-w3-content]')?.remove();item.panel.querySelector('.w3-summary')?.remove();if(key==='recruitmentDashboard')await renderDashboard(client,item.panel);else await renderList(client,item.panel,key,item.rpcName,permissions);};
    created.forEach((item)=>item.tab.addEventListener('click',()=>activate(item.key)));tabs.hidden=false;if(!authorization.bootstrap_admin&&!authorization.staff_management_access)await activate('recruitmentDashboard');return true;
  };
  window.aadhyantRecruitmentOperations=Object.freeze({initialize,definitions,canMutate,isRequirementMatchable,isCandidateMatchable,canMatchRequirement,candidateSearchArgs,friendlyMatchError,openCandidatePicker});
}());
