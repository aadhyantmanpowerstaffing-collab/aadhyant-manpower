'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup,value,importOne,subscribe,requirement}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const migration=fs.readFileSync('supabase/migrations/20261028055133_archive_console_contacts.sql','utf8');
async function prepare(){const db=await setup();await db.exec(migration);return db;}
const archive=async(db,ids)=>(await value(db,'select public.admin_console_archive_contacts($1::uuid[]) result',[ids])).result;
const contacts=async db=>(await value(db,'select public.admin_console_contacts() result')).result;
test('removes selected subscribed contacts, preserves identity/consent/history, filters manual audiences and blocks stale selection',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);await subscribe(db,id);
 await db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543211"]']);
 await db.query('insert into public.whatsapp_outbound_messages(contact_id) values($1)',[id]);
 const before=await value(db,'select to_jsonb(w) profile from public.whatsapp_contacts w where id=$1',[id]);
 assert.equal((await contacts(db)).length,2);
 assert.deepEqual(await archive(db,[id,id]),{archived:1});
 assert.deepEqual((await contacts(db)).map(r=>r.contact_id).includes(id),false);
 const after=await value(db,"select to_jsonb(w)-'console_archived_at' profile from public.whatsapp_contacts w where id=$1",[id]);
 delete before.profile.console_archived_at;assert.deepEqual(after.profile,before.profile);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_inbound_messages where contact_id=$1',[id])).n,1);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages where contact_id=$1',[id])).n,1);
 for(const source of ['contacts','registered']){
  const rows=(await value(db,"select public.admin_console_audience($1,$2,'all') result",[requirement,source])).result;
  assert.equal(rows.some(r=>r.contact_id===id),false);
 }
 assert.equal((await value(db,'select private.selected_job_contact_eligible($1,$2) ok',[id,requirement])).ok,false);
 assert.deepEqual(await archive(db,[id]),{archived:0});
 assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='whatsapp.console_contacts_archived'")).n,2);
});
test('archives STOP and linked candidate contacts without modifying suppression or candidate records',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);
 const candidate=(await value(db,"insert into public.candidates(mobile) values('9876543210') returning id")).id;
 await db.query("update public.whatsapp_contacts set candidate_id=$1,resolution_status='resolved',marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='fixture' where id=$2",[candidate,id]);
 assert.deepEqual(await archive(db,[id]),{archived:1});
 assert.equal((await contacts(db)).length,0);
 assert.equal((await value(db,'select count(*)::int n from public.candidates where id=$1',[candidate])).n,1);
 assert.equal((await value(db,'select marketing_consent_status s from public.whatsapp_contacts where id=$1',[id])).s,'opted_out');
});
test('rejects invalid batches and non-admins without changing contacts, with restricted RPC grants',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);
 for(const ids of [null,[],[null],Array(501).fill(id)])await assert.rejects(archive(db,ids),/Choose 1 to 500/);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_archive_contacts(uuid[])','execute') ok")).ok,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(archive(db,[id]),/Admin access/);
 await db.exec("select set_config('test.admin','yes',false); select set_config('test.uid','',false)");await assert.rejects(archive(db,[id]),/Admin access/);
 assert.equal((await value(db,'select console_archived_at is null ok from public.whatsapp_contacts where id=$1',[id])).ok,true);
});
