'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {flowSetup,value,root}=require('./whatsapp-console-runtime-helpers.js');
async function chatSetup(compact=false){
 const f=await flowSetup();await f.db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014122353_whatsapp_compact_chat_registration.sql'),'utf8'));await f.db.exec('update private.whatsapp_console_config set registration_chat_enabled=true,registration_flow_id=null,registration_flow_hash=null,registration_flow_verified_at=null');
 if(compact)await f.db.exec('update private.whatsapp_console_config set compact_chat_enabled=true');
 const start=(await value(f.db,'select public.console_process_registration_chat($1,null) data',[f.inbound])).data;
 assert.equal(start.status,'started');return {...f,start};
}
async function chatPrompt(f,outbound){
 const msg=(await f.db.query('select * from public.console_claim_registration_chat($1,$2)',[outbound,'chat-worker'])).rows[0];assert.ok(msg,'prompt claim');
 await f.db.query("select public.console_registration_chat_boundary($1,$2,'1234567891','1234567890')",[outbound,'chat-worker']);
 await f.db.query('select public.mark_whatsapp_outbound_sent($1,$2,$3,null)',[outbound,'chat-worker','wamid.chat-'+outbound]);
 return msg;
}
async function chatAnswer(f,outbound,answer,options={}){
 const prompt=await value(f.db,'select * from public.whatsapp_outbound_messages where id=$1',[outbound]);
 const v=prompt.template_variables,type=options.type||(typeof answer==='number'?(v.mode!=='compact'&&v.step===4?'list':'button'):'text');
 const action=type==='text'?null:`REGCHAT|${options.session||v.session_id}|${options.step??v.step}|${answer}`;
 const m=(await value(f.db,`insert into public.whatsapp_inbound_messages(id,contact_id,webhook_event_id,message_type,action_id,provider_timestamp,correlation_key)
 select gen_random_uuid(),$1,e.id,$2,$3,clock_timestamp(),$4 from public.whatsapp_webhook_events e limit 1 returning id`,[options.contact||f.id,type,action,options.context===null?null:options.context||prompt.provider_message_id])).id;
 if(options.timestamp)await f.db.query('update public.whatsapp_inbound_messages set provider_timestamp=$1 where id=$2',[options.timestamp,m]);
 const run=()=>value(f.db,'select public.console_process_registration_chat($1,$2) data',[m,type==='text'?answer:null]);
 return {m,run,result:(await run()).data};
}

module.exports={chatSetup,chatPrompt,chatAnswer,value};
