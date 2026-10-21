'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {setup,regularJob,person,value,submit,publish}=require('./fixtures/registration-catchup-runtime-setup');
const prep=db=>value(db,'select private.prepare_new_candidate_job_alerts() n');
test('late registration reopens the existing empty campaign once and drains through canonical sender',async()=>{
 const {db}=await setup();try{
 const job=await regularJob(db);
 assert.equal((await value(db,'select campaign_status from public.whatsapp_campaigns')).campaign_status,'completed');
 await person(db);assert.equal((await prep(db)).n,1);assert.equal((await prep(db)).n,0);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,1);
 assert.equal((await value(db,'select campaign_status from public.whatsapp_campaigns')).campaign_status,'queued');
 const msgs=(await db.query("select * from public.console_claim_registered_alerts('new-registration')")).rows;
 assert.equal(msgs.length,1);assert.equal(msgs[0].template_name,'aadhyant_registered_job_alert_v4');
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[msgs[0].message_id])).ok,true);
 assert.equal((await prep(db)).n,0);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages where requirement_id=$1',[job])).n,1);
 assert.equal((await value(db,"select public.console_provider_boundary($1,'new-registration','1234567891','1234567890') ok",[msgs[0].message_id])).ok,true);
 }finally{await db.close()}
});
test('real three-vacancy shapes match education, free-text trade choices, age and preferred location without substring leaks',async()=>{
 const {db}=await setup();try{
 await regularJob(db,{code:'HELPER',qualification:'Other',trade:'5th / 10th / 12th'});
 await regularJob(db,{code:'CNC',qualification:'ITI'});
 await regularJob(db,{code:'DIPLOMA',qualification:'Diploma',trade:'Mechanical Diploma / Graduate Trainee',max:30});
 const helper=await person(db,{qualification:'12th',trade:'',phone:'9876543211'});
 const iti=await person(db,{phone:'9876543212'});
 const diploma=await person(db,{qualification:'Diploma',trade:'Mechanical',phone:'9876543213'});
 await person(db,{qualification:'Diploma',trade:'Electrical',phone:'9876543214'});
 await person(db,{age:45,phone:'9876543215'});
 await person(db,{location:'Sanandpur',phone:'9876543216'});
 await person(db,{location:'Kadi',phone:'9876543217'});
 assert.equal((await prep(db)).n,3);
 const got=(await db.query('select candidate_id from public.whatsapp_campaign_recipients order by candidate_id')).rows.map(x=>x.candidate_id).sort();
 assert.deepEqual(got,[helper,iti,diploma].sort());
 }finally{await db.close()}
});
test('No/STOP, closed or filled jobs, cancelled campaigns, existing applications and manual exclusions never backfill',async()=>{
 const {db}=await setup();try{
 const job=await regularJob(db);const cid=await person(db,{general:false});assert.equal((await prep(db)).n,0);
 await db.query('select public.save_candidate_alert_choices(true,false,\'Sanand\')');
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp',opt_out_reason_category='user_request'");assert.equal((await prep(db)).n,0);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_in',opted_out_at=null,opt_out_source=null,opt_out_reason_category=null;update public.employer_requirements set filled_positions=100");assert.equal((await prep(db)).n,0);
 await db.exec("update public.employer_requirements set filled_positions=0,requirement_stage='closed'");assert.equal((await prep(db)).n,0);
 await db.exec("update public.employer_requirements set requirement_stage='open';update public.whatsapp_campaigns set cancelled_at=clock_timestamp()");assert.equal((await prep(db)).n,0);
 await db.exec('update public.whatsapp_campaigns set cancelled_at=null');
 await db.query('insert into public.candidate_applications(candidate_id,requirement_id) values($1,$2)',[cid,job]);assert.equal((await prep(db)).n,0);
 await db.exec('delete from public.candidate_applications');
 await db.query(`insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,exclusion_reason) select camp.id,$1,w.id,'manual_exclude','excluded','manual_exclude' from public.whatsapp_campaigns camp cross join public.whatsapp_contacts w`,[cid]);assert.equal((await prep(db)).n,0);
 }finally{await db.close()}
});
test('minute wake discovers late subscribers; stale templates wait and sender rechecks current profile and STOP',async()=>{
 const {db}=await setup();try{
 await regularJob(db);const cid=await person(db);
 await db.exec("update public.whatsapp_template_catalog set synced_at=clock_timestamp()-interval '2 days';update private.whatsapp_automatic_dispatch_state set last_requested_at=null");
 const before=(await value(db,'select count(*)::int n from net.requests')).n;
 await db.exec('select private.wake_registered_alert_worker()');
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaign_recipients')).n,1);
 assert.equal((await value(db,'select count(*)::int n from net.requests')).n,before+1);
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('stale')")).rows.length,0);
 await db.exec('update public.whatsapp_template_catalog set synced_at=clock_timestamp()');
 const m=(await db.query("select * from public.console_claim_registered_alerts('fresh')")).rows[0];assert.ok(m);
 await db.query('update public.candidates set age=50 where id=$1',[cid]);assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[m.message_id])).ok,false);
 await db.query('update public.candidates set age=25 where id=$1',[cid]);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp',opt_out_reason_category='user_request'");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[m.message_id])).ok,false);
 }finally{await db.close()}
});
test('global pause and private grants hold; repeat registration and timer calls cannot duplicate recipients',async()=>{
 const {db}=await setup();try{
 await regularJob(db);await person(db);
 await db.query('select public.admin_console_set_automatic_alerts(false,100)');assert.equal((await prep(db)).n,0);
 await db.query('select public.admin_console_set_automatic_alerts(true,100)');assert.equal((await prep(db)).n,1);
 await db.query('select public.save_candidate_alert_choices(true,false,\'Sanand\')');assert.equal((await prep(db)).n,0);
 const g=await value(db,"select has_function_privilege('authenticated','private.prepare_new_candidate_job_alerts()','execute') browser,has_function_privilege('anon','public.console_claim_registered_alerts(text)','execute') anon,has_function_privilege('service_role','public.console_claim_registered_alerts(text)','execute') worker");assert.deepEqual(g,{browser:false,anon:false,worker:true});
 }finally{await db.close()}
});
test('Same-Day Pay catches up only separately opted-in local candidates and retains the approved Hindi template',async()=>{
 const {db,payload}=await setup();try{
 const t=JSON.parse(require('node:fs').readFileSync('docs/whatsapp/same-day-pay-template-hi-v1.json','utf8'));
 await db.query('select public.console_sync_templates($1)',[JSON.stringify([{...t,id:'1234567899',status:'APPROVED'}])]);
 const job=await submit(db,{...payload,required_headcount:'10'});await publish(db,job);
 const opted=await person(db,{general:false,sameDay:true});
 await person(db,{phone:'9876543212',general:true,sameDay:false});
 await person(db,{phone:'9876543213',general:false,sameDay:true,location:'Kadi'});
 assert.equal((await prep(db)).n,1);
 const rows=(await db.query("select * from public.console_claim_registered_alerts('shift-catchup')")).rows;assert.equal(rows.length,1);
 assert.equal(rows[0].template_name,'aadhyant_same_day_pay_hi_v1');assert.equal(rows[0].template_language,'hi');
 assert.equal((await value(db,'select candidate_id from public.whatsapp_outbound_messages where id=$1',[rows[0].message_id])).candidate_id,opted);
 }finally{await db.close()}
});
test('bounded catchup drains without starving later registrations and cannot bypass the shared daily quota',async()=>{
 const {db}=await setup();try{
 await regularJob(db);
 for(let i=0;i<103;i++)await person(db,{phone:String(9890000000+i)});
 assert.equal((await prep(db)).n,100);assert.equal((await prep(db)).n,3);assert.equal((await prep(db)).n,0);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaign_recipients')).n,103);
 await db.query('select public.admin_console_set_automatic_alerts(true,10)');
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('quota-first')")).rows.length,10);
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('quota-second')")).rows.length,0);
 }finally{await db.close()}
});
