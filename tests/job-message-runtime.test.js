'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:full}=require('./fixtures/full-job-runtime-setup');
const {value,importOne,subscribe,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
const api=require('../admin/job-message');
const migration=fs.readFileSync('supabase/migrations/20261101032123_wanotifier_job_message_composer.sql','utf8');
const fields={qualification:'10th / 12th / ITI',group_1:'10th / 12th',ctc_1:'₹17,174/month',take_home_1:'₹15,326/month',ot_1:'₹121/hour',group_2:'ITI',ctc_2:'₹17,495/month',take_home_2:'₹15,602/month',ot_2:'₹122/hour',benefits:'PF & ESIC; bus; canteen; 8 hours duty'};
const spec=l=>({...JSON.parse(fs.readFileSync('docs/whatsapp/job-salary-details-'+l+'-v2.json','utf8')),id:l==='en'?'1234567801':'1234567802',status:'APPROVED'});
async function setup(){const {db}=await full();for(const f of ['20261016124516_readable_whatsapp_job_layout.sql','20261016131116_concise_registered_job_alerts.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));await db.exec(migration);await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([spec('en'),spec('hi')])]);const id=await importOne(db);await subscribe(db,id);return {db,id};}
async function prepare(f,language='en',data=fields,operation='00000000-0000-0000-0000-000000000081'){
 const tid=(await value(f.db,'select id from public.whatsapp_template_catalog where name=$1',[api.name(language)])).id;
 const cid=(await value(f.db,'select public.admin_console_prepare_job_message($1,$2,$3::uuid[],$4,$5,$6::jsonb) id',[requirement,tid,[f.id],'Salary details',operation,JSON.stringify(data)])).id;
 return {cid,tid};
}
test('both languages match submitted bodies; two salary groups, OT, benefits and Interested remain variable',()=>{
 for(const language of ['en','hi']){assert.equal(spec(language).components[0].text,api.bodies[language]);const text=api.render(language,fields);assert.match(text,/₹17,174/);assert.match(text,/₹122\/hour/);assert.match(text,/96244 53543/);assert.match(text,/Interested/);assert.doesNotMatch(text,/\{\{/);}
 for(const bad of [{...fields,ot_1:''},{...fields,group_1:'x\nother'},{...fields,benefits:'x'.repeat(301)},{...fields,ctc_1:'{{2}}'},{...fields,secret:'private'}])assert.throws(()=>api.render('en',bad));
});
test('template sync rejects v1, wrong buttons, body changes and additional components',async t=>{
 const f=await setup();t.after(()=>f.db.close());
 assert.equal((await value(f.db,'select count(*)::int n from public.whatsapp_template_catalog where compatible')).n,2);
 for(const mutate of [s=>s.components[1].buttons[0].text='Apply',s=>s.components[0].text+=' altered',s=>s.components.push({type:'HEADER',text:'extra'})]){const s=spec('en');mutate(s);await f.db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([s])]);assert.equal((await value(f.db,'select compatible from public.whatsapp_template_catalog where name=$1',[s.name])).compatible,false);}
});
for(const language of ['en','hi'])test(language+' prepares, approves, queues once and binds the exact job/message to the canonical outbox',async t=>{
 const f=await setup();t.after(()=>f.db.close());const {db}=f,{cid}=await prepare(f,language);
 assert.equal((await prepare(f,language)).cid,cid);
 const saved=(await value(db,'select public.admin_console_job_message_preview($1) p',[cid])).p;assert.equal(saved.message,api.render(language,fields));assert.equal(saved.requirement_code,'TEST_JOB');
 await assert.rejects(prepare(f,language,{...fields,ctc_1:'₹1'}),/operation conflicts/);
 await assert.rejects(db.query('select public.admin_console_queue($1)',[cid]),/Approved/);
 await db.query('select public.admin_console_approve($1)',[cid]);
 assert.equal((await value(db,'select public.admin_console_queue($1) n',[cid])).n,1);await db.query('select public.admin_console_queue($1)',[cid]);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,1);
 const out=await value(db,'select * from public.whatsapp_outbound_messages');assert.equal(out.template_language,language);assert.equal(out.max_attempts,1);assert.equal(out.template_variables.ctc_1,fields.ctc_1);assert.equal(out.template_variables.template_contract,'salary_details_v2');
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[out.id])).ok,true);
 assert.equal((await db.query('select * from public.console_claim_campaign($1,$2)',[cid,'legacy-worker'])).rows.length,0);
 const claimed=(await db.query('select * from public.console_claim_job_message_campaign($1,$2)',[cid,'synthetic-worker'])).rows;assert.equal(claimed.length,1);
 await db.query("update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='fixture' where id=$1",[f.id]);
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[out.id])).ok,false);
 await assert.rejects(db.query("select public.console_provider_boundary($1,'synthetic-worker','1234567891','1234567890')",[out.id]));
});
test('job edits, tampered fields, missing template approval and unauthorized preparation fail closed',async t=>{
 const f=await setup();t.after(()=>f.db.close());const {db}=f,{cid,tid}=await prepare(f);
 await assert.rejects(db.query('select public.admin_console_prepare($1,$2,$3::uuid[],$4,$5)',[requirement,tid,[f.id],'Unsafe generic','00000000-0000-0000-0000-000000000082']),/Use Job Message/);
 await db.query("update public.employer_requirements set job_role='Changed role' where id=$1",[requirement]);
 await assert.rejects(db.query('select public.admin_console_approve($1)',[cid]),/Template changed/);
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,0);
 await db.exec("update public.whatsapp_template_catalog set status='PENDING'");await assert.rejects(prepare(f));
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(prepare(f),/Admin access/);
 for(const role of ['anon','service_role'])assert.equal((await value(db,"select has_function_privilege($1,'public.admin_console_prepare_job_message(uuid,uuid,uuid[],text,uuid,jsonb,timestamp with time zone)','EXECUTE') ok",[role])).ok,false);
 assert.equal((await value(db,"select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname in ('admin_console_prepare_job_message','admin_console_job_message_route','console_template_valid','whatsapp_vacancy_send_eligible') and p.prosecdef and not coalesce(p.proconfig,'{}') @> array['search_path=\"\"']")).n,0);
});
test('Interested uses the exact canonical outgoing message and never guesses the last job or grants alerts consent',async t=>{
 const f=await setup();t.after(()=>f.db.close());const {db}=f,{cid}=await prepare(f);
 await db.query('select public.admin_console_approve($1)',[cid]);await db.query('select public.admin_console_queue($1)',[cid]);
 await db.exec("update public.whatsapp_outbound_messages set state='sent',provider_message_id='wamid.exact-job';update public.whatsapp_contacts set marketing_consent_status='unknown',consent_recorded_at=null,consent_scope=null,consent_source=null,consent_policy_version=null");
 const inbound=async context=>(await value(db,"insert into public.whatsapp_inbound_messages(id,contact_id,message_type,action_id,provider_timestamp,correlation_key) values(gen_random_uuid(),$1,'button','INTERESTED',clock_timestamp(),$2) returning id",[f.id,context])).id;
 const unknown=await inbound('wamid.other-job');assert.equal((await value(db,'select public.console_process_interested($1) data',[unknown])).data.status,'ignored');
 const id=await inbound('wamid.exact-job'),result=(await value(db,'select public.console_process_interested($1) data',[id])).data;
 assert.equal(result.status,'registration_required');assert.equal(result.requirement_id,requirement);
 await db.query('select public.console_process_interested($1)',[id]);assert.equal((await value(db,"select count(*)::int n from public.audit_logs where action='whatsapp.interested_registration_required'")).n,1);
 assert.equal((await value(db,'select marketing_consent_status from public.whatsapp_contacts')).marketing_consent_status,'unknown');assert.equal((await value(db,'select count(*)::int n from public.candidates')).n,0);
});
