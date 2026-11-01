'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto');
const api=require('../admin/job-message');
class Element{
 constructor(tag,text=''){this.tag=tag;this.textContent=text;this.children=[];this.dataset={};this.attrs={};this.handlers={};this.classList={toggle(){}};this.value='';}
 append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=nodes;}setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,v){this.handlers[k]=v;}querySelectorAll(s){return walk(this).filter(n=>s.split(',').includes(n.tag));}scrollIntoView(){}
}
const walk=n=>[n,...n.children.flatMap(walk)],text=n=>n.textContent+n.children.map(text).join(' ');
async function setup(pending=false){
 const main=new Element('main'),nav=new Element('nav'),calls=[];
 const job={id:'00000000-0000-0000-0000-000000000002',requirement_code:'AAD-2026-000023',job_role:'Operator',requirement_stage:'open',qualification:'10th / 12th / ITI'};
 const templates=['en','hi'].map(l=>({id:l,name:api.name(l),language:l,body:api.bodies[l],buttons:[{text:'Interested'}],status:pending?'PENDING':'APPROVED',compatible:true,synced_at:new Date().toISOString()}));
 const document={createElement:t=>new Element(t),createTextNode:t=>new Element('#text',t),querySelector:s=>s==='.admin-main'?main:nav,querySelectorAll:()=>[],addEventListener(){}};
 const client={rpc:async(name,args)=>{calls.push([name,args]);const data={admin_console_inbox:[],admin_console_templates:{templates,sender_ready:false},admin_console_registration_flow:{ready:false},admin_console_campaigns:[],admin_console_contact_labels:{lists:['ITI'],tags:['Sanand']},list_recruitment_requirements:[job],get_public_job_requirements:[job],admin_console_audience:[{contact_id:'eligible',mobile_masked:'+91XXXXXX3210',name_masked:'S•••',eligible:true},{contact_id:'no-consent',mobile_masked:'+91XXXXXX3211',eligible:false}],admin_console_prepare_job_message:'saved-id'};
 if(!Object.hasOwn(data,name))throw Error('Unexpected RPC '+name);return {data:data[name]};}};
 const window={AadhyantJobMessage:api};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,document,Date,crypto,Option:function(t,v){const n=new Element('option',t);n.value=v;return n;}});
 await window.AadhyantWhatsAppConsole.initialize({client,authorization:{bootstrap_admin:true}});await nav.children[0].handlers.click();
 const panel=main.children[0],find=label=>{const n=walk(panel).find(n=>n.tag==='button'&&n.textContent===label);assert.ok(n,'missing '+label);return n;};
 const control=label=>{const n=walk(panel).find(n=>n.tag==='label'&&n.textContent===label);assert.ok(n,'missing label '+label);return n.children[0];};
 await find('Job Message').handlers.click();
 return {calls,panel,find,control};
}
test('operator fills two salary groups, previews Interested and saves through canonical Job Message RPC',async()=>{
 const f=await setup();let c=f.control('Job for Registration');c.value='00000000-0000-0000-0000-000000000002';c.handlers.change();
 c=f.control('Campaign Name');c.value='Operator hiring';c.handlers.input();
 const values={'Salary Group 1 — qualification / role':'10th / 12th','Group 1 — CTC':'₹17,174','Group 1 — Take Home':'₹15,326','Group 1 — OT per hour':'₹121/hour','Salary Group 2 — qualification / role':'ITI','Group 2 — CTC':'₹17,495','Group 2 — Take Home':'₹15,602','Group 2 — OT per hour':'₹122/hour','Benefits & Duty':'PF & ESIC; bus; canteen; 8 hours'};
 for(const [label,value] of Object.entries(values)){c=f.control(label);c.value=value;c.handlers.input();}
 assert.match(text(f.panel),/₹17,174/);assert.match(text(f.panel),/Interested/);
 c=f.control('Message Language');c.value='hi';c.handlers.change();assert.match(text(f.panel),/हाथ में वेतन/);assert.equal(f.control('Group 1 — CTC').value,'₹17,174');
 await f.find('Choose Recipients').handlers.click();assert.equal(walk(f.panel).find(n=>n.attrs['aria-label']==='Select +91XXXXXX3211').disabled,true);
 await f.find('Select Eligible on This Page').handlers.click();await f.find('Preview Message').handlers.click();assert.match(text(f.panel),/₹15,602/);assert.match(text(f.panel),/Interested/);
 await f.find('Save Campaign for Approval').handlers.click();const saved=f.calls.find(([n])=>n==='admin_console_prepare_job_message')[1];assert.equal(saved.p_template_id,'hi');assert.equal(saved.p_fields.ctc_1,'₹17,174');assert.deepEqual(Array.from(saved.p_contact_ids),['eligible']);assert.equal(saved.p_job_id,'00000000-0000-0000-0000-000000000002');
 assert.ok(!f.calls.some(([n])=>n==='admin_console_prepare'||n==='admin_console_queue'));
});
test('pending templates permit drafting and preview but disable recipient selection',async()=>{
 const f=await setup(true);assert.equal(f.find('Choose Recipients').disabled,true);assert.match(text(f.panel),/awaiting approval or a fresh sync/);assert.equal(f.calls.filter(([n])=>n==='admin_console_prepare_job_message').length,0);
});
