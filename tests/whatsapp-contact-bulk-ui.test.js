'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element{
 constructor(tag){this.tag=tag;this.textContent='';this.children=[];this.dataset={};this.attrs={};this.handlers={};this.classList={toggle(){}};this.value='';}
 append(...v){this.children.push(...v);}replaceChildren(...v){this.children=v;}setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,v){this.handlers[k]=v;}querySelectorAll(){return [];}scrollIntoView(){}showModal(){this.open=true;}close(){this.open=false;}remove(){this.removed=true;}
}
const walk=n=>[n,...n.children.flatMap(walk)];
async function setup({archiveError=false}={}){const main=new Element('main'),group=new Element('nav'),calls=[];let deleted=false;
 const rows=Array.from({length:100},(_,i)=>({contact_id:'contact-'+i,name_masked:'C•••',mobile_masked:'+91XXXXXX'+i,consent:'unknown',resolution_status:'unresolved'}));
 const document={createElement:t=>new Element(t),querySelector:s=>s==='.admin-main'?main:group,querySelectorAll:()=>[]};
 const client={rpc:async(name,args)=>{calls.push([name,args]);if(name==='admin_console_inbox')return{data:[]};if(name==='admin_console_contacts')return{data:deleted?[]:rows.map((r,i)=>({...r,contact_id:'contact-'+(args.p_offset+i)}))};if(name==='admin_console_archive_contacts'){if(archiveError)return{error:{message:'Contact removal unavailable. Try again.'}};deleted=true;return{data:{archived:args.p_ids.length}};}if(name==='admin_console_record_consent'){if(args.p_contact_id==='contact-1')return{error:{message:'Opted-out contacts must re-enroll'}};return{data:true};}throw Error(name);}};
 const window={};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,document,Date,Option:class extends Element{constructor(label,value){super('option');this.textContent=label;this.value=value;}}});await window.AadhyantWhatsAppConsole.initialize({client,authorization:{bootstrap_admin:true}});await group.children[0].handlers.click();
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
