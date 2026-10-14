'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {chatSetup,chatPrompt,chatAnswer,value}=require('./fixtures/chat-runtime-helpers.js');
const personal='Synthetic Candidate | 25 | male | Gujarat | Ahmedabad | Sanand';
const education='iti | Fitter | fresher | yes';
async function next(f,out,answer){const prompt=await chatPrompt(f,out);assert.equal(prompt.template_variables.mode,'compact');return chatAnswer(f,out,answer);}
for(const alerts of [1,2])test('compact intake registers after four answers, with independent alert choice '+alerts,async t=>{
 const f=await chatSetup(true);t.after(()=>f.db.close());let out=f.start.outbound_id;
 for(const answer of [1,personal,education]){const a=await next(f,out,answer);assert.equal(a.result.status,'next_question');out=a.result.outbound_id;}
 const a=await next(f,out,alerts);assert.equal(a.result.status,'registered');assert.equal(a.result.job_alerts_selected,alerts===1);
 assert.equal((await value(f.db,"select count(*)::int n from public.whatsapp_outbound_messages where purpose='registration_chat' and template_variables->>'kind'='question'")).n,4);
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,1);assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,1);
 assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts where id=$1',[f.id])).marketing_consent_status,alerts===1?'opted_in':'unknown');
 assert.equal((await a.run()).data.status,'replay');assert.deepEqual((await value(f.db,'select answers from private.whatsapp_registration_chats')).answers,{});
 const c=await value(f.db,'select gender,highest_qualification,candidate_type,interview_available from public.candidates');assert.deepEqual(c,{gender:'Male',highest_qualification:'ITI',candidate_type:'Fresher',interview_available:'Yes'});
});
test('compact groups accept one value per line and reject missing/extra, invalid age, unsupported enum and links without partial storage',async t=>{
 const f=await chatSetup(true);t.after(()=>f.db.close());let out=(await next(f,f.start.outbound_id,1)).result.outbound_id;
 for(const answer of ['Name | 25 | Male | Gujarat | Ahmedabad',personal+' | unexpected','Name | 15 | Male | Gujarat | Ahmedabad | Sanand','Name | bad | Male | Gujarat | Ahmedabad | Sanand','Name | 25 | invalid | Gujarat | Ahmedabad | Sanand','https://example.invalid | 25 | Male | Gujarat | Ahmedabad | Sanand']){
  const a=await next(f,out,answer);assert.equal(a.result.status,'invalid_answer');out=a.result.outbound_id;assert.deepEqual((await value(f.db,'select answers from private.whatsapp_registration_chats')).answers,{registration_consent:true});
 }
 const a=await next(f,out,personal.replaceAll(' | ','\n'));assert.equal(a.result.status,'next_question');out=a.result.outbound_id;
 const before=(await value(f.db,'select answers from private.whatsapp_registration_chats')).answers;
 for(const answer of ['ITI | Fitter | Unknown | Yes','ITI | Fitter | Fresher | Maybe','invalid | Fitter | Fresher | Yes','ITI | Fitter | Fresher | Yes | extra']){
  const a=await next(f,out,answer);assert.equal(a.result.status,'invalid_answer');out=a.result.outbound_id;assert.deepEqual((await value(f.db,'select answers from private.whatsapp_registration_chats')).answers,before);
 }
 assert.equal((await next(f,out,education.replaceAll(' | ','\n'))).result.status,'next_question');
});
test('compact consent needs the exact current button; stale registration Yes cannot subscribe at the final step',async t=>{
 const f=await chatSetup(true);t.after(()=>f.db.close());const first=f.start.outbound_id;let out=(await next(f,first,1)).result.outbound_id;
 out=(await next(f,out,personal)).result.outbound_id;out=(await next(f,out,education)).result.outbound_id;await chatPrompt(f,out);
 const stale=await chatAnswer(f,first,1);assert.equal(stale.result.status,'stale');
 const text=await chatAnswer(f,out,'Yes');assert.equal(text.result.status,'invalid_answer');assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,0);
 assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
});
test('compact cancellation clears grouped answers and prevents later prompt claims',async t=>{
 const f=await chatSetup(true);t.after(()=>f.db.close());let out=(await next(f,f.start.outbound_id,1)).result.outbound_id;out=(await next(f,out,personal)).result.outbound_id;
 const a=await chatAnswer(f,out,'CANCEL');assert.equal(a.result.status,'cancelled');assert.deepEqual((await value(f.db,'select answers from private.whatsapp_registration_chats')).answers,{});
 assert.equal((await f.db.query("select * from public.console_claim_registration_chat($1,'worker')",[out])).rows.length,0);
});
test('compact duplicate Candidate identity goes to review without merging profiles or subscribing',async t=>{
 const f=await chatSetup(true);t.after(()=>f.db.close());let out=f.start.outbound_id;for(const answer of [1,personal,education])out=(await next(f,out,answer)).result.outbound_id;
 await f.db.exec("insert into public.candidates(full_name,age,mobile,profile_status,status) values('Profile A',25,'9876543210','active','new'),('Profile B',25,'9876543210','active','new')");
 const a=await next(f,out,1);assert.equal(a.result.status,'review');assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,2);
 assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,0);assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
});

test('intake mode changed after claim cannot authorize a send; private parser has no browser grants',async t=>{
 const f=await chatSetup(true);t.after(()=>f.db.close());const out=f.start.outbound_id;
 await f.db.query("select * from public.console_claim_registration_chat($1,'worker')",[out]);
 await f.db.query("update public.whatsapp_outbound_messages set template_variables=template_variables||'{\"mode\":\"legacy\"}'::jsonb where id=$1",[out]);
 await assert.rejects(f.db.query("select public.console_registration_chat_boundary($1,'worker','1234567891','1234567890')",[out]),/eligibility changed/);
 for(const role of ['anon','authenticated','service_role'])assert.equal((await value(f.db,"select has_function_privilege($1,'private.parse_compact_registration_group(integer,text)','EXECUTE') ok",[role])).ok,false);
});
