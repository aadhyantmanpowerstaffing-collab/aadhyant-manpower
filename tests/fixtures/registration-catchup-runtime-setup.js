'use strict';
const fs=require('node:fs');
const base=require('./same-day-runtime-setup');
async function setup(){
 const f=await base.setup(),db=f.db;
 await db.exec(`alter table public.candidates add column if not exists age integer,add column if not exists date_of_birth date,add column if not exists preferred_job_location text;
 create table public.candidate_preferences(candidate_id uuid,preferred_locations text[]);
 create table private.whatsapp_web_registrations(token_hash bytea primary key,reply_id uuid,completed_at timestamptz,result jsonb);
 create function public.submit_whatsapp_registration_form(text,jsonb,jsonb default '{}') returns jsonb language sql as $$select '{"status":"registered"}'::jsonb$$;
 create schema vault;create schema net;create schema cron;
 create table vault.secrets(id uuid default gen_random_uuid(),name text,secret text);create view vault.decrypted_secrets as select name,secret decrypted_secret from vault.secrets;
 create function vault.create_secret(text,text,text) returns uuid language plpgsql as $$declare id uuid;begin insert into vault.secrets(name,secret) values($2,$1) returning secrets.id into id;return id;end;$$;
 create table net.requests(id bigserial,url text,body jsonb,headers jsonb,timeout_milliseconds int);
 create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds int) returns bigint language plpgsql as $$declare rid bigint;begin insert into net.requests(url,body,headers,timeout_milliseconds) values($1,$2,$3,$4) returning id into rid;return rid;end;$$;
 create table cron.jobs(name text,schedule text,command text);create function cron.schedule(text,text,text) returns bigint language plpgsql as $$begin insert into cron.jobs values($1,$2,$3);return 1;end;$$;`);
 for(const file of ['20261017053905_explicit_candidate_alert_choices.sql','20261019120114_candidate_alert_audit_source_fix.sql','20261019061339_same_day_hindi_alert_sender.sql','20261019051702_same_day_private_supervisor_contact.sql','20261019045940_same_day_immediate_payment.sql','20261019130011_overnight_same_day_shifts.sql','20261020053644_same_day_hindi_all_shifts.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261019122406_immediate_registered_alert_dispatch.sql','utf8').replace(/^create extension if not exists (pg_net|pg_cron);$/gm,''));
 await db.exec(fs.readFileSync('supabase/migrations/20261019123133_one_time_automatic_wake_credentials.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261021054700_new_candidate_open_job_alerts.sql','utf8'));
 const t=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v4.json','utf8'));
 await db.query('select public.console_sync_templates($1)',[JSON.stringify([{...t,id:'1234567898',status:'APPROVED'}])]);
 await db.query('select public.admin_console_set_automatic_alerts(true,100)');
 f.payload.payment_time=f.payload.ends_at;return f;
}
async function regularJob(db,{code='JOB-NEW',qualification='ITI',trade='All Trade',location='Sanand GIDC, near Coca-Cola Company, Bol Gam, Ahmedabad, Gujarat',min=18,max=40}={}){
 const row=(await db.query(`insert into public.employer_requirements(id,requirement_code,company_name,job_role,job_location,required_headcount,filled_positions,qualification,iti_trade,age_min,age_max,experience_requirement,ctc,approx_in_hand,working_hours,compensation_cadence,requirement_stage,requirement_visibility,review_status)
 values(gen_random_uuid(),$1,'Synthetic Company','Operator',$2,100,0,$3,$4,$5,$6,'Both',22000,20000,'8 hours','monthly','open','public','approved') returning id`,[code,location,qualification,trade,String(min),String(max)])).rows[0];
 return row.id;
}
async function person(db,{phone='9876543211',qualification='ITI',trade='Fitter',age=25,location='Sanand',general=true,sameDay=false}={}){
 const id=await base.candidate(db,phone);
 await db.query('update public.candidates set highest_qualification=$2,specialization=$3,age=$4,current_location=$5,preferred_job_location=$5 where id=$1',[id,qualification,trade,age,location]);
 await db.query('select public.save_candidate_alert_choices($1,$2,$3)',[general,sameDay,location]);return id;
}
module.exports={...base,setup,regularJob,person};
