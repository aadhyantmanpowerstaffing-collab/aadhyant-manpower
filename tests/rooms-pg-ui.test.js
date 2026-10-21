'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const js=fs.readFileSync('rooms-pg/rooms.js','utf8'),client=fs.readFileSync('supabase-client.js','utf8');
test('Owner login and dashboard share an isolated session while Candidate browsing retains the existing Candidate session',()=>{
 const key=pathname=>{let options;const window={location:{pathname,origin:'https://aadhyantmanpower.in'},AADHYANT_CONFIG:{expectedOrigin:'https://aadhyantmanpower.in',supabaseUrl:'https://wsuctjhbqiedttfnwjvf.supabase.co',supabaseProjectRef:'wsuctjhbqiedttfnwjvf',supabasePublishableKey:'synthetic-public-key'},supabase:{createClient:(u,k,o)=>{options=o;return {};}}};vm.runInNewContext(client,{window,URL});return options.auth;};
 const owner=key('/rooms-pg/owner/login.html');assert.ok(owner.storageKey.endsWith('-room-owner-auth-token'));assert.equal(key('/rooms-pg/owner/').storageKey,owner.storageKey);assert.notEqual(key('/contractor/login.html').storageKey,owner.storageKey);assert.equal(key('/rooms-pg/').storageKey,key('/candidate/portal/index.html').storageKey);assert.equal(key('/rooms-pg/admin.html').storageKey,key('/admin/index.html').storageKey);
});
test('Existing Candidate and Admin navigation links point to accommodation and production explicitly packages every runtime asset',()=>{
 for(const p of ['candidate/portal/index.html','candidate/portal/jobs.html','candidate/portal/profile.html'])assert.match(fs.readFileSync(p,'utf8'),/href="\/rooms-pg\/"/);
 assert.match(fs.readFileSync('admin/index.html','utf8'),/\/rooms-pg\/admin.html/);
 const build=fs.readFileSync('scripts/build-production-artifact.js','utf8');for(const f of ['index.html','admin.html','rooms.js','rooms.css','owner/index.html','owner/login.html','owner/register.html'])assert.ok(build.includes(`'rooms-pg/${f}'`));
});
async function fixture(page,{session=null,owner=null,candidate=null,propertyRows=[],filterValues={},sendError=false}={}){
 const nodes=new Map(),calls=[];const node=()=>({hidden:true,children:[],dataset:{},append(...n){this.children.push(...n);},replaceChildren(...n){this.children=n;},querySelector(){return node();},closest(){return null;},classList:{},elements:{},scrollIntoView(){},showModal(){this.open=true;},close(){this.open=false;},reset(){}});
 const get=s=>{if(!nodes.has(s))nodes.set(s,node());return nodes.get(s);};
 const connection={auth:{getSession:async()=>({data:{session}}),onAuthStateChange(){}},rpc:async(name,args)=>{calls.push({name,args});if(name==='send_room_enquiry')return sendError?{error:{message:'synthetic failure'}}:{data:'10000000-0000-4000-8000-000000000005'};return {data:name==='room_owner_context'?owner:name==='get_candidate_portal_context'?candidate:name==='list_room_properties'?(args?.p_filters?{items:propertyRows,total:propertyRows.length}:propertyRows):[]};}};
 const document={body:{dataset:{roomsPage:page}},querySelector:s=>s==='#filters'&&page!=='browse'?null:get(s),querySelectorAll:s=>s==='[data-owner-management-nav]'?[get(s)]:[],createElement:node};
 const window={aadhyantSupabase:{client:connection,isConfigured:true},addEventListener(){}};
 const code=js.replace(" start().catch(()=>say('Accommodation access could not be confirmed. Check your portal account or try again after the module is activated.'));"," window.finished=start();");
 vm.runInNewContext(code,{document,window,location:{origin:'https://aadhyantmanpower.in',reload(){}},Intl,Date,URL,crypto,FormData:class{get(name){return filterValues[name]??null;}}});await window.finished;return {get,calls};
}
test('Signed-out visitors can browse but Owner management remains gated without a session',async()=>{
 const f=await fixture('owner');assert.equal(f.get('#owner-workspace').hidden,true);assert.equal(f.calls.length,0);assert.match(f.get('#message').textContent,/Sign in/);
 const publicView=await fixture('browse');assert.ok(publicView.calls.some(c=>c.name==='list_room_properties'&&c.args.p_filters&&c.args.p_scope===undefined));assert.ok(!publicView.calls.some(c=>c.name==='list_room_enquiries'));
});
test('Pending Owner sees approval status without property/enquiry reads; active Owner uses owner-only RPC scopes',async()=>{
 const pending=await fixture('owner',{session:{user:{id:'synthetic'}},owner:{status:'pending'}});assert.equal(pending.get('#owner-workspace').hidden,true);assert.ok(!pending.calls.some(c=>c.name==='list_room_properties'));assert.match(pending.get('#message').textContent,/approval/);
 const active=await fixture('owner',{session:{user:{id:'synthetic'}},owner:{status:'active'}});assert.equal(active.get('#owner-workspace').hidden,false);assert.ok(active.calls.some(c=>c.name==='list_room_properties'&&c.args.p_scope==='owner'));assert.ok(active.calls.some(c=>c.name==='list_room_enquiries'&&c.args.p_scope==='owner'));
});
test('Enquiry markup requires explicit contact-sharing consent; image and map rendering exclude script content',()=>{
 const html=fs.readFileSync('rooms-pg/index.html','utf8');assert.match(html,/name="consent" type="checkbox" required/);assert.match(html,/share this mobile number and message/);assert.doesNotMatch(html,/name="consent"[^>]*checked/);assert.doesNotMatch(js,/\.innerHTML\s*=|\.from\s*\(/);assert.match(js,/createObjectURL/);assert.match(js,/revokeObjectURL/);assert.match(js,/canvas\.toDataURL\('image\/jpeg'/);
});

// Presentation must preserve Owner access gates while distinguishing public browsing.
test('Owner dashboard uses dedicated management navigation and keeps public browsing separate',()=>{
 const html=fs.readFileSync('rooms-pg/owner/index.html','utf8'),header=html.match(/<header[\s\S]*?<\/header>/)[0];
 assert.match(header,/Owner workspace navigation/);assert.match(header,/My Properties/);assert.match(header,/Enquiries/);assert.doesNotMatch(header,/Find a Room|Candidate Portal/);
 assert.match(html,/View public room listings/);assert.match(html,/target="_blank" rel="noopener noreferrer"/);
});
test('Owner status explains incomplete, pending and suspended states without exposing management',async()=>{
 const first=await fixture('owner',{session:{user:{id:'synthetic'}}});assert.equal(first.get('#owner-profile').hidden,false);assert.equal(first.get('#owner-status').hidden,false);assert.match(first.get('#owner-status-title').textContent,/Complete your owner profile/);
 for(const status of ['pending','suspended']){const f=await fixture('owner',{session:{user:{id:'synthetic'}},owner:{status,display_name:'Synthetic Owner',phone:'9000000000'}});assert.equal(f.get('#owner-workspace').hidden,true);assert.equal(f.get('[data-owner-management-nav]').hidden,true);assert.equal(f.get('#owner-status').hidden,false);assert.match(f.get('#owner-status-description').textContent,status==='pending'?/Each property is reviewed separately/:/listings are hidden/);assert.ok(!f.calls.some(c=>['list_room_properties','list_room_enquiries'].includes(c.name)));}
 const active=await fixture('owner',{session:{user:{id:'synthetic'}},owner:{status:'active',display_name:'Synthetic Owner',phone:'9000000000'}});assert.equal(active.get('[data-owner-management-nav]').hidden,false);assert.match(active.get('#owner-status-title').textContent,/approved/);assert.equal(active.get('#owner-profile').hidden,true);
});

test('Candidate room search removes Owner switching and verifies Candidate context before showing Dashboard and Sign Out',async()=>{
 const html=fs.readFileSync('rooms-pg/index.html','utf8'),header=html.match(/<header[\s\S]*?<\/header>/)[0];assert.doesNotMatch(header,/Owner Portal|Find a Room|Candidate Portal/);assert.match(header,/My Room Enquiries/);assert.equal((html.match(/id="my-enquiries"/g)||[]).length,1);
 // All types is an intentionally empty filter value, so it cannot be required.
 assert.doesNotMatch(html,/<select name="property_type" required/);
 const member=await fixture('browse',{session:{user:{id:'synthetic'}},candidate:[{candidate_id:'candidate-synthetic'}]});assert.equal(member.get('[data-candidate-dashboard]').textContent,'Candidate Dashboard');assert.equal(member.get('[data-candidate-dashboard]').href,'/candidate/portal/');assert.equal(member.get('#logout').hidden,false);
 const other=await fixture('browse',{session:{user:{id:'synthetic-admin'}}});assert.equal(other.get('#logout').hidden,true);assert.notEqual(other.get('[data-candidate-dashboard]').textContent,'Candidate Dashboard');
 const guest=await fixture('browse');assert.ok(!guest.calls.some(c=>c.name==='get_candidate_portal_context'));assert.equal(guest.get('#logout').hidden,true);
});

const publicRoom={id:'10000000-0000-4000-8000-000000000006',title:'Synthetic Test Room',property_type:'room',area:'Test Area',address:'Synthetic workplace area address',rent:8000,deposit:0,unit:'room',suitable_for:'any',sharing:7,capacity:10,available:3,facilities:'Drinking Water',rules:'Confirm charges',map_url:'javascript:alert(1)',photos:[],availability_updated_at:'2026-10-21'};
const nodeText=n=>[n.textContent||'',...(n.children||[]).map(nodeText)].join(' ');
test('compact cards distinguish whole-room rent from per-bed rent, use safe placeholders and label Everyone',async()=>{
 const f=await fixture('browse',{propertyRows:[publicRoom]});let text=nodeText(f.get('#properties'));assert.match(text,/entire room/);assert.match(text,/whole room, not per person/);assert.match(text,/Everyone/);assert.match(text,/Up to 7 people/);assert.match(text,/No photos added/);assert.match(text,/Send Enquiry/);assert.match(text,/Search address on Map/);assert.doesNotMatch(text,/undefined|NaN/);
 const g=await fixture('browse',{propertyRows:[{...publicRoom,unit:'bed',suitable_for:'girls'}]});text=nodeText(g.get('#properties'));assert.match(text,/one bed in a shared room/);assert.match(text,/Girls/);assert.doesNotMatch(text,/whole room/);
});
test('public filter payload excludes workplace and private scope while directions use escaped user-supplied workplace',async()=>{
 const f=await fixture('browse',{propertyRows:[publicRoom],filterValues:{suitable_for:'girls',max_sharing:'4',unit:'bed',facility:'water',sort:'rent_low',workplace:'Synthetic Company & Gate 2'}});
 const args=f.calls.find(c=>c.name==='list_room_properties').args;assert.equal(args.p_filters.max_sharing,4);assert.equal(args.p_filters.sort,'rent_low');assert.equal(args.p_filters.unit,'bed');assert.equal(args.p_filters.workplace,undefined);assert.equal(args.p_scope,undefined);assert.match(f.get('#results-count').textContent,/1 property found/);
 const walk=n=>[n,...(n.children||[]).flatMap(walk)],links=walk(f.get('#properties')).filter(n=>n.href);assert.ok(links.every(n=>n.href.startsWith('https://www.google.com/maps/')));const route=links.find(n=>n.href.includes('/dir/'));assert.ok(route);assert.equal(new URL(route.href).searchParams.get('origin'),'Synthetic Company & Gate 2');assert.equal(route.rel,'noopener noreferrer');
});
test('enquiry confirmation appears only after a confirmed write, preserves explicit consent, and failed requests retain entries',async()=>{
 for(const sendError of [false,true]){
  const f=await fixture('browse',{session:{user:{id:'synthetic-candidate'}},candidate:[{candidate_id:'synthetic'}],propertyRows:[publicRoom],sendError});
  const walk=n=>[n,...(n.children||[]).flatMap(walk)];walk(f.get('#properties')).find(n=>n.textContent==='Send Enquiry').onclick();await new Promise(setImmediate);
  const form=f.get('#enquiry-form'),button={disabled:false,closest:()=>form};form.querySelector=()=>button;form.elements={phone:{value:'9876543211'},message:{value:'Synthetic enquiry'},consent:{checked:true}};
  f.get('#enquiry-title').textContent='Synthetic Test Room';form.onsubmit({preventDefault(){},currentTarget:form});await new Promise(setImmediate);
  const write=f.calls.find(c=>c.name==='send_room_enquiry');assert.equal(write.args.p_consent,true);assert.equal(f.get('#enquiry-success').open,!sendError?true:undefined);assert.equal(form.elements.message.value,'Synthetic enquiry');
  if(!sendError){assert.match(f.get('#message').textContent,/Enquiry sent/);assert.match(nodeText(f.get('#properties')),/View Enquiry/)}
 }
 const html=fs.readFileSync('rooms-pg/index.html','utf8');assert.match(html,/id="enquiry-success"/);assert.match(html,/not a confirmed booking/);assert.doesNotMatch(html,/name="consent"[^>]*checked/);
});
