'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base,submit,publish,candidate,value}=require('./fixtures/same-day-runtime-setup');
const {requirement,importOne,subscribe,prep}=require('./fixtures/whatsapp-console-runtime-helpers');
const templates=['registered-job-alert-template-v5.json','same-day-pay-template-hi-v2.json','registered-job-alert-template-hi-v2.json'].map((f,i)=>({...JSON.parse(fs.readFileSync('docs/whatsapp/'+f)),id:String(1234567800+i),status:'APPROVED'}));
async function setup(){const f=await base(),db=f.db;
await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);alter table public.employer_requirements add column created_at timestamptz default now();create function private.job_alert_choice_allows(uuid,uuid,timestamptz) returns boolean language sql as $$select true$$;");
for(const file of ['20261019061339_same_day_hindi_alert_sender.sql','20261022090957_hindi_registered_manual_campaigns.sql','20261023172336_recruitment_reel_automation.sql','20261024120849_poster_reel_drafts.sql','20261024160504_whatsapp_job_reel_delivery.sql','20261024162733_hindi_whatsapp_job_reel.sql','20261025035454_hindi_job_alert_contact_line.sql','20261025042420_all_job_contact_lines.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261027112302_manual_video_campaign.sql','utf8'));await db.query('select public.console_sync_templates($1)',[JSON.stringify(templates)]);return f;}

test('manual Hindi video binds current reel, sends canonical fields and fails closed on STOP and changed job',async()=>{const {db}=await setup();try{
const template=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-video-template-hi-v1.json'));template.id='1234567898';template.status='APPROVED';await db.query('select public.console_sync_templates($1)',[JSON.stringify([template])]);
await db.exec("update private.reel_config set enabled=true,whatsapp_delivery_enabled=true");
await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);
const contact=await importOne(db);await subscribe(db,contact);const tid=(await value(db,'select id from public.whatsapp_template_catalog where name=$1',[template.name])).id;
await assert.rejects(prep(db,contact,tid),/current job video/);
const j=(await value(db,"select public.reel_worker_claim('render-worker') j")).j;await db.query("select public.reel_worker_finish($1,$2,'render-worker',true)",[j.id,j.claim]);
const preview=(await value(db,'select public.admin_console_preview_manual_video($1,$2) p',[requirement,template.name])).p;assert.equal(preview.reel_ready,true);assert.doesNotMatch(preview.message,/\{\{/);
const c=(await prep(db,contact,tid)).id;assert.equal((await value(db,'select count(*)::int n from private.whatsapp_campaign_reels where campaign_id=$1',[c])).n,1);
await db.query('select public.admin_console_approve($1)',[c]);await db.query('select public.admin_console_queue($1)',[c]);const o=await value(db,'select * from public.whatsapp_outbound_messages');assert.ok(o.template_variables.company);await db.query("select public.console_sender_connection('1234567891','1234567890')");const claimed=(await db.query("select * from public.console_claim_campaign($1,'manual-video-worker')",[c])).rows;assert.equal(claimed.length,1);assert.ok((await value(db,"select public.console_claimed_reel_object($1,'manual-video-worker') path",[o.id])).path.endsWith('.mp4'));assert.equal((await value(db,"select public.console_claimed_reel_object($1,'wrong-worker') path",[o.id])).path,null);assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[o.id])).ok,true);
await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='test' where id=$1",[contact]);assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[o.id])).ok,false);
await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_in',opted_out_at=null,opt_out_source=null where id=$1",[contact]);
await db.query("update public.employer_requirements set job_role='Changed role' where id=$1",[requirement]);assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[o.id])).ok,false);
}finally{await db.close();}});
