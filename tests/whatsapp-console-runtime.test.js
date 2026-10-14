'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {root,value,setup,sync,importOne,subscribe,prep,template,requirement,senderSetup,queuedSender,replySetup,flowSetup,flowProfile,submitFlow}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const consoleMigration=fs.readFileSync(path.join(root,'supabase/migrations/20261013105042_whatsapp_campaign_console.sql'),'utf8');
test('synced approved template binds server metadata and immutable preview; language/version are not browser arguments',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);const c=(await prep(db,id,tid)).id;
 const row=await value(db,'select template_name,template_language,template_version,console_template_snapshot from public.whatsapp_campaigns where id=$1',[c]);
 assert.equal(row.template_language,'en');assert.equal(row.template_version,'1');assert.equal(row.console_template_snapshot.body,template.components[0].text);
 assert.equal((await prep(db,id,tid)).id,c);await sync(db,[{...template,components:[{type:'BODY',text:'Changed {{1}} / {{2}}'},template.components[1]]}]);
 await assert.rejects(db.query('select public.admin_console_approve($1)',[c]),/Template changed/);
});
test('permission provenance is explicit; imports/lists never opt in and STOP cannot be overridden',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);
 await db.query('select public.admin_console_label_contacts($1::uuid[],$2::jsonb,$3::jsonb)',[[id],'["ITI Leads"]','["Sanand"]']);
 assert.equal((await value(db,"select public.admin_console_contacts('ITI Leads','Sanand',0) list")).list.length,1);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
 await assert.rejects(db.query('select public.admin_console_record_consent($1,$2,now())',[id,'imported_file']),/Actual consent/);
 await db.query("select public.admin_console_record_consent($1,'phone_call',now())",[id]);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_in');
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp_inbound'");
 await assert.rejects(db.query("select public.admin_console_record_consent($1,'phone_call',now())",[id]),/re-enroll/);
});
test('schedule persists on canonical outbox; sender readiness and explicit approval precede queueing',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);const when=new Date(Date.now()+3600000).toISOString(),c=(await prep(db,id,tid,undefined,when)).id;
 await assert.rejects(db.query('select public.admin_console_queue($1)',[c]),/not verified/);
 await db.exec('update private.whatsapp_console_config set sender_ready=true');
 await assert.rejects(db.query('select public.admin_console_queue($1)',[c]),/Approved/);
 await db.query('select public.admin_console_approve($1)',[c]);await db.query('select public.admin_console_queue($1)',[c]);await db.query('select public.admin_console_queue($1)',[c]);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,1);
 assert.equal(new Date((await value(db,'select next_attempt_at from public.whatsapp_outbound_messages')).next_attempt_at).toISOString(),when);
});
test('Meta rejection, stale metadata, no template, past schedule and anonymous RPCs fail closed',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);
 await assert.rejects(prep(db,id,tid,undefined,new Date(Date.now()-60000).toISOString()),/future time/);
 await sync(db,[{...template,status:'REJECTED'}]);await assert.rejects(prep(db,id,tid));
 await sync(db);await db.exec("update public.whatsapp_template_catalog set synced_at=now()-interval '25 hours'");await assert.rejects(prep(db,id,tid));
 for(const role of ['anon','authenticated'])assert.equal((await value(db,"select has_function_privilege($1,'public.console_sync_templates(jsonb)','execute') ok",[role])).ok,false);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamp with time zone)','execute') ok")).ok,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_console_contacts()'),/Admin access/);
});
test('reports display actual canonical delivery states and masked recipients',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);const c=(await prep(db,id,tid)).id;
 await db.query('select public.admin_console_approve($1)',[c]);await db.exec('update private.whatsapp_console_config set sender_ready=true');await db.query('select public.admin_console_queue($1)',[c]);
 await db.exec("update public.whatsapp_outbound_messages set state='read',sent_at=now(),delivered_at=now(),read_at=now()");
 const report=(await value(db,'select public.admin_console_report($1) data',[c])).data;assert.equal(report[0].status,'read');assert.equal(report[0].mobile_masked,'+91XXXXXX3210');
 const campaigns=(await value(db,'select public.admin_console_campaigns() data')).data;assert.equal(campaigns[0].read,1);
});
test('extra template parameters and media headers are incompatible; list/tag audience filters precede pagination',async t=>{
 const db=await setup();t.after(()=>db.close());await sync(db,[{...template,components:[{type:'BODY',text:'{{1}} {{2}} {{4}}'},template.components[1]]}]);assert.equal((await value(db,'select compatible from public.whatsapp_template_catalog')).compatible,false);
 await sync(db,[{...template,components:[...template.components,{type:'HEADER',format:'IMAGE'}]}]);assert.equal((await value(db,'select compatible from public.whatsapp_template_catalog')).compatible,false);
 await sync(db);await sync(db,[{...template,components:[template.components[1]]}]);assert.equal((await value(db,'select compatible from public.whatsapp_template_catalog')).compatible,false);
 const id=await importOne(db);await subscribe(db,id);await db.query('select public.admin_console_label_contacts($1::uuid[],$2::jsonb,$3::jsonb)',[[id],'["ITI"]','["Sanand"]']);
 assert.equal((await value(db,"select public.admin_console_audience($1,'contacts','all',0,'ITI','Sanand') data",[requirement])).data.length,1);
 assert.equal((await value(db,"select public.admin_console_audience($1,'contacts','all',0,'Other','Sanand') data",[requirement])).data.length,0);
});
test('numbers-only import normalizes/deduplicates without invented demographics or consent; malformed batch rolls back',async t=>{
 const db=await setup();t.after(()=>db.close());const result=(await value(db,'select public.admin_console_import_numbers($1::jsonb) data',['["+91 9876543210","9876543210"]'])).data;
 assert.equal(result.added,1);assert.equal(result.reused,1);let contact=await value(db,'select marketing_consent_status,imported_profile from public.whatsapp_contacts');assert.equal(contact.marketing_consent_status,'unknown');assert.deepEqual(contact.imported_profile,{Source:'number_import'});
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture'");await db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543210"]']);assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_out');
 await assert.rejects(db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543211","bad"]']),/Invalid Indian/);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});
test('console installation rejects retained legacy data and rolls back all new objects',async t=>{
 const db=await setup(false);t.after(()=>db.close());await importOne(db);await assert.rejects(db.exec(consoleMigration),/Complete the authorized retirement purge/);await db.exec('rollback');assert.equal((await value(db,"select to_regclass('public.whatsapp_template_catalog') id")).id,null);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});
test('sender claim honors readiness, schedule and canonical campaign identity; boundary rechecks changed template',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign,tid}=await queuedSender(db);await db.exec('update private.whatsapp_console_config set sender_ready=false');assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows.length,0);await db.exec('update private.whatsapp_console_config set sender_ready=true');const msg=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows[0];assert.ok(msg);await db.query("update public.whatsapp_template_catalog set status='REJECTED' where id=$1",[tid]);await assert.rejects(db.query("select public.console_provider_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'test-worker']),/Sender or template/);assert.equal((await value(db,'select send_phase from public.whatsapp_outbound_messages')).send_phase,'claimed');});
test('late STOP and cancelled job prevent provider boundary; anonymous/service grants remain separated',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign,id}=await queuedSender(db);const msg=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows[0];await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture' where id=$1",[id]);await assert.rejects(db.query("select public.console_provider_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'test-worker']),/suppressed/);await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_in',opted_out_at=null,opt_out_source=null;update public.employer_requirements set requirement_stage='closed'");await assert.rejects(db.query("select public.console_provider_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'test-worker']),/eligibility changed/);const grants=await value(db,"select has_function_privilege('anon','public.console_claim_campaign(uuid,text)','EXECUTE') anon,has_function_privilege('authenticated','public.console_sender_connection(text,text)','EXECUTE') client,has_function_privilege('service_role','public.console_claim_campaign(uuid,text)','EXECUTE') backend");assert.deepEqual(grants,{anon:false,client:false,backend:true});});
test('future schedule is not claimed; expired provider-call lease requires reconciliation and is never reclaimed',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign}=await queuedSender(db);await db.exec("update public.whatsapp_outbound_messages set next_attempt_at=clock_timestamp()+interval '1 hour'");assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows.length,0);await db.exec('update public.whatsapp_outbound_messages set next_attempt_at=clock_timestamp()');const msg=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows[0];assert.equal((await value(db,"select public.console_provider_boundary($1,$2,'1234567891','1234567890') yes",[msg.message_id,'test-worker'])).yes,true);await db.exec("update public.whatsapp_outbound_messages set lease_expires_at=clock_timestamp()-interval '1 second'");assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'next-worker'])).rows.length,0);assert.equal((await value(db,'select send_phase from public.whatsapp_outbound_messages')).send_phase,'reconciliation_required');});
test('imported Interested reply is correlated and idempotent, records registration-needed without inventing a candidate',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign,id}=await queuedSender(db);await db.exec("update public.whatsapp_outbound_messages set state='sent',provider_message_id='wamid.fixture'");const m=(await value(db,"insert into public.whatsapp_inbound_messages(id,contact_id,message_type,action_id,provider_timestamp,correlation_key) values(gen_random_uuid(),$1,'button','INTERESTED',clock_timestamp(),'wamid.fixture') returning id",[id])).id;const result=(await value(db,'select public.console_process_interested($1) data',[m])).data;assert.equal(result.status,'registration_required');await db.query('select public.console_process_interested($1)',[m]);assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='whatsapp.interested_registration_required'")).n,1);assert.equal((await value(db,"select public.admin_console_replies($1,0) data",[campaign])).data[0].last_error_category,'registration_required');assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);});
test('future queueing cannot claim automatic scheduling before scheduler installation',async t=>{const db=await senderSetup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);await db.query("select public.console_sender_connection('1234567891','1234567890')");const c=(await prep(db,id,tid,undefined,new Date(Date.now()+3600000).toISOString())).id;await db.query('select public.admin_console_approve($1)',[c]);await assert.rejects(db.query('select public.admin_console_queue($1)',[c]),/Automatic scheduler/);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);});

test('registration reply reuses canonical outbox, preserves unknown consent, and is once per original job message',async t=>{
 const {db,inbound,campaign}=await replySetup();t.after(()=>db.close());
 const claimed=(await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'reply-worker'])).rows;
 assert.equal(claimed.length,1);assert.equal(claimed[0].message_type,'session_text');assert.equal(claimed[0].template_variables.requirement_code,'TEST_JOB');
 assert.equal((await value(db,"select public.console_registration_boundary($1,$2,'1234567891','1234567890') ok",[claimed[0].message_id,'reply-worker'])).ok,true);
 await db.query("select public.mark_whatsapp_outbound_sent($1,$2,'wamid.registration-reply',null)",[claimed[0].message_id,'reply-worker']);
 assert.equal((await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'replay'])).rows.length,0);
 await db.exec(`insert into public.whatsapp_inbound_messages select gen_random_uuid(),contact_id,message_type,action_id,provider_timestamp,processing_status,processed_at,last_error_category,last_error_code,redacted_response,correlation_key,application_id,created_at,webhook_event_id from public.whatsapp_inbound_messages where id='${inbound}'`);
 const other=(await value(db,'select id from public.whatsapp_inbound_messages where id<>$1 order by created_at desc limit 1',[inbound])).id;
 assert.equal((await db.query('select * from public.console_claim_registration_reply($1,$2)',[other,'second-button'])).rows.length,0);
 assert.equal((await value(db,"select count(*)::int n from public.whatsapp_outbound_messages where purpose='interested_registration'")).n,1);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
 assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);
 assert.equal((await value(db,'select public.admin_console_replies($1,0) data',[campaign])).data[0].registration_reply_status,'sent');
 for(const role of ['anon','authenticated'])assert.equal((await value(db,"select has_function_privilege($1,'public.console_claim_registration_reply(uuid,text)','execute') ok",[role])).ok,false);
});
for(const scenario of ['expired','future','unsigned','wrong-correlation','closed-job','blocked','stop'])test('registration reply fails closed: '+scenario,async t=>{
 const {db,inbound}=await replySetup();t.after(()=>db.close());
 const changes={expired:"update public.whatsapp_inbound_messages set provider_timestamp=clock_timestamp()-interval '25 hours'",future:"update public.whatsapp_inbound_messages set provider_timestamp=clock_timestamp()+interval '1 hour'",unsigned:'update public.whatsapp_webhook_events set signature_verified=false','wrong-correlation':"update public.whatsapp_inbound_messages set correlation_key='wamid.other'",'closed-job':"update public.employer_requirements set requirement_stage='closed'",blocked:"update public.whatsapp_contacts set resolution_status='blocked'",stop:"update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture'"};
 await db.exec(changes[scenario]);assert.equal((await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'worker'])).rows.length,0);
});
test('STOP and session expiry after reply claim prevent provider boundary; expired lease never reclaims',async t=>{
 const {db,inbound}=await replySetup();t.after(()=>db.close());const msg=(await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'worker'])).rows[0];
 await db.exec("update public.whatsapp_contacts set transactional_contact_status='suppressed'");
 await assert.rejects(db.query("select public.console_registration_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'worker']),/eligibility changed/);
 await db.exec("update public.whatsapp_contacts set transactional_contact_status='unknown';update public.whatsapp_inbound_messages set provider_timestamp=clock_timestamp()-interval '25 hours'");
 await assert.rejects(db.query("select public.console_registration_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'worker']),/eligibility changed/);
 await db.exec("update public.whatsapp_inbound_messages set provider_timestamp=clock_timestamp();update public.whatsapp_outbound_messages set lease_expires_at=clock_timestamp()-interval '1 second' where purpose='interested_registration'");
 assert.equal((await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'replay'])).rows.length,0);
 assert.equal((await value(db,"select send_phase from public.whatsapp_outbound_messages where purpose='interested_registration'")).send_phase,'terminal');
});
test('expired provider-call lease reconciles even after the service window closes',async t=>{
 const {db,inbound}=await replySetup();t.after(()=>db.close());const msg=(await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'worker'])).rows[0];
 await db.query("select public.console_registration_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'worker']);
 await db.exec("update public.whatsapp_inbound_messages set provider_timestamp=clock_timestamp()-interval '25 hours';update public.whatsapp_outbound_messages set lease_expires_at=clock_timestamp()-interval '1 second' where purpose='interested_registration'");
 assert.equal((await db.query('select * from public.console_claim_registration_reply($1,$2)',[inbound,'replay'])).rows.length,0);
 assert.equal((await value(db,"select send_phase from public.whatsapp_outbound_messages where purpose='interested_registration'")).send_phase,'reconciliation_required');
});

test('Flow submission creates canonical basic registration/application and explicit all-job consent once',async t=>{
 const f=await flowSetup();t.after(()=>f.db.close());assert.match(f.reply.flow_token,/^[a-f0-9]{64}$/);assert.equal(f.reply.flow_id,'1234567899');
 const s=await submitFlow(f);assert.equal((await s.result()).data.status,'registered');
 const candidate=await value(f.db,'select * from public.candidates');assert.equal(candidate.mobile,'9876543210');assert.equal(candidate.profile_completion_status,'incomplete');assert.equal(candidate.profile_status,'active');
 const contact=await value(f.db,'select * from public.whatsapp_contacts');assert.equal(contact.marketing_consent_status,'opted_in');assert.equal(contact.consent_source,'whatsapp_flow');assert.equal(contact.sharing_subscription.scope,'all');assert.equal(contact.consent_policy_version,'wa-registration-alerts-v1');
 assert.equal((await s.result()).data.status,'already_processed');const again=await submitFlow(f);assert.equal((await again.result()).data.status,'already_completed');
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,1);assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,1);
 assert.equal((await value(f.db,"select count(*)::int n from public.audit_logs where action='whatsapp.flow_registration_completed'")).n,1);
 const report=(await value(f.db,'select public.admin_console_replies($1,0) data',[f.campaign])).data;assert.ok(report.some(r=>r.action_id==='REGISTRATION_SUBMIT'&&r.application_id&&r.job_alert_consent===true));await f.db.query('select public.console_registration_flow_failure($1)',[s.m]);assert.equal((await value(f.db,'select processing_status from public.whatsapp_inbound_messages where id=$1',[s.m])).processing_status,'processed');
 const redacted=await value(f.db,'select redacted_response from public.whatsapp_inbound_messages where id=$1',[s.m]);assert.equal('full_name' in redacted.redacted_response,false);
 for(const role of ['anon','authenticated'])assert.equal((await value(f.db,"select has_function_privilege($1,'public.console_process_registration_flow(uuid)','EXECUTE') ok",[role])).ok,false);
});
test('unchecked alert consent registers the Candidate without subscribing',async t=>{const f=await flowSetup();t.after(()=>f.db.close());const s=await submitFlow(f,{...flowProfile,job_alert_consent:false});await s.result();const c=await value(f.db,'select marketing_consent_status,consent_source from public.whatsapp_contacts');assert.equal(c.marketing_consent_status,'unknown');assert.equal(c.consent_source,null);});
for(const scenario of ['no-registration-consent','string-alert-consent','wrong-policy','wrong-token','wrong-contact','unsigned','stop','closed-job','expired','identity-conflict'])test('Flow registration rejects '+scenario+' without partial Candidate/application/consent changes',async t=>{
 const f=await flowSetup();t.after(()=>f.db.close());let profile={...flowProfile},overrides={};
 if(scenario==='no-registration-consent')profile.registration_consent=false;
 if(scenario==='string-alert-consent')profile.job_alert_consent='true';
 if(scenario==='wrong-policy')profile.consent_policy_version='forged';
 if(scenario==='wrong-token')overrides.token='b'.repeat(64);
 if(scenario==='wrong-contact'){overrides.contact=(await value(f.db,"insert into public.whatsapp_contacts(provider_address,indian_mobile_key) values('+919876543211','9876543211') returning id")).id;}
 if(scenario==='unsigned')await f.db.exec('update public.whatsapp_webhook_events set signature_verified=false');
 if(scenario==='stop')await f.db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture'");
 if(scenario==='closed-job')await f.db.exec("update public.employer_requirements set requirement_stage='closed'");
 if(scenario==='expired')await f.db.exec("update public.whatsapp_outbound_messages set created_at=clock_timestamp()-interval '25 hours' where purpose='interested_registration'");
 if(scenario==='identity-conflict')await f.db.exec("insert into public.candidates(full_name,age,mobile,profile_status,status) values('Different person',25,'9876543210','active','new')");
 const before=await value(f.db,'select count(*)::int n from public.candidates');const s=await submitFlow(f,profile,overrides);await assert.rejects(s.result());
 assert.equal((await value(f.db,'select count(*)::int n from public.candidates')).n,before.n);assert.equal((await value(f.db,'select count(*)::int n from public.candidate_applications')).n,0);
 assert.equal((await value(f.db,'select marketing_consent_status from public.whatsapp_contacts where id=$1',[f.id])).marketing_consent_status,scenario==='stop'?'opted_out':'unknown');
});
test('unverified Flow uses the existing site link',async t=>{
 const f=await replySetup();t.after(()=>f.db.close());await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014092316_whatsapp_registration_flow.sql'),'utf8'));
 const row=(await f.db.query('select * from public.console_claim_registration_reply($1,$2)',[f.inbound,'worker'])).rows[0];assert.equal(row.flow_id,null);assert.equal(row.flow_token,null);
});
test('changed verified Flow rolls back the provider boundary without authorizing a send',async t=>{
 const f=await replySetup();t.after(()=>f.db.close());await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014092316_whatsapp_registration_flow.sql'),'utf8'));
 await f.db.query("select public.console_verify_registration_flow('1234567899',$1,'1234567890')",['a'.repeat(64)]);
 const row=(await f.db.query('select * from public.console_claim_registration_reply($1,$2)',[f.inbound,'worker'])).rows[0];
 await f.db.query("select public.console_verify_registration_flow('1234567898',$1,'1234567890')",['b'.repeat(64)]);
 await assert.rejects(f.db.query("select public.console_registration_boundary($1,'worker','1234567891','1234567890')",[row.message_id]),/Flow changed/);
 assert.equal((await value(f.db,'select send_phase from public.whatsapp_outbound_messages where id=$1',[row.message_id])).send_phase,'claimed');
});
