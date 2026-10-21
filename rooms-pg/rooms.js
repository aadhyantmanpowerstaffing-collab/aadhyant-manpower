(() => {
 'use strict';
 const $=s=>document.querySelector(s), page=document.body.dataset.roomsPage, client=window.aadhyantSupabase?.client;
 const make=(tag,text,cls)=>{const n=document.createElement(tag);if(text!=null)n.textContent=String(text);if(cls)n.className=cls;return n;};
 const rpc=async(name,args={})=>{const {data,error}=await client.rpc(name,args);if(error)throw error;return data;};
 const say=text=>{$('#message').textContent=text;};
 const money=n=>new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(Number(n));
 const date=v=>new Date(v).toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'});
 const nice=s=>String(s||'').replaceAll('_',' ');
 let offset=0,context=null,rows=[],editing=null,photos=[],enquiryProperty=null,draftKey=null;
 const busy=async(button,fn)=>{if(button.disabled)return;button.disabled=true;try{await fn();}catch(_){const form=button.closest('form'),m=form?.querySelector('.form-message');const text='This action could not be confirmed. Check your details and connection, then retry. Your entered details are still here.';if(m)m.textContent=text;else say(text);}finally{button.disabled=false;}};
 const action=(label,fn,quiet=true)=>{const b=make('button',label,quiet?'quiet':'');b.type='button';b.onclick=()=>busy(b,fn);return b;};
 const link=(label,url,cls='quiet')=>{const a=make('a',label,cls);a.href=url;return a;};
 const safeMap=url=>{try{const u=new URL(url);return u.protocol==='https:'&&((u.hostname==='www.google.com'&&u.pathname.startsWith('/maps'))||['maps.google.com','maps.app.goo.gl'].includes(u.hostname))?u.href:null;}catch(_){return null;}};
 const photoNode=(src,title)=>{const img=make('img');img.src=src;img.alt=title;img.loading='lazy';return img;};
 function gallery(p){const n=make('div',null,'photos');for(const src of p.photos||[])if(/^data:image\/jpeg;base64,[A-Za-z0-9+/]+=*$/.test(src))n.append(photoNode(src,p.title));return n;}
 function render(p){
  const n=make('article',null,'property');n.append(make('span',page==='browse'?`${p.available} ${p.unit}${p.available===1?'':'s'} available`:nice(p.status),'badge'),make('h2',p.title),make('p',`${nice(p.property_type)} · ${p.area}`),gallery(p),make('p',`${money(p.rent)} / ${p.unit} / month`,'price'));
  const dl=make('dl');for(const [k,v] of [['Deposit',money(p.deposit)],['Suitable for',nice(p.suitable_for)],['Sharing',`${p.sharing} people / room`],['Vacancies',`${p.available} of ${p.capacity} ${p.unit}s`]]){const d=make('div');d.append(make('dt',k),make('dd',v));dl.append(d);}n.append(dl,make('p',p.address),make('p',`Facilities: ${p.facilities||'Ask the owner'}`),make('p',`Rules / extra charges: ${p.rules||'Confirm with the owner'}`),make('p',`Availability updated ${date(p.availability_updated_at)}`,'note'));
  const map=safeMap(p.map_url);if(map){const a=link('View on Google Maps',map);a.target='_blank';a.rel='noopener noreferrer';n.append(a);}
  const actions=make('div',null,'actions');
  if(page==='browse')actions.append(action('Enquire about this property',async()=>{const {data,error}=await client.auth.getSession();if(error)throw error;if(!data.session){location.href='/candidate/portal/login.html?rooms=1';return;}await rpc('get_candidate_portal_context');enquiryProperty=p.id;$('#enquiry-title').textContent=p.title;$('#enquiry-form').reset();$('#enquiry-form .form-message').textContent='';$('#enquiry-dialog').showModal();},false));
  if(page==='owner'){
   if(p.review_note)n.append(make('p',`Admin feedback: ${p.review_note}`));
   actions.append(action('Edit Property',()=>openProperty(p)));
   const f=make('form');f.className='availability-edit';const l=make('label',`Available ${p.unit}s`),i=make('input');i.type='number';i.min='0';i.max=String(p.capacity);i.required=true;i.value=String(p.available);l.append(i);const listed=make('label',null,'consent'),check=make('input');check.type='checkbox';check.checked=p.is_listed;listed.append(check,make('span','Show this listing when approved'));const b=make('button','Update Availability');f.append(l,listed,b);f.onsubmit=e=>{e.preventDefault();busy(b,async()=>{await rpc('update_room_availability',{p_id:p.id,p_available:Number(i.value),p_listed:check.checked});await loadProperties();say('Availability updated.');});};n.append(f);
  }
  if(page==='admin'){
   n.append(make('p',`Owner: ${p.owner_name} · ${p.owner_status}`));const l=make('label','Review feedback'),note=make('textarea');note.maxLength=1000;note.value=p.review_note||'';l.append(note);n.append(l);
   for(const [status,label] of [['approved','Approve Property'],['correction_required','Request Correction'],['rejected','Reject / Unpublish']])actions.append(action(label,async()=>{if(status!=='approved'&&note.value.trim().length<3){say('Enter review feedback before requesting correction or rejecting.');return;}await rpc('review_room_record',{p_kind:'property',p_id:p.id,p_status:status,p_note:note.value.trim()});await loadProperties();say('Property review saved.');},status!=='approved'));
  }
  n.append(actions);return n;
 }
 async function loadProperties(){
  const f=$('#filters'),values=f?new FormData(f):null;
  rows=await rpc('list_room_properties',{p_scope:page==='owner'?'owner':page==='admin'?'admin':'public',p_area:values?.get('area')?.trim()||'',p_max_rent:values?.get('max_rent')?Number(values.get('max_rent')):null,p_type:values?.get('property_type')||'',p_offset:offset});
  $('#properties').replaceChildren();for(const p of rows||[])$('#properties').append(render(p));
  if(!rows?.length)$('#properties').append(make('p',page==='browse'?'No approved properties currently match these filters. Try a nearby area or a higher budget.':page==='owner'?(offset?'No more properties on this page. Use Previous to return.':'No properties yet. Add your first property for Admin review.'):'No properties to review.','panel'));
  $('#previous').hidden=offset===0;$('#next').hidden=rows?.length!==12;
 }
 async function loadEnquiries(){
  const list=$('#enquiry-list');const records=await rpc('list_room_enquiries',{p_scope:page==='owner'?'owner':'candidate'});list.replaceChildren();
  for(const r of records){const n=make('article',null,'enquiry');n.append(make('span',nice(r.status),'badge'),make('h3',r.property_title),make('p',r.area),make('p',r.message),make('p',`Sent ${date(r.created_at)}`,'note'));if(r.contact_phone)n.append(make('p',`Shared contact: ${r.contact_phone}`));
   const actions=make('div',null,'actions');for(const [status,label] of page==='owner'?[['contacted','Mark Contacted'],['closed','Close Enquiry']]:[['withdrawn','Withdraw Enquiry']])if(r.status!=='withdrawn')actions.append(action(label,async()=>{await rpc('update_room_enquiry',{p_id:r.id,p_status:status});await loadEnquiries();}));n.append(actions);list.append(n);}
  if(!records.length)list.append(make('p','No room enquiries yet.','panel'));
 }
 async function resizePhotos(files){
  if(files.length>3)throw new Error('Choose up to three photos');const result=[];
  for(const file of files){if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>12000000)throw new Error('Use JPEG, PNG or WebP images under 12 MB');
   const url=URL.createObjectURL(file);try{const img=new Image();img.src=url;await img.decode();const canvas=document.createElement('canvas'),scale=Math.min(1,720/img.width,720/img.height);canvas.width=Math.max(1,Math.round(img.width*scale));canvas.height=Math.max(1,Math.round(img.height*scale));canvas.getContext('2d').drawImage(img,0,0,canvas.width,canvas.height);let data=canvas.toDataURL('image/jpeg',.65);if(data.length>180000)data=canvas.toDataURL('image/jpeg',.35);if(data.length>180000)throw new Error('Photo is too large');result.push(data);}finally{URL.revokeObjectURL(url);}}
  return result;
 }
 function openProperty(p=null){editing=p?.id||null;draftKey=crypto.randomUUID();photos=p?.photos||[];const f=$('#property-form');f.reset();for(const k of ['title','property_type','area','address','rent','deposit','unit','suitable_for','sharing','capacity','available','facilities','rules','map_url'])if(p)f.elements[k].value=p[k]??'';$('#property-form-title').textContent=p?'Edit Property':'Add Property';$('#photo-preview').replaceChildren(...photos.map(src=>photoNode(src,'Existing property photo')));f.querySelector('.form-message').textContent='';$('#property-dialog').showModal();}
 function ownerStatus(){
  const status=context?.status||'incomplete';
  const copy={incomplete:['Complete your owner profile','Profile needed','Submit your name and mobile below. Aadhyant will review your owner account before property posting is enabled.'],pending:['Your account is under review','Pending approval','Your owner details have been submitted. After Aadhyant approves your account, you can add properties here. Each property is reviewed separately before it appears publicly.'],active:['Your owner account is approved','Approved owner','You can add and manage properties below. New listings and changes to property details need a separate review. Availability updates do not restart that review.'],suspended:['Your owner account is suspended','Access suspended','Property management is paused and your listings are hidden from public search. Contact Aadhyant for assistance.']}[status]||['Owner access unavailable','Review required','Contact Aadhyant to check your owner account.'];
  $('#owner-status').hidden=false;$('#owner-status-title').textContent=copy[0];$('#owner-status-badge').textContent=copy[1];$('#owner-status-description').textContent=copy[2];$('#owner-display-name').textContent=context?`${context.display_name} · ${context.phone}`:'';
  $('#refresh-owner-status').onclick=()=>busy($('#refresh-owner-status'),async()=>{await owner();say('Account status refreshed.');});
 }
 async function owner(){
  $('#owner-workspace').hidden=true;$('#owner-profile').hidden=true;document.querySelectorAll('[data-owner-management-nav]').forEach(n=>n.hidden=true);
  context=await rpc('room_owner_context');$('#logout').hidden=false;ownerStatus();
  if(!context){$('#owner-profile').hidden=false;$('#owner-profile-form').onsubmit=e=>{e.preventDefault();const f=e.currentTarget;busy(f.querySelector('button'),async()=>{await rpc('register_room_owner',{p_name:f.elements.name.value.trim(),p_phone:f.elements.phone.value.trim()});await owner();say('Owner details submitted. Your account is awaiting Aadhyant approval.');});};return;}
  if(context.status!=='active'){say(`Owner account: ${context.status==='pending'?'pending approval':nice(context.status)}. See your account status below.`);return;}
  say('');document.querySelectorAll('[data-owner-management-nav]').forEach(n=>n.hidden=false);
  $('#owner-workspace').hidden=false;$('#add-property').onclick=()=>openProperty();
  $('#property-form').onsubmit=e=>{e.preventDefault();const f=e.currentTarget;busy(f.querySelector('button:not([type=button])'),async()=>{const data=Object.fromEntries(new FormData(f));if(Number(data.available)>Number(data.capacity)){f.querySelector('.form-message').textContent='Available units cannot exceed total capacity.';return;}if(data.map_url&&!safeMap(data.map_url)){f.querySelector('.form-message').textContent='Use a Google Maps link.';return;}data.photos=$('#clear-photos').checked?[]:$('#photo-input').files.length?await resizePhotos([...$('#photo-input').files]):photos;await rpc('save_room_property',{p_id:editing,p_data:data,p_request_key:draftKey});$('#property-dialog').close();offset=0;await loadProperties();say('Property submitted for Admin review.');});};
  await loadProperties();try{await loadEnquiries();}catch(_){$('#enquiry-list').replaceChildren(make('p','Enquiries could not be loaded. Refresh Account Status to retry.','panel'));}
 }
 async function admin(){
  const owners=await rpc('list_room_owners');$('#admin-workspace').hidden=false;
  const target=$('#owners');target.replaceChildren();for(const o of owners){const n=make('article',null,'owner');n.append(make('h3',o.display_name),make('p',`${o.phone} · ${nice(o.status)}`));const a=make('div',null,'actions');for(const [s,label] of [['active','Approve Owner'],['suspended','Suspend Owner']])a.append(action(label,async()=>{await rpc('review_room_record',{p_kind:'owner',p_id:o.user_id,p_status:s,p_note:''});await admin();}));n.append(a);target.append(n);}if(!owners.length)target.append(make('p','No owner accounts pending review.','panel'));await loadProperties();
 }
 async function start(){
  if(!client||!window.aadhyantSupabase?.isConfigured){say('Rooms & PG is not connected yet. Please try again after the module is activated.');return;}
  for(const b of document.querySelectorAll('[data-close]'))b.onclick=()=>document.getElementById(b.dataset.close).close();
  if(['login','register'].includes(page)){
   const f=$('#auth-form');f.onsubmit=e=>{e.preventDefault();busy(f.querySelector('button'),async()=>{const email=f.elements.email.value.trim(),password=f.elements.password.value;if(page==='register'){
    if(password!==f.elements.confirmPassword.value||password.length<10||!/[A-Za-z]/.test(password)||!/[0-9]/.test(password)){say('Use matching passwords with at least 10 characters, a letter and a number.');return;}
    const {error}=await client.auth.signUp({email,password,options:{emailRedirectTo:new URL('/rooms-pg/owner/',location.origin).href,data:{onboarding_type:'room_owner'}}});if(error)throw error;f.reset();say('Check your email to confirm your account, then sign in and submit your owner details. If already registered, use Sign In or Forgot Password.');
   }else{const {error}=await client.auth.signInWithPassword({email,password});if(error){say('Unable to sign in. Check your email and password.');return;}location.href='/rooms-pg/owner/';}});};return;
  }
  const {data,error}=await client.auth.getSession();if(error)throw error;
  if(['owner','admin'].includes(page)&&!data.session){say('Sign in to the correct portal to continue.');$('#message').append(link('Sign In',page==='owner'?'/rooms-pg/owner/login.html':'/admin/login.html'));return;}
  const userId=data.session?.user?.id;
  client.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||event==='SIGNED_IN'&&session?.user?.id!==userId){document.querySelectorAll('#owner-workspace,#admin-workspace,#enquiries,#owner-profile,#owner-status,[data-owner-management-nav]').forEach(n=>n.hidden=true);$('#properties')?.replaceChildren();$('#enquiry-list')?.replaceChildren();location.reload();}});
  if(page==='owner')$('#logout').hidden=!data.session;$('#logout').onclick=()=>busy($('#logout'),async()=>{const {error}=await client.auth.signOut();if(error)throw error;location.href='/rooms-pg/owner/login.html';});
  if($('#previous')){$('#previous').onclick=()=>{offset=Math.max(0,offset-12);loadProperties().catch(()=>say('Could not load properties. Retry.'));};$('#next').onclick=()=>{offset+=12;loadProperties().catch(()=>say('Could not load properties. Retry.'));};}
  if(page==='owner'){await owner();return;}if(page==='admin'){await admin();return;}
  $('#filters').onsubmit=e=>{e.preventDefault();offset=0;busy(e.currentTarget.querySelector('button'),loadProperties);};
  $('#my-enquiries').onclick=()=>busy($('#my-enquiries'),async()=>{if(!data.session){location.href='/candidate/portal/login.html?rooms=1';return;}await rpc('get_candidate_portal_context');$('#enquiries').hidden=false;await loadEnquiries();$('#enquiries').scrollIntoView({behavior:'smooth'});});
  $('#enquiry-form').onsubmit=e=>{e.preventDefault();const f=e.currentTarget;busy(f.querySelector('button[type=submit]'),async()=>{await rpc('send_room_enquiry',{p_property:enquiryProperty,p_phone:f.elements.phone.value.trim(),p_message:f.elements.message.value.trim(),p_consent:f.elements.consent.checked});$('#enquiry-dialog').close();say('Enquiry sent. The owner can now view your message and shared contact. This is not a booking.');});};
  await loadProperties();
 }
 window.addEventListener('pagehide',()=>{if(['owner','admin'].includes(page))document.querySelectorAll('#owner-workspace,#admin-workspace,#owner-profile,#owner-status,[data-owner-management-nav]').forEach(n=>n.hidden=true);});
 window.addEventListener('pageshow',e=>{if(e.persisted)location.reload();});
 start().catch(()=>say('Accommodation access could not be confirmed. Check your portal account or try again after the module is activated.'));
})();
