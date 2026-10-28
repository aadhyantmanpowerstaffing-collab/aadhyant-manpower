'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup,value,importOne,subscribe}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const archiveMigration=fs.readFileSync('supabase/migrations/20261028055133_archive_console_contacts.sql','utf8');
const migration=fs.readFileSync('supabase/migrations/20261028062609_restore_imported_contacts_and_label_options.sql','utf8');
async function prepare(){const db=await setup();await db.exec(archiveMigration);await db.exec(migration);return db;}
const archive=(db,ids)=>db.query('select public.admin_console_archive_contacts($1::uuid[])',[ids]);
const options=async db=>(await value(db,'select public.admin_console_contact_labels() result')).result;
const row={Name:'Sample Person',Email:'person@example.invalid',Mobile:'9876543210',Gender:'Male',Age:25,State:'Gujarat',District:'Ahmedabad'};
test('number re-import restores only requested archived identities and preserves consent, labels, STOP and history',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);await subscribe(db,id);
 await db.query("update public.whatsapp_contacts set imported_profile=imported_profile||'{\"Lists\":[\"New Batch\"],\"Tags\":[\"Sanand\"]}' where id=$1",[id]);
 await db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543211"]']);
 const other=(await value(db,"select id from public.whatsapp_contacts where indian_mobile_key='9876543211'")).id;
 await archive(db,[id,other]);
 const before=(await value(db,"select to_jsonb(w)-'console_archived_at'-'updated_at' profile from public.whatsapp_contacts w where id=$1",[id])).profile;
 const result=(await value(db,'select public.admin_console_import_numbers($1::jsonb) result',['["+91 9876543210","9876543210"]'])).result;
 assert.equal(result.restored,1);assert.equal(result.added,0);assert.equal(result.consent_changed,false);assert.equal(result.queued,0);
 assert.deepEqual((await value(db,"select to_jsonb(w)-'console_archived_at'-'updated_at' profile from public.whatsapp_contacts w where id=$1",[id])).profile,before);
 assert.equal((await value(db,'select console_archived_at is not null hidden from public.whatsapp_contacts where id=$1',[other])).hidden,true);
 assert.equal((await value(db,'select jsonb_array_length(public.admin_console_contacts()) n')).n,1);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_inbound_messages')).n,1);
 await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='fixture' where id=$1",[id]);
 await archive(db,[id]);await db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543210"]']);
 assert.equal((await value(db,'select marketing_consent_status s from public.whatsapp_contacts where id=$1',[id])).s,'opted_out');
});
test('Excel/CSV re-import restores selected archived contacts without overwriting saved group labels or permission',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);await subscribe(db,id);
 await db.query("update public.whatsapp_contacts set imported_profile=imported_profile||'{\"Lists\":[\"Batch A\"],\"Tags\":[\"ITI\"]}' where id=$1",[id]);
 await archive(db,[id]);
 const result=(await value(db,'select public.admin_console_import_contacts($1::jsonb) result',[JSON.stringify([row,row])])).result;
 assert.equal(result.restored,1);assert.equal(result.added,0);assert.equal(result.consent_changed,false);
 assert.deepEqual(await options(db),{lists:['Batch A'],tags:['ITI']});
 assert.equal((await value(db,'select marketing_consent_status s from public.whatsapp_contacts where id=$1',[id])).s,'opted_in');
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});
test('label options are deduplicated/sorted across all pages, exclude archived records, and require Admin',async t=>{
 const db=await prepare();t.after(()=>db.close());
 await db.exec(`insert into public.whatsapp_contacts(provider_address,indian_mobile_key,resolution_status,imported_profile)
 select '+91'||(9876500000+i)::text,(9876500000+i)::text,'unresolved',jsonb_build_object('Lists',jsonb_build_array(case when i=0 then 'Page Two' else 'Batch A' end,'Batch A'),'Tags',jsonb_build_array('ITI','Sanand')) from generate_series(0,120) i;`);
 assert.deepEqual(await options(db),{lists:['Batch A','Page Two'],tags:['ITI','Sanand']});
 await db.exec("update public.whatsapp_contacts set console_archived_at=now() where indian_mobile_key='9876500000'");
 assert.deepEqual(await options(db),{lists:['Batch A'],tags:['ITI','Sanand']});
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_contact_labels()','execute') ok")).ok,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(options(db),/Admin access/);
 await assert.rejects(db.query('select public.admin_console_import_contacts($1::jsonb)',[JSON.stringify([row])]),/Admin access/);
});
test('invalid import rolls back restoration and missing/non-array legacy labels do not break options',async t=>{
 const db=await prepare();t.after(()=>db.close());const id=await importOne(db);await archive(db,[id]);
 await assert.rejects(db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543210","bad"]']),/Invalid Indian/);
 assert.equal((await value(db,'select console_archived_at is not null hidden from public.whatsapp_contacts where id=$1',[id])).hidden,true);
 await db.query("update public.whatsapp_contacts set console_archived_at=null,imported_profile='{\"Lists\":null,\"Tags\":42}' where id=$1",[id]);
 assert.deepEqual(await options(db),{lists:[],tags:[]});
});
