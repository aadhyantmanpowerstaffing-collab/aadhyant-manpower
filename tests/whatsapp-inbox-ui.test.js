'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element{
 constructor(tag,text=''){this.tag=tag;this.textContent=text;this.children=[];this.dataset={};this.attrs={};this.handlers={};this.classList={toggle(){}};this.value='';}
 append(...items){this.children.push(...items);}replaceChildren(...items){this.children=items;}setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,v){this.handlers[k]=v;}querySelectorAll(){return [];}scrollIntoView(){};
}
function walk(n){return [n,...n.children.flatMap(walk)];}
function text(n){return n.textContent+ n.children.map(text).join(' ');}
async function setup(){const main=new Element('main'),group=new Element('nav'),calls=[];const row={contact_id:'contact-1',name_masked:'A•••',mobile_masked:'+91XXXXXX1234',consent:'unknown',unread_count:1,latest_at:'2026-10-16',latest_direction:'incoming',latest_status:'received',attention:true};let marked=false,fail=false;
 const document={createElement:t=>new Element(t),createTextNode:t=>new Element('#text',t),querySelector:s=>s==='.admin-main'?main:group,querySelectorAll:()=>[]};
 const client={rpc:async(name,args)=>{calls.push([name,args]);if(fail)return {error:{message:'Admin access required'}};if(name==='admin_console_inbox')return {data:[row]};if(name==='admin_console_conversation')return {data:[{id:'in-1',direction:'incoming',summary:'<img src=x onerror=alert(1)>',created_at:'2026-10-16',status:'processed',unread:!marked},{id:'out-1',direction:'outgoing',summary:'Vacancy posting reply',created_at:'2026-10-16',status:'delivered',sent_at:'2026-10-16',delivered_at:'2026-10-16',template_name:'aadhyant_employer_post_job'}]};if(name==='admin_console_mark_inbox_read'){marked=true;return {data:1};}throw Error('Unexpected RPC '+name);}};
 const window={};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,document,Date,Option:class extends Element{constructor(t,v){super('option',t);this.value=v;}}});await window.AadhyantWhatsAppConsole.initialize({client,authorization:{bootstrap_admin:true}});
 await group.children[0].handlers.click();const panel=main.children[0];const find=(label)=>walk(panel).find(x=>x.tag==='button'&&(x.textContent===label||x.attrs['aria-label']===label));return {main,panel,calls,find,setFail:()=>{fail=true;}};}
test('operator opens Inbox and Sent, reads a single conversation and marks only visible incoming IDs without sending',async()=>{const f=await setup();assert.match(text(f.panel),/Inbox/);assert.match(text(f.panel),/Sent/);assert.match(text(f.panel),/Select a contact/);
 await f.find('Open conversation +91XXXXXX1234').handlers.click();assert.match(text(f.panel),/Vacancy posting reply/);assert.match(text(f.panel),/delivered/);assert.match(text(f.panel),/<img src=x/);assert.ok(!walk(f.panel).some(x=>x.tag==='img'));
 await f.find('Mark Visible Messages as Read').handlers.click();const mark=f.calls.find(x=>x[0]==='admin_console_mark_inbox_read');assert.equal(JSON.stringify(mark[1]),JSON.stringify({p_contact_id:'contact-1',p_message_ids:['in-1']}));
 await f.find('Sent').handlers.click();assert.equal(f.calls.at(-1)[1].p_folder,'sent');assert.match(text(f.panel),/Sent & Outgoing/);assert.ok(f.calls.every(x=>/^admin_console_(inbox|conversation|mark_inbox_read)$/.test(x[0])));
});
test('failed refresh gives a visible error without changing or sending messages',async()=>{const f=await setup();f.setFail();await f.find('Refresh Messages').handlers.click();assert.match(text(f.panel),/Admin access required/);assert.equal(f.calls.at(-1)[0],'admin_console_inbox');});
