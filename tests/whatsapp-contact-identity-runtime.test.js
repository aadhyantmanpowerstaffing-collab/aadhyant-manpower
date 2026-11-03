'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base,value}=require('./fixtures/whatsapp-console-runtime-helpers');
const migration=fs.readFileSync('supabase/migrations/20261103104500_whatsapp_contact_full_identity.sql','utf8');
async function setup(){
 const db=await base();
 await db.exec("create function private.current_candidate_portal_id() returns uuid language sql as $$select null::uuid$$;");
 for(const file of ['20261028055133_archive_console_contacts.sql','20261102124028_interview_whatsapp_permission.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 await db.exec(migration);return db;
}
const contacts=async(db,list=null,tag=null,offset=0)=>(await value(db,'select public.admin_console_contacts($1,$2,$3) rows',[list,tag,offset])).rows;
test('full identities preserve canonical name priority, import fallback, consent, filtering, pagination and archival',async t=>{
 const db=await setup();t.after(()=>db.close());
 await db.exec(`insert into public.candidates(id,full_name,mobile) values('10000000-0000-4000-8000-000000000001','  Synthetic Candidate  ','9876543210');
 insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,imported_profile,marketing_consent_status,transactional_contact_status,opted_out_at,opt_out_source)
 values('+919876543210','9876543210','10000000-0000-4000-8000-000000000001','resolved','{"Name":"Imported Alias","Lists":["Batch A"],"Tags":["ITI"]}','opted_out','suppressed',now(),'fixture'),
 ('+919876543211','9876543211',null,'unresolved','{"Name":"  Synthetic Import  ","Lists":["Batch B"]}','unknown','unknown',null,null),
 ('+919876543212','9876543212',null,'unresolved','{"Name":"   "}','unknown','unknown',null,null);`);
 let rows=await contacts(db,'Batch A','ITI');assert.equal(rows.length,1);
 assert.equal(rows[0].full_name,'Synthetic Candidate');assert.equal(rows[0].mobile,'+919876543210');
 assert.equal(rows[0].consent,'opted_out');assert.equal(rows[0].interview_permission,'suppressed');assert.equal(rows[0].candidate_linked,true);
 assert.equal(rows[0].mobile_masked,'+91XXXXXX3210');
 assert.equal((await contacts(db,'Batch B'))[0].full_name,'Synthetic Import');
 assert.equal((await contacts(db)).find(r=>r.mobile==='+919876543212').full_name,'Contact');
 await db.query('select public.admin_console_archive_contacts($1::uuid[])',[[rows[0].contact_id]]);
 assert.deepEqual(await contacts(db,'Batch A'),[]);
 await db.exec(`insert into public.whatsapp_contacts(provider_address,indian_mobile_key,imported_profile)
 select '+91'||(9000000000+i)::text,(9000000000+i)::text,jsonb_build_object('Name','Synthetic '||i) from generate_series(1,101) i;`);
 rows=await contacts(db);const next=await contacts(db,null,null,100);assert.equal(rows.length,100);assert.equal(next.length,3);
 assert.ok(next.every(r=>!rows.some(first=>first.contact_id===r.contact_id)));
 await assert.rejects(contacts(db,null,null,-1),/Invalid offset/);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);
});
test('only authorized Admin sessions can obtain full contact identities',async t=>{
 const db=await setup();t.after(()=>db.close());
 for(const role of ['anon','service_role'])assert.equal((await value(db,"select has_function_privilege($1,'public.admin_console_contacts(text,text,integer)','execute') ok",[role])).ok,false);
 assert.equal((await value(db,"select has_function_privilege('authenticated','public.admin_console_contacts(text,text,integer)','execute') ok")).ok,true);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(contacts(db),/Admin access required/);
 await db.exec("select set_config('test.admin','yes',false);select set_config('test.uid','',false)");await assert.rejects(contacts(db),/Admin access required/);
});
