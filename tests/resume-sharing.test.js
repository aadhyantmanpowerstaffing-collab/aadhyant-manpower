const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element {
 constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.events={};this.attributes={};this.disabled=false;this.checked=false;this.isConnected=true;this._text='';}
 set textContent(v){this._text=String(v);this.children=[];} get textContent(){return this._text+this.children.map(c=>typeof c==='string'?c:c.textContent).join('');}
 append(...items){this.children.push(...items);}replaceChildren(...items){const disconnect=n=>{if(typeof n!=='string'){n.isConnected=false;n.children.forEach(disconnect);}};this.children.forEach(disconnect);this._text='';this.children=items;}
 setAttribute(k,v){this.attributes[k]=v;}addEventListener(k,f){(this.events[k]??=[]).push(f);}async fire(k){for(const f of this.events[k]||[])await f({target:this});}
}
const all=(n,p)=>[...(p(n)?[n]:[]),...n.children.filter(c=>typeof c!=='string').flatMap(c=>all(c,p))];
function setup(handler){const popups=[],calls=[],timers=[],revoked=[];const win={addEventListener(){},open(){const p={opener:'parent',location:{replace(u){p.url=u;}},close(){p.closed=true;}};popups.push(p);return p;}};
 const sandbox={window:win,document:{createElement:t=>new Element(t),createTextNode:t=>String(t)},URL:{createObjectURL:()=> 'blob:local-test',revokeObjectURL:u=>revoked.push(u)},Blob,setTimeout:f=>timers.push(f)};vm.runInNewContext(fs.readFileSync('assets/js/resume-sharing.js','utf8'),sandbox);
 const client={rpc:async(name,args)=>{calls.push({name,args});return handler(name,args);},storage:{from(bucket){return{download:async name=>({data:new Blob(['%PDF-test']),error:null})}}}};
 return{api:win.AadhyantResumeSharing,client,root:new Element('section'),calls,popups,win,revoked,timers};}
const row={item_key:'doc',item_kind:'document',document_id:'doc',label:'resume.pdf',recipient_type:'company',recipient_id:'co',recipient_name:'Company A',source_token:'src',revision:null,available:true,shared:false,has_grant:false};
const base={application_id:'app',items:[row]};
const clone=o=>JSON.parse(JSON.stringify(o));
const buttons=x=>all(x.root,n=>n.tagName==='BUTTON');
test('Candidate sharing is read-only with no consent control or automatic write',async()=>{const x=setup(async()=>({data:base}));await x.api.candidate(x.root,x.client,'REQ');assert.equal(x.calls.length,1);assert.equal(x.calls[0].name,'get_candidate_document_sharing');assert.equal(buttons(x).length,0);assert.equal(all(x.root,n=>n.tagName==='INPUT').length,0);assert.match(x.root.textContent,/No separate sharing action/);});
test('Candidate sees only effective Admin sharing status',async()=>{const data=clone(base);data.items[0].shared=true;const x=setup(async()=>({data}));await x.api.candidate(x.root,x.client,'REQ');assert.match(x.root.textContent,/resume.pdf — shared with Company A/);assert.equal(buttons(x).length,0);});
test('Admin requires item availability, not Candidate consent',async()=>{for(const available of [false,true]){const data=clone(base);data.items[0].available=available;const x=setup(async()=>({data}));await x.api.admin(x.root,x.client,'app');assert.equal(buttons(x).length,available?1:0);}});
test('Admin shares exact item recipient and source revision; double-click has one write',async()=>{let finish;const x=setup(name=>name==='admin_list_application_document_sharing'?{data:base}:new Promise(r=>{finish=r;}));await x.api.admin(x.root,x.client,'app');const b=buttons(x)[0];const pending=b.fire('click');await b.fire('click');assert.equal(x.calls.length,2);assert.equal(x.calls[1].name,'admin_set_application_document_share');assert.equal(x.calls[1].args.p_item_key,'doc');assert.equal(x.calls[1].args.p_source_token,'src');assert.equal(x.calls[1].args.p_recipient_id,'co');assert.equal(x.calls[1].args.p_share,true);finish({data:true});await pending;});
test('Stop sharing is available even after an item becomes unavailable',async()=>{const data=clone(base);Object.assign(data.items[0],{has_grant:true,available:false});const x=setup(async name=>({data:name==='admin_list_application_document_sharing'?data:true}));await x.api.admin(x.root,x.client,'app');assert.equal(buttons(x)[0].textContent,'Stop sharing');await buttons(x)[0].fire('click');assert.equal(x.calls[1].args.p_share,false);});
test('Write failure remains safe and permits deliberate retry',async()=>{const x=setup(async name=>name==='admin_list_application_document_sharing'?{data:base}:{error:Error('private secret')});await x.api.admin(x.root,x.client,'app');const b=buttons(x)[0];await b.fire('click');assert.equal(b.disabled,false);assert.match(x.root.textContent,/could not be saved/);assert.doesNotMatch(x.root.textContent,/private secret/);});
test('Bank UAN ESIC require explicit View details and never load with the listing',async()=>{for(const kind of ['bank','uan','esic']){const x=setup(async name=>({data:name==='get_shared_application_items'?[{item_key:kind,item_kind:kind,label:kind}]:{uan_number:'123456789012'}}));await x.api.tenant(x.root,x.client,'app','company');assert.equal(x.calls.length,1);assert.doesNotMatch(x.root.textContent,/123456789012/);await buttons(x)[0].fire('click');assert.equal(x.calls[1].name,'get_shared_application_joining_detail');assert.equal(x.calls[1].args.p_item_key,kind);assert.match(x.root.textContent,/123456789012/);await buttons(x)[0].fire('click');assert.doesNotMatch(x.root.textContent,/123456789012/);}});
test('Admin detail view does not share or put financial values in the grant request',async()=>{const data={application_id:'app',items:[{...row,item_key:'bank',item_kind:'bank',label:'Bank details'}]};const x=setup(async name=>({data:name==='admin_list_application_document_sharing'?data:{bank_account_number:'123456789012'}}));await x.api.admin(x.root,x.client,'app');await buttons(x).find(b=>b.textContent==='View details').fire('click');assert.equal(x.calls.length,2);assert.equal(x.calls[1].name,'admin_get_application_joining_detail');assert.equal(x.calls.some(c=>c.name==='admin_set_application_document_share'),false);});
test('Revoked joining details show no value; stale modal gets no delayed data',async()=>{const x=setup(async name=>name==='get_shared_application_items'?{data:[{item_key:'bank',item_kind:'bank',label:'Bank details'}]}:{error:Error('secret')});await x.api.tenant(x.root,x.client,'app','company');await buttons(x)[0].fire('click');assert.match(x.root.textContent,/unavailable/);assert.doesNotMatch(x.root.textContent,/secret/);let release;const late=setup(()=>new Promise(r=>{release=r;}));const pending=late.api.tenant(late.root,late.client,'app','company');late.root.isConnected=false;release({data:[{...row,label:'sensitive.pdf'}]});await pending;assert.doesNotMatch(late.root.textContent,/sensitive/);});
test('PDF JPEG PNG use authenticated downloads and fresh access checks',async()=>{for(const mime of ['application/pdf','image/jpeg','image/png']){const x=setup(async name=>({data:name==='get_shared_application_items'?[row]:[{bucket_name:'candidate-private',object_name:'private/path',mime_type:mime}]}));await x.api.tenant(x.root,x.client,'app','company');await buttons(x)[0].fire('click');assert.equal(x.calls[1].name,'get_shared_application_document_access');assert.equal(x.popups[0].opener,null);assert.equal(x.popups[0].url,'blob:local-test');assert.doesNotMatch(x.root.textContent,/private\/path/);}});
test('Unavailable and unsupported document access fail closed',async()=>{for(const access of [[],[{bucket_name:'candidate-private',object_name:'x',mime_type:'text/html'}]]){const x=setup(async name=>({data:name==='get_shared_application_items'?[row]:access}));await x.api.tenant(x.root,x.client,'app','company');await buttons(x)[0].fire('click');assert.equal(x.popups[0].closed,true);assert.equal(x.popups[0].url,undefined);}});
test('Shared module is explicitly included in each required portal and artifact allowlist',()=>{for(const f of ['candidate/portal/applications.html','admin/index.html','company/applications.html','contractor/applications.html'])assert.match(fs.readFileSync(f,'utf8'),/assets\/js\/resume-sharing\.js/);assert.match(fs.readFileSync('scripts/build-production-artifact.js','utf8'),/'assets\/js\/resume-sharing\.js'/);const s=fs.readFileSync('assets/js/resume-sharing.js','utf8');assert.doesNotMatch(s,/getPublicUrl|createSignedUrl|service_role|innerHTML|localStorage/);});

test('All four portal entry points invoke the correct sharing mode',()=>{for(const [file,mode] of [['candidate/portal/candidate.js','candidate'],['admin/recruitment-operations.js','admin'],['company/company.js','tenant'],['contractor/contractor.js','tenant']])assert.ok(fs.readFileSync(file,'utf8').includes('AadhyantResumeSharing?.'+mode+'('),file);});

const groups=x=>all(x.root,n=>n.tagName==='DETAILS');
const groupButton=(group,label)=>all(group,n=>n.tagName==='BUTTON'&&n.textContent===label)[0];
const joiningRows=['esic','bank','uan'].map(kind=>({...row,item_key:kind,item_kind:kind,label:kind}));
test('Admin groups by recipient once and orders Documents, Bank, UAN, ESIC',async()=>{
 const data={items:[...joiningRows,row,{...row,recipient_type:'contractor',recipient_id:'other',recipient_name:'Contractor B'}]};
 const x=setup(async()=>({data}));await x.api.admin(x.root,x.client,'app');
 assert.deepEqual(groups(x).map(g=>g.attributes['data-sharing-category']),['document','bank','uan','esic','document']);
 assert.equal(all(x.root,n=>n.className==='sharing-recipient-name').length,2);
 assert.equal(x.calls.length,1);
 assert.equal(groups(x).filter(g=>g.open).length,1);
 const contractor=groups(x)[4];contractor.open=true;await contractor.fire('toggle');
 await groupButton(contractor,'Share item').fire('click');
 assert.equal(x.calls[1].args.p_recipient_id,'other');assert.equal(x.calls[1].args.p_recipient_type,'contractor');
});
test('Company and Contractor open one section without fetching private values',async()=>{
 for(const portal of ['company','contractor']){
  const x=setup(async()=>({data:[...joiningRows,row]}));await x.api.tenant(x.root,x.client,'app',portal);
  const [docs,bank,uan]=groups(x);bank.open=true;await bank.fire('toggle');
  assert.equal(docs.open,false);assert.equal(bank.open,true);assert.equal(x.calls.length,1);
  uan.open=true;await uan.fire('toggle');assert.equal(bank.open,false);assert.equal(uan.open,true);assert.equal(x.calls.length,1);
 }
});
test('Switching sections removes visible identifiers; reopening requires a fresh authorized read',async()=>{
 const x=setup(async name=>({data:name==='get_shared_application_items'?joiningRows:{bank_account_number:'111122223333',bank_account_last4:'3333'}}));
 await x.api.tenant(x.root,x.client,'app','company');const [bank,uan]=groups(x);
 await groupButton(bank,'View details').fire('click');assert.match(x.root.textContent,/111122223333/);
 assert.doesNotMatch(x.root.textContent,/Saved account ending/);
 uan.open=true;await uan.fire('toggle');assert.doesNotMatch(x.root.textContent,/111122223333/);
 bank.open=true;await bank.fire('toggle');assert.doesNotMatch(x.root.textContent,/111122223333/);
 await groupButton(bank,'View details').fire('click');assert.equal(x.calls.filter(c=>c.name==='get_shared_application_joining_detail').length,2);
});
test('A delayed detail response cannot repopulate a closed or reopened section',async()=>{
 let release;const x=setup(name=>name==='get_shared_application_items'?{data:joiningRows}:new Promise(r=>{release=r;}));
 await x.api.tenant(x.root,x.client,'app','company');const [bank,uan]=groups(x);
 const pending=groupButton(bank,'View details').fire('click');uan.open=true;await uan.fire('toggle');bank.open=true;await bank.fire('toggle');
 release({data:{bank_account_number:'111122223333'}});await pending;
 assert.doesNotMatch(x.root.textContent,/111122223333/);assert.equal(groupButton(bank,'View details').disabled,false);
});
test('Admin retains the selected section after a confirmed share without loading values',async()=>{
 const data={items:[row,...joiningRows]};const x=setup(async name=>({data:name==='admin_list_application_document_sharing'?data:true}));
 await x.api.admin(x.root,x.client,'app');const bank=groups(x)[1];bank.open=true;await bank.fire('toggle');
 await groupButton(bank,'Share item').fire('click');assert.equal(groups(x).filter(g=>g.open).length,1);
 assert.equal(groups(x).find(g=>g.open).attributes['data-sharing-category'],'bank');
 assert.equal(x.calls.some(c=>c.name.includes('get_application_joining_detail')),false);
});
test('Each sharing portal includes its scoped responsive stylesheet in the production artifact',()=>{
 for(const f of ['candidate/portal/applications.html','admin/index.html','company/applications.html','contractor/applications.html']) assert.match(fs.readFileSync(f,'utf8'),/assets\/css\/resume-sharing\.css/);
 assert.match(fs.readFileSync('scripts/build-production-artifact.js','utf8'),/'assets\/css\/resume-sharing\.css'/);
 assert.match(fs.readFileSync('assets/css/resume-sharing.css','utf8'),/max-width: 560px/);
});

test('Portable preview initializes both frames and all three views from its actual serialized scripts',async()=>{
 const {buildPreview}=require('../scripts/build-sharing-layout-preview.js');
 const html=buildPreview();
 const scripts=[...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)].map(m=>m[1]);
 assert.equal(scripts.length,1);
 assert.equal((html.match(/http-equiv="Content-Security-Policy"/g)||[]).length,1);
 assert.match(html,/connect-src 'none'/);
 assert.doesNotMatch(html,/<(?:script|link)\b[^>]*(?:src|href)=/i);
 const frames=[{srcdoc:''},{srcdoc:''}];
 const links=['company','admin','contractor'].map(mode=>({
  href:'file:///preview.html?portal='+mode, attributes:{},
  get hash(){return new URL(this.href,'file:///preview.html').hash;},
  setAttribute(k,v){this.attributes[k]=v;}
 }));
 const document={querySelectorAll:s=>s==='iframe'?frames:links};
 vm.runInNewContext(scripts[0],{document,URL});
 for(const link of links){
  link.onclick({preventDefault(){}});
  assert.equal(link.attributes['aria-current'],'page');
  assert.ok(frames[0].srcdoc.length>1000);
  assert.equal(frames[0].srcdoc,frames[1].srcdoc);
  const innerScripts=[...frames[0].srcdoc.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)].map(m=>m[1]);
  assert.equal(innerScripts.length,1);
  const root=new Element('section'),counts=new Element('p');
  const win={addEventListener(){}};
  vm.runInNewContext(innerScripts[0],{
   window:win,URL,Blob,setTimeout(){},
   document:{createElement:t=>new Element(t),createTextNode:t=>String(t),getElementById:id=>id==='sharing'?root:counts}
  });
  await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(all(root,n=>n.tagName==='DETAILS').map(n=>n.attributes['data-sharing-category']),['document','bank','uan','esic']);
  assert.match(root.textContent,/Sample_Candidate_Resume.pdf/);
  assert.match(counts.textContent,/Synthetic detail reads: 0/);
 }
});
