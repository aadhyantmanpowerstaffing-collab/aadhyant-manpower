'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base}=require('./fixtures/automatic-alert-runtime-setup');
const {value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
const map=JSON.parse(fs.readFileSync('docs/whatsapp/full-job-field-map.json','utf8'));
const upgrade=fs.readFileSync('supabase/migrations/20261016114752_complete_whatsapp_job_information.sql','utf8');
const {setup}=require('./fixtures/full-job-runtime-setup');
test('full renderer includes every candidate-facing field, structured benefits, complete description and IST interview date',async()=>{const {db}=await setup();try{
 const raw=JSON.parse(fs.readFileSync('tests/fixtures/full-job-example.json','utf8'));
 for(const [k,v] of Object.entries(raw))await db.query('update public.employer_requirements set '+k+'=$1 where id=$2',[v,requirement]);
 await db.query("insert into private.vacancy_candidate_benefits values($1,'uniform','provided',null,null),($1,'joining_bonus','cash',1000,'one_time')",[requirement]);
 const vars=(await value(db,'select private.registered_alert_variables($1) v',[requirement])).v;
 const all=Object.values(vars).join(' ');
 for(const [section,fields] of Object.entries(map.sections))for(const [k,label] of fields){if(['open_positions','required_headcount','interview_date_display'].includes(k))continue;assert.ok(vars[section].includes(label+': '),k+' missing label');assert.ok(vars[section].includes(raw[k].replaceAll('_',' ')),k+' missing value');}
 assert.match(all,/01 Nov 2026 10:00 IST/);assert.match(all,/Uniform: provided/);assert.match(all,/Joining Bonus: INR 1000 one time/);assert.match(all,/Safety rules apply/);
 const preview=(await value(db,'select public.admin_console_preview_full_job_alert($1) p',[requirement])).p;
 assert.equal(preview.within_limits,true);assert.equal(preview.template_name,'aadhyant_registered_job_alert_v2');assert.doesNotMatch(preview.message,/\{\{/);
 // New candidate-visible benefit edits must change the frozen message fingerprint.
 await db.exec("update private.vacancy_candidate_benefits set amount=2000 where benefit_type='joining_bonus'");
 assert.notDeepEqual((await value(db,'select private.registered_alert_variables($1) v',[requirement])).v,vars);
 }finally{await db.close();}});
test('empty fields are omitted, zero is preserved, descriptions are not truncated and legacy envelopes stay strict',async()=>{const {db}=await setup();try{
 await db.query("update public.employer_requirements set company_name='Example',employee_pf='0',additional_notes=$1",['x'.repeat(2000)]);
 const v=(await value(db,'select private.registered_alert_variables($1) v',[requirement])).v;
 assert.equal(v.description_1+v.description_2,'x'.repeat(2000));assert.match(v.deductions,/Employee PF \(INR\): 0/);assert.doesNotMatch(v.job_identity,/Department:/);
 assert.equal((await value(db,'select private.whatsapp_safe_flat_json($1::jsonb) ok',[JSON.stringify(v)])).ok,true);
 for(const bad of [{...v,bank_account:'private'},{...v,description_1:'x'.repeat(1001)},{...v,description_1:'one\ntwo'},{job_details:'x'.repeat(501)}])assert.equal((await value(db,'select private.whatsapp_safe_flat_json($1::jsonb) ok',[JSON.stringify(bad)])).ok,false);
 await db.query('update public.employer_requirements set additional_notes=$1',['x'.repeat(2001)]);
 assert.equal((await value(db,'select public.admin_console_preview_full_job_alert($1) p',[requirement])).p.within_limits,false);
 await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_console_preview_full_job_alert($1)',[requirement]),/Admin access/);
 assert.equal((await value(db,"select has_function_privilege('anon','public.admin_console_preview_full_job_alert(uuid)','execute') ok")).ok,false);
 }finally{await db.close();}});
test('only exact approved v2 metadata can enable and prepare automatic campaigns; v1 is insufficient',async()=>{const {db}=await setup();try{
 await assert.rejects(db.query('select public.admin_console_set_automatic_alerts(true,10)'),/Approved template/);
 const template=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v2.json','utf8'));template.id='1234567899';template.status='APPROVED';
 await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([template])]);
 assert.equal((await value(db,"select compatible from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v2'")).compatible,true);
 await db.query('select public.admin_console_set_automatic_alerts(true,10)');
 const c=(await value(db,"insert into public.candidates(mobile,profile_status,status) values('9876543210','active','new') returning id")).id;
 await db.query("insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version) values('+919876543210','9876543210',$1,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'test')",[c]);
 await db.query("update public.employer_requirements set review_status='approved',additional_notes=repeat('x',1200) where id=$1",[requirement]);
 const row=(await db.query("select * from public.console_claim_registered_alerts('v2-worker')")).rows[0];assert.ok(row);assert.equal(row.template_name,'aadhyant_registered_job_alert_v2');assert.equal(row.template_variables.template_contract,'registered_full_v2');assert.equal(row.template_variables.description_1.length,1000);assert.equal(row.template_variables.description_2.length,200);
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[row.message_id])).ok,true);
 await db.query("update public.employer_requirements set accommodation_status='free' where id=$1",[requirement]);
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[row.message_id])).ok,false);
 }finally{await db.close();}});
