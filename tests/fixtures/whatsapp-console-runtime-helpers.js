'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const root=path.resolve(__dirname,'../..');
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
async function setup(install=true){const db=new PGlite();await db.exec(fixture);await db.exec(fs.readFileSync(path.join(__dirname,'sharing-send-guard-baseline.sql'),'utf8'));await db.exec(migration);await db.exec("alter table public.whatsapp_outbound_messages add column state text default 'queued'; alter table public.candidates add column full_name text default 'Sample',add column highest_qualification text,add column specialization text,add column candidate_type text,add column current_location text,add column district text,add column state text; alter table public.employer_requirements add column qualification text,add column experience_requirement text;");await db.exec(upgrade);await db.exec("alter table public.whatsapp_outbound_messages add column next_attempt_at timestamptz default now(),add column send_phase text default 'ready',add column sent_at timestamptz,add column delivered_at timestamptz,add column read_at timestamptz,add column failed_at timestamptz,add column last_error_category text;create function public.admin_cancel_whatsapp_campaign(uuid) returns boolean language plpgsql as $f$begin update public.whatsapp_campaigns set campaign_status='cancelled',cancelled_at=clock_timestamp() where id=$1;return true;end;$f$;");await db.exec("create table public.whatsapp_webhook_events(id uuid);create table public.whatsapp_message_events(id uuid);");if(install)await db.exec(consoleMigration);return db;}
const value=async(db,sql,args=[])=>(await db.query(sql,args)).rows[0];
async function importOne(db){await db.query('select public.admin_import_sharing_contacts($1::jsonb)',[JSON.stringify([row])]);return (await value(db,'select id from public.whatsapp_contacts')).id;}
async function subscribe(db,id,scope='all',filters={locations:[],trades:[]}){
 const msg=(await value(db,"insert into public.whatsapp_inbound_messages values(gen_random_uuid(),$1,'text','SUBSCRIBE_JOB_UPDATES',clock_timestamp()) returning id",[id])).id;
 await db.query('select public.subscribe_whatsapp_sharing_updates($1,$2::jsonb)',[msg,JSON.stringify({scope,...filters})]);return msg;
}
const template={id:'1234567890',name:'aadhyant_vacancy_alert_v1',language:'en',status:'APPROVED',components:[{type:'BODY',text:'Vacancy: {{1}}\nRole: {{2}}'},{type:'BUTTONS',buttons:[{type:'QUICK_REPLY',text:'Interested'},{type:'QUICK_REPLY',text:'Stop alerts'}]}]};
const sync=async(db,data=[template])=>{await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify(data)]);return(await value(db,'select id from public.whatsapp_template_catalog limit 1')).id;};
const prep=(db,id,tid,op='00000000-0000-0000-0000-000000000070',schedule=null)=>value(db,'select public.admin_console_prepare($1,$2,$3::uuid[],$4,$5,$6) id',[requirement,tid,[id],'Job campaign',op,schedule]);

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
 `);await db.exec(fs.readFileSync(path.join(__dirname,'console-sender-contracts.sql'),'utf8'));await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261013114237_whatsapp_console_sender.sql'),'utf8'));return db;}
async function queuedSender(db,schedule=null){const tid=await sync(db),id=await importOne(db);await subscribe(db,id);await db.query("select public.console_sender_connection('1234567891','1234567890')");const campaign=(await prep(db,id,tid,undefined,schedule)).id;await db.query('select public.admin_console_approve($1)',[campaign]);await db.query('select public.admin_console_queue($1)',[campaign]);await db.exec("update public.whatsapp_outbound_messages set destination='+919876543210',template_name='aadhyant_vacancy_alert_v1',template_language='en',template_version='1',template_variables='{}'");return {id,campaign,tid};}

async function replySetup(){
 const db=await senderSetup();
 await db.exec(`alter table public.whatsapp_inbound_messages add column webhook_event_id uuid;
 alter table public.whatsapp_webhook_events add column signature_verified boolean;
 alter table public.whatsapp_outbound_messages add column message_type text default 'template';
 alter table public.whatsapp_outbound_messages add constraint whatsapp_outbound_messages_message_type_check check(message_type='template');`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014084313_whatsapp_interested_registration_reply.sql'),'utf8'));
 const fixture=await queuedSender(db);
 await db.exec(`update public.whatsapp_outbound_messages set state='read',provider_message_id='wamid.registration-fixture';
 update public.whatsapp_contacts set marketing_consent_status='unknown',consent_source=null,consent_scope=null,consent_recorded_at=null,consent_policy_version=null;
 insert into public.whatsapp_webhook_events values(gen_random_uuid(),true);`);
 const inbound=(await value(db,`insert into public.whatsapp_inbound_messages(id,contact_id,webhook_event_id,message_type,action_id,provider_timestamp,correlation_key)
 select gen_random_uuid(),$1,e.id,'button','INTERESTED',clock_timestamp(),'wamid.registration-fixture' from public.whatsapp_webhook_events e returning id`,[fixture.id])).id;
 await db.query('select public.console_process_interested($1)',[inbound]);
 return {db,inbound,...fixture};
}

async function flowSetup(){
 const f=await replySetup(),db=f.db;
 await db.exec(`alter table public.candidates add column age integer,add column gender text,add column interview_available text,add column consent boolean,add column profile_completion_status text default 'incomplete',add column acquisition_source_type text,add column acquisition_source_reference text;
 alter table public.candidate_applications add column id uuid default gen_random_uuid() primary key,add column source_type text,add column application_status text,add column source_reference text,add column correlation_id uuid,add unique(candidate_id,requirement_id);
 alter table public.whatsapp_inbound_messages add column campaign_recipient_id uuid;
 alter table public.whatsapp_inbound_messages add constraint whatsapp_inbound_interested_link_check check ((campaign_recipient_id is null and application_id is null) or (campaign_recipient_id is not null and application_id is not null and processing_status='processed'));`);
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014092316_whatsapp_registration_flow.sql'),'utf8'));
 await db.exec(fs.readFileSync(path.join(root,'supabase/migrations/20261014104931_whatsapp_chat_registration.sql'),'utf8'));
 await db.query("select public.console_verify_registration_flow('1234567899',$1,'1234567890')",['a'.repeat(64)]);
 const reply=(await db.query('select * from public.console_claim_registration_reply($1,$2)',[f.inbound,'flow-worker'])).rows[0];
 await db.query("select public.console_registration_boundary($1,$2,'1234567891','1234567890')",[reply.message_id,'flow-worker']);
 await db.query("select public.mark_whatsapp_outbound_sent($1,$2,'wamid.flow',null)",[reply.message_id,'flow-worker']);
 return {...f,reply};
}
const flowProfile={form_kind:'aadhyant_registration_v1',consent_policy_version:'wa-registration-alerts-v1',full_name:'Synthetic Candidate',age:'25',gender:'Male',state:'Gujarat',district:'Ahmedabad',current_village_city:'Sanand',highest_qualification:'ITI',course_trade_specialization:'Fitter',experience_status:'Fresher',interview_available:'Yes',registration_consent:true,job_alert_consent:true};
async function submitFlow(f,profile=flowProfile,overrides={}){
 const m=(await value(f.db,`insert into public.whatsapp_inbound_messages(id,contact_id,webhook_event_id,message_type,action_id,provider_timestamp,correlation_key,redacted_response)
 select gen_random_uuid(),$1,e.id,'flow','REGISTRATION_SUBMIT',clock_timestamp(),$2,$3::jsonb from public.whatsapp_webhook_events e limit 1 returning id`,[overrides.contact||f.id,overrides.token||f.reply.flow_token,JSON.stringify(profile)])).id;
 return {m,result:()=>value(f.db,'select public.console_process_registration_flow($1) data',[m])};
}

module.exports={root,value,setup,sync,importOne,subscribe,prep,template,requirement,senderSetup,queuedSender,replySetup,flowSetup,flowProfile,submitFlow};
