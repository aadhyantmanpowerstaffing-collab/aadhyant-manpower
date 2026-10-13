'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.resolve(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261013045750_job_sharing_contacts.sql'),'utf8');
const consoleMigration=fs.readFileSync(path.join(root,'supabase/migrations/20261013105042_whatsapp_campaign_console.sql'),'utf8');
const upgrade=fs.readFileSync(path.join(root,'supabase/migrations/20261013091247_selected_job_campaigns.sql'),'utf8');
const source26=fs.readFileSync(path.join(root,'supabase/migrations/026_whatsapp_integration_core.sql'),'utf8');
const source28=fs.readFileSync(path.join(root,'supabase/migrations/028_whatsapp_vacancy_campaigns.sql'),'utf8');
const table=(source,name)=>source.match(new RegExp('create table public\\.'+name+' \\([\\s\\S]*?\\n\\);'))[0];
const admin='00000000-0000-0000-0000-000000000001',requirement='00000000-0000-0000-0000-000000000002';
const fixture=`
create schema auth;create schema private;create schema extensions;
create role anon;create role authenticated;create role service_role;
create table auth.users(id uuid primary key);insert into auth.users values('${admin}');
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
create function private.can_manage_whatsapp_campaigns() returns boolean language sql as $$select current_setting('test.admin',true)='yes'$$;
create function extensions.gen_random_uuid() returns uuid language sql as $$select pg_catalog.gen_random_uuid()$$;
create table public.candidates(id uuid primary key default gen_random_uuid(),mobile text,whatsapp_number text,profile_status text,status text);
create table public.employer_requirements(id uuid primary key,requirement_stage text,requirement_visibility text,job_location text,company_location text,iti_trade text,requirement_code text,job_role text);
create table public.candidate_applications(candidate_id uuid,requirement_id uuid);
create table public.audit_logs(actor_user_id uuid,actor_type text,action text,entity_type text,entity_id uuid,source text,metadata jsonb);
${table(source26,'whatsapp_contacts')}
alter table public.whatsapp_contacts enable row level security;
create table public.whatsapp_inbound_messages(id uuid primary key,contact_id uuid references public.whatsapp_contacts(id),message_type text,action_id text,provider_timestamp timestamptz);
create table public.whatsapp_outbound_messages(id uuid primary key default gen_random_uuid(),contact_id uuid,candidate_id uuid,requirement_id uuid,purpose text,consent_class text,correlation_id uuid,idempotency_key text unique);
${table(source28,'whatsapp_campaigns')}
${table(source28,'whatsapp_campaign_recipients')}
create function private.whatsapp_contact_allows_purpose(uuid,text) returns boolean language sql stable as $$select exists(select 1 from public.whatsapp_contacts w where w.id=$1 and w.marketing_consent_status='opted_in' and w.resolution_status<>'blocked')$$;
create function private.vacancy_is_application_eligible(uuid) returns boolean language sql stable as $$select exists(select 1 from public.employer_requirements where id=$1 and requirement_stage='open')$$;
-- Existing provider is deliberately stubbed: this suite never calls a real worker.
create function public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer)
returns uuid language plpgsql as $$declare result uuid;begin
insert into public.whatsapp_outbound_messages(contact_id,candidate_id,requirement_id,purpose,consent_class,idempotency_key,correlation_id)
values($1,$2,$3,$4,$5,$10,$11) on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into result;return result;end;$$;
insert into public.employer_requirements values('${requirement}','open','public','Sanand','Gujarat','Fitter','TEST_JOB','Fitter');
select set_config('test.uid','${admin}',false);select set_config('test.admin','yes',false);
`;
const row={Name:'Sample Person',Email:'person@example.invalid',Mobile:'9876543210',Gender:'Male',Age:25,State:'Gujarat',District:'Ahmedabad'};
async function setup(install=true){const db=new PGlite();await db.exec(fixture);await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/sharing-send-guard-baseline.sql'),'utf8'));await db.exec(migration);await db.exec("alter table public.whatsapp_outbound_messages add column state text default 'queued'; alter table public.candidates add column full_name text default 'Sample',add column highest_qualification text,add column specialization text,add column candidate_type text,add column current_location text,add column district text,add column state text; alter table public.employer_requirements add column qualification text,add column experience_requirement text;");await db.exec(upgrade);await db.exec("alter table public.whatsapp_outbound_messages add column next_attempt_at timestamptz default now(),add column send_phase text default 'ready',add column sent_at timestamptz,add column delivered_at timestamptz,add column read_at timestamptz,add column failed_at timestamptz,add column last_error_category text;create function public.admin_cancel_whatsapp_campaign(uuid) returns boolean language plpgsql as $f$begin update public.whatsapp_campaigns set campaign_status='cancelled',cancelled_at=clock_timestamp() where id=$1;return true;end;$f$;");await db.exec("create table public.whatsapp_webhook_events(id uuid);create table public.whatsapp_message_events(id uuid);");if(install)await db.exec(consoleMigration);return db;}
const value=async(db,sql,args=[])=>(await db.query(sql,args)).rows[0];
async function importOne(db){await db.query('select public.admin_import_sharing_contacts($1::jsonb)',[JSON.stringify([row])]);return (await value(db,'select id from public.whatsapp_contacts')).id;}
async function subscribe(db,id,scope='all',filters={locations:[],trades:[]}){
 const msg=(await value(db,"insert into public.whatsapp_inbound_messages values(gen_random_uuid(),$1,'text','SUBSCRIBE_JOB_UPDATES',clock_timestamp()) returning id",[id])).id;
 await db.query('select public.subscribe_whatsapp_sharing_updates($1,$2::jsonb)',[msg,JSON.stringify({scope,...filters})]);return msg;
}
const template={id:'1234567890',name:'aadhyant_vacancy_alert_v1',language:'en',status:'APPROVED',components:[{type:'BODY',text:'Vacancy: {{1}}\nRole: {{2}}'},{type:'BUTTONS',buttons:[{type:'QUICK_REPLY',text:'Interested'},{type:'QUICK_REPLY',text:'Stop alerts'}]}]};
const sync=async(db,data=[template])=>{await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify(data)]);return(await value(db,'select id from public.whatsapp_template_catalog limit 1')).id;};
const prep=(db,id,tid,op='00000000-0000-0000-0000-000000000070',schedule=null)=>value(db,'select public.admin_console_prepare($1,$2,$3::uuid[],$4,$5,$6) id',[requirement,tid,[id],'Job campaign',op,schedule]);
test('synced approved template binds server metadata and immutable preview; language/version are not browser arguments',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);const c=(await prep(db,id,tid)).id;
 const row=await value(db,'select template_name,template_language,template_version,console_template_snapshot from public.whatsapp_campaigns where id=$1',[c]);
 assert.equal(row.template_language,'en');assert.equal(row.template_version,'1');assert.equal(row.console_template_snapshot.body,template.components[0].text);
 assert.equal((await prep(db,id,tid)).id,c);await sync(db,[{...template,components:[{type:'BODY',text:'Changed {{1}} / {{2}}'},template.components[1]]}]);
 await assert.rejects(db.query('select public.admin_console_approve($1)',[c]),/Template changed/);
});
test('permission provenance is explicit; imports/lists never opt in and STOP cannot be overridden',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);
 await db.query('select public.admin_console_label_contacts($1::uuid[],$2::jsonb,$3::jsonb)',[[id],'["ITI Leads"]','["Sanand"]']);
 assert.equal((await value(db,"select public.admin_console_contacts('ITI Leads','Sanand',0) list")).list.length,1);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
 await assert.rejects(db.query('select public.admin_console_record_consent($1,$2,now())',[id,'imported_file']),/Actual consent/);
 await db.query("select public.admin_console_record_consent($1,'phone_call',now())",[id]);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_in');
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp_inbound'");
 await assert.rejects(db.query("select public.admin_console_record_consent($1,'phone_call',now())",[id]),/re-enroll/);
});
test('schedule persists on canonical outbox; sender readiness and explicit approval precede queueing',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);const when=new Date(Date.now()+3600000).toISOString(),c=(await prep(db,id,tid,undefined,when)).id;
 await assert.rejects(db.query('select public.admin_console_queue($1)',[c]),/not verified/);
 await db.exec('update private.whatsapp_console_config set sender_ready=true');
 await assert.rejects(db.query('select public.admin_console_queue($1)',[c]),/Approved/);
 await db.query('select public.admin_console_approve($1)',[c]);await db.query('select public.admin_console_queue($1)',[c]);await db.query('select public.admin_console_queue($1)',[c]);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,1);
 assert.equal(new Date((await value(db,'select next_attempt_at from public.whatsapp_outbound_messages')).next_attempt_at).toISOString(),when);
});
test('Meta rejection, stale metadata, no template, past schedule and anonymous RPCs fail closed',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);
 await assert.rejects(prep(db,id,tid,undefined,new Date(Date.now()-60000).toISOString()),/future time/);
 await sync(db,[{...template,status:'REJECTED'}]);await assert.rejects(prep(db,id,tid));
 await sync(db);await db.exec("update public.whatsapp_template_catalog set synced_at=now()-interval '25 hours'");await assert.rejects(prep(db,id,tid));
 for(const role of ['anon','authenticated'])assert.equal((await value(db,"select has_function_privilege($1,'public.console_sync_templates(jsonb)','execute') ok",[role])).ok,false);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamp with time zone)','execute') ok")).ok,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_console_contacts()'),/Admin access/);
});
test('reports display actual canonical delivery states and masked recipients',async t=>{
 const db=await setup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);const c=(await prep(db,id,tid)).id;
 await db.query('select public.admin_console_approve($1)',[c]);await db.exec('update private.whatsapp_console_config set sender_ready=true');await db.query('select public.admin_console_queue($1)',[c]);
 await db.exec("update public.whatsapp_outbound_messages set state='read',sent_at=now(),delivered_at=now(),read_at=now()");
 const report=(await value(db,'select public.admin_console_report($1) data',[c])).data;assert.equal(report[0].status,'read');assert.equal(report[0].mobile_masked,'+91XXXXXX3210');
 const campaigns=(await value(db,'select public.admin_console_campaigns() data')).data;assert.equal(campaigns[0].read,1);
});
test('extra template parameters and media headers are incompatible; list/tag audience filters precede pagination',async t=>{
 const db=await setup();t.after(()=>db.close());await sync(db,[{...template,components:[{type:'BODY',text:'{{1}} {{2}} {{4}}'},template.components[1]]}]);assert.equal((await value(db,'select compatible from public.whatsapp_template_catalog')).compatible,false);
 await sync(db,[{...template,components:[...template.components,{type:'HEADER',format:'IMAGE'}]}]);assert.equal((await value(db,'select compatible from public.whatsapp_template_catalog')).compatible,false);
 await sync(db);await sync(db,[{...template,components:[template.components[1]]}]);assert.equal((await value(db,'select compatible from public.whatsapp_template_catalog')).compatible,false);
 const id=await importOne(db);await subscribe(db,id);await db.query('select public.admin_console_label_contacts($1::uuid[],$2::jsonb,$3::jsonb)',[[id],'["ITI"]','["Sanand"]']);
 assert.equal((await value(db,"select public.admin_console_audience($1,'contacts','all',0,'ITI','Sanand') data",[requirement])).data.length,1);
 assert.equal((await value(db,"select public.admin_console_audience($1,'contacts','all',0,'Other','Sanand') data",[requirement])).data.length,0);
});
test('numbers-only import normalizes/deduplicates without invented demographics or consent; malformed batch rolls back',async t=>{
 const db=await setup();t.after(()=>db.close());const result=(await value(db,'select public.admin_console_import_numbers($1::jsonb) data',['["+91 9876543210","9876543210"]'])).data;
 assert.equal(result.added,1);assert.equal(result.reused,1);let contact=await value(db,'select marketing_consent_status,imported_profile from public.whatsapp_contacts');assert.equal(contact.marketing_consent_status,'unknown');assert.deepEqual(contact.imported_profile,{Source:'number_import'});
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture'");await db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543210"]']);assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_out');
 await assert.rejects(db.query('select public.admin_console_import_numbers($1::jsonb)',['["9876543211","bad"]']),/Invalid Indian/);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});
test('console installation rejects retained legacy data and rolls back all new objects',async t=>{
 const db=await setup(false);t.after(()=>db.close());await importOne(db);await assert.rejects(db.exec(consoleMigration),/Complete the authorized retirement purge/);await db.exec('rollback');assert.equal((await value(db,"select to_regclass('public.whatsapp_template_catalog') id")).id,null);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
});
async function senderSetup(){const db=await setup();await db.exec(`
 alter table public.audit_logs add column correlation_id uuid;
 alter table public.whatsapp_outbound_messages add column destination text,add column template_name text,add column template_language text,add column template_version text,add column template_variables jsonb default '{}',add column attempt_count integer default 0,add column max_attempts integer default 3,add column created_at timestamptz default now(),add column updated_at timestamptz default now(),add column lease_owner text,add column lease_expires_at timestamptz,add column last_error_code text,add column provider_message_id text;
 alter table public.whatsapp_inbound_messages add column processing_status text default 'received',add column processed_at timestamptz,add column last_error_category text,add column last_error_code text,add column redacted_response jsonb default '{}',add column correlation_key text,add column application_id uuid,add column created_at timestamptz default now();
 create function public.set_whatsapp_contact_suppression(uuid,boolean,text,text) returns boolean language sql as $$select true$$;
 create function public.accept_whatsapp_webhook_event(text,text,text,jsonb) returns uuid language sql as $$select gen_random_uuid()$$;
 create function public.upsert_whatsapp_inbound_contact(text) returns uuid language sql as $$select null::uuid$$;
 create function public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb) returns uuid language sql as $$select gen_random_uuid()$$;
 create function public.record_whatsapp_message_event(uuid,uuid,text,text,text,timestamptz,text,text,text) returns uuid language sql as $$select gen_random_uuid()$$;
 create function public.process_whatsapp_interested_response(uuid) returns jsonb language sql as $$select '{"status":"canonical_application_delegate"}'::jsonb$$;
 `);await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/console-sender-contracts.sql'),'utf8'));await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261013114237_whatsapp_console_sender.sql'),'utf8'));return db;}
async function queuedSender(db,schedule=null){const tid=await sync(db),id=await importOne(db);await subscribe(db,id);await db.query("select public.console_sender_connection('1234567891','1234567890')");const campaign=(await prep(db,id,tid,undefined,schedule)).id;await db.query('select public.admin_console_approve($1)',[campaign]);await db.query('select public.admin_console_queue($1)',[campaign]);await db.exec("update public.whatsapp_outbound_messages set destination='+919876543210',template_name='aadhyant_vacancy_alert_v1',template_language='en',template_version='1',template_variables='{}'");return {id,campaign,tid};}
test('sender claim honors readiness, schedule and canonical campaign identity; boundary rechecks changed template',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign,tid}=await queuedSender(db);await db.exec('update private.whatsapp_console_config set sender_ready=false');assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows.length,0);await db.exec('update private.whatsapp_console_config set sender_ready=true');const msg=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows[0];assert.ok(msg);await db.query("update public.whatsapp_template_catalog set status='REJECTED' where id=$1",[tid]);await assert.rejects(db.query("select public.console_provider_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'test-worker']),/Sender or template/);assert.equal((await value(db,'select send_phase from public.whatsapp_outbound_messages')).send_phase,'claimed');});
test('late STOP and cancelled job prevent provider boundary; anonymous/service grants remain separated',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign,id}=await queuedSender(db);const msg=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows[0];await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='fixture' where id=$1",[id]);await assert.rejects(db.query("select public.console_provider_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'test-worker']),/suppressed/);await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_in',opted_out_at=null,opt_out_source=null;update public.employer_requirements set requirement_stage='closed'");await assert.rejects(db.query("select public.console_provider_boundary($1,$2,'1234567891','1234567890')",[msg.message_id,'test-worker']),/eligibility changed/);const grants=await value(db,"select has_function_privilege('anon','public.console_claim_campaign(uuid,text)','EXECUTE') anon,has_function_privilege('authenticated','public.console_sender_connection(text,text)','EXECUTE') client,has_function_privilege('service_role','public.console_claim_campaign(uuid,text)','EXECUTE') backend");assert.deepEqual(grants,{anon:false,client:false,backend:true});});
test('future schedule is not claimed; expired provider-call lease requires reconciliation and is never reclaimed',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign}=await queuedSender(db);await db.exec("update public.whatsapp_outbound_messages set next_attempt_at=clock_timestamp()+interval '1 hour'");assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows.length,0);await db.exec('update public.whatsapp_outbound_messages set next_attempt_at=clock_timestamp()');const msg=(await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'test-worker'])).rows[0];assert.equal((await value(db,"select public.console_provider_boundary($1,$2,'1234567891','1234567890') yes",[msg.message_id,'test-worker'])).yes,true);await db.exec("update public.whatsapp_outbound_messages set lease_expires_at=clock_timestamp()-interval '1 second'");assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[campaign,'next-worker'])).rows.length,0);assert.equal((await value(db,'select send_phase from public.whatsapp_outbound_messages')).send_phase,'reconciliation_required');});
test('imported Interested reply is correlated and idempotent, records registration-needed without inventing a candidate',async t=>{const db=await senderSetup();t.after(()=>db.close());const {campaign,id}=await queuedSender(db);await db.exec("update public.whatsapp_outbound_messages set state='sent',provider_message_id='wamid.fixture'");const m=(await value(db,"insert into public.whatsapp_inbound_messages(id,contact_id,message_type,action_id,provider_timestamp,correlation_key) values(gen_random_uuid(),$1,'button','INTERESTED',clock_timestamp(),'wamid.fixture') returning id",[id])).id;const result=(await value(db,'select public.console_process_interested($1) data',[m])).data;assert.equal(result.status,'registration_required');await db.query('select public.console_process_interested($1)',[m]);assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='whatsapp.interested_registration_required'")).n,1);assert.equal((await value(db,"select public.admin_console_replies($1,0) data",[campaign])).data[0].last_error_category,'registration_required');assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);});
test('future queueing cannot claim automatic scheduling before scheduler installation',async t=>{const db=await senderSetup();t.after(()=>db.close());const tid=await sync(db),id=await importOne(db);await subscribe(db,id);await db.query("select public.console_sender_connection('1234567891','1234567890')");const c=(await prep(db,id,tid,undefined,new Date(Date.now()+3600000).toISOString())).id;await db.query('select public.admin_console_approve($1)',[c]);await assert.rejects(db.query('select public.admin_console_queue($1)',[c]),/Automatic scheduler/);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);});
