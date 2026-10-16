'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:full}=require('./fixtures/full-job-runtime-setup');
const {value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
const readable=fs.readFileSync('supabase/migrations/20261016124516_readable_whatsapp_job_layout.sql','utf8');
const upgrade=fs.readFileSync('supabase/migrations/20261016131116_concise_registered_job_alerts.sql','utf8');
const template=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v4.json','utf8'));
async function setup(){const f=await full();await f.db.exec(readable);await f.db.exec(upgrade);return f;}
test('summary has separate salary/duty lines, correct bounds and full-job fingerprint without exposing omitted details',async()=>{const {db}=await setup();try{
 const raw=JSON.parse(fs.readFileSync('tests/fixtures/full-job-example.json','utf8'));raw.additional_notes='x'.repeat(2000);
 for(const [k,v] of Object.entries(raw))await db.query('update public.employer_requirements set '+k+'=$1 where id=$2',[v,requirement]);
 const vars=(await value(db,'select private.registered_alert_variables($1) v',[requirement])).v;
 assert.equal(vars.template_contract,'registered_summary_v4');assert.match(vars.job_fingerprint,/^[a-f0-9]{64}$/);assert.match(vars.salary,/15000 to 18000/);assert.match(vars.take_home,/13259/);assert.match(vars.benefits,/charges apply/);assert.doesNotMatch(vars.benefits,/Free transport/);
 const preview=(await value(db,'select public.admin_console_preview_full_job_alert($1) p',[requirement])).p;
 assert.equal(preview.template_name,template.name);assert.equal(preview.within_limits,true);assert.ok(preview.body_characters<=1024);assert.match(preview.message,/\n• CTC \/ Salary: .+\n• Approx. take home: .+\n• Overtime: .+\n• Duty:/);assert.doesNotMatch(preview.message,/\{\{|job_fingerprint|x{30}/);
 assert.equal((await value(db,'select private.registered_alert_body() body')).body,template.components[0].text);
 await db.query("update public.employer_requirements set additional_notes='Updated safety rules' where id=$1",[requirement]);const changed=(await value(db,'select private.registered_alert_variables($1) v',[requirement])).v;assert.notEqual(changed.job_fingerprint,vars.job_fingerprint);assert.equal(changed.salary,vars.salary);
 for(const bad of [{...changed,bank_account:'private'},{...changed,salary:'one\ntwo'},{...changed,job_fingerprint:'bad'},{...changed,qualification:'x'.repeat(301)},{...changed,qualification:'x'.repeat(300),salary:'y'.repeat(300),benefits:'z'.repeat(300)}])assert.equal((await value(db,'select private.whatsapp_safe_flat_json($1::jsonb) ok',[JSON.stringify(bad)])).ok,false);
 await db.query("update public.employer_requirements set employee_pf='0',employer_pf='0',employee_esic='0',employer_esic='0',transport_status='free',canteen_status='free' where id=$1",[requirement]);const zero=(await value(db,'select private.registered_alert_variables($1) v',[requirement])).v;assert.doesNotMatch(zero.benefits,/PF listed|ESIC listed/);assert.match(zero.benefits,/Free transport; Free canteen/);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_preview_full_job_alert(uuid)','execute') ok")).ok,false);await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_console_preview_full_job_alert($1)',[requirement]),/Admin access/);
 }finally{await db.close();}});
test('only approved v4 can prepare automatic canonical summary; omitted benefit changes pause frozen sends',async()=>{const {db}=await setup();try{
 const old=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v2.json','utf8'));await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([{...old,id:'1234567899',status:'APPROVED'}])]);await assert.rejects(db.query('select public.admin_console_set_automatic_alerts(true,10)'),/Approved template/);
 await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([{...template,id:'1234567800',status:'APPROVED'}])]);await db.query('select public.admin_console_set_automatic_alerts(true,10)');
 const c=(await value(db,"insert into public.candidates(mobile,profile_status,status) values('9876543210','active','new') returning id")).id;
 await db.query("insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version) values('+919876543210','9876543210',$1,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'test')",[c]);
 await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);const row=(await db.query("select * from public.console_claim_registered_alerts('summary-worker')")).rows[0];assert.ok(row);assert.equal(row.template_name,template.name);assert.equal(row.template_variables.template_contract,'registered_summary_v4');assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[row.message_id])).ok,true);
 await db.query("insert into private.vacancy_candidate_benefits values($1,'uniform','provided',null,null)",[requirement]);assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[row.message_id])).ok,false);
 }finally{await db.close();}});
