'use strict';
const fs=require('node:fs');
const {setup:base,value}=require('./same-day-runtime-setup');
const {importOne,subscribe}=require('./whatsapp-console-runtime-helpers');
const migration='supabase/migrations/20261028090000_registration_video_campaign.sql';
async function setup(){const f=await base(),db=f.db;
await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);alter table public.employer_requirements add column created_at timestamptz default now();create function private.job_alert_choice_allows(uuid,uuid,timestamptz) returns boolean language sql as $$select true$$;");
for(const file of ['20261019061339_same_day_hindi_alert_sender.sql','20261022090957_hindi_registered_manual_campaigns.sql','20261023172336_recruitment_reel_automation.sql','20261024120849_poster_reel_drafts.sql','20261024160504_whatsapp_job_reel_delivery.sql','20261024162733_hindi_whatsapp_job_reel.sql','20261025035454_hindi_job_alert_contact_line.sql','20261025042420_all_job_contact_lines.sql','20261027112302_manual_video_campaign.sql','20261028055133_archive_console_contacts.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
await db.exec("create function private.console_campaign_delivery(uuid) returns jsonb language sql as $$select '{}'::jsonb$$");await db.exec(fs.readFileSync(migration,'utf8'));
const body=(await value(db,'select private.registration_video_body() body')).body;
const spec={id:'1234567897',name:'aadhyant_registration_video_hi_v1',language:'hi',status:'APPROVED',components:[{type:'HEADER',format:'VIDEO'},{type:'BODY',text:body},{type:'BUTTONS',buttons:[{type:'URL',text:'Register Now',url:'https://aadhyantmanpower.in/'},{type:'QUICK_REPLY',text:'Stop alerts'}]}]};
await db.query('select public.console_sync_templates($1)',[JSON.stringify([spec])]);const media='10000000-0000-0000-0000-000000000001';
await db.query('select public.console_register_promotion_media($1,auth.uid(),1200)',[media]);await db.exec("select public.console_sender_connection('1234567891','1234567890')");return{db,media,spec};}

module.exports={setup};
