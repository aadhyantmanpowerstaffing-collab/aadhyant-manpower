'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.resolve(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261013045750_job_sharing_contacts.sql'),'utf8');
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
async function setup(){const db=new PGlite();await db.exec(fixture);await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/sharing-send-guard-baseline.sql'),'utf8'));await db.exec(migration);return db;}
const value=async(db,sql,args=[])=>(await db.query(sql,args)).rows[0];
async function importOne(db){await db.query('select public.admin_import_sharing_contacts($1::jsonb)',[JSON.stringify([row])]);return (await value(db,'select id from public.whatsapp_contacts')).id;}
async function subscribe(db,id,scope='all',filters={locations:[],trades:[]}){
 const msg=(await value(db,"insert into public.whatsapp_inbound_messages values(gen_random_uuid(),$1,'text','SUBSCRIBE_JOB_UPDATES',clock_timestamp()) returning id",[id])).id;
 await db.query('select public.subscribe_whatsapp_sharing_updates($1,$2::jsonb)',[msg,JSON.stringify({scope,...filters})]);return msg;
}
test('migration compiles; import dedupes and creates no Candidate, consent or outbound',async t=>{
 const db=await setup();t.after(()=>db.close());await importOne(db);await importOne(db);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,1);
 assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');
});
test('import authorization, malformed rows and mixed invalid batch fail atomically',async t=>{
 const db=await setup();t.after(()=>db.close());await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_import_sharing_contacts($1::jsonb)',[JSON.stringify([row])]),/Admin access/);
 await db.exec("select set_config('test.admin','yes',false)");await assert.rejects(db.query('select public.admin_import_sharing_contacts($1::jsonb)',[JSON.stringify([row,{...row,Mobile:'9123456789',Gender:null}])]),/Invalid import/);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_contacts')).n,0);
});
test('verified subscription, filtered trade/location, STOP replay and import preservation',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);
 assert.equal((await value(db,'select private.sharing_contact_eligible($1,$2) ok',[id,requirement])).ok,false);
 const event=await subscribe(db,id,'filtered',{locations:['Sanand'],trades:['Fitter']});assert.equal((await value(db,'select private.sharing_contact_eligible($1,$2) ok',[id,requirement])).ok,true);
 await db.exec("update public.employer_requirements set iti_trade='Welder'");assert.equal((await value(db,'select private.sharing_contact_eligible($1,$2) ok',[id,requirement])).ok,false);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp_inbound'");
 await db.query('select public.subscribe_whatsapp_sharing_updates($1,$2::jsonb)',[event,JSON.stringify({scope:'all',locations:[],trades:[]})]);await importOne(db);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'opted_out');
});
test('manual prepare, explicit approve, idempotent queue and send-time cancellation/STOP',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);await subscribe(db,id);
 const args=[requirement,'00000000-0000-0000-0000-000000000003',[id],'Sharing Pilot','approved_template','en','1'];
 const prepare='select public.admin_prepare_sharing_campaign($1,$2,$3::uuid[],$4,$5,$6,$7) id';
 const campaign=(await value(db,prepare,args)).id;assert.equal((await value(db,prepare,args)).id,campaign);
 await assert.rejects(db.query('select public.admin_queue_sharing_campaign($1)',[campaign]),/Approved/);
 await db.query('select public.admin_approve_sharing_campaign($1)',[campaign]);await db.query('select public.admin_queue_sharing_campaign($1)',[campaign]);await db.query('select public.admin_queue_sharing_campaign($1)',[campaign]);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,1);
 const outbound=(await value(db,'select id from public.whatsapp_outbound_messages')).id;
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[outbound])).ok,true);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp_inbound'");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[outbound])).ok,false);
 await db.exec("update public.whatsapp_campaigns set campaign_status='cancelled',cancelled_at=clock_timestamp()");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[outbound])).ok,false);
});
test('anonymous lacks RPC execute; subscriber RPC service-only; projections mask mobile',async t=>{
 const db=await setup();t.after(()=>db.close());await importOne(db);
 const checks=await value(db,"select has_function_privilege('anon','public.admin_import_sharing_contacts(jsonb)','execute') anon,has_function_privilege('authenticated','public.subscribe_whatsapp_sharing_updates(uuid,jsonb)','execute') candidate,has_function_privilege('service_role','public.subscribe_whatsapp_sharing_updates(uuid,jsonb)','execute') service");assert.deepEqual(checks,{anon:false,candidate:false,service:true});
 const r=await value(db,'select public.admin_list_sharing_contacts() list');assert.equal(r.list[0].mobile_masked,'+91XXXXXX3210');assert.equal(JSON.stringify(r.list).includes(row.Mobile),false);assert.equal(JSON.stringify(r.list).includes(row.Email),false);
});
test('profile filters narrow the audience and never reveal email or full phone',async t=>{
 const db=await setup();t.after(()=>db.close());await importOne(db);
 const query='select public.admin_list_sharing_contacts(null,$1::jsonb,0) list';
 assert.equal((await value(db,query,[JSON.stringify({state:'Gujarat',gender:'Male',age_min:'24',age_max:'26'})])).list.length,1);
 assert.equal((await value(db,query,[JSON.stringify({district:'Mehsana'})])).list.length,0);
 await assert.rejects(db.query(query,[JSON.stringify({age_min:'not a number'})]),/Invalid contact filters/);
});
test('unknown consent, blocked identity and wrong subscription cannot be selected manually',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);
 const sql='select public.admin_prepare_sharing_campaign($1,$2,$3::uuid[],$4,$5,$6,$7) id',args=[requirement,'00000000-0000-0000-0000-000000000009',[id],'Sharing Test','approved_template','en','1'];
 await assert.rejects(db.query(sql,args),/not eligible/);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaigns')).n,0);
 await subscribe(db,id,'filtered',{locations:['Kadi'],trades:[]});await assert.rejects(db.query(sql,args),/not eligible/);
 await db.exec("update public.whatsapp_contacts set resolution_status='blocked'");await assert.rejects(db.query(sql,args),/not eligible/);
});
test('job closure after queue and changed subscription stop an outbound attempt',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);await subscribe(db,id);
 const campaign=(await value(db,'select public.admin_prepare_sharing_campaign($1,$2,$3::uuid[],$4,$5,$6,$7) id',[requirement,'00000000-0000-0000-0000-000000000008',[id],'Sharing Test','approved_template','en','1'])).id;
 await db.query('select public.admin_approve_sharing_campaign($1)',[campaign]);await db.query('select public.admin_queue_sharing_campaign($1)',[campaign]);const outbound=(await value(db,'select id from public.whatsapp_outbound_messages')).id;
 await db.exec("update public.employer_requirements set requirement_stage='closed'");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[outbound])).ok,false);
 await db.exec("update public.employer_requirements set requirement_stage='open'; update public.whatsapp_contacts set sharing_subscription='{}'");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[outbound])).ok,false);
});
test('guard baseline/RLS mismatches stop installation without partially changing schema',async t=>{
 const db=new PGlite();t.after(()=>db.close());await db.exec(fixture);await assert.rejects(db.exec(migration),/Send guard baseline changed/);await db.exec('rollback');
 assert.equal((await value(db,"select count(*)::int n from information_schema.columns where table_name='whatsapp_contacts' and column_name='imported_profile'")).n,0);
});
