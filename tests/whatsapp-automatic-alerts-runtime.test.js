'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {senderSetup,value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
const migration=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261016105424_automatic_registered_job_alerts.sql'),'utf8');
const {setup}=require('./fixtures/automatic-alert-runtime-setup');
async function person(db,mobile='9876543210',scope='all_job_alerts',qualification='Unrelated'){
 const c=(await value(db,"insert into public.candidates(mobile,whatsapp_number,profile_status,status,highest_qualification) values($1,$1,'active','new',$2) returning id",[mobile,qualification])).id;
 return (await value(db,`insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version)
 values('+91'||$1,$1,$2,'resolved','opted_in','whatsapp_web',$3,clock_timestamp(),'synthetic-test') returning id`,[mobile,c,scope])).id;
}
const publish=db=>db.query("update public.employer_requirements set review_status='approved',qualification='ITI',ctc=17000,approx_in_hand=15000,compensation_cadence='monthly',working_hours='8 hours',transport_status='free' where id=$1",[requirement]);
const enable=db=>db.query('select public.admin_console_set_automatic_alerts(true,10)');
test('automatic publication, exact full-information template, consent, deduplication and final send boundary',async()=>{
 const {db,template,sync}=await setup();try{
 const contact=await person(db);const portal=await person(db,'9876543212','vacancy_alerts');await db.query("update public.whatsapp_contacts set consent_source='candidate_portal',consent_policy_version='candidate-job-alerts-v1' where id=$1",[portal]);assert.equal((await value(db,'select private.registered_alert_contact_eligible($1) ok',[portal])).ok,true);await db.query("update public.whatsapp_contacts set marketing_consent_status='unknown' where id=$1",[portal]);await person(db,'9876543211','single_test');
 assert.equal((await value(db,'select public.admin_console_automatic_alerts() data')).data.enabled,false);
 await enable(db);
 // A rejected/private vacancy does not create any publication or campaign.
 await db.exec("update public.employer_requirements set job_role='Associate'");
 assert.equal((await value(db,'select count(*)::int n from private.whatsapp_job_publications')).n,0);
 await publish(db);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaign_recipients')).n,1);
 const campaign=(await value(db,'select id from public.whatsapp_campaigns')).id;
 await publish(db);await db.exec("update public.employer_requirements set requirement_visibility='private';update public.employer_requirements set requirement_visibility='public'");
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,1);
 assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'manual'])).rows.length,0);
 const rows=(await db.query("select * from public.console_claim_registered_alerts('automatic-test')")).rows;
 assert.equal(rows.length,1);assert.match(rows[0].template_variables.salary_details,/17000/);assert.match(rows[0].template_variables.benefits_details,/Free transport/);
 assert.equal(rows[0].template_name,'aadhyant_registered_job_alert_v1');
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,true);
 // STOP after claim is authoritative; registration alone never grants permission.
 await db.query("update public.whatsapp_contacts set marketing_consent_status='unknown' where id=$1",[contact]);
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,false);
 await assert.rejects(db.query("select public.console_provider_boundary($1,'automatic-test','1234567891','1234567890')",[rows[0].message_id]));
 await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_in' where id=$1",[contact]);
 await db.exec("update public.employer_requirements set ctc=19000");
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,false);
 await db.exec("update public.employer_requirements set ctc=17000,filled_positions=10");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,false);await db.exec("update public.employer_requirements set filled_positions=0");
 template.components[1].buttons[0].url='https://example.invalid/{{1}}';await sync();
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,false);
 }finally{await db.close();}
});
test('disabled jobs never replay; template outages defer authorized future publications',async()=>{
 const {db,template,sync}=await setup();try{
 await person(db);await publish(db);await enable(db);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,0);
 const job='00000000-0000-0000-0000-000000000099';
 template.status='PENDING';await sync();
 await db.query("insert into public.employer_requirements(id,requirement_stage,requirement_visibility,review_status,requirement_code,job_role) values($1,'open','public','approved','JOB-NEW','Associate')",[job]);
 assert.equal((await value(db,'select outcome from private.whatsapp_job_publications where requirement_id=$1',[job])).outcome,'template_unavailable');
 template.status='APPROVED';await sync();
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('recovery')")).rows.length,1);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,1);
 }finally{await db.close();}
});
test('pause, ambiguous identity and grants fail closed',async()=>{
 const {db}=await setup();try{
 const id=await person(db);await enable(db);await publish(db);
 await db.query("insert into public.candidates(mobile,profile_status,status) values('9876543210','active','new')");
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('duplicate')")).rows.length,0);
 const anon=(await value(db,"select has_function_privilege('anon','public.console_claim_registered_alerts(text)','execute') ok")).ok;assert.equal(anon,false);
 assert.equal((await value(db,"select has_function_privilege('authenticated','public.console_claim_campaign_before_registered(uuid,text)','execute') ok")).ok,false);
 await db.query('select public.admin_console_set_automatic_alerts(false,10)');
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('paused')")).rows.length,0);
 }finally{await db.close();}
});

test('ten attempts per batch and rolling daily cap defer the remaining audience without duplicate queue entries',async()=>{
 const {db}=await setup();try{
 for(let i=0;i<12;i++)await person(db,String(9876543200+i));
 await enable(db);await publish(db);
 const rows=(await db.query("select * from public.console_claim_registered_alerts('quota')")).rows;
 assert.equal(rows.length,10);
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('parallel')")).rows.length,0);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,10);
 assert.equal((await value(db,"select count(*)::int n from public.whatsapp_campaign_recipients where recipient_status='included'")).n,2);
 await db.exec("update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',updated_at=clock_timestamp()-interval '25 hours',lease_owner=null,lease_expires_at=null");
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('tomorrow')")).rows.length,2);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,12);
 }finally{await db.close();}
});

test('a queued contact that withdraws consent does not block a later vacancy campaign',async()=>{
 const {db}=await setup();try{
 const contact=await person(db);await enable(db);await publish(db);
 await db.query("select * from public.console_claim_registered_alerts('first')");
 await db.exec("update public.whatsapp_outbound_messages set state='queued',send_phase='ready',attempt_count=0,lease_owner=null,lease_expires_at=null");
 await db.query("update public.whatsapp_contacts set marketing_consent_status='unknown' where id=$1",[contact]);
 await person(db,'9876543211');
 await db.exec("insert into public.employer_requirements(id,requirement_stage,requirement_visibility,review_status,requirement_code,job_role) values('00000000-0000-0000-0000-000000000098','open','public','approved','JOB-NEXT','Associate')");
 const rows=(await db.query("select * from public.console_claim_registered_alerts('next')")).rows;
 assert.equal(rows.length,1);assert.equal(rows[0].template_variables.requirement_code,'JOB-NEXT');
 }finally{await db.close();}
});
