'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {replySetup,value}=require('./fixtures/whatsapp-console-runtime-helpers.js');
const migration=fs.readFileSync('supabase/migrations/20261016145231_whatsapp_conversation_inbox.sql','utf8');
async function setup(t){const f=await replySetup();t.after(()=>f.db.close());await f.db.exec(migration);return f;}
const list=async(f,folder='inbox',filter='all',search='',offset=0)=>(await value(f.db,'select public.admin_console_inbox($1,$2,$3,$4) data',[folder,filter,search,offset])).data;
const thread=async(f,id=f.id,offset=0)=>(await value(f.db,'select public.admin_console_conversation($1,$2) data',[id,offset])).data;
test('inbox unifies canonical inbound/outbound and preserves private data and delivery state',async t=>{const f=await setup(t);
 await f.db.query("update public.whatsapp_inbound_messages set action_id='POST_JOB' where id=$1",[f.inbound]);
 const before=await value(f.db,'select count(*)::int n from public.whatsapp_outbound_messages');
 const rows=await thread(f);assert.ok(rows.some(x=>x.direction==='incoming'&&x.summary.includes('POST JOB')));assert.ok(rows.some(x=>x.direction==='outgoing'&&x.status==='read'));
 const serialized=JSON.stringify(rows);for(const secret of ['9876543210','wamid.registration-fixture','correlation_key','template_variables','destination','redacted_response'])assert.ok(!serialized.includes(secret),secret);
 const contacts=await list(f);assert.equal(contacts.length,1);assert.equal(contacts[0].mobile_masked,'+91XXXXXX3210');assert.equal(contacts[0].unread_count,2);assert.equal((await list(f,'sent')).length,1);assert.equal((await list(f,'inbox','all','9999')).length,0);
 assert.deepEqual(await value(f.db,'select count(*)::int n from public.whatsapp_outbound_messages'),before);
});
test('read markers are per operator, exact visible message IDs, replay safe and never provider receipts',async t=>{const f=await setup(t);const second='00000000-0000-0000-0000-000000000099';await f.db.query('insert into auth.users(id) values($1)',[second]);
 const before=await f.db.query('select state,read_at from public.whatsapp_outbound_messages order by id');
 const mark=()=>value(f.db,'select public.admin_console_mark_inbox_read($1,$2) n',[f.id,[f.inbound]]);
 assert.equal((await mark()).n,1);assert.equal((await mark()).n,0);assert.equal((await list(f,'inbox','unread'))[0].unread_count,1);
 const remaining=(await thread(f)).filter(x=>x.direction==='incoming'&&x.unread).map(x=>x.id);await f.db.query('select public.admin_console_mark_inbox_read($1,$2)',[f.id,remaining]);assert.equal((await list(f,'inbox','unread')).length,0);
 const late=(await value(f.db,"insert into public.whatsapp_inbound_messages(id,contact_id,message_type,processing_status,created_at) values(gen_random_uuid(),$1,'text','received',clock_timestamp()) returning id",[f.id])).id;
 assert.equal((await list(f,'inbox','unread'))[0].unread_count,1);assert.equal((await thread(f)).find(x=>x.id===late).unread,true);
 await f.db.query("select set_config('test.uid',$1,false)",[second]);assert.equal((await list(f,'inbox','unread'))[0].unread_count,3);
 assert.deepEqual((await f.db.query('select state,read_at from public.whatsapp_outbound_messages order by id')).rows,before.rows);
 const other=(await value(f.db,"insert into public.whatsapp_contacts(provider_address,indian_mobile_key) values('+919876543211','9876543211') returning id")).id;
 await assert.rejects(f.db.query('select public.admin_console_mark_inbox_read($1,$2)',[other,[f.inbound]]),/does not belong/);
});
test('attention, stable bounded history pages and safe unknown actions do not expose personal answers',async t=>{const f=await setup(t);
 await f.db.query("update public.whatsapp_inbound_messages set action_id='PRIVATE 123456789012 bank 99999',processing_status='failed' where id=$1",[f.inbound]);
 assert.equal((await list(f,'inbox','attention')).length,1);assert.ok(!(JSON.stringify(await thread(f))).includes('PRIVATE'));
 await f.db.query("insert into public.whatsapp_inbound_messages(id,contact_id,message_type,processing_status,created_at) select gen_random_uuid(),$1,'text','received','2026-01-01'::timestamptz from generate_series(1,105)",[f.id]);
 const a=await thread(f),b=await thread(f,f.id,100);assert.equal(a.length,100);assert.ok(b.length>0);assert.equal(new Set([...a,...b].map(x=>x.direction+x.id)).size,a.length+b.length);assert.deepEqual(await thread(f),a);
});
test('Admin permission, bounded arguments and private table ACLs fail closed for browser roles',async t=>{const f=await setup(t);
 for(const args of [[null,'all','',0],['inbox','bogus','',0],['inbox','all','12345',0],['inbox','all','',-1]])await assert.rejects(list(f,...args),/Invalid inbox filter/);
 await assert.rejects(thread(f,f.id,-1),/Invalid offset/);await assert.rejects(f.db.query('select public.admin_console_mark_inbox_read($1,$2)',[f.id,[]]),/Choose up to/);
 for(const role of ['anon','authenticated','service_role'])assert.equal((await value(f.db,"select has_table_privilege($1,'private.whatsapp_inbox_reads','SELECT') ok",[role])).ok,false);
 for(const fn of ['public.admin_console_inbox(text,text,text,integer)','public.admin_console_conversation(uuid,integer)','public.admin_console_mark_inbox_read(uuid,uuid[])'])assert.equal((await value(f.db,"select has_function_privilege('anon',$1,'execute') ok",[fn])).ok,false);
 await f.db.exec("select set_config('test.admin','no',false)");await assert.rejects(list(f),/Admin access required/);await assert.rejects(thread(f),/Admin access required/);await assert.rejects(f.db.query('select public.admin_console_mark_inbox_read($1,$2)',[f.id,[f.inbound]]),/Admin access required/);
});

test('Admin Inbox/Sent exposes saved full identity, retains masking compatibility and rejects other roles',async t=>{
 const f=await setup(t);await f.db.exec(fs.readFileSync('supabase/migrations/20261026064736_whatsapp_inbox_contact_identity.sql','utf8'));
 await f.db.query("update public.whatsapp_contacts set imported_profile=jsonb_build_object('Name','Synthetic Full Name') where id=$1",[f.id]);
 for(const folder of ['inbox','sent']){const row=(await list(f,folder))[0];assert.equal(row.mobile,'+919876543210');assert.equal(row.full_name,'Synthetic Full Name');assert.equal(row.mobile_masked,'+91XXXXXX3210');}
 const grants=await value(f.db,"select has_function_privilege('anon','public.admin_console_inbox(text,text,text,integer)','execute') anon,has_function_privilege('service_role','public.admin_console_inbox(text,text,text,integer)','execute') service");assert.deepEqual(grants,{anon:false,service:false});
 await f.db.exec("select set_config('test.admin','no',false)");await assert.rejects(list(f),/Admin access required/);
});
