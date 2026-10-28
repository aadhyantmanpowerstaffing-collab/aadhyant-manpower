'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {chatSetup,value}=require('./fixtures/chat-runtime-helpers.js');
const migration='20261028033902_whatsapp_inbox_message_text.sql';
async function setup(t){
 const f=await chatSetup();t.after(()=>f.db.close());
 for(const name of ['20261016140500_whatsapp_employer_post_job.sql','20261016145231_whatsapp_conversation_inbox.sql','20261016151003_whatsapp_operator_replies.sql'])await f.db.exec(fs.readFileSync('supabase/migrations/'+name,'utf8'));
 await f.db.exec(`alter table public.whatsapp_inbound_messages alter column id set default gen_random_uuid(),add column safe_text text check(length(safe_text)<=2000),add column provider_message_id text unique;`);
 const core=fs.readFileSync('supabase/migrations/026_whatsapp_integration_core.sql','utf8');
 await f.db.exec(core.slice(core.indexOf('create function private.whatsapp_safe_flat_json'),core.indexOf('create function private.normalize_indian_whatsapp_phone')));
 await f.db.exec('drop function public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)');
 await f.db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));
 f.event=(await value(f.db,'select id from public.whatsapp_webhook_events limit 1')).id;
 return f;
}
const record=async(f,text,key='wamid.new',type='text',action=null)=>(await value(f.db,'select public.record_whatsapp_inbound_message($1,$2,$3,clock_timestamp(),$4,$5,$6,null,null) id',[f.event,f.id,key,type,text,action])).id;
const thread=async f=>(await value(f.db,'select public.admin_console_conversation($1) data',[f.id])).data;
test('new Gujarati text round-trips through canonical ingress and Admin history; replay never overwrites it',async t=>{
 const f=await setup(t);await f.db.exec("update private.whatsapp_registration_chats set status='completed'");
 const text='મને સાણંદમાં નોકરી જોઈએ છે.\nઇન્ટરવ્યૂ ક્યારે છે?',id=await record(f,text);
 assert.equal((await value(f.db,'select safe_text from public.whatsapp_inbound_messages where id=$1',[id])).safe_text,text);
 assert.equal((await thread(f)).find(r=>r.id===id).summary,text);
 assert.equal(await record(f,'changed'),id);assert.equal((await thread(f)).find(r=>r.id===id).summary,text);
 const legacy=await record(f,null,'wamid.legacy');assert.match((await thread(f)).find(r=>r.id===legacy).summary,/text was not saved/);
 const long='અ'.repeat(4096),longId=await record(f,long,'wamid.long');assert.equal((await thread(f)).find(r=>r.id===longId).summary,long);
 await f.db.exec("select set_config('test.admin','no',false)");await assert.rejects(thread(f),/Admin access required/);
});
test('registration answers, Flow payloads and sensitive identifiers remain excluded from transcript',async t=>{
 const f=await setup(t);const id=await record(f,'Synthetic Private Name');assert.equal((await value(f.db,'select safe_text from public.whatsapp_inbound_messages where id=$1',[id])).safe_text,null);
 await f.db.exec("update private.whatsapp_registration_chats set status='completed'");
 const form=await record(f,'Private form value','wamid.flow','flow','REGISTRATION_SUBMIT');assert.equal((await value(f.db,'select safe_text from public.whatsapp_inbound_messages where id=$1',[form])).safe_text,null);
 for(const [i,text] of ['Aadhaar 1234 5678 9012','bank account 1234567890','UAN 123456789012','ESIC 1234567890'].entries()){
  const mid=await record(f,text,'wamid.private'+i);assert.equal((await thread(f)).find(r=>r.id===mid).summary,'[Sensitive details omitted]');
 }
 const mid=await record(f,'Call 9876543210 https://example.invalid/?token=private','wamid.numbers');const summary=(await thread(f)).find(r=>r.id===mid).summary;assert.equal(summary,'Call [Number omitted] [Link omitted]');
 for(const role of ['anon','authenticated'])assert.equal((await value(f.db,"select has_function_privilege($1,'public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)','execute') ok",[role])).ok,false);
 assert.equal((await value(f.db,"select has_function_privilege('service_role','public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)','execute') ok")).ok,true);
});
