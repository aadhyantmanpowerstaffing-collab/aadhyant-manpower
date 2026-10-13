'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.resolve(__dirname,'..');
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261013045750_job_sharing_contacts.sql'),'utf8');
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
async function setup(){const db=new PGlite();await db.exec(fixture);await db.exec(fs.readFileSync(path.join(__dirname,'fixtures/sharing-send-guard-baseline.sql'),'utf8'));await db.exec(migration);await db.exec("alter table public.whatsapp_outbound_messages add column state text default 'queued'; alter table public.candidates add column full_name text default 'Sample',add column highest_qualification text,add column specialization text,add column candidate_type text,add column current_location text,add column district text,add column state text; alter table public.employer_requirements add column qualification text,add column experience_requirement text;");await db.exec(upgrade);return db;}
const value=async(db,sql,args=[])=>(await db.query(sql,args)).rows[0];
async function importOne(db){await db.query('select public.admin_import_sharing_contacts($1::jsonb)',[JSON.stringify([row])]);return (await value(db,'select id from public.whatsapp_contacts')).id;}
async function subscribe(db,id,scope='all',filters={locations:[],trades:[]}){
 const msg=(await value(db,"insert into public.whatsapp_inbound_messages values(gen_random_uuid(),$1,'text','SUBSCRIBE_JOB_UPDATES',clock_timestamp()) returning id",[id])).id;
 await db.query('select public.subscribe_whatsapp_sharing_updates($1,$2::jsonb)',[msg,JSON.stringify({scope,...filters})]);return msg;
}
const prepareSql='select public.admin_prepare_selected_job_campaign($1,$2,$3::uuid[],$4,$5,$6,$7) id';
const args=id=>[requirement,'00000000-0000-0000-0000-000000000030',[id],'Selected job test','approved_template','en','1'];
const optedIn=async(db,id)=>db.query("update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source='fixture',consent_scope='job_alerts',consent_recorded_at=clock_timestamp(),consent_policy_version='fixture-v1',opted_out_at=null,opt_out_source=null,opt_out_reason_category=null where id=$1",[id]);
test('manual outreach permits an opted-in nonregistered contact without subscription; import alone never does',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);
 await assert.rejects(db.query(prepareSql,args(id)),/not eligible/);await optedIn(db,id);
 assert.equal((await value(db,'select private.selected_job_contact_eligible($1,$2) ok',[id,requirement])).ok,true);
 const campaign=(await value(db,prepareSql,args(id))).id;assert.equal((await value(db,prepareSql,args(id))).id,campaign);
 assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);
 await assert.rejects(db.query('select public.admin_queue_selected_job_campaign($1)',[campaign]),/Approved/);
 await db.query('select public.admin_approve_selected_job_campaign($1)',[campaign]);await db.query('select public.admin_queue_selected_job_campaign($1)',[campaign]);await db.query('select public.admin_queue_selected_job_campaign($1)',[campaign]);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,1);
 const out=(await value(db,'select id from public.whatsapp_outbound_messages')).id;
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[out])).ok,true);
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp_inbound'");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[out])).ok,false);
});
test('registered nonmatches are visible in All view, eligible to select, with advisory mismatch reasons',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);await optedIn(db,id);
 await db.exec("insert into public.candidates(id,mobile,profile_status,status,full_name,highest_qualification,specialization,candidate_type,current_location,district,state) values('00000000-0000-0000-0000-000000000040','9876543210','active','new','Sample Candidate','12th','Welder','Fresher','Kadi','Mehsana','Gujarat'); update public.whatsapp_contacts set candidate_id='00000000-0000-0000-0000-000000000040',resolution_status='resolved'; update public.employer_requirements set qualification='ITI',experience_requirement='Experienced';");
 const query='select public.admin_preview_selected_job_contacts($1,$2,$3,0) list';
 assert.equal((await value(db,query,[requirement,'registered','suggested'])).list.length,0);
 const rows=(await value(db,query,[requirement,'registered','all'])).list;
 assert.equal(rows.length,1);assert.equal(rows[0].eligible,true);assert.equal(rows[0].suggested,false);assert.deepEqual(rows[0].match_reasons,['Qualification differs','Trade differs','Experience differs','Location differs']);
 assert.equal(JSON.stringify(rows).includes('9876543210'),false);
 const campaign=(await value(db,prepareSql,args(id))).id;await db.query('select public.admin_approve_selected_job_campaign($1)',[campaign]);
 await db.exec("insert into public.candidate_applications values('00000000-0000-0000-0000-000000000040','00000000-0000-0000-0000-000000000002')");await assert.rejects(db.query('select public.admin_queue_selected_job_campaign($1)',[campaign]),/changed or suppressed/);
});
test('STOP before approval, ambiguous identities and explicit filtered subscription remain blocked',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);await optedIn(db,id);
 const campaign=(await value(db,prepareSql,args(id))).id;
 await db.exec("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=clock_timestamp(),opt_out_source='whatsapp_inbound'");await assert.rejects(db.query('select public.admin_approve_selected_job_campaign($1)',[campaign]),/changed or suppressed/);
 await optedIn(db,id);await db.exec("update public.whatsapp_contacts set resolution_status='ambiguous'");assert.equal((await value(db,'select private.selected_job_contact_eligible($1,$2) ok',[id,requirement])).ok,false);
 await db.exec("update public.whatsapp_contacts set resolution_status='unresolved'");await subscribe(db,id,'filtered',{locations:['Kadi'],trades:[]});assert.equal((await value(db,'select private.selected_job_contact_eligible($1,$2) ok',[id,requirement])).ok,false);
});
test('closed jobs and cancellation prevent delivery; operation mismatch does not alter frozen audience',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);await optedIn(db,id);const a=args(id),campaign=(await value(db,prepareSql,a)).id;
 await assert.rejects(db.query(prepareSql,[...a.slice(0,3),'Changed name',...a.slice(4)]),/conflicts/);
 await db.query('select public.admin_approve_selected_job_campaign($1)',[campaign]);await db.query('select public.admin_queue_selected_job_campaign($1)',[campaign]);const out=(await value(db,'select id from public.whatsapp_outbound_messages')).id;
 await db.exec("update public.employer_requirements set requirement_stage='closed'");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[out])).ok,false);
 await db.exec("update public.employer_requirements set requirement_stage='open';update public.whatsapp_campaigns set campaign_status='cancelled',cancelled_at=clock_timestamp()");assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[out])).ok,false);
});
test('admin-only RPCs and bounded query filters reject unauthorized callers',async t=>{
 const db=await setup();t.after(()=>db.close());const id=await importOne(db);
 for(const signature of ['public.admin_preview_selected_job_contacts(uuid,text,text,integer)','public.admin_prepare_selected_job_campaign(uuid,uuid,uuid[],text,text,text,text)','public.admin_queue_selected_job_campaign(uuid)'])assert.equal((await value(db,'select has_function_privilege($1,$2,\'execute\') ok',['anon',signature])).ok,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query(prepareSql,args(id)),/Admin access/);
 await db.exec("select set_config('test.admin','yes',false)");await assert.rejects(db.query('select public.admin_preview_selected_job_contacts($1,\'registered\',\'all\',6000)',[requirement]),/Invalid/);
});
test('registered candidates without contact are shown as unavailable, never silently selectable',async t=>{
 const db=await setup();t.after(()=>db.close());await db.exec("insert into public.candidates(id,profile_status,status,full_name) values('00000000-0000-0000-0000-000000000045','active','new','No WhatsApp Contact')");
 const rows=(await value(db,"select public.admin_preview_selected_job_contacts($1,'registered','all',0) list",[requirement])).list;
 assert.equal(rows.length,1);assert.equal(rows[0].contact_id,null);assert.equal(rows[0].eligible,false);assert.equal(rows[0].status,'WhatsApp contact unavailable');
});
