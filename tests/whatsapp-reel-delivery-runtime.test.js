'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base}=require('./fixtures/full-job-runtime-setup');
const {value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
async function setup(){const {db}=await base();
for(const f of ['20261016124516_readable_whatsapp_job_layout.sql','20261016131116_concise_registered_job_alerts.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);alter table public.employer_requirements add column created_at timestamptz default now(),add column work_engagement text default 'regular';create function private.same_day_alert_eligible(uuid,uuid,timestamptz) returns boolean language sql as $$select true$$;create function private.job_alert_choice_allows(uuid,uuid,timestamptz) returns boolean language sql as $$select true$$;");
for(const f of ['20261023172336_recruitment_reel_automation.sql','20261024120849_poster_reel_drafts.sql','20261024160504_whatsapp_job_reel_delivery.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
return db;}
test('video delivery installs paused, validates exact video header, and rejects stale or mismatched templates',async()=>{const db=await setup();try{
assert.equal((await value(db,'select whatsapp_delivery_enabled enabled from private.reel_config')).enabled,false);
await assert.rejects(db.query('select public.admin_set_reel_whatsapp_delivery(true)'),/Approved video template/);
await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_set_reel_whatsapp_delivery(false)'),/Admin/);await db.exec("select set_config('test.admin','yes',false)");
const body=(await value(db,'select private.video_job_alert_body() body')).body;
const buttons=[{type:'URL',text:'View Job & Apply',url:'https://aadhyantmanpower.in/jobs/?requirement={{1}}'},{type:'QUICK_REPLY',text:'Stop alerts'}];
const row={id:'1234567899',name:'aadhyant_registered_job_video_en_v1',language:'en',status:'PENDING',components:[{type:'HEADER',format:'VIDEO'},{type:'BODY',text:body},{type:'BUTTONS',buttons}]};
for(const [header,expected] of [[{type:'HEADER',format:'VIDEO'},true],[{type:'HEADER',format:'IMAGE'},false],[{type:'FOOTER',text:'x'},false]]){
row.components[0]=header;await db.query('select public.console_sync_templates($1)',[JSON.stringify([row])]);const t=await value(db,'select compatible,status from public.whatsapp_template_catalog where name=$1',[row.name]);assert.equal(t.compatible,expected);assert.equal(t.status,'PENDING');}
assert.equal((await value(db,"select has_function_privilege('authenticated','public.console_claimed_reel_object(uuid,text)','execute') ok")).ok,false);
assert.equal((await value(db,"select has_table_privilege('authenticated','private.whatsapp_campaign_reels','select') ok")).ok,false);
assert.equal((await value(db,"select public.console_claimed_reel_object($1,'wrong') path",[requirement])).path,null);
}finally{await db.close();}});
test('enabled delivery waits for a current canonical Reel without creating a text campaign',async()=>{const db=await setup();try{
await db.exec('update private.reel_config set enabled=true,whatsapp_delivery_enabled=true;update private.whatsapp_console_config set automatic_alerts_enabled=true;');
await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);
assert.equal((await value(db,'select count(*)::int n from private.requirement_reels')).n,1);
assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,0);
await db.query('select private.prepare_registered_publication($1)',[requirement]);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,0);
}finally{await db.close();}});
test('one ready Reel binds to one canonical campaign; lease, suppression and changed job prevent media access',async()=>{const db=await setup();try{
const body=(await value(db,'select private.video_job_alert_body() body')).body;
const template={id:'1234567899',name:'aadhyant_registered_job_video_en_v1',language:'en',status:'APPROVED',components:[{type:'HEADER',format:'VIDEO'},{type:'BODY',text:body},{type:'BUTTONS',buttons:[{type:'URL',text:'View Job & Apply',url:'https://aadhyantmanpower.in/jobs/?requirement={{1}}'},{type:'QUICK_REPLY',text:'Stop alerts'}]}]};
await db.query('select public.console_sync_templates($1)',[JSON.stringify([template])]);
await db.exec("update private.reel_config set enabled=true,whatsapp_delivery_enabled=true;update private.whatsapp_console_config set automatic_alerts_enabled=true,automatic_alerts_approved_by='00000000-0000-0000-0000-000000000001';");
const c=(await value(db,"insert into public.candidates(mobile,profile_status,status) values('9876543210','active','new') returning id")).id;
await db.query("insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version) values('+919876543210','9876543210',$1,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'test')",[c]);
await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);
assert.equal((await db.query("select * from public.console_claim_registered_alerts('video-worker')")).rows.length,0);
const j=(await value(db,"select public.reel_worker_claim('render-worker') j")).j;await db.query("select public.reel_worker_finish($1,$2,'render-worker',true)",[j.id,j.claim]);
const row=(await db.query("select * from public.console_claim_registered_alerts('video-worker')")).rows[0];assert.ok(row);assert.equal(row.template_name,template.name);
assert.equal((await value(db,"select public.console_claimed_reel_object($1,'wrong') path",[row.message_id])).path,null);
assert.ok((await value(db,"select public.console_claimed_reel_object($1,'video-worker') path",[row.message_id])).path.endsWith('.mp4'));
await db.query('select private.prepare_registered_publication($1)',[requirement]);assert.equal((await value(db,'select count(*)::int n from private.whatsapp_campaign_reels')).n,1);
await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp'");assert.equal((await value(db,"select public.console_claimed_reel_object($1,'video-worker') path",[row.message_id])).path,null);
await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_in',opted_out_at=null,opt_out_source=null");
await db.query("update public.employer_requirements set job_role='Changed role' where id=$1",[requirement]);assert.equal((await value(db,"select public.console_claimed_reel_object($1,'video-worker') path",[row.message_id])).path,null);
}finally{await db.close();}});
