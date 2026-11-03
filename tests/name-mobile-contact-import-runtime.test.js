'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup,value}=require('./fixtures/whatsapp-console-runtime-helpers.js');
test('name/mobile-only import saves names, deduplicates and preserves permission without queuing messages',async t=>{
 const db=await setup();t.after(()=>db.close());
 for(const file of ['20261028055133_archive_console_contacts.sql','20261028062609_restore_imported_contacts_and_label_options.sql','20261103112331_name_mobile_contact_import.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));
 const row={Name:'Sample Person',Mobile:'9876543210'};
 const result=(await value(db,'select public.admin_console_import_contacts($1::jsonb) result',[JSON.stringify([row,row])])).result;
 assert.equal(result.added,1);assert.equal(result.reused,1);assert.equal(result.consent_changed,false);assert.equal(result.queued,0);
 const saved=await value(db,'select imported_profile,marketing_consent_status from public.whatsapp_contacts');
 assert.equal(saved.imported_profile.Name,row.Name);assert.equal(saved.marketing_consent_status,'unknown');
 for(const extra of [{Age:'bad'},{Age:17},{Gender:'bad'},{State:'x'.repeat(161)},{Mobile:'bad'}])await assert.rejects(db.query('select public.admin_console_import_contacts($1::jsonb)',[JSON.stringify([{...row,...extra}])]),/Invalid import row/);
 await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='fixture'");
 await db.query('select public.admin_console_import_contacts($1::jsonb)',[JSON.stringify([{...row,Email:'',Gender:'',Age:'',State:'',District:''}])]);
 assert.equal((await value(db,'select marketing_consent_status s from public.whatsapp_contacts')).s,'opted_out');
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);
 await db.exec("select set_config('test.admin','no',false)");
 await assert.rejects(db.query('select public.admin_console_import_contacts($1::jsonb)',[JSON.stringify([row])]),/Admin access/);
});
