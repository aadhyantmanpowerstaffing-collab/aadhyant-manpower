'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {flowSetup,flowProfile,value,root}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261016093617_whatsapp_single_page_registration.sql'),'utf8');
async function setup(){
 const f=await flowSetup();
 await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014122353_whatsapp_compact_chat_registration.sql'),'utf8'));
 await f.db.exec('alter table public.candidates add column pincode text,add column total_experience text,add column previous_job_role text,add column preferred_job_location text;');
 await f.db.exec(migration);
 // Synthetic already-delivered canonical reply; production issuance is separately tested below.
 f.token='c'.repeat(64);
 await f.db.query("update private.whatsapp_console_config set registration_web_enabled=true");
 await f.db.query('update public.whatsapp_outbound_messages set registration_web_token=$1 where id=$2',[f.token,f.reply.message_id]);
 await f.db.query("insert into private.whatsapp_web_registrations(token_hash,reply_id,inbound_id,expires_at) values(sha256(convert_to($1,'UTF8')),$2,$3,clock_timestamp()+interval '1 hour')",[f.token,f.reply.message_id,f.inbound]);
 f.profile={...flowProfile,consent_policy_version:'wa-web-registration-alerts-v1'};
 f.context=async(token=f.token)=>(await value(f.db,'select public.get_whatsapp_registration_form($1) data',[token])).data;
 f.submit=async(profile=f.profile,optional={},token=f.token)=>(await value(f.db,'select public.submit_whatsapp_registration_form($1,$2,$3) data',[token,JSON.stringify(profile),JSON.stringify(optional)])).data;
 return f;
}
test('private form saves one canonical profile/application, separate all-job permission and safe idempotent receipt',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 const c=await f.context();assert.equal(c.status,'ready');assert.equal(c.phone_masked.slice(0,9),'+91XXXXXX');assert.ok(!JSON.stringify(c).includes('Synthetic Candidate'));
 const result=await f.submit(f.profile,{pincode:'382110',preferred_job_location:'Sanand'});assert.deepEqual(result,{status:'registered',job_alerts_selected:true});
 assert.deepEqual(await f.submit({...f.profile,job_alert_consent:false}),result);
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,1);
 assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,1);
 assert.equal((await value(f.db,'select pincode from public.candidates')).pincode,'382110');
 const w=await value(f.db,'select marketing_consent_status,consent_scope,consent_source,consent_policy_version from public.whatsapp_contacts');
 assert.deepEqual(w,{marketing_consent_status:'opted_in',consent_scope:'all_job_alerts',consent_source:'whatsapp_web',consent_policy_version:'wa-web-registration-alerts-v1'});
 assert.equal((await f.context()).status,'completed');
});
test('unchecked optional alert choice completes registration without enrolling',async t=>{
 const f=await setup();t.after(()=>f.db.close());assert.equal((await f.submit({...f.profile,job_alert_consent:false})).status,'registered');
 assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
});
test('invalid capability, expired link and undelivered reply expose no context and cannot submit',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 for(const token of ['', 'z'.repeat(64),'d'.repeat(64)]){assert.equal(await f.context(token),null);await assert.rejects(f.submit(f.profile,{},token));}
 await f.db.exec("update private.whatsapp_web_registrations set expires_at=clock_timestamp()-interval '1 second'");assert.equal(await f.context(),null);await assert.rejects(f.submit());
 await f.db.exec("update private.whatsapp_web_registrations set expires_at=clock_timestamp()+interval '1 hour';update public.whatsapp_outbound_messages set state='failed' where registration_web_token is not null");
 assert.equal(await f.context(),null);await assert.rejects(f.submit());
});
test('STOP, contact ambiguity and closed jobs prevent form submission at final boundary',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 await f.db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp'");assert.equal(await f.context(),null);await assert.rejects(f.submit());
 await f.db.exec("update public.whatsapp_contacts set marketing_consent_status='unknown',opted_out_at=null,opt_out_source=null,resolution_status='ambiguous'");await assert.rejects(f.submit());
 await f.db.exec("update public.whatsapp_contacts set resolution_status='unresolved';update public.employer_requirements set requirement_stage='closed'");await assert.rejects(f.submit());
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,0);
});
test('tampered profile fields, absent consent and malformed optional details leave no partial records',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 for(const profile of [{...f.profile,registration_consent:false},{...f.profile,contact_id:f.id},{...f.profile,age:'15'},{...f.profile,job_alert_consent:'true'}])await assert.rejects(f.submit(profile));
 for(const optional of [{pincode:'invalid'},{mobile:'9999999999'},{pincode:123456}])await assert.rejects(f.submit(f.profile,optional));
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,0);
 assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,0);
});
test('duplicate identity is held for review without creating profiles or new alert permission',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 await f.db.query("insert into public.candidates(mobile,full_name,age,status,profile_status) select indian_mobile_key,'Existing',25,'new','active' from public.whatsapp_contacts");
 await f.db.query("insert into public.candidates(whatsapp_number,full_name,age,status,profile_status) select indian_mobile_key,'Other',25,'new','active' from public.whatsapp_contacts");
 await assert.rejects(f.submit());assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,2);
 assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
});
test('anon has only capability RPC access, private state/helper and sender claim remain inaccessible',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 assert.equal((await value(f.db,"select has_table_privilege('anon','private.whatsapp_web_registrations','SELECT') ok")).ok,false);
 assert.equal((await value(f.db,"select has_function_privilege('anon','private.complete_whatsapp_registration(uuid,uuid,uuid,jsonb,text)','EXECUTE') ok")).ok,false);
 assert.equal((await value(f.db,"select has_function_privilege('anon','public.console_claim_registration_reply(uuid,text)','EXECUTE') ok")).ok,false);
 assert.equal((await value(f.db,"select has_function_privilege('anon','public.submit_whatsapp_registration_form(text,jsonb,jsonb)','EXECUTE') ok")).ok,true);
 await f.db.exec('set role anon');assert.equal((await f.context()).status,'ready');assert.equal((await f.submit()).status,'registered');
});
test('enabled routing issues one bound form capability through the canonical lease and refuses a changed send mode',async t=>{
 const {replySetup}=require('./fixtures/whatsapp-console-runtime-helpers.js');
 const f=await replySetup();t.after(()=>f.db.close());
 await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014092316_whatsapp_registration_flow.sql'),'utf8'));
 await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014104931_whatsapp_chat_registration.sql'),'utf8'));
 await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014122353_whatsapp_compact_chat_registration.sql'),'utf8'));
 await f.db.exec(migration);
 assert.equal((await value(f.db,'select registration_web_enabled from private.whatsapp_console_config')).registration_web_enabled,false);
 await f.db.exec('update private.whatsapp_console_config set registration_web_enabled=true,registration_chat_enabled=true');
 assert.deepEqual((await value(f.db,'select public.console_process_registration_chat($1,null) data',[f.inbound])).data,{handled:false});
 const r=(await f.db.query("select * from public.console_claim_registration_reply($1,'web-worker')",[f.inbound])).rows[0];
 assert.match(r.web_token,/^[a-f0-9]{64}$/);assert.equal(r.flow_token,null);assert.equal(r.flow_id,null);
 assert.equal((await value(f.db,'select public.get_whatsapp_registration_form($1) data',[r.web_token])).data,null);
 assert.equal((await f.db.query("select * from public.console_claim_registration_reply($1,'replay-worker')",[f.inbound])).rows.length,0);
 await f.db.exec('update private.whatsapp_console_config set registration_web_enabled=false');
 await assert.rejects(f.db.query("select public.console_registration_boundary($1,'web-worker','1234567891','1234567890')",[r.message_id]));
 await f.db.exec('update private.whatsapp_console_config set registration_web_enabled=true');
 await f.db.query("select public.console_registration_boundary($1,'web-worker','1234567891','1234567890')",[r.message_id]);
 await f.db.query("select public.mark_whatsapp_outbound_sent($1,'web-worker','wamid.webform',null)",[r.message_id]);
 assert.equal((await value(f.db,'select public.get_whatsapp_registration_form($1) data',[r.web_token])).data.status,'ready');
});
test('a checked alert choice uses submit time and an unchecked choice preserves independent existing permission',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 await f.db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source='written_permission',consent_scope='all_job_alerts',consent_policy_version='independent',consent_recorded_at=clock_timestamp()");
 const before=await value(f.db,'select consent_recorded_at,consent_policy_version from public.whatsapp_contacts');
 await f.submit({...f.profile,job_alert_consent:false});
 assert.deepEqual(await value(f.db,'select consent_recorded_at,consent_policy_version from public.whatsapp_contacts'),before);
});
