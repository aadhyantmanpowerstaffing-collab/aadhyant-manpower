'use strict';const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const script=fs.readFileSync('assets/js/candidate-phone-auth.js','utf8');
function fixture(options={}){let time=100000;const calls=[];const client={rpc:async(...args)=>{calls.push(['ready',...args]);return {data:options.ready!==false};},auth:{signInWithOtp:async(args)=>{calls.push(['request',args]);return {error:options.sendError?{}:null};},verifyOtp:async(args)=>{calls.push(['verify',args]);return options.verifyError?{error:{}}:{data:{session:{},user:{phone:options.phone||'919876543210',phone_confirmed_at:options.unverified?null:'2099-01-01'}}};},signOut:async()=>{calls.push(['signOut']);return {error:null};}}};const window={};vm.runInNewContext(script,{window,document:{querySelector:()=>null},Date});const flow=window.AadhyantCandidatePhoneAuth.create(client,options.signup===true,()=>time);return {flow,calls,advance:()=>time+=61000};}
test('registration requests a phone account; login never silently creates another account',async()=>{for(const signup of [true,false]){const f=fixture({signup});await f.flow.request('9876543210');assert.equal(f.calls[1][1].phone,'+919876543210');assert.equal(f.calls[1][1].options.shouldCreateUser,signup);assert.equal('channel' in f.calls[1][1].options,false);await f.flow.verify('654321');assert.equal(f.flow.verified,true);assert.equal(f.calls[2][1].type,'sms');f.flow.clear();assert.equal(f.flow.verified,false);}});
test('disabled provider and malformed mobile cannot send OTP',async()=>{const f=fixture({ready:false});await assert.rejects(()=>f.flow.request('9876543210'),/not activated/);assert.equal(f.calls.length,1);await assert.rejects(()=>f.flow.request('bad'),/valid/);});
test('cooldown applies to successful and uncertain sends with no automatic retry',async()=>{for(const sendError of [true,false]){const f=fixture({sendError});try{await f.flow.request('9876543210');}catch{}await assert.rejects(()=>f.flow.request('9876543210'),/one minute/);assert.equal(f.calls.filter(c=>c[0]==='request').length,1);}});
for(const options of [{verifyError:true},{phone:'919999999999'},{unverified:true}])test('failed or mismatched verification cannot unlock the form '+JSON.stringify(options),async()=>{const f=fixture(options);await f.flow.request('9876543210');await assert.rejects(()=>f.flow.verify('654321'));assert.equal(f.flow.verified,false);});

test('changing number while verification is in flight cannot unlock registration with a stale result',async()=>{
 const window={};let release;const calls=[];const client={rpc:async()=>({data:true}),auth:{signInWithOtp:async()=>({}),verifyOtp:async()=>{await new Promise(resolve=>release=resolve);return {data:{session:{},user:{phone:'919876543210',phone_confirmed_at:'2099-01-01'}}};},signOut:async()=>{calls.push('signOut');return {error:null};}}};
 vm.runInNewContext(script,{window,document:{querySelector:()=>null},Date});const flow=window.AadhyantCandidatePhoneAuth.create(client,true);await flow.request('9876543210');const work=flow.verify('654321');flow.clear();release();await assert.rejects(()=>work);assert.equal(flow.verified,false);assert.deepEqual(calls,['signOut']);
});

test('clearing a verified phone session signs out before another number is used',async()=>{const f=fixture();await f.flow.request('9876543210');await f.flow.verify('654321');await f.flow.clear(true);assert.equal(f.flow.verified,false);assert.equal(f.calls.filter(c=>c[0]==='signOut').length,1);});


test('changing mobile while activation status is loading prevents a stale OTP send',async()=>{
 const window={};let release;const calls=[];const client={rpc:async()=>{await new Promise(resolve=>release=resolve);return {data:true};},auth:{signInWithOtp:async(args)=>{calls.push(args);return {error:null};},verifyOtp:async()=>({}),signOut:async()=>({error:null})}};
 vm.runInNewContext(script,{window,document:{querySelector:()=>null},Date});const flow=window.AadhyantCandidatePhoneAuth.create(client,true);const work=flow.request('9876543210');await Promise.resolve();flow.clear();release();await assert.rejects(()=>work,/could not be confirmed/);assert.equal(calls.length,0);
});


test('a verified phone without an active Candidate context is signed out',async()=>{
 const handlers={},calls=[],elements={
  '[data-phone-number]':{value:'9876543210',disabled:false,focus(){}},
  '[data-phone-code]':{value:'123456',hidden:false},
  '[data-phone-request]':{disabled:false},
  '[data-phone-verify]':{disabled:false,hidden:false},
  '[data-phone-status]':{textContent:''},
  '[data-phone-change]':{addEventListener:(event,fn)=>handlers.change=fn}
 };
 for(const selector of ['[data-phone-request]','[data-phone-verify]'])elements[selector].addEventListener=(event,fn)=>handlers[selector]=fn;
 const login={hidden:true,querySelector:selector=>elements[selector]};
 const email={open:true};
 const client={rpc:async(name)=>{calls.push(['rpc',name]);return name==='get_candidate_phone_auth_status'?{data:true}:{error:{message:'no candidate'}};},
  auth:{signInWithOtp:async()=>({error:null}),verifyOtp:async()=>({data:{session:{},user:{phone:'919876543210',phone_confirmed_at:'2099-01-01'}}}),
   signOut:async()=>{calls.push(['signOut']);return {error:null};},onAuthStateChange:()=>{}}
 };
 const window={aadhyantSupabase:{client}};
 vm.runInNewContext(script,{window,document:{querySelector:s=>s==='[data-phone-login]'?login:s==='[data-email-login]'?email:null},Date,addEventListener(){}});
 await new Promise(resolve=>setImmediate(resolve));assert.equal(login.hidden,false);
 await handlers['[data-phone-request]'].call({});
 await handlers['[data-phone-verify]'].call({});
 assert.equal(calls.filter(x=>x[0]==='signOut').length,1);
 assert.match(elements['[data-phone-status]'].textContent,/no active Candidate Portal account/);
});
