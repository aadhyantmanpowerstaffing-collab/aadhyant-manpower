'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element{
 constructor(tag){this.tag=tag;this.textContent='';this.children=[];this.dataset={};this.attrs={};this.handlers={};this.classList={toggle(){}};this.value='';}
 append(...v){this.children.push(...v);}replaceChildren(...v){this.children=v;}setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,v){this.handlers[k]=v;}querySelectorAll(){return [];}scrollIntoView(){}showModal(){this.open=true;}close(){this.open=false;}remove(){this.removed=true;}
}
const walk=n=>[n,...n.children.flatMap(walk)];
async function setup({archiveError=false,labelError=false}={}){const main=new Element('main'),group=new Element('nav'),calls=[];let deleted=false,labelOptions={lists:['Batch A'],tags:['Sanand']};
 const rows=Array.from({length:100},(_,i)=>({contact_id:'contact-'+i,name_masked:'C•••',mobile_masked:'+91XXXXXX'+i,consent:'unknown',resolution_status:'unresolved'}));
 const document={createElement:t=>new Element(t),createTextNode:t=>Object.assign(new Element('#text'),{textContent:t}),querySelector:s=>s==='.admin-main'?main:group,querySelectorAll:()=>[]};
 const client={rpc:async(name,args)=>{calls.push([name,args]);if(name==='admin_console_contact_labels')return labelError?{error:{message:'Labels unavailable'}}:{data:labelOptions};if(name==='admin_console_label_contacts'){labelOptions={lists:args.p_lists,tags:args.p_tags};return{data:args.p_ids.length};}if(name==='admin_console_import_contacts')return{data:{added:1,reused:1,restored:1}};if(name==='admin_console_import_numbers')return{data:{added:0,reused:2,restored:2}};if(name==='admin_console_templates')return{data:{templates:[{id:'template-1',name:'current',status:'APPROVED',compatible:true,synced_at:new Date().toISOString()}],sender_ready:true}};if(name==='admin_console_registration_flow')return{data:{ready:true}};if(name==='admin_console_automatic_alerts')return{data:{enabled:false,template_ready:true,worker_ready:false,eligible_subscribers:0}};if(name==='admin_console_campaigns')return{data:[]};if(name==='list_recruitment_requirements')return{data:[{id:'job-1',requirement_code:'JOB-1',requirement_stage:'open'}]};if(name==='get_public_job_requirements')return{data:[{requirement_code:'JOB-1'}]};if(name==='admin_console_audience')return{data:[]};if(name==='admin_console_inbox')return{data:[]};if(name==='admin_console_contacts')return{data:deleted?[]:rows.map((r,i)=>({...r,contact_id:'contact-'+(args.p_offset+i)}))};if(name==='admin_console_archive_contacts'){if(archiveError)return{error:{message:'Contact removal unavailable. Try again.'}};deleted=true;return{data:{archived:args.p_ids.length}};}if(name==='admin_console_record_consent'){if(args.p_contact_id==='contact-1')return{error:{message:'Opted-out contacts must re-enroll'}};return{data:true};}throw Error(name);}};
 const window={AadhyantSharingImport:{read:async()=>({rows:[{Mobile:'9876543210'}],duplicates:[],errors:[]})}};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,document,Date,crypto:{randomUUID:()=> 'operation-1'},Option:class extends Element{constructor(label,value){super('option');this.textContent=label;this.value=value;}}});await window.AadhyantWhatsAppConsole.initialize({client,authorization:{bootstrap_admin:true}});await group.children[0].handlers.click();
 const find=label=>walk(main).find(n=>!n.removed&&n.tag==='button'&&n.textContent===label);
 await find('Contacts').handlers.click();
 return{main,find,calls,click:async label=>{await find(label).handlers.click();await new Promise(resolve=>setImmediate(resolve));}};
}
test('select page, retain cross-page selection within limit, clear selection, and cancel delete without a write',async()=>{
 const f=await setup();assert.equal(f.find('Delete Selected').disabled,true);await f.click('Select All on This Page');assert.equal(f.find('Delete Selected').disabled,false);
 await f.click('Next');await f.click('Select All on This Page');assert.ok(walk(f.main).some(n=>n.textContent==='200 selected (up to 500)'));
 await f.click('Delete Selected');assert.ok(walk(f.main).some(n=>n.textContent==='Delete 200 selected contacts?'));await f.click('Cancel');assert.ok(!f.calls.some(([n])=>n==='admin_console_archive_contacts'));
 await f.click('Clear Selection');assert.equal(f.find('Delete Selected').disabled,true);
});
test('deletes exact reviewed selection only after confirmation and displays server result',async()=>{
 const f=await setup();await f.click('Select All on This Page');await f.click('Delete Selected');assert.ok(!f.calls.some(([n])=>n==='admin_console_archive_contacts'));
 await f.click('Confirm Delete');const sent=f.calls.find(([n])=>n==='admin_console_archive_contacts');assert.equal(sent[1].p_ids.length,100);assert.equal(sent[1].p_ids[0],'contact-0');assert.ok(walk(f.main).some(n=>n.textContent==='100 contacts removed from Contacts and manual bulk selection. History preserved.'));assert.equal(f.find('Delete Selected').disabled,true);
});

test('bulk permission requires attestation, records exact selection and retains failed IDs',async()=>{
 const f=await setup();assert.equal(f.find('Bulk Record Permission').disabled,true);
 await f.click('Select All on This Page');await f.click('Bulk Record Permission');
 await f.click('Save Bulk Permission');assert.ok(!f.calls.some(([n])=>n==='admin_console_record_consent'));
 const dialog=walk(f.main).find(n=>n.tag==='dialog'&&!n.removed);
 walk(dialog).find(n=>n.type==='checkbox').checked=true;
 walk(dialog).find(n=>n.type==='datetime-local').value=new Date(Date.now()-3600000).toISOString().slice(0,16);
 walk(dialog).find(n=>n.tag==='select').value='written_permission';
 await f.click('Save Bulk Permission');
 const calls=f.calls.filter(([n])=>n==='admin_console_record_consent');assert.equal(calls.length,100);
 assert.equal(calls[0][1].p_source,'written_permission');assert.equal(calls[99][1].p_contact_id,'contact-99');
 assert.ok(walk(f.main).some(n=>n.textContent==='1 selected (up to 500)'));
 assert.ok(walk(f.main).some(n=>n.textContent.startsWith('99 permissions recorded · 1 not recorded.')));
});

test('failed removal retains the selection and reports the error without claiming success',async()=>{
 const f=await setup({archiveError:true});await f.click('Select All on This Page');await f.click('Delete Selected');await f.click('Confirm Delete');
 assert.ok(walk(f.main).some(n=>n.textContent==='Contact removal unavailable. Try again.'));
 assert.ok(walk(f.main).some(n=>n.textContent==='100 selected (up to 500)'));
 assert.equal(f.find('Delete Selected').disabled,false);
});

const fieldInput=(main,label)=>walk(main).find(n=>n.tag==='label'&&n.textContent===label).children[0];
test('saved Lists/Tags populate contact filters and organization pickers; saved changes reload dropdowns',async()=>{
 const f=await setup();
 assert.deepEqual(fieldInput(f.main,'Contact List').children.map(n=>n.textContent),['All contact lists','Batch A']);
 assert.deepEqual(fieldInput(f.main,'Saved Tags').children.map(n=>n.textContent),['Choose a saved tag','Sanand']);fieldInput(f.main,'Contact List').value='Batch A';await f.click('Filter Contacts');
 const saved=fieldInput(f.main,'Saved Lists');saved.value='Batch A';saved.handlers.change();assert.equal(fieldInput(f.main,'Lists').value,'Batch A');
 fieldInput(f.main,'Lists').value='New Batch';fieldInput(f.main,'Tags').value='ITI';
 await f.click('Select All on This Page');
 fieldInput(f.main,'Lists').value='New Batch';fieldInput(f.main,'Tags').value='ITI';
 await f.click('Save Lists and Tags');
 assert.deepEqual(fieldInput(f.main,'Contact List').children.map(n=>n.textContent),['All contact lists','New Batch']);
 assert.ok(walk(f.main).some(n=>n.textContent.startsWith('Lists and tags saved.')));assert.equal(f.calls.filter(([name])=>name==='admin_console_contacts').at(-1)[1].p_list,null);
});
test('import resets prior list/tag filters and selection, reloads contacts and reports restored count',async()=>{
 const f=await setup();fieldInput(f.main,'Contact List').value='Batch A';fieldInput(f.main,'Tag').value='Sanand';await f.click('Filter Contacts');
 await f.click('Select All on This Page');fieldInput(f.main,'Mobile Numbers').value='9876543210\n9876543211';await f.click('Import Numbers');
 const request=f.calls.filter(([name])=>name==='admin_console_contacts').at(-1)[1];
 assert.equal(request.p_list,null);assert.equal(request.p_tag,null);assert.equal(request.p_offset,0);
 assert.ok(walk(f.main).some(n=>n.textContent==='0 selected (up to 500)'));
 assert.ok(walk(f.main).some(n=>n.textContent.includes('2 restored')));
});
test('campaign dropdown choices pass exact saved list/tag to recipient query and survive a rerender',async()=>{
 const f=await setup();await f.click('Campaigns');await f.click('Create Campaign');
 const list=fieldInput(f.main,'Contact List'),tag=fieldInput(f.main,'Contact Tag');assert.equal(list.tag,'select');assert.equal(tag.tag,'select');
 list.value='Batch A';list.handlers.change();tag.value='Sanand';tag.handlers.change();
 const audience=fieldInput(f.main,'Audience');audience.value='contacts';audience.handlers.change();
 assert.equal(fieldInput(f.main,'Contact List').value,'Batch A');
 const title=fieldInput(f.main,'Campaign Name');title.value='New Campaign';title.handlers.input();
 const job=fieldInput(f.main,'Job');job.value='job-1';job.handlers.change();const template=fieldInput(f.main,'Message Template');template.value='template-1';template.handlers.change();
 await f.click('Choose Recipients');const args=f.calls.find(([name])=>name==='admin_console_audience')[1];
 assert.equal(args.p_list,'Batch A');assert.equal(args.p_tag,'Sanand');assert.equal(args.p_source,'contacts');
});

test('reviewed file import shows its restored count and clears stale filter and selection',async()=>{
 const f=await setup();fieldInput(f.main,'Contact List').value='Batch A';await f.click('Filter Contacts');await f.click('Select All on This Page');
 const file=walk(f.main).find(n=>n.type==='file');file.files=[{name:'contacts.csv'}];await file.handlers.change();await f.click('Import Reviewed Contacts');
 assert.ok(f.calls.some(([name])=>name==='admin_console_import_contacts'));
 assert.equal(f.calls.filter(([name])=>name==='admin_console_contacts').at(-1)[1].p_list,null);
 assert.ok(walk(f.main).some(n=>n.textContent.includes('1 restored')));
});
test('failed label loading visibly blocks recipient query instead of silently selecting every contact',async()=>{
 const f=await setup({labelError:true});await f.click('Campaigns');await f.click('Create Campaign');await f.click('Choose Recipients');
 assert.ok(!f.calls.some(([name])=>name==='admin_console_audience'));
 assert.ok(walk(f.main).some(n=>n.textContent==='Refresh to load saved lists and tags before choosing recipients.'));
});

test('page contact search limits select-all to matching visible contacts',async()=>{
 const f=await setup();const search=walk(f.main).find(n=>n.placeholder==='Name or last 4 digits on this page');search.value='+91XXXXXX99';await f.click('Search This Page');await f.click('Select All on This Page');assert.ok(walk(f.main).some(n=>n.textContent==='1 selected (up to 500)'));
 await f.click('Delete Selected');assert.ok(walk(f.main).some(n=>n.textContent==='Delete 1 selected contacts?'));assert.ok(!f.calls.some(([n])=>n==='admin_console_archive_contacts'));
});
test('overview and settings use existing read APIs and template filters keep unsupported matches out of campaigns',async()=>{
 const f=await setup();await f.click('Overview');assert.ok(walk(f.main).some(n=>n.textContent==='WhatsApp overview'));assert.ok(walk(f.main).some(n=>n.textContent==='Latest page · up to 50 campaigns'));await f.click('Settings');assert.ok(walk(f.main).some(n=>n.textContent==='Connection & team'));
 await f.click('Templates');const search=walk(f.main).find(n=>n.placeholder==='Template name or message text');search.value='no such template';await f.click('Filter Templates');assert.ok(walk(f.main).some(n=>n.textContent==='No templates match these filters.'));assert.ok(!f.calls.some(([n])=>/prepare|queue|approve|record_consent/.test(n)));
});
