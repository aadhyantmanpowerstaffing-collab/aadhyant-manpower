(() => {
  'use strict';
  const $ = (s) => document.querySelector(s);
  const client = window.aadhyantSupabase?.client;
  const query = new URLSearchParams(location.search);
  const role = ['candidate','company','contractor','admin'].includes(query.get('role')) ? query.get('role') : 'candidate';
  const rpc = async (name, args = {}) => { const {data,error} = await client.rpc(name,args); if(error) throw error; return data; };
  const make = (tag, text, cls) => { const n = document.createElement(tag); if(text != null) n.textContent = String(text); if(cls) n.className = cls; return n; };
  const money = (v) => new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:2}).format(Number(v));
  const nice = (v) => String(v || '').replaceAll('_',' ');
  const date = (v) => new Intl.DateTimeFormat('en-IN',{dateStyle:'medium',timeZone:'Asia/Kolkata'}).format(new Date(`${v}T12:00:00+05:30`));
  const indiaDate = () => new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  const time = (v) => String(v || '').slice(0,5);
  const message = (v, error = false) => { $('#message').textContent = v; $('#message').classList.toggle('error',error); };
  let signedIn = false, allowed = false, candidate = false, offset = 0, busy = false, submissionKey = null, availability = null, poolOffset = 0, refreshing = false;
  const form = $('#job-form');
  const write = async (fn) => { if(busy) return;busy=true;document.querySelectorAll('button').forEach(b=>b.disabled=true);try{await fn();}finally{busy=false;document.querySelectorAll('button').forEach(b=>b.disabled=false);} };
  const button = (label, action, secondary = false) => { const b=make('button',label,secondary?'secondary':'');b.type='button';b.onclick=()=>write(action).catch(e=>message(e?.message || 'Action could not be completed. Refresh and retry.',true));return b; };
  const details = (pairs) => {const dl=make('dl');pairs.forEach(([k,v])=>{const d=make('div');d.append(make('dt',k),make('dd',v || 'Not specified'));dl.append(d);});return dl;};
  const login = () => role==='candidate'?'/candidate/portal/login.html':`/${role}/login.html`;
  const card = (job) => {
    const t=job.terms, n=make('article',null,'job');n.id=`job-${job.requirement_code}`;
    n.append(make('span',nice(job.review_status),'badge'),make('h3',job.job_role),make('p',job.company_name,'company'),make('p',job.job_location),make('p',money(t.pay_amount),'pay'));
    n.querySelector('.pay').append(make('small','per person · complete shift'));
    n.append(details([['Date',date(t.work_date)],['Shift',`${time(t.starts_at)}–${time(t.ends_at)} IST · ${Number(job.hours)} hours`],['People needed',job.required_headcount],['Confirmed',job.confirmed_count ?? '—'],['Places remaining',job.remaining_places ?? '—'],['Payment',`Same day, ${time(t.payment_time)} IST`],['Paid by',nice(t.payment_by)],['Method',nice(t.payment_method)],['Report at',t.reporting_point],['Supervisor',`${t.contact_name} · ${t.contact_phone}`]]));
    if(t.facilities)n.append(make('p',t.facilities));
    if(job.review_feedback)n.append(make('p',`Review feedback: ${job.review_feedback}`,'error'));
    if(job.expired)n.append(make('p','This shift has already started. No new availability is accepted.','error'));
    const actions=make('div',null,'actions');
    if(role==='candidate') {
      if(job.my_application) actions.append(make('span','Availability submitted · see My Shifts','badge'));
      else if(Number(job.remaining_places)===0) actions.append(make('span','Fully booked','badge'));
      else if(job.expired) actions.append(make('span','Applications closed','badge'));
      else if(candidate && !job.expired)actions.append(button('I’m Available',async()=>{await rpc('apply_same_day_job',{p_requirement_id:job.id});message('Availability submitted. Wait for the employer to confirm your place.');await load();}));
      else {const a=make('a','Sign in to Apply');a.href=login();actions.append(a);}
    } else if(allowed && role!=='admin') {
      if(['draft','correction_required'].includes(job.review_status))actions.append(button('Edit & Resubmit',async()=>openForm(job),true));
      if(job.review_status==='approved'&&job.stage==='open')actions.append(button('Close Shift',async()=>{if(!confirm('Close this shift to new applications? Existing work and payment history will remain.'))return;await rpc(role==='company'?'close_company_portal_open_vacancy':'close_contractor_portal_open_vacancy',{p_requirement_id:job.id});await load();},true));
    } else if(allowed && role==='admin' && job.review_status==='pending_review') {
      actions.append(button('Approve & Publish',async()=>{await rpc('admin_approve_and_publish_vacancy',{p_requirement_id:job.id});message('Shift approved and published. Alerts remain subject to consent, template approval and sender activation.');await load();}));
      actions.append(button('Request Correction',async()=>{const reason=prompt('Explain the correction needed:');if(!reason?.trim())return;await rpc('admin_request_vacancy_correction',{p_requirement_id:job.id,p_reason:reason.trim()});await load();},true));
      actions.append(button('Reject',async()=>{const reason=prompt('Explain why this shift is rejected:');if(!reason?.trim())return;await rpc('admin_reject_vacancy',{p_requirement_id:job.id,p_reason:reason.trim()});await load();},true));
    }
    n.append(actions);return n;
  };
  async function loadApplications(){
    if(!allowed&&!candidate)return;
    const rows=await rpc('list_same_day_applications');$('#applications-panel').hidden=false;$('#applications').replaceChildren();
    $('#applications-title').textContent=role==='candidate'?'My Shifts':'Availability, Attendance & Payments';
    if(!rows?.length)$('#applications').append(make('p','No shift applications yet.'));
    for(const r of rows || []){
      const n=make('article',null,'application');n.append(make('h3',`${r.requirement_code} · ${r.job_role}`),make('p',`${r.candidate_name} ${r.candidate_phone?`· ${r.candidate_phone}`:''}`),make('p',`${date(r.work_date)} · ${money(r.pay_amount)} · payment at ${time(r.payment_time)} IST`),make('span',r.work_status==='completed'?'Payment pending':r.work_status==='paid'?'Payment recorded':nice(r.work_status),'badge'));
      if(r.payment_received_at)n.append(make('p','Payment received — confirmed by candidate.'));
      else if(r.work_status==='paid')n.append(make('p','Waiting for candidate to confirm receipt.'));
      else if(['completed','attended','confirmed'].includes(r.work_status)&&new Date(`${r.work_date}T${time(r.payment_time)}:00+05:30`)<new Date())n.append(make('p','Payment time has passed — review required.','error'));
      if(r.payment_reference)n.append(make('p',`Payment reference: ${r.payment_reference}`));
      const actions=make('div',null,'actions');
      const change=async(action,reference=null)=>{await rpc('update_same_day_work',{p_application_id:r.application_id,p_action:action,p_reference:reference});await load();};
      if(role==='candidate'&&r.work_status==='paid'&&!r.payment_received_at)actions.append(button('Payment Received',async()=>{if(confirm('Confirm that you received the full agreed payment for this shift?'))await change('received');}));
      if(role!=='candidate'){
        const next={available:['Confirm Place','confirm'],confirmed:['Mark Attended','attend'],attended:['Work Completed','complete'],completed:['Record Payment','paid']}[r.work_status];
        if(next)actions.append(button(next[0],async()=>{let ref=null;if(next[1]==='paid'){ref=prompt('Payment reference / cash receipt note (optional). Record only after payment is made.','');if(ref===null)return;if(!confirm(`Record ${money(r.pay_amount)} as paid? The candidate will confirm receipt separately.`))return;}await change(next[1],ref);}));
        if(['available','confirmed'].includes(r.work_status))actions.append(button('Cancel Place',async()=>{if(confirm('Cancel this candidate’s place?'))await change('cancel');},true));
      }
      n.append(actions);$('#applications').append(n);
    }
  }
  async function load(){
    const scope=allowed&&role==='admin'?'admin':allowed&&['company','contractor'].includes(role)?'owner':'public';
    const rows=await rpc('list_same_day_jobs',{p_scope:scope,p_limit:20,p_offset:offset,p_code:query.get('job') || null});
    $('#jobs').replaceChildren();(rows || []).forEach(j=>$('#jobs').append(card(j)));
    if(!rows?.length)$('#jobs').append(make('p',scope==='public'?'No upcoming approved shifts yet. Check back soon.':'No Same-Day Pay jobs submitted yet.','panel'));
    $('#previous').hidden=offset===0;$('#next').hidden=rows?.length!==20;
    await loadApplications();
  }
  function renderAvailability(data){
    availability=data;const f=$('#availability-form');
    f.elements.today.checked=data.available_dates.includes(data.today);f.elements.tomorrow.checked=data.available_dates.includes(data.tomorrow);
    f.elements.local_area.value=data.local_area || '';
    $('#available-today').textContent=`Available today · ${date(data.today)}`;
    $('#available-tomorrow').textContent=`Available tomorrow · ${date(data.tomorrow)}`;
    $('#availability-panel').hidden=false;
  }
  async function loadPool(){
    if(!allowed)return;
    const rows=await rpc('list_same_day_available_candidates',{p_date:$('#pool-date').value,p_limit:25,p_offset:poolOffset});
    const target=$('#pool-results');target.replaceChildren();
    if(!rows?.length)target.append(make('p','No candidates have marked availability for this date.'));
    for(const r of rows || []){const n=make('article',null,'application');n.append(make('h3',r.candidate_name),make('p',`${r.local_area} · ${date(r.available_date)}`));target.append(n);}
    $('#pool-previous').hidden=poolOffset===0;$('#pool-next').hidden=rows?.length!==25;
  }
  async function refreshPlaces(){
    if(refreshing||busy)return;refreshing=true;
    try{await load();}catch(_){message('Place counts could not refresh. Use Refresh Places to retry.',true);}finally{refreshing=false;}
  }

  function updateDuration(){const v=form.elements.starts_at.value;const hours=$('#duration').value;if(!v||hours==='custom')return;const [h,m]=v.split(':').map(Number);const end=h*60+m+Number(hours)*60;if(end>=1440){$('#duration').value='custom';return;}form.elements.ends_at.value=`${String(Math.floor(end/60)).padStart(2,'0')}:${String(end%60).padStart(2,'0')}`;}
  function openForm(job=null){
    form.reset();submissionKey=crypto.randomUUID();$('#form-message').textContent='';form.elements.requirement_id.value=job?.id || '';
    $('#company-field').hidden=role!=='contractor';form.elements.company_name.required=role==='contractor';
    form.elements.work_date.min=indiaDate();$('#form-title').textContent=job?'Edit & Resubmit Shift':'Post Same-Day Pay Job';
    if(job){for(const [k,v] of Object.entries({...job,...job.terms}))if(form.elements[k]&&k!=='requirement_id')form.elements[k].value=v ?? '';$('#duration').value=['4','8'].includes(String(Number(job.hours)))?String(Number(job.hours)):'custom';}
    $('#job-dialog').showModal();
  }
  async function start(){
    document.querySelector(`[data-role="${role}"]`).setAttribute('aria-current','page');
    $('#new-job').onclick=()=>openForm();$('#close-dialog').onclick=()=>$('#job-dialog').close();
    $('#duration').onchange=updateDuration;form.elements.starts_at.onchange=updateDuration;
    $('#previous').onclick=()=>{offset=Math.max(0,offset-20);load().catch(()=>message('Shifts could not be loaded.',true));};$('#next').onclick=()=>{offset+=20;load().catch(()=>message('Shifts could not be loaded.',true));};
    form.onsubmit=e=>{e.preventDefault();write(async()=>{if(!form.reportValidity())return;const data=Object.fromEntries(new FormData(form));const id=data.requirement_id || null;delete data.requirement_id;await rpc('submit_same_day_job',{p_role:role,p_payload:data,p_request_key:submissionKey,p_requirement_id:id});$('#job-dialog').close();message('Submitted for Admin review. Candidates will see the shift after approval.');await load();}).catch(e=>{$('#form-message').textContent=e?.message || 'Submission could not be confirmed. Keep this form open and retry with the same details.';});};
    if(!client){message('The portal connection is unavailable.',true);return;}
    const {data:{session}}=await client.auth.getSession();signedIn=!!session;
    if(signedIn){
      if(role==='candidate'){try{const pref=await rpc('get_candidate_alert_choices');candidate=true;$('#preferences').hidden=false;const fields=$('#preference-form').elements;fields.general.value=typeof pref.general_alerts==='boolean'?(pref.general_alerts?'yes':'no'):'';fields.same_day.value=typeof pref.same_day_alerts==='boolean'?(pref.same_day_alerts?'yes':'no'):'';fields.current_job_location.value=pref.current_job_location||'';}catch(_){/* Other account types can browse public shifts. */}}
      else if(role==='admin'){try{await rpc('list_same_day_jobs',{p_scope:'admin',p_limit:1,p_offset:0,p_code:null});allowed=true;}catch(_){}}
      else {try{const data=await rpc(role==='company'?'get_company_portal_context':'get_contractor_portal_context');const c=Array.isArray(data)?data[0]:data;allowed=role==='company'?c?.can_manage_requirements===true:c?.can_manage_vacancies===true;}catch(_){}}
    }
    if((role==='candidate'&&!candidate)||(role!=='candidate'&&!allowed)){
      const access=$('#access');access.hidden=false;access.append(make('h2',signedIn?'Choose your account workspace':'Use your existing portal account'),make('p',signedIn?'This account does not have access to the selected workspace. Choose the correct role above, or sign in with the appropriate account.':'Sign in, then open Same-Day Pay Jobs from your portal. New candidates can register using the existing Candidate registration form.'));
      const a=make('a',`Open ${nice(role)} Login`);a.href=login();access.append(a);
      if(role==='candidate'){const a=make('a',' · Register as Candidate');a.href='/candidate/portal/register.html';access.append(a);}
    }
    $('#new-job').hidden=!allowed||role==='admin';
    if(allowed){$('#list-eyebrow').textContent=role==='admin'?'REVIEW & OPERATIONS':'MY SHIFT POSTS';$('#list-title').textContent=role==='admin'?'Same-Day Pay Review':'My Same-Day Pay Jobs';}
    $('#preference-form').onsubmit=e=>{e.preventDefault();write(async()=>{const f=e.currentTarget;if(!['yes','no'].includes(f.elements.general.value)||!['yes','no'].includes(f.elements.same_day.value))throw new Error('Choose Yes or No for both alerts.');await rpc('save_candidate_alert_choices',{p_general:f.elements.general.value==='yes',p_same_day:f.elements.same_day.value==='yes',p_current_job_location:f.elements.current_job_location.value.trim()});message('Both WhatsApp alert choices saved. Sanand location rules apply to Same-Day Pay alerts.');}).catch(()=>message('Preference could not be saved.',true));};
    if(candidate){
      try{renderAvailability(await rpc('get_same_day_availability'));}catch(_){$('#availability-panel').hidden=false;$('#availability-status').textContent='Availability could not be loaded. Refresh this page before saving.';}
      $('#availability-form').onsubmit=e=>{e.preventDefault();const f=e.currentTarget;write(async()=>{
        if(!availability)throw new Error('Refresh this page before saving availability.');
        const dates=[];if(f.elements.today.checked)dates.push(availability.today);if(f.elements.tomorrow.checked)dates.push(availability.tomorrow);
        renderAvailability(await rpc('save_same_day_availability',{p_dates:dates,p_local_area:f.elements.local_area.value.trim()}));
        $('#availability-status').textContent=dates.length?'Availability saved for the selected dates. Apply separately to a shift.':'Availability removed.';
      }).catch(e=>{$('#availability-status').textContent=e?.message || 'Availability could not be saved.';});};
    }
    if(allowed){
      const today=indiaDate();const tomorrow=new Date(`${today}T12:00:00Z`);tomorrow.setUTCDate(tomorrow.getUTCDate()+1);
      for(const [d,label] of [[today,'Today'],[tomorrow.toISOString().slice(0,10),'Tomorrow']]){const o=make('option',`${label} · ${date(d)}`);o.value=d;$('#pool-date').append(o);}
      $('#worker-pool').hidden=false;
      const pool=()=>loadPool().catch(()=>{$('#pool-results').replaceChildren(make('p','Available workers could not be loaded. Refresh the date and retry.','error'));});
      $('#pool-date').onchange=()=>{poolOffset=0;pool();};$('#pool-refresh').onclick=pool;
      $('#pool-previous').onclick=()=>{poolOffset=Math.max(0,poolOffset-25);pool();};$('#pool-next').onclick=()=>{poolOffset+=25;pool();};await pool();
    }
    $('#refresh-jobs').onclick=refreshPlaces;
    document.addEventListener('visibilitychange',()=>{if(!document.hidden)refreshPlaces();});
    setInterval(()=>{if(!document.hidden)refreshPlaces();},30000);
    message('');await load();
  }
  start().catch(()=>message('This workspace is not available yet. Refresh after the portal update is deployed.',true));
})();
