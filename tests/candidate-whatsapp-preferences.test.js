const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element {
  constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.events={};this.attributes={};this.disabled=false;this.checked=false;this.isConnected=true;this._text='';}
  set textContent(v){this._text=String(v);this.children=[];}get textContent(){return this._text+this.children.map(n=>typeof n==='string'?n:n.textContent).join('');}
  append(...nodes){this.children.push(...nodes);}replaceChildren(...nodes){this.children=nodes;this._text='';}
  setAttribute(k,v){this.attributes[k]=v;}addEventListener(k,f){this.events[k]=f;}
  fire(name){return this.events[name]?.({preventDefault(){}});}
}
const all=(n,p)=>[...(p(n)?[n]:[]),...n.children.filter(n=>typeof n!=='string').flatMap(n=>all(n,p))];
const base=()=>({marketing_status:'unknown',phone_masked:'+91 ******0001',profile_token:'a'.repeat(32),updated_at:null,policy_version:'candidate-job-alerts-v1',enrollment_available:true,effective_opt_in:false});
const saved=()=>({...base(),marketing_status:'opted_in',effective_opt_in:true,updated_at:'2026-09-28T07:00:00.123456+00:00'});
function setup(handler){
  const window={},root=new Element('section'),calls=[];
  vm.runInNewContext(fs.readFileSync('assets/js/candidate-whatsapp-preferences.js','utf8'),{window,document:{createElement:t=>new Element(t),createTextNode:t=>t}});
  const client={rpc:async(name,args)=>{calls.push({name,args});return handler(name,args);}};
  return{root,calls,mount:()=>window.AadhyantWhatsAppPreferences.mount(root,client),form:()=>all(root,n=>n.tagName==='FORM')[0],choice:()=>all(root,n=>n.tagName==='INPUT')[0],button:()=>all(root,n=>n.tagName==='BUTTON')[0]};
}
test('preference load is read-only and starts unchecked without marketing enrollment',async()=>{
  const x=setup(async()=>({data:base()}));await x.mount();assert.equal(x.calls.length,1);assert.equal(x.calls[0].name,'get_candidate_whatsapp_alert_preference');
  assert.equal(x.choice().checked,false);assert.match(x.root.textContent,/separate from your application and document sharing/);
});
test('explicit selection saves only the canonical preference and exact concurrency tokens',async()=>{
  const x=setup(async name=>({data:name.startsWith('get_')?base():saved()}));await x.mount();x.choice().checked=true;await x.form().fire('submit');
  const sent=JSON.parse(JSON.stringify(x.calls[1]));assert.deepEqual(sent,{name:'set_candidate_whatsapp_alert_preference',args:{p_opt_in:true,p_expected_updated_at:null,p_policy_version:'candidate-job-alerts-v1',p_profile_token:'a'.repeat(32)}});
  assert.match(x.root.textContent,/preference saved/);assert.equal(x.calls.length,2);
});
test('duplicate submit is suppressed while the write is pending',async()=>{
  let release;const x=setup(name=>name.startsWith('get_')?{data:base()}:new Promise(r=>release=r));await x.mount();x.choice().checked=true;
  const form=x.form();const pending=form.fire('submit');await form.fire('submit');assert.equal(x.calls.length,2);assert.equal(x.button().disabled,true);
  release({data:saved()});await pending;
});
test('STOP conflict refreshes authoritative status with no automatic write retry',async()=>{
  let reads=0;const stopped={...saved(),marketing_status:'opted_out',effective_opt_in:false};
  const x=setup(name=>name.startsWith('get_')?{data:++reads===1?saved():stopped}:{error:{message:'internal detail never render'}});
  await x.mount();await x.form().fire('submit');assert.equal(x.choice().checked,false);
  assert.equal(x.calls.filter(c=>c.name.startsWith('set_')).length,1);assert.match(x.root.textContent,/save was not confirmed/);assert.doesNotMatch(x.root.textContent,/internal detail/);
});
test('opt-out preserves the exact microsecond revision from the server',async()=>{
  const x=setup(name=>({data:name.startsWith('get_')?saved():{...saved(),marketing_status:'opted_out',effective_opt_in:false}}));
  await x.mount();x.choice().checked=false;await x.form().fire('submit');assert.equal(x.calls[1].args.p_expected_updated_at,saved().updated_at);assert.equal(x.calls[1].args.p_opt_in,false);
});
test('blocked account/number cannot trigger enrollment',async()=>{
  const x=setup(()=>({data:{...base(),enrollment_available:false}}));await x.mount();assert.equal(x.button().disabled,true);await x.form().fire('submit');assert.equal(x.calls.length,1);
});
test('missing backend does not expose native errors or offer a write',async()=>{
  const x=setup(()=>({error:{message:'sensitive native body'}}));await x.mount();assert.equal(x.choice(),undefined);assert.match(x.root.textContent,/profile and applications are unaffected/);assert.doesNotMatch(x.root.textContent,/sensitive native/);
});
test('malformed or raw-phone output fails closed',async()=>{
  for(const data of [{...base(),phone_masked:'+919876600001'},{...base(),policy_version:'unreviewed'},{...base(),effective_opt_in:true},{...base(),updated_at:'bad'}]){
    const x=setup(()=>({data}));await x.mount();assert.equal(x.choice(),undefined);assert.equal(x.calls.length,1);
  }
});
test('unconfirmed write and failed reread leave no enabled control',async()=>{
  let first=true;const x=setup(()=>{if(first){first=false;return{data:base()};}return{error:{message:'offline'}};});
  await x.mount();x.choice().checked=true;await x.form().fire('submit');assert.equal(x.choice(),undefined);assert.match(x.root.textContent,/Reload this page/);
});
test('older pending read cannot replace a newer preference mount',async()=>{
  let release,n=0;const x=setup(()=>++n===1?new Promise(r=>release=r):{data:saved()});
  const old=x.mount();await x.mount();release({data:base()});await old;assert.equal(x.choice().checked,true);
});
test('profile integration is gated and allowlisted independently of profile save',()=>{
  const html=fs.readFileSync('candidate/portal/profile.html','utf8'),js=fs.readFileSync('candidate/portal/candidate.js','utf8');
  assert.match(html,/<\/form>[\s\S]*data-whatsapp-preferences/);assert.match(html,/assets\/js\/candidate-whatsapp-preferences.js/);
  assert.match(js,/async function profile\(\)\{if\(!await gate\(\)\)return;void window.AadhyantWhatsAppPreferences/);
  assert.match(fs.readFileSync('scripts/build-production-artifact.js','utf8'),/'assets\/js\/candidate-whatsapp-preferences.js'/);
});
