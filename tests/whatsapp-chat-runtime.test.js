'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {chatSetup,chatPrompt,chatAnswer,value}=require('./fixtures/chat-runtime-helpers.js');

const chatAnswers=[1,'Synthetic Candidate','25',1,4,'Fitter','Gujarat','Ahmedabad','Sanand',1,1];
async function chatUntilAlerts(f){let outbound=f.start.outbound_id;for(const answer of chatAnswers){await chatPrompt(f,outbound);const a=await chatAnswer(f,outbound,answer);assert.equal(a.result.status,'next_question');outbound=a.result.outbound_id;}return outbound;}
for(const alerts of [1,2])test('chat completes canonical registration once with independently chosen all-job consent: '+alerts,async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());const out=await chatUntilAlerts(f);await chatPrompt(f,out);const result=await chatAnswer(f,out,alerts);
 assert.equal(result.result.status,'registered');assert.equal(result.result.job_alerts_selected,alerts===1);
 const contact=await value(f.db,'select marketing_consent_status,consent_source,sharing_subscription from public.whatsapp_contacts where id=$1',[f.id]);
 assert.equal(contact.marketing_consent_status,alerts===1?'opted_in':'unknown');if(alerts===1){assert.equal(contact.consent_source,'whatsapp_chat');assert.equal(contact.sharing_subscription.scope,'all');}
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,1);assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,1);
 assert.equal((await result.run()).data.status,'replay');assert.equal((await value(f.db,"select count(*)::int n from public.audit_logs where action='whatsapp.chat_registration_completed'")).n,1);
 const reports=(await value(f.db,'select public.admin_console_replies($1,0) data',[f.campaign])).data;assert.ok(reports.some(r=>r.registration_channel==='chat'&&r.application_id&&r.job_alert_consent===(alerts===1)));assert.equal(JSON.stringify(reports).includes('Synthetic Candidate'),false);
 assert.deepEqual((await value(f.db,'select answers from private.whatsapp_registration_chats')).answers,{});
 await chatPrompt(f,result.result.outbound_id);assert.equal((await f.db.query('select * from public.console_claim_registration_chat($1,$2)',[result.result.outbound_id,'replay-worker'])).rows.length,0);
 assert.equal((await value(f.db,"select bool_and(template_variables::text not like '%Synthetic Candidate%') ok from public.whatsapp_outbound_messages where purpose='registration_chat'")).ok,true);
});
test('consent text Yes never grants consent; No on exact registration button cancels without Candidate creation',async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());await chatPrompt(f,f.start.outbound_id);const invalid=await chatAnswer(f,f.start.outbound_id,'Yes');assert.equal(invalid.result.status,'invalid_answer');
 assert.deepEqual((await value(f.db,'select answers from private.whatsapp_registration_chats')).answers,{});
 await chatPrompt(f,invalid.result.outbound_id);const no=await chatAnswer(f,invalid.result.outbound_id,2);assert.equal(no.result.status,'cancelled');
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,0);assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
});
test('chat rejects stale/wrong prompt buttons and cross-contact session claims without shifting questions',async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());const out=f.start.outbound_id;await chatPrompt(f,out);
 for(const options of [{context:'wamid.wrong'},{session:'00000000-0000-0000-0000-000000000099'},{step:11}]){
  const a=await chatAnswer(f,out,1,options);assert.ok(['stale','stale_button'].includes(a.result.status));
 }
 assert.equal((await value(f.db,'select step from private.whatsapp_registration_chats')).step,0);
 const other=(await value(f.db,"insert into public.whatsapp_contacts(provider_address,indian_mobile_key) values('+919876543211','9876543211') returning id")).id;
 const a=await chatAnswer(f,out,1,{contact:other});assert.equal(a.result.status,'no_session');
 assert.equal((await value(f.db,'select step from private.whatsapp_registration_chats')).step,0);
});
test('STOP after claim and closed job prevent chat provider boundary; cancellation clears partial data',async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());const out=f.start.outbound_id;
 const claimed=(await f.db.query('select * from public.console_claim_registration_chat($1,$2)',[out,'worker'])).rows[0];assert.ok(claimed);
 await f.db.exec("update public.whatsapp_contacts set transactional_contact_status='suppressed'");
 await assert.rejects(f.db.query("select public.console_registration_chat_boundary($1,'worker','1234567891','1234567890')",[out]),/eligibility changed/);
 await f.db.exec("update public.whatsapp_contacts set transactional_contact_status='unknown';update public.employer_requirements set requirement_stage='closed'");
 await assert.rejects(f.db.query("select public.console_registration_chat_boundary($1,'worker','1234567891','1234567890')",[out]),/eligibility changed/);
 await f.db.query('select public.console_cancel_registration_chat($1)',[f.id]);assert.equal((await value(f.db,'select status from private.whatsapp_registration_chats')).status,'cancelled');
});
test('ambiguous chat lease cannot auto-send twice; explicit RESUME creates a new prompt for the same step',async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());const out=f.start.outbound_id;
 await f.db.query("select * from public.console_claim_registration_chat($1,'worker')",[out]);await f.db.query("select public.console_registration_chat_boundary($1,'worker','1234567891','1234567890')",[out]);
 await f.db.query("update public.whatsapp_outbound_messages set lease_expires_at=clock_timestamp()-interval '1 second' where id=$1",[out]);
 assert.equal((await f.db.query("select * from public.console_claim_registration_chat($1,'replay')",[out])).rows.length,0);
 assert.equal((await value(f.db,'select send_phase from public.whatsapp_outbound_messages where id=$1',[out])).send_phase,'reconciliation_required');
 const a=await chatAnswer(f,out,'RESUME',{context:null});assert.equal(a.result.status,'resumed');assert.notEqual(a.result.outbound_id,out);await chatPrompt(f,a.result.outbound_id);
 assert.equal((await value(f.db,'select step from private.whatsapp_registration_chats')).step,0);
});
for(const scenario of ['expired','unsigned','future','identity-conflict','late-stop'])test('chat finalization fails closed: '+scenario,async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());const out=await chatUntilAlerts(f);await chatPrompt(f,out);
 if(scenario==='expired')await f.db.exec("update private.whatsapp_registration_chats set expires_at=clock_timestamp()-interval '1 second'");
 if(scenario==='unsigned')await f.db.exec('update public.whatsapp_webhook_events set signature_verified=false');
 if(scenario==='identity-conflict')await f.db.exec("insert into public.candidates(full_name,age,mobile,profile_status,status) values('Someone else',25,'9876543210','active','new')");
 if(scenario==='late-stop')await f.db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture'");
 const a=await chatAnswer(f,out,1,scenario==='future'?{timestamp:new Date(Date.now()+3600000).toISOString()}:{});
 assert.notEqual(a.result.status,'registered');assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,0);
 assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,scenario==='late-stop'?'opted_out':'unknown');
});
test('chat private storage and RPC grants cannot be reached by browser roles',async t=>{
 const f=await chatSetup();t.after(()=>f.db.close());for(const role of ['anon','authenticated']){
  for(const fn of ['public.console_process_registration_chat(uuid,text)','public.console_claim_registration_chat(uuid,text)','public.console_cancel_registration_chat(uuid)','private.complete_whatsapp_registration(uuid,uuid,uuid,jsonb,text)'])assert.equal((await value(f.db,'select has_function_privilege($1,$2,\'EXECUTE\') ok',[role,fn])).ok,false);
  assert.equal((await value(f.db,"select has_table_privilege($1,'private.whatsapp_registration_chats','SELECT') ok",[role])).ok,false);
 }
});
