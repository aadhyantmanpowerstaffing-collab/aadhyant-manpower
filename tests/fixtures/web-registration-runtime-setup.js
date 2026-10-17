'use strict';
const fs=require('node:fs'),path=require('node:path');
const {flowSetup,flowProfile,value,root}=require('./whatsapp-console-runtime-helpers');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261016093617_whatsapp_single_page_registration.sql'),'utf8');
async function setup(){
 const f=await flowSetup();
 await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014122353_whatsapp_compact_chat_registration.sql'),'utf8'));
 await f.db.exec('alter table public.candidates add column pincode text,add column total_experience text,add column previous_job_role text,add column preferred_job_location text;');
 await f.db.exec(migration);
 // Synthetic already-delivered canonical reply; production issuance is separately tested below.
 f.token='c'.repeat(64);
 await f.db.query("update private.whatsapp_console_config set registration_web_enabled=true");
 await f.db.query('update public.whatsapp_outbound_messages set registration_web_token=$1 where id=$2',[f.token,f.reply.message_id]);
 await f.db.query("insert into private.whatsapp_web_registrations(token_hash,reply_id,inbound_id,expires_at) values(sha256(convert_to($1,'UTF8')),$2,$3,clock_timestamp()+interval '1 hour')",[f.token,f.reply.message_id,f.inbound]);
 f.profile={...flowProfile,consent_policy_version:'wa-web-registration-alerts-v1'};
 f.context=async(token=f.token)=>(await value(f.db,'select public.get_whatsapp_registration_form($1) data',[token])).data;
 f.submit=async(profile=f.profile,optional={},token=f.token)=>(await value(f.db,'select public.submit_whatsapp_registration_form($1,$2,$3) data',[token,JSON.stringify(profile),JSON.stringify(optional)])).data;
 return f;
}
module.exports={setup};
