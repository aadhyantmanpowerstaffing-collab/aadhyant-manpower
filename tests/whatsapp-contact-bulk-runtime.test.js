'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup,value,importOne,subscribe}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const migration=fs.readFileSync('supabase/migrations/20261026040538_whatsapp_contact_bulk_actions.sql','utf8');
async function prepare(){const db=await setup();await db.exec(migration);return db;}
test('deletes only selected unused imports, deduplicates IDs, audits counts and allows idempotent retries',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);
 await db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543211"]']);
 const result=(await value(db,'select public.admin_console_delete_contacts($1::uuid[]) result',[[id,id]])).result;
 assert.deepEqual(result,{deleted:1,kept:0});assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
 assert.deepEqual((await value(db,'select public.admin_console_delete_contacts($1::uuid[]) result',[[id]])).result,{deleted:0,kept:0});
 assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='whatsapp.console_contacts_deleted'")).n,2);
});
test('keeps subscribed and STOP contacts, candidate links, suppression and message history',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);await subscribe(db,id);
 const del=async()=> (await value(db,'select public.admin_console_delete_contacts($1::uuid[]) result',[[id]])).result;
 assert.deepEqual(await del(),{deleted:0,kept:1});
 await db.exec("delete from public.whatsapp_inbound_messages;update public.whatsapp_contacts set marketing_consent_status='unknown',sharing_subscription='{}',consent_recorded_at=null,last_inbound_at=null");
 await db.exec("update public.whatsapp_contacts set transactional_contact_status='suppressed'");assert.equal((await del()).kept,1);
 await db.exec("update public.whatsapp_contacts set transactional_contact_status='unknown',marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='fixture'");assert.equal((await del()).kept,1);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='unknown',opted_out_at=null,opt_out_source=null");
 await db.query("insert into public.whatsapp_outbound_messages(contact_id) values($1)",[id]);assert.equal((await del()).kept,1);
});
test('rejects anonymous/non-admin calls, invalid IDs and oversized batches',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);
 for(const ids of [null,[],[null],Array(501).fill(id)])await assert.rejects(db.query('select public.admin_console_delete_contacts($1::uuid[])',[ids]),/Choose 1 to 500/);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_delete_contacts(uuid[])','execute') ok")).ok,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_console_delete_contacts($1::uuid[])',[[id]]),/Admin access/);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});

test('candidate links and additional foreign-key history are retained',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);
 const candidate=(await value(db,"insert into public.candidates(mobile) values('9876543210') returning id")).id;
 await db.query("update public.whatsapp_contacts set candidate_id=$1,resolution_status='resolved' where id=$2",[candidate,id]);
 const del=async()=> (await value(db,'select public.admin_console_delete_contacts($1::uuid[]) result',[[id]])).result;
 assert.equal((await del()).kept,1);
 await db.exec("update public.whatsapp_contacts set candidate_id=null,resolution_status='unresolved';create table public.synthetic_contact_history(contact_id uuid references public.whatsapp_contacts(id))");
 await db.query('insert into public.synthetic_contact_history values($1)',[id]);assert.equal((await del()).kept,1);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});
