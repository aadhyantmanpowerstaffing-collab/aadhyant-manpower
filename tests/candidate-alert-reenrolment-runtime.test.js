'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base,candidate,value}=require('./fixtures/same-day-runtime-setup');
const migration=fs.readFileSync('supabase/migrations/20261021122825_candidate_alert_reenrolment.sql','utf8');
async function setup(){const f=await base(),db=f.db;await db.exec(`alter table public.candidates add column if not exists preferred_job_location text;create table public.candidate_preferences(candidate_id uuid,preferred_locations text[]);
 create table private.whatsapp_web_registrations(token_hash bytea primary key,reply_id uuid,completed_at timestamptz,result jsonb);
 create function public.submit_whatsapp_registration_form(text,jsonb,jsonb default '{}') returns jsonb language sql as $$select '{"status":"registered"}'::jsonb$$;`);
 for(const file of ['20261017053905_explicit_candidate_alert_choices.sql','20261019120114_candidate_alert_audit_source_fix.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(migration);const cid=await candidate(db);await db.query("select public.save_candidate_alert_choices(true,true,'Sanand')");return{...f,cid};}
async function stop(db,reason='user_stop',source='whatsapp_inbound'){await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',transactional_contact_status='suppressed',opted_out_at=clock_timestamp(),opt_out_source=$1,opt_out_reason_category=$2",[source,reason]);}
async function restart(db,{general=true,sameDay=false,location='Sanand',confirmed=true,operation=crypto.randomUUID(),expectedUser}={}){const uid=expectedUser??(await value(db,'select auth.uid() id')).id;return(await value(db,'select public.restart_candidate_whatsapp_alerts($1,$2,$3,$4,$5,$6) result',[general,sameDay,location,confirmed,operation,uid])).result;}

test('explicit own-account re-enrolment clears only user STOP, records independent choices and fresh auditable consent',async()=>{const {db,cid}=await setup();try{
 await stop(db);assert.equal((await value(db,'select public.get_candidate_alert_choices() result')).result.can_restart_alerts,true);
 await assert.rejects(db.query("select public.save_candidate_alert_choices(true,true,'Sanand')"),/STOP is active/);
 const old=(await value(db,'select consent_recorded_at from public.whatsapp_contacts')).consent_recorded_at;
 assert.equal((await restart(db,{general:false,sameDay:true})).restarted,true);
 const w=await value(db,'select marketing_consent_status,transactional_contact_status,opt_out_source,opt_out_reason_category,opted_out_at,consent_recorded_at,consent_policy_version from public.whatsapp_contacts');
 assert.equal(w.marketing_consent_status,'opted_in');assert.equal(w.transactional_contact_status,'unknown');assert.equal(w.opt_out_source,null);assert.equal(w.opted_out_at,null);assert.equal(w.opt_out_reason_category,null);assert.equal(w.consent_policy_version,'candidate-alert-restart-v1');assert.ok(w.consent_recorded_at>=old);
 const state=(await value(db,'select public.get_candidate_alert_choices() result')).result;assert.equal(state.general_alerts,false);assert.equal(state.same_day_alerts,true);assert.equal(state.can_restart_alerts,false);
 const audit=await value(db,"select metadata from public.audit_logs where action='candidate.alerts_restarted' and entity_id=$1",[cid]);assert.equal(audit.metadata.previous_reason,'user_stop');assert.equal(audit.metadata.general_alerts,false);assert.equal(audit.metadata.same_day_alerts,true);assert.equal(audit.metadata.current_job_location,undefined);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);
 }finally{await db.close();}});

test('missing confirmation, both No, null choices and malformed location cannot change STOP',async()=>{const {db}=await setup();try{
 await stop(db);await assert.rejects(restart(db,{expectedUser:crypto.randomUUID()}),/Active Candidate/);for(const args of [{confirmed:false},{general:false,sameDay:false},{general:null},{location:'x'.repeat(161)},{operation:null}])await assert.rejects(restart(db,args),/Confirm your new consent/);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_out');
 assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='candidate.alerts_restarted'")).n,0);
 }finally{await db.close();}});

test('replay is once-only; changed payload and replay after a later STOP require a fresh confirmation',async()=>{const {db}=await setup();try{
 await stop(db);const operation=crypto.randomUUID();await restart(db,{operation});const before=await value(db,'select consent_recorded_at from public.whatsapp_contacts');
 assert.equal((await restart(db,{operation})).restarted,false);assert.deepEqual(await value(db,'select consent_recorded_at from public.whatsapp_contacts'),before);
 await assert.rejects(restart(db,{operation,sameDay:true}),/does not match/);await stop(db);
 await assert.rejects(restart(db,{operation}),/already used/);assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_out');
 await restart(db);assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='candidate.alerts_restarted'")).n,2);
 }finally{await db.close();}});

test('administrative suppression, blocked identity and changed mobile are never removed by self-service',async()=>{const {db,cid}=await setup();try{
 for(const [reason,source] of [['admin_review','admin'],['user_stop','admin'],['user_request','whatsapp_inbound']]){await stop(db,reason,source);await assert.rejects(restart(db),/cannot restart/)}
 await stop(db);await db.exec("update public.whatsapp_contacts set resolution_status='blocked',candidate_id=null");assert.equal((await value(db,'select public.get_candidate_alert_choices() result')).result.can_restart_alerts,false);await assert.rejects(restart(db),/identity requires review/);
 await db.query("update public.whatsapp_contacts set resolution_status='resolved',candidate_id=$1",[cid]);await db.query("update public.candidates set mobile='9876543222' where id=$1",[cid]);await assert.rejects(restart(db),/identity requires review/);
 assert.equal((await value(db,'select transactional_contact_status from public.whatsapp_contacts')).transactional_contact_status,'suppressed');
 }finally{await db.close();}});

test('no Candidate access, cross-contact binding and duplicate identity fail closed; only authenticated RPC is exposed',async()=>{const {db,cid}=await setup();try{
 await stop(db);await db.exec("select set_config('test.candidate','',false)");await assert.rejects(restart(db),/Active Candidate/);
 await db.query("select set_config('test.candidate',$1,false)",[cid]);const other=await candidate(db,'9876543222');await db.query("select set_config('test.candidate',$1,false)",[cid]);await db.query('update public.whatsapp_contacts set candidate_id=$1',[other]);await assert.rejects(restart(db),/identity requires review/);
 await db.query('update public.whatsapp_contacts set candidate_id=$1',[cid]);await db.query('update public.candidates set whatsapp_number=(select mobile from public.candidates where id=$1) where id=$2',[cid,other]);await assert.rejects(restart(db),/mobile requires review/);
 const grants=await value(db,"select has_function_privilege('anon','public.restart_candidate_whatsapp_alerts(boolean,boolean,text,boolean,uuid,uuid)','execute') anon,has_function_privilege('authenticated','public.restart_candidate_whatsapp_alerts(boolean,boolean,text,boolean,uuid,uuid)','execute') member,has_function_privilege('service_role','public.restart_candidate_whatsapp_alerts(boolean,boolean,text,boolean,uuid,uuid)','execute') worker,has_function_privilege('authenticated','public.get_candidate_alert_choices_before_reenrolment()','execute') legacy");assert.deepEqual(grants,{anon:false,member:true,worker:false,legacy:false});
 }finally{await db.close();}});
