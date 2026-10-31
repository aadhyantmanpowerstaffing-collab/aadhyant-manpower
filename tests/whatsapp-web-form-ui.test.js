'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const script=fs.readFileSync('candidate/apply/form.js','utf8');
const flush=()=>new Promise(resolve=>setImmediate(resolve));
function fixture({token='a'.repeat(64),fail=false,hold=false,holdContext=false}={}){
 const calls=[],handlers={},events={},nodes={},values={full_name:' Sample Candidate ',age:'25',gender:'Male',state:'Gujarat',district:'Ahmedabad',current_village_city:'Sanand',highest_qualification:'ITI',candidate_type:'Fresher',interview_available:'Yes',pincode:'',previous_job_role:'',preferred_job_location:'',job_alert_consent:'no',same_day_alert_consent:'yes',current_job_location:'Sanand GIDC'};
 const node=()=>({textContent:'',hidden:true,className:'',value:'',focus(){this.focused=true}});
 const form=nodes['[data-application-form]']={...node(),elements:{registration_consent:{checked:true},job_alert_consent:{checked:false}},reportValidity:()=>true,addEventListener:(event,fn)=>handlers[event]=fn,querySelector:()=>button,reset(){this.resetCalled=true}};
 const button={disabled:false};let release,releaseContext;let reloads=0;
 const rpc=async(name,args)=>{calls.push({name,args});if(name==='get_whatsapp_registration_form'){if(holdContext)await new Promise(resolve=>releaseContext=resolve);return {data:{status:'ready',requirement_code:'AAD-2026-000003',job_role:'Associate',job_location:'Sanand',phone_masked:'+91XXXXXX5800'}};}
 if(hold)await new Promise(resolve=>release=resolve);return fail?{error:{message:'INTERNAL_SECRET_DETAIL'}}:{data:{status:'registered',job_alerts_selected:args.p_profile.job_alert_consent}};};
 const context={window:{aadhyantSupabase:{client:{rpc}},AadhyantRegistrationOptions:{sets:{states:['Gujarat']},districtsByState:{Gujarat:['Ahmedabad']},setupCandidateForm(){},setupStateDistrict(){},candidateSpecialization:()=>'',candidateExperience:()=>''}},document:{querySelector:s=>nodes[s]||(nodes[s]=node())},location:{hash:'#token='+token,reload(){reloads++}},URLSearchParams,FormData:class{get(k){return values[k]}},addEventListener(name,fn){events[name]=fn}};
 vm.runInNewContext(script,context);return {form,button,calls,nodes,handlers,values,release:()=>release?.(),releaseContext:()=>releaseContext?.(),changeLink:(value)=>{context.location.hash=value;events.hashchange();},get reloads(){return reloads},event:(name,value)=>events[name](value),submit:()=>handlers.submit({preventDefault(){}})};
}
test('single page collects dropdown choices and sends no editable phone/contact/job binding',async()=>{
 const f=fixture();await flush();assert.equal(f.form.hidden,false);await f.submit();const args=f.calls[1].args;
 assert.equal(args.p_profile.full_name,'Sample Candidate');assert.equal(args.p_profile.course_trade_specialization,'General');assert.equal(args.p_profile.job_alert_consent,false);
 assert.equal('mobile' in args.p_profile,false);assert.equal('requirement_id' in args,false);assert.equal(f.form.hidden,true);assert.ok(f.form.resetCalled);assert.equal(f.nodes['[data-receipt]'].hidden,false);
});
test('double submit is latched; ambiguous failure keeps entered details and allows the same idempotent request',async()=>{
 const f=fixture({fail:true,hold:true});await flush();const pending=f.submit();await flush();await f.submit();assert.equal(f.calls.length,2);assert.equal(f.button.disabled,true);f.release();await pending;
 assert.equal(f.form.hidden,false);assert.ok(!f.form.resetCalled);assert.equal(f.button.disabled,false);assert.match(f.nodes['[data-status]'].textContent,/could not be confirmed/);assert.doesNotMatch(f.nodes['[data-status]'].textContent,/INTERNAL_SECRET_DETAIL/);
});
test('missing or malformed private capability never calls an API or exposes the form',async()=>{
 for(const token of ['', 'invalid']){const f=fixture({token});await flush();assert.equal(f.calls.length,0);assert.equal(f.form.hidden,true);}
});

test('blank alert answers never submit and independent Yes/No values are sent explicitly',async()=>{const f=fixture();await flush();f.values.job_alert_consent='';await f.submit();assert.equal(f.calls.length,1);assert.match(f.nodes['[data-status]'].textContent,/Choose Yes or No/);f.values.job_alert_consent='no';await f.submit();assert.equal(f.calls[1].args.p_profile.job_alert_consent,false);assert.equal(f.calls[1].args.p_optional.same_day_alert_consent,true);});


test('a different private link clears the old job and profile before reloading, and blocks stale submission',async()=>{
 const f=fixture();await flush();f.changeLink('#token='+ 'b'.repeat(64));
 assert.equal(f.reloads,1);assert.equal(f.form.hidden,true);assert.ok(f.form.resetCalled);
 assert.equal(f.nodes['[data-job-role]'].textContent,'');assert.equal(f.nodes['[data-bound-phone]'].value,'');
 await f.submit();assert.equal(f.calls.length,1);
});
test('same-token hash updates keep the current form; missing token invalidates it',async()=>{
 const f=fixture();await flush();f.changeLink('#token='+ 'a'.repeat(64)+'&extra=1');assert.equal(f.reloads,0);assert.equal(f.form.hidden,false);
 f.changeLink('');assert.equal(f.reloads,1);assert.equal(f.form.hidden,true);
});
test('old context response cannot reopen the previous job after the link changes',async()=>{
 const f=fixture({holdContext:true});await f.submit();assert.equal(f.calls.length,1);
 f.changeLink('#token='+ 'b'.repeat(64));f.releaseContext();await flush();assert.equal(f.form.hidden,true);assert.equal(f.nodes['[data-job-role]'].textContent,'');
});
test('old submission response cannot display a receipt for a newly opened job link',async()=>{
 const f=fixture({hold:true});await flush();const pending=f.submit();await flush();
 f.changeLink('#token='+ 'b'.repeat(64));f.release();await pending;
 assert.equal(f.nodes['[data-receipt]'].hidden,true);assert.equal(f.form.hidden,true);assert.equal(f.reloads,1);
});

test('back-forward cache restores must revalidate the private link before submission',async()=>{
 const f=fixture();await flush();f.event('pagehide',{});await f.submit();assert.equal(f.calls.length,1);
 f.event('pageshow',{persisted:true});assert.equal(f.reloads,1);
});
