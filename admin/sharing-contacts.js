(() => {
  'use strict';
  const make=(tag,text='')=>{const n=document.createElement(tag);n.textContent=text;return n;};
  const call=async(client,name,args={})=>{const r=await client.rpc(name,args);if(r.error)throw r.error;return r.data;};
  const selectPublishedVacancies=(requirements,published)=>{
    const codes=new Set(published.map(row=>row.requirement_code));
    return requirements.filter(row=>row.id&&row.requirement_stage==='open'&&codes.has(row.requirement_code));
  };
  async function initialize({client,authorization}){
    if(!authorization?.bootstrap_admin&&!authorization?.staff_management_access)return false;
    const group=document.querySelector('[data-nav-group="whatsapp"]'),main=document.querySelector('.admin-main');if(!group||!main)return false;
    const tab=make('button','Job Updates / Sharing Contacts');tab.type='button';tab.dataset.w3Tab='sharingContacts';tab.setAttribute('role','tab');tab.setAttribute('aria-selected','false');group.append(tab);
    const panel=make('section');panel.className='record-panel sharing-panel';panel.dataset.panel='sharingContacts';panel.hidden=true;main.append(panel);
    const title=make('h2','Job Updates / Sharing Contacts'),message=make('p');message.setAttribute('role','status');message.className='admin-message';
    const intro=make('p','Import your contacts, select a job and prepare updates for people who want to share opportunities.');
    const subscribe=make('a','Open Subscription Page');subscribe.className='admin-button admin-button-secondary';subscribe.href='../job-updates/';subscribe.target='_blank';subscribe.rel='noopener';
    const file=make('input');file.type='file';file.accept='.xlsx,.csv';file.setAttribute('aria-label','Import XLSX or CSV contacts');
    const importPreview=make('div'),save=make('button','Import Reviewed Contacts');importPreview.className='sharing-import-preview';save.type='button';save.disabled=true;
    const vacancy=make('select');vacancy.setAttribute('aria-label','Select public vacancy');vacancy.append(new Option('Select a job',''));
    const filters=make('div');filters.className='campaign-criteria-grid';
    for(const [key,label] of [['state','State'],['district','District'],['gender','Gender'],['age_min','Minimum age'],['age_max','Maximum age']]){
      const field=make('label',label),input=key==='gender'?make('select'):make('input');input.name=key;
      if(key==='gender')for(const v of ['','Male','Female','Other / Prefer not to say'])input.append(new Option(v||'Any',v));
      if(key.startsWith('age_')){input.type='number';input.min='18';input.max='75';}field.append(input);filters.append(field);
    }
    const refresh=make('button','Apply Filters'),previous=make('button','Previous'),next=make('button','Next'),contacts=make('div'),selectedCount=make('p','0 selected'),campaigns=make('div'),composer=make('form');
    [refresh,previous,next].forEach(b=>b.type='button');
    const templateFields={};composer.className='sharing-card sharing-composer';const templateGrid=make('div');templateGrid.className='sharing-template-grid';composer.append(make('h3','3. Prepare Campaign'),make('p','Add your approved template details, then review the selected audience.'),templateGrid);
    for(const [key,label] of [['campaign_name','Campaign name'],['template_name','Approved template name'],['template_language','Template language'],['template_version','Template version']]){
      const field=make('label',label),input=make('input');input.required=true;input.maxLength=key.endsWith('name')?160:80;field.append(input);templateGrid.append(field);templateFields[key]=input;
    }
    const warning=make('p','These contacts receive updates for sharing. Candidate qualification, experience, salary and shift matching is not verified.');warning.className='sharing-note';
    const prepare=make('button','Review Selected Audience');prepare.type='submit';prepare.className='admin-button admin-button-primary';const composerFooter=make('div');composerFooter.className='sharing-card-footer';selectedCount.className='sharing-selection-count';composerFooter.append(selectedCount,prepare);composer.append(warning,composerFooter);
    const heading=make('header');heading.className='sharing-heading';const headingCopy=make('div');headingCopy.append(make('p','WHATSAPP OUTREACH'),title,intro);heading.append(headingCopy,subscribe);
    const importCard=make('section');importCard.className='sharing-card sharing-import';const importCopy=make('div');importCopy.append(make('h3','1. Import Contacts'),make('p','Excel or CSV · up to 500 contacts per file. Duplicate numbers are checked automatically.'));
    const upload=make('label');upload.className='sharing-upload';upload.append(make('span','Choose an Excel or CSV file'),file,make('small','Name, Email, Mobile, Gender, Age, State, District'));
    save.className='admin-button admin-button-primary';const importFooter=make('div');importFooter.className='sharing-card-footer';importFooter.append(make('span','Import preserves existing consent and STOP settings.'),save);importCard.append(importCopy,upload,importPreview,importFooter);
    const audienceCard=make('section');audienceCard.className='sharing-card sharing-audience';const jobField=make('label','Job to share');jobField.className='sharing-job-field';jobField.append(vacancy);
    refresh.className='admin-button admin-button-secondary';const filterActions=make('div');filterActions.className='sharing-filter-actions';filterActions.append(refresh);
    previous.className=next.className='admin-button admin-button-quiet';const pagination=make('div');pagination.className='sharing-pagination';pagination.append(previous,next);
    audienceCard.append(make('h3','2. Select Job and Contacts'),make('p','Filter your contact list and select eligible subscribers.'),jobField,filters,filterActions,contacts,pagination);
    const historyCard=make('section');historyCard.className='sharing-card';campaigns.className='sharing-campaign-list';historyCard.append(make('h3','Recent Campaigns'),campaigns);
    panel.append(heading,message,importCard,audienceCard,composer,historyCard);
    let parsed=null,offset=0,loading=false,importing=false,operation=crypto.randomUUID(),pending=false;const selected=new Set();
    const notice=(text,error=false)=>{message.textContent=text;message.classList.toggle('is-error',error);};
    const reset=()=>{selected.clear();selectedCount.textContent='0 selected';operation=crypto.randomUUID();};
    function table(rows){if(!rows.length){const empty=make('div');empty.className='sharing-empty';empty.append(make('strong','No contacts found'),make('p','Import a contact file or change your filters to see results.'));return empty;}const t=make('table'),head=make('tr');['Select','Name','Mobile','Gender','Age','State','District','Consent','Alerts','Status'].forEach(s=>head.append(make('th',s)));t.append(head);
      for(const row of rows){const tr=make('tr'),td=make('td'),box=make('input');box.type='checkbox';box.disabled=!row.eligible;box.checked=selected.has(row.contact_id);box.setAttribute('aria-label','Select '+row.mobile_masked);
        box.addEventListener('change',()=>{if(box.checked){if(selected.size>=500){box.checked=false;notice('Select at most 500 contacts.',true);return;}selected.add(row.contact_id);}else selected.delete(row.contact_id);selectedCount.textContent=selected.size+' selected';});td.append(box);tr.append(td);
        [row.name_masked,row.mobile_masked,row.gender,row.age,row.state,row.district,row.consent,row.alert_scope||'Not subscribed',row.eligible?'Eligible':row.resolution_status==='blocked'?'Blocked':row.resolution_status==='ambiguous'?'Duplicate identity':row.consent!=='opted_in'?'Consent required':!row.alert_scope?'Subscription required':'Job does not match subscription'].forEach(v=>tr.append(make('td',String(v??'—'))));t.append(tr);}
      const wrap=make('div');wrap.className='table-wrap';wrap.append(t);return wrap;
    }
    async function loadContacts(){if(loading)return;loading=true;previous.disabled=next.disabled=refresh.disabled=true;
      try{const criteria={};for(const n of filters.querySelectorAll('input,select'))if(n.value.trim())criteria[n.name]=n.value.trim();
        const rows=await call(client,'admin_list_sharing_contacts',{p_requirement_id:vacancy.value||null,p_filters:criteria,p_offset:offset});contacts.replaceChildren(table(rows));previous.disabled=offset===0;next.disabled=rows.length<100||offset>=5000;notice(rows.length+' contacts shown. '+selected.size+' selected.');
      }catch(_){notice('Sharing contacts are unavailable. The reviewed database release must be installed before use.',true);}finally{loading=false;refresh.disabled=false;}
    }
    async function loadCampaigns(){const rows=await call(client,'admin_list_sharing_campaigns');campaigns.replaceChildren();
      for(const row of rows){const card=make('article');card.className='sharing-campaign-card';card.append(make('h4',row.campaign_name),make('p',`${row.requirement_code} · ${row.campaign_status} · ${row.audience_count} recipients`));
        if(row.campaign_status==='audience_ready'||row.campaign_status==='approved'){
          const approve=row.campaign_status==='audience_ready',action=make('button',approve?'Approve Campaign':'Queue Approved Audience');action.type='button';action.className='admin-button admin-button-primary';
          action.addEventListener('click',async()=>{action.disabled=true;try{await call(client,approve?'admin_approve_sharing_campaign':'admin_queue_sharing_campaign',{p_campaign_id:row.id});await loadCampaigns();notice(approve?'Approved. Queueing remains a separate action.':'Queued through the canonical outbox. Delivery requires an enabled reviewed worker.');}catch(_){notice('Campaign action was not confirmed. Refresh to check its current state.',true);await loadCampaigns().catch(()=>{});}});card.append(action);
        }
        if(['audience_ready','approved','queued','sending'].includes(row.campaign_status)){
          const cancel=make('button','Cancel Campaign');cancel.type='button';cancel.className='admin-button admin-button-quiet';cancel.addEventListener('click',async()=>{cancel.disabled=true;try{await call(client,'admin_cancel_whatsapp_campaign',{p_campaign_id:row.id});await loadCampaigns();notice('Campaign cancelled.');}catch(_){notice('Cancellation was not confirmed. Refresh before trying again.',true);}});card.append(cancel);
        }
        campaigns.append(card);
      }
      if(!rows.length)campaigns.append(make('p','No sharing campaigns yet.'));
    }
    file.addEventListener('change',async()=>{parsed=null;save.disabled=true;importPreview.replaceChildren();try{if(!file.files[0])return;const current=file.files[0];const result=await window.AadhyantSharingImport.read(current);if(file.files[0]!==current)return;parsed=result;
      importPreview.append(make('p',`${parsed.rows.length} valid unique contacts · ${parsed.duplicates.length} duplicates · ${parsed.errors.length} invalid rows. Import does not enroll contacts or send messages.`));
      for(const e of parsed.errors.slice(0,10))importPreview.append(make('p',`Row ${e.row}: ${e.reasons.join(', ')}`));save.disabled=!parsed.rows.length||parsed.errors.length>0;
    }catch(error){notice(error.message||'File could not be read.',true);}});
    save.addEventListener('click',async()=>{if(importing||!parsed||save.disabled)return;importing=true;save.disabled=true;file.disabled=true;
      try{const result=await call(client,'admin_import_sharing_contacts',{p_rows:parsed.rows});notice(`${result.added} added, ${result.reused} already present. Consent unchanged. No messages queued.`);parsed=null;file.value='';importPreview.replaceChildren();offset=0;reset();await loadContacts();}
      catch(_){notice('Import was not confirmed. Re-reading or importing the same numbers is safe; existing consent is preserved.',true);}finally{importing=false;file.disabled=false;save.disabled=!parsed;}
    });
    refresh.addEventListener('click',()=>{offset=0;reset();void loadContacts();});vacancy.addEventListener('change',()=>{offset=0;reset();void loadContacts();});previous.addEventListener('click',()=>{offset=Math.max(0,offset-100);void loadContacts();});next.addEventListener('click',()=>{offset+=100;void loadContacts();});
    composer.addEventListener('submit',async e=>{e.preventDefault();if(pending)return;if(!vacancy.value||!selected.size){notice('Select a job and at least one eligible subscriber.',true);return;}
      pending=true;prepare.disabled=true;try{await call(client,'admin_prepare_sharing_campaign',{p_requirement_id:vacancy.value,p_operation_key:operation,p_contact_ids:[...selected],...Object.fromEntries(Object.entries(templateFields).map(([k,n])=>['p_'+k,n.value.trim()]))});reset();await loadCampaigns();notice('Audience frozen. Review and approve the campaign before queueing.');}catch(_){notice('Preparation was not confirmed. The same operation identity is retained for a safe retry.',true);}finally{pending=false;prepare.disabled=false;}
    });
    tab.addEventListener('click',async()=>{document.querySelectorAll('[data-tab],[data-w3-tab],[data-product-tab]').forEach(n=>n.setAttribute('aria-selected',String(n===tab)));document.querySelectorAll('[data-panel]').forEach(n=>n.hidden=n!==panel);panel.scrollIntoView({block:'start',behavior:'auto'});
      try{if(vacancy.options.length===1){const [rows,published]=await Promise.all([call(client,'list_recruitment_requirements',{p_search:null,p_stage:'open',p_limit:100,p_offset:0}),call(client,'get_public_job_requirements',{p_limit:50,p_offset:0})]);for(const r of selectPublishedVacancies(rows,published))vacancy.append(new Option(`${r.requirement_code} · ${r.job_role}`,r.id));}await loadContacts();await loadCampaigns();}catch(_){notice('Sharing Contacts requires the reviewed release before use.',true);}finally{window.aadhyantAdminProduct?.afterNavigation?.('sharingContacts');}
    });return true;
  }
  window.AadhyantSharingContacts=Object.freeze({initialize,selectPublishedVacancies});
})();
