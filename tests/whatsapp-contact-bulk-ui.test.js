'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element{
 constructor(tag){this.tag=tag;this.textContent='';this.children=[];this.dataset={};this.attrs={};this.handlers={};this.classList={toggle(){}};this.value='';}
 append(...v){this.children.push(...v);}replaceChildren(...v){this.children=v;}setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,v){this.handlers[k]=v;}querySelectorAll(){return [];}scrollIntoView(){}showModal(){this.open=true;}close(){this.open=false;}remove(){this.removed=true;}
}
const walk=n=>[n,...n.children.flatMap(walk)];
async function setup(){const main=new Element('main'),group=new Element('nav'),calls=[];let deleted=false;
 const rows=Array.from({length:100},(_,i)=>({contact_id:'contact-'+i,name_masked:'C•••',mobile_masked:'+91XXXXXX'+i,consent:'unknown',resolution_status:'unresolved'}));
 const document={createElement:t=>new Element(t),querySelector:s=>s==='.admin-main'?main:group,querySelectorAll:()=>[]};
 const client={rpc:async(name,args)=>{calls.push([name,args]);if(name==='admin_console_inbox')return{data:[]};if(name==='admin_console_contacts')return{data:deleted?[]:rows.map((r,i)=>({...r,contact_id:'contact-'+(args.p_offset+i)}))};if(name==='admin_console_delete_contacts'){deleted=true;return{data:{deleted:args.p_ids.length,kept:0}};}throw Error(name);}};
 const window={};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,document,Date});await window.AadhyantWhatsAppConsole.initialize({client,authorization:{bootstrap_admin:true}});await group.children[0].handlers.click();
 const find=label=>walk(main).find(n=>!n.removed&&n.tag==='button'&&n.textContent===label);
 await find('Contacts').handlers.click();
 return{main,find,calls,click:async label=>{await find(label).handlers.click();await new Promise(resolve=>setImmediate(resolve));}};
}
test('select page, retain cross-page selection within limit, clear selection, and cancel delete without a write',async()=>{
 const f=await setup();assert.equal(f.find('Delete Selected').disabled,true);await f.click('Select All on This Page');assert.equal(f.find('Delete Selected').disabled,false);
 await f.click('Next');await f.click('Select All on This Page');assert.ok(walk(f.main).some(n=>n.textContent==='200 selected (up to 500)'));
 await f.click('Delete Selected');assert.ok(walk(f.main).some(n=>n.textContent==='Delete 200 selected contacts?'));await f.click('Cancel');assert.ok(!f.calls.some(([n])=>n==='admin_console_delete_contacts'));
 await f.click('Clear Selection');assert.equal(f.find('Delete Selected').disabled,true);
});
test('deletes exact reviewed selection only after confirmation and displays server result',async()=>{
 const f=await setup();await f.click('Select All on This Page');await f.click('Delete Selected');assert.ok(!f.calls.some(([n])=>n==='admin_console_delete_contacts'));
 await f.click('Confirm Delete');const sent=f.calls.find(([n])=>n==='admin_console_delete_contacts');assert.equal(sent[1].p_ids.length,100);assert.equal(sent[1].p_ids[0],'contact-0');assert.ok(walk(f.main).some(n=>n.textContent==='100 deleted · 0 protected contacts kept.'));assert.equal(f.find('Delete Selected').disabled,true);
});
