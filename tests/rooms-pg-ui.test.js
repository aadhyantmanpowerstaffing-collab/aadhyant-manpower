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
async function fixture(page,{session=null,owner=null,propertyRows=[]}={}){
 const nodes=new Map(),calls=[];const node=()=>({hidden:true,children:[],dataset:{},append(...n){this.children.push(...n);},replaceChildren(...n){this.children=n;},querySelector(){return node();},closest(){return null;},classList:{},elements:{},scrollIntoView(){}});
 const get=s=>{if(!nodes.has(s))nodes.set(s,node());return nodes.get(s);};
 const connection={auth:{getSession:async()=>({data:{session}}),onAuthStateChange(){}},rpc:async(name,args)=>{calls.push({name,args});return {data:name==='room_owner_context'?owner:name==='list_room_properties'?propertyRows:[]};}};
 const document={body:{dataset:{roomsPage:page}},querySelector:s=>s==='#filters'&&page!=='browse'?null:get(s),querySelectorAll:s=>s==='[data-owner-management-nav]'?[get(s)]:[],createElement:node};
 const window={aadhyantSupabase:{client:connection,isConfigured:true},addEventListener(){}};
 const code=js.replace(" start().catch(()=>say('Accommodation access could not be confirmed. Check your portal account or try again after the module is activated.'));"," window.finished=start();");
 vm.runInNewContext(code,{document,window,location:{origin:'https://aadhyantmanpower.in',reload(){}},Intl,Date,URL,crypto,FormData:class{get(){return null;}}});await window.finished;return {get,calls};
}
test('Signed-out visitors can browse but Owner management remains gated without a session',async()=>{
 const f=await fixture('owner');assert.equal(f.get('#owner-workspace').hidden,true);assert.equal(f.calls.length,0);assert.match(f.get('#message').textContent,/Sign in/);
 const publicView=await fixture('browse');assert.ok(publicView.calls.some(c=>c.name==='list_room_properties'&&c.args.p_scope==='public'));assert.ok(!publicView.calls.some(c=>c.name==='list_room_enquiries'));
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
