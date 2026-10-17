'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base,submit,publish,candidate,value}=require('./fixtures/same-day-runtime-setup');
const upgrade=fs.readFileSync('supabase/migrations/20261017053905_explicit_candidate_alert_choices.sql','utf8');
async function setup(){const f=await base(),db=f.db;await db.exec(`alter table public.candidates add column if not exists preferred_job_location text;create table public.candidate_preferences(candidate_id uuid,preferred_locations text[]);
 create table private.whatsapp_web_registrations(token_hash bytea primary key,reply_id uuid,completed_at timestamptz,result jsonb);
 create function public.submit_whatsapp_registration_form(text,jsonb,jsonb default '{}') returns jsonb language sql as $$select '{"status":"registered"}'::jsonb$$;`);await db.exec(upgrade);return f;}
async function save(db,g,d,location='Not Working'){return db.query('select public.save_candidate_alert_choices($1,$2,$3)',[g,d,location]);}
test('new candidates have no default choice, mandatory booleans, exact independent choices and narrow grants',async()=>{const {db}=await setup();try{
 await candidate(db);let state=(await value(db,'select public.get_candidate_alert_choices() s')).s;assert.equal(state.general_alerts,null);assert.equal(state.same_day_alerts,null);
 await assert.rejects(save(db,null,true),/Choose Yes or No/);await assert.rejects(save(db,true,null),/Choose Yes or No/);
 await save(db,false,true,'Sanand GIDC');state=(await value(db,'select public.get_candidate_alert_choices() s')).s;assert.equal(state.general_alerts,false);assert.equal(state.same_day_alerts,true);assert.equal(state.sanand_eligible,true);
 assert.equal((await value(db,"select has_function_privilege('anon','public.save_candidate_alert_choices(boolean,boolean,text)','execute') w,has_table_privilege('authenticated','private.candidate_alert_choices','update') direct")).w,false);
 }finally{await db.close();}});
test('current living, current job and preferred location independently qualify Sanand; substring lookalikes do not',async()=>{const {db}=await setup();try{
 const cid=await candidate(db);await db.query("update public.candidates set current_location='Kadi' where id=$1",[cid]);await save(db,true,true,'Kadi');assert.equal((await value(db,'select private.candidate_is_sanand_local($1) ok',[cid])).ok,false);
 await save(db,true,true,'Sanand GIDC');assert.equal((await value(db,'select private.candidate_is_sanand_local($1) ok',[cid])).ok,true);
 await save(db,true,true,'Not Working');await db.query("update public.candidates set current_location='સાણંદ' where id=$1",[cid]);assert.equal((await value(db,'select private.candidate_is_sanand_local($1) ok',[cid])).ok,true);
 await db.query("update public.candidates set current_location='Kadi',preferred_job_location='Sanand' where id=$1",[cid]);assert.equal((await value(db,'select private.candidate_is_sanand_local($1) ok',[cid])).ok,true);
 await db.query("update public.candidates set preferred_job_location='Sanandpur' where id=$1",[cid]);assert.equal((await value(db,'select private.candidate_is_sanand_local($1) ok',[cid])).ok,false);
 await db.query("insert into public.candidate_preferences values($1,array['Sanand GIDC'])",[cid]);assert.equal((await value(db,'select private.candidate_is_sanand_local($1) ok',[cid])).ok,true);
 }finally{await db.close();}});
test('general No and shift Yes never authorizes a regular publication; general Yes and shift No does the reverse',async()=>{const {db,payload:p}=await setup();try{
 const job=await submit(db,p);await candidate(db);await save(db,false,true,'Sanand');const w=(await value(db,'select id from public.whatsapp_contacts')).id;
 assert.equal((await value(db,'select private.job_alert_choice_allows($1,$2) ok',[job,w])).ok,true);
 assert.equal((await value(db,"select private.job_alert_choice_allows('00000000-0000-0000-0000-000000000002',$1) ok",[w])).ok,false);
 await save(db,true,false,'Sanand');assert.equal((await value(db,'select private.job_alert_choice_allows($1,$2) ok',[job,w])).ok,false);
 assert.equal((await value(db,"select private.job_alert_choice_allows('00000000-0000-0000-0000-000000000002',$1) ok",[w])).ok,true);
 await save(db,false,false);assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_out');await save(db,true,false);assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_in');
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp',opt_out_reason_category='user_request'");await assert.rejects(save(db,true,true,'Sanand'),/STOP is active/);
 }finally{await db.close();}});
test('cross-candidate access, ambiguous numbers and blocked contacts cannot change preferences',async()=>{const {db}=await setup();try{
 const cid=await candidate(db);await save(db,true,true,'Sanand');await db.exec("select set_config('test.candidate','',false)");await assert.rejects(save(db,true,true,'Sanand'),/Active Candidate/);
 await db.query("select set_config('test.candidate',$1,false)",[cid]);await db.exec("update public.whatsapp_contacts set resolution_status='blocked',candidate_id=null");await assert.rejects(save(db,true,true,'Sanand'),/requires review/);
 assert.equal((await value(db,'select count(*)::int n from private.candidate_alert_choices')).n,1);
 }finally{await db.close();}});
test('private WhatsApp form saves both answers atomically, preserves replay and refuses malformed choices',async()=>{
 const {setup:web}=require('./fixtures/web-registration-runtime-setup');const f=await web(),db=f.db;try{
 await db.exec(`alter table public.employer_requirements add column work_engagement text default 'regular';create table public.candidate_preferences(candidate_id uuid,preferred_locations text[]);create table private.same_day_preferences(candidate_id uuid primary key,enabled boolean,changed_at timestamptz);create table private.whatsapp_job_publications(requirement_id uuid,campaign_id uuid,published_at timestamptz,job_snapshot jsonb,authorized_by uuid,outcome text);`);
 await db.exec(upgrade);
 await assert.rejects(f.submit(f.profile,{same_day_alert_consent:'yes',current_job_location:'Sanand'}),/Choose Yes or No/);
 assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);
 const result=await f.submit({...f.profile,job_alert_consent:false},{same_day_alert_consent:true,current_job_location:'Sanand GIDC'});
 assert.equal(result.job_alerts_selected,false);assert.equal(result.same_day_alerts_selected,true);
 let a=await value(db,'select * from private.candidate_alert_choices');assert.equal(a.general_alerts,false);assert.equal(a.same_day_alerts,true);
 assert.deepEqual(await f.submit({...f.profile,job_alert_consent:true},{same_day_alert_consent:false,current_job_location:'Kadi'}),result);
 a=await value(db,'select * from private.candidate_alert_choices');assert.equal(a.general_alerts,false);assert.equal(a.same_day_alerts,true);assert.equal((await value(db,'select count(*)::int n from public.candidate_applications')).n,1);
 }finally{await db.close();}
});
test('publication and final provider guard honor independent choices and a later location change',async()=>{const {db,payload:p}=await setup();try{
 const shift=await submit(db,p);await candidate(db);await save(db,false,true,'Sanand GIDC');
 const template=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v4.json','utf8'));await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([{...template,id:'1234567898',status:'APPROVED'}])]);await db.query('select public.admin_console_set_automatic_alerts(true,10)');
 await publish(db,shift);await publish(db,'00000000-0000-0000-0000-000000000002');
 const rows=(await db.query("select * from public.console_claim_registered_alerts('choices-isolated')")).rows;assert.equal(rows.length,1);assert.match(rows[0].template_variables.job_role,/Same-Day Pay/);
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,true);
 await save(db,false,true,'Kadi');assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,false);
 await assert.rejects(db.query("select public.console_provider_boundary($1,'choices-isolated','1234567891','1234567890')",[rows[0].message_id]));
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaign_recipients')).n,1);
 }finally{await db.close();}});

test('both No completes registration and preserves a bound replay receipt without bypassing a later STOP',async()=>{const {setup:web}=require('./fixtures/web-registration-runtime-setup');const f=await web(),db=f.db;try{await db.exec(`alter table public.employer_requirements add column work_engagement text default 'regular';create table public.candidate_preferences(candidate_id uuid,preferred_locations text[]);create table private.same_day_preferences(candidate_id uuid primary key,enabled boolean,changed_at timestamptz);create table private.whatsapp_job_publications(requirement_id uuid,campaign_id uuid,published_at timestamptz,job_snapshot jsonb,authorized_by uuid,outcome text);`);await db.exec(upgrade);await db.exec(fs.readFileSync('supabase/migrations/20261017055551_completed_registration_choice_receipt.sql','utf8'));const result=await f.submit({...f.profile,job_alert_consent:false},{same_day_alert_consent:false,current_job_location:'Not Working'});assert.equal(result.status,'registered');assert.equal(result.same_day_alerts_selected,false);assert.equal((await f.context()).status,'completed');assert.deepEqual(await f.submit({...f.profile,job_alert_consent:true},{same_day_alert_consent:true,current_job_location:'Sanand'}),result);assert.equal((await value(db,'select count(*)::int n from public.candidate_applications')).n,1);await db.exec("update public.whatsapp_contacts set opt_out_reason_category='user_request',opt_out_source='whatsapp',transactional_contact_status='suppressed'");assert.equal(await f.context(),null);await assert.rejects(f.submit({...f.profile,job_alert_consent:true},{same_day_alert_consent:true,current_job_location:'Sanand'}),/unavailable/);}finally{await db.close();}});
