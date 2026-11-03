'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup}=require('./fixtures/automatic-alert-runtime-setup');
const {value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
const migration=fs.readFileSync('supabase/migrations/20261103074538_remove_site_daily_alert_cap.sql','utf8');
test('migration removes the site cap without enabling automatic alerts, and old client values cannot reinstate it',async t=>{
 const {db}=await setup();t.after(()=>db.close());await db.exec(migration);
 let cfg=await value(db,'select automatic_alerts_enabled enabled,automatic_alerts_daily_limit cap from private.whatsapp_console_config');assert.equal(cfg.enabled,false);assert.equal(cfg.cap,null);
 await db.query('select public.admin_console_set_automatic_alerts(false,100)');assert.equal((await value(db,'select automatic_alerts_daily_limit cap from private.whatsapp_console_config')).cap,null);
 await db.query("update public.whatsapp_template_catalog set name='aadhyant_registered_job_alert_v5',compatible=true");
 await assert.rejects(db.query('select public.admin_console_set_automatic_alerts(true,100)'),/Refresh the page/);
 await db.query('select public.admin_console_set_automatic_alerts(true)');cfg=await value(db,'select automatic_alerts_enabled enabled,automatic_alerts_daily_limit cap from private.whatsapp_console_config');assert.equal(cfg.enabled,true);assert.equal(cfg.cap,null);
 const audit=await value(db,"select metadata from public.audit_logs where action='whatsapp.automatic_alerts_configured' and metadata->>'enabled'='true' limit 1");assert.equal(audit.metadata.daily_limit,null);assert.equal(audit.metadata.site_daily_cap,false);
 await db.query('select public.admin_console_set_automatic_alerts(false,null)');assert.equal((await value(db,'select automatic_alerts_enabled enabled from private.whatsapp_console_config')).enabled,false);
});
test('new cap settings retain Admin-only access and service-only canonical claims',async t=>{
 const {db}=await setup();t.after(()=>db.close());await db.exec(migration);await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_console_set_automatic_alerts(true,null)'),/Admin access required/);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_set_automatic_alerts(boolean,integer)','EXECUTE') ok")).ok,false);
 assert.equal((await value(db,"select has_function_privilege('authenticated','public.console_claim_registered_alerts_before_registration_catchup(text)','EXECUTE') ok")).ok,false);
 assert.equal((await value(db,"select has_function_privilege('service_role','public.console_claim_registered_alerts_before_registration_catchup(text)','EXECUTE') ok")).ok,true);
});
test('canonical bounded batches continue past 100 daily attempts, preserve consent exclusion and never requeue old attempts',async t=>{
 const {db}=await setup();t.after(()=>db.close());
 await db.exec(`with people as (insert into public.candidates(mobile,whatsapp_number,profile_status,status,highest_qualification)
 select '98765'||lpad(i::text,5,'0'),'98765'||lpad(i::text,5,'0'),'active','new','Unrelated' from generate_series(1,103) i returning id,mobile)
 insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version)
 select '+91'||mobile,mobile,id,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'synthetic-test' from people;`);
 await db.query('select public.admin_console_set_automatic_alerts(true,100)');await db.query("update public.employer_requirements set review_status='approved',qualification='ITI',ctc=17000,approx_in_hand=15000,compensation_cadence='monthly',working_hours='8 hours',transport_status='free' where id=$1",[requirement]);
 for(let i=0;i<10;i++){
  assert.equal((await db.query('select * from public.console_claim_registered_alerts($1)',['before-'+i])).rows.length,10);
  await db.exec("update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',lease_owner=null,lease_expires_at=null");
 }
 assert.equal((await db.query("select * from public.console_claim_registered_alerts('capped')")).rows.length,0);
 await db.exec(migration);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='unknown' where id=(select whatsapp_contact_id from public.whatsapp_campaign_recipients where recipient_status='included' order by id limit 1)");
 const after=(await db.query("select * from public.console_claim_registered_alerts_before_registration_catchup('after')")).rows;assert.equal(after.length,2);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,102);
 assert.equal((await value(db,"select count(*)::int n from public.whatsapp_campaign_recipients where recipient_status='excluded'")).n,1);
 await db.exec("update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',lease_owner=null,lease_expires_at=null");assert.equal((await db.query("select * from public.console_claim_registered_alerts_before_registration_catchup('again')")).rows.length,0);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,102);
});
