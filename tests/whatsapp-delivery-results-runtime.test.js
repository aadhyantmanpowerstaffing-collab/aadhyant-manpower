'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {senderSetup,queuedSender,value}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const migration=fs.readFileSync('supabase/migrations/20261028072609_campaign_delivery_results_and_claim_guard.sql','utf8');
async function prepare(){const db=await senderSetup();await db.exec(`alter table public.whatsapp_message_events add column outbound_message_id uuid,add column status text,add column provider_timestamp timestamptz,add column created_at timestamptz default now(),add column provider_error_code text,add column provider_error_category text;`);await db.exec(`alter function public.console_claim_campaign(uuid,text) rename to console_claim_campaign_before_registered;
 create function public.console_claim_campaign(p_campaign_id uuid,p_worker_id text) returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid) language plpgsql security definer set search_path='' as $$begin
 if p_campaign_id is null or exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and audience_mode='registered_alerts') then return;end if;
 return query select * from public.console_claim_campaign_before_registered(p_campaign_id,p_worker_id);end;$$;`);await db.exec(migration);const f=await queuedSender(db);return{db,...f};}
test('full-campaign summary separates delivered/read, pending, failed, review and awaiting delivery without double counting',async t=>{
 const {db,campaign}=await prepare();t.after(()=>db.close());
 const summary=async()=>(await value(db,'select public.admin_console_campaign_delivery($1) result',[campaign])).result;
 for(const [state,phase,key] of [['queued','ready','pending'],['sending','claimed','pending'],['sent','terminal','awaiting'],['delivered','terminal','delivered'],['read','terminal','delivered'],['failed','terminal','failed'],['failed','reconciliation_required','review'],['suppressed','terminal','not_sent']]){
  await db.query('update public.whatsapp_outbound_messages set state=$1,send_phase=$2',[state,phase]);const d=await summary();assert.equal(d.total,1);assert.equal(d[key],1);assert.equal(d.delivered+d.awaiting+d.pending+d.review+d.failed+d.not_sent,1);assert.equal(d.read,state==='read'?1:0);
 }
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(summary(),/Console campaign required/);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_campaign_delivery(uuid)','execute') ok")).ok,false);
});
test('report recovers latest provider failure code from webhook events when outbox error is empty',async t=>{
 const {db,campaign}=await prepare();t.after(()=>db.close());await db.exec("update public.whatsapp_outbound_messages set state='failed',last_error_category=null,last_error_code=null");
 await db.exec("insert into public.whatsapp_message_events(id,outbound_message_id,status,provider_timestamp,provider_error_code,provider_error_category) select gen_random_uuid(),id,'failed',now()-interval '1 minute','131026','Message undeliverable' from public.whatsapp_outbound_messages;insert into public.whatsapp_message_events(id,outbound_message_id,status,provider_timestamp,provider_error_code,provider_error_category) select gen_random_uuid(),id,'failed',now(),'131048','Spam Rate limit hit' from public.whatsapp_outbound_messages;");
 const report=(await value(db,'select public.admin_console_report($1) result',[campaign])).result;assert.equal(report[0].failure_code,'131048');assert.equal(report[0].failure,'Spam Rate limit hit');assert.ok(report[0].mobile);
 await db.exec("update public.whatsapp_outbound_messages set state='read'");assert.equal((await value(db,'select public.admin_console_report($1) result',[campaign])).result[0].failure_code,null);
 const campaigns=(await value(db,'select public.admin_console_campaigns() result')).result;assert.equal(campaigns[0].delivery.delivered,1);assert.equal(campaigns[0].delivery.read,1);
});
test('completed campaign claim returns immediately without expensive template evaluation or touching sent messages',async t=>{
 const {db,campaign}=await prepare();t.after(()=>db.close());await db.exec("update public.whatsapp_outbound_messages set state='sent',provider_message_id='wamid.complete';create or replace function private.console_template_valid(p_campaign_id uuid) returns boolean language plpgsql as $$begin raise exception 'Expensive template validation must not run for completed dispatch';end;$$;");
 const before=(await value(db,'select to_jsonb(o) data from public.whatsapp_outbound_messages o')).data;
 assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'complete-worker'])).rows.length,0);
 assert.deepEqual((await value(db,'select to_jsonb(o) data from public.whatsapp_outbound_messages o')).data,before);
});
test('pending claim keeps consent and template guards; claiming never directly calls a provider',async t=>{
 const {db,campaign}=await prepare();t.after(()=>db.close());const rows=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'safe-worker'])).rows;assert.equal(rows.length,1);
 assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'other-worker'])).rows.length,0);
 assert.equal((await value(db,'select state,send_phase from public.whatsapp_outbound_messages')).send_phase,'claimed');
});

test('manual entrypoint keeps automatic quota separation and internal claim function stays ungranted',async t=>{
 const {db,campaign}=await prepare();t.after(()=>db.close());
 await db.exec("alter table public.whatsapp_campaigns drop constraint if exists whatsapp_campaigns_audience_mode_check");
 await db.query("update public.whatsapp_campaigns set audience_mode='registered_alerts' where id=$1",[campaign]);
 assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'manual-worker'])).rows.length,0);
 for(const role of ['anon','authenticated','service_role'])assert.equal((await value(db,"select has_function_privilege($1,'public.console_claim_campaign_before_registered(uuid,text)','execute') ok",[role])).ok,false);
});
