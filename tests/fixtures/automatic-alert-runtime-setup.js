'use strict';
const fs=require('node:fs'),path=require('node:path');
const {senderSetup,value}=require('./whatsapp-console-runtime-helpers');
const migration=fs.readFileSync(path.join(__dirname,'../../supabase/migrations/20261016105424_automatic_registered_job_alerts.sql'),'utf8');
async function setup(){
 const db=await senderSetup();
 await db.exec(`alter table public.candidates add column created_at timestamptz default clock_timestamp();alter table public.employer_requirements add column review_status text default 'pending',add column required_headcount integer default 10,add column filled_positions integer default 0,add column ctc numeric,add column approx_in_hand numeric,add column working_hours text,add column transport_status text,add column compensation_cadence text;
 create or replace function private.vacancy_is_application_eligible(uuid) returns boolean language sql stable as $$select exists(select 1 from public.employer_requirements where id=$1 and review_status='approved' and requirement_stage='open' and requirement_visibility='public' and filled_positions<required_headcount)$$;`);
 const safe=fs.readFileSync(path.join(__dirname,'../../supabase/migrations/026_whatsapp_integration_core.sql'),'utf8');
 await db.exec(safe.slice(safe.indexOf('create function private.whatsapp_safe_flat_json'),safe.indexOf('create function private.normalize_indian_whatsapp_phone')));
 await db.exec("alter table public.whatsapp_outbound_messages add column message_type text default 'template';drop function public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer);");
 const corrected=fs.readFileSync(path.join(__dirname,'../../supabase/migrations/027_fix_whatsapp_special_expression_qualification.sql'),'utf8');
 await db.exec(corrected.slice(corrected.indexOf('create or replace function public.enqueue_whatsapp_outbound_message'),corrected.indexOf('create or replace function public.claim_whatsapp_outbound_batch')));
 await db.exec(migration);
 const body=(await value(db,'select private.registered_alert_body() body')).body;
 const buttons=(await value(db,'select private.registered_alert_buttons() buttons')).buttons;buttons[0].example=['https://aadhyantmanpower.in/jobs/?requirement=TEST_JOB'];
 const template={id:'1234567898',name:'aadhyant_registered_job_alert_v1',language:'en',status:'APPROVED',components:[{type:'BODY',text:body},{type:'BUTTONS',buttons}]};
 const sync=()=>db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([template])]);await sync();
 await db.query("select public.console_sender_connection('1234567891','1234567890')");await db.query('select public.console_automatic_worker_heartbeat()');
 return {db,template,sync};
}

module.exports={setup};
