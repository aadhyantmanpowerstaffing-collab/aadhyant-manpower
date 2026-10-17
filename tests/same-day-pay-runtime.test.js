'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:full}=require('./fixtures/full-job-runtime-setup');
const {value}=require('./fixtures/whatsapp-console-runtime-helpers');
const migration=fs.readFileSync('supabase/migrations/20261017045434_same_day_pay_jobs.sql','utf8');
const company='00000000-0000-0000-0000-000000000011',contractor='00000000-0000-0000-0000-000000000012';
async function setup(){const f=await full(),db=f.db;
 await db.exec(fs.readFileSync('supabase/migrations/20261016124516_readable_whatsapp_job_layout.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/20261016131116_concise_registered_job_alerts.sql','utf8'));
 await db.exec(`alter table public.employer_requirements alter column id set default gen_random_uuid();alter table public.employer_requirements add column if not exists company_id uuid,add column if not exists source_type text,add column if not exists review_feedback text;
 alter table public.candidate_applications add column id uuid primary key default gen_random_uuid();create unique index on public.candidate_applications(candidate_id,requirement_id);
 create table public.requirement_contractors(requirement_id uuid,contractor_id uuid,origin_type text,submission_status text,review_feedback text);
 create function private.current_candidate_portal_id() returns uuid language sql stable as $$select nullif(current_setting('test.candidate',true),'')::uuid$$;
 create function private.can_review_vacancies() returns boolean language sql stable as $$select current_setting('test.role',true)='admin'$$;
 create function private.can_manage_company_portal() returns boolean language sql stable as $$select current_setting('test.role',true)='company'$$;
 create function private.can_manage_contractor_vacancies() returns boolean language sql stable as $$select current_setting('test.role',true)='contractor'$$;
 create function private.current_company_portal_id(boolean) returns uuid language sql stable as $$select case when current_setting('test.role',true)='company' then coalesce(nullif(current_setting('test.company',true),''),'${company}')::uuid end$$;
 create function private.current_contractor_portal_id(boolean) returns uuid language sql stable as $$select case when current_setting('test.role',true)='contractor' then '${contractor}'::uuid end$$;
 create function private.normalized_vacancy_review_status(uuid) returns text language sql stable as $$select review_status from public.employer_requirements where id=$1$$;
 -- Minimal canonical RPC adapters: exercise this migration's actual functions, not real customer accounts or a provider.
 create function public.manage_company_portal_vacancy(p_action text,p_requirement_id uuid default null,p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,p_shift_details text default null,p_working_hours text default null,p_additional_notes text default null)
 returns table(id uuid) language plpgsql as $f$declare rid uuid:=p_requirement_id;begin
 if not private.can_manage_company_portal() then raise exception 'denied';end if;
 if p_action='create' then insert into public.employer_requirements(company_id,source_type,company_name,requirement_code,job_role,job_location,required_headcount,filled_positions,requirement_stage,requirement_visibility,review_status,shift_details,working_hours,additional_notes) values(private.current_company_portal_id(true),'employer_portal','Synthetic Company','TEST_'||replace(gen_random_uuid()::text,'-',''),p_job_role,p_job_location,p_required_headcount,0,'draft','private','draft',p_shift_details,p_working_hours,p_additional_notes) returning employer_requirements.id into rid;
 elsif p_action='update' then update public.employer_requirements set job_role=p_job_role,job_location=p_job_location,required_headcount=p_required_headcount,shift_details=p_shift_details,working_hours=p_working_hours,additional_notes=p_additional_notes where employer_requirements.id=rid;
 elsif p_action in ('submit','resubmit') then update public.employer_requirements set review_status='pending_review' where employer_requirements.id=rid;else raise exception 'unknown action';end if;
 return query select rid;end;$f$;
 create function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid default null,p_client_name text default null,p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,p_shift_details text default null,p_working_hours text default null,p_additional_notes text default null)
 returns table(id uuid) language plpgsql as $f$declare rid uuid:=p_requirement_id;begin
 if not private.can_manage_contractor_vacancies() then raise exception 'denied';end if;
 if p_action='create' then insert into public.employer_requirements(source_type,company_name,requirement_code,job_role,job_location,required_headcount,filled_positions,requirement_stage,requirement_visibility,review_status,shift_details,working_hours,additional_notes) values('contractor_portal',p_client_name,'TEST_'||replace(gen_random_uuid()::text,'-',''),p_job_role,p_job_location,p_required_headcount,0,'draft','private','draft',p_shift_details,p_working_hours,p_additional_notes) returning employer_requirements.id into rid;
 insert into public.requirement_contractors values(rid,'${contractor}','contractor_submission','draft');
 elsif p_action='update' then update public.employer_requirements set job_role=p_job_role,job_location=p_job_location where employer_requirements.id=rid;
 elsif p_action in ('submit','resubmit') then update public.employer_requirements set review_status='pending_review' where employer_requirements.id=rid;update public.requirement_contractors set submission_status='submitted' where requirement_id=rid;end if;return query select rid;end;$f$;
 create function public.apply_candidate_job(text) returns uuid language plpgsql as $$declare aid uuid;begin insert into public.candidate_applications(candidate_id,requirement_id) select private.current_candidate_portal_id(),r.id from public.employer_requirements r where r.requirement_code=$1 returning id into aid;return aid;end;$$;
 select set_config('test.role','company',false);
 `);
 await db.exec(migration);
 const tomorrow=(await value(db,"select ((clock_timestamp() at time zone 'Asia/Kolkata')::date+1)::text d")).d;
 const payload={job_role:'Packing Helper',job_location:'Sanand GIDC, Gate 2',company_name:'Synthetic Client',required_headcount:'1',work_date:tomorrow,starts_at:'08:00',ends_at:'12:00',pay_amount:'350',payment_time:'18:00',payment_method:'upi',payment_by:'company',reporting_point:'Gate 2',contact_name:'Synthetic Supervisor',contact_phone:'9876543210',facilities:'Bring safety shoes'};
 return {db,payload};
}
async function submit(db,p,role='company',key=crypto.randomUUID(),id=null){return(await value(db,'select public.submit_same_day_job($1,$2::jsonb,$3,$4) id',[role,JSON.stringify(p),key,id])).id;}
async function publish(db,id){await db.query("update public.employer_requirements set review_status='approved',requirement_stage='open',requirement_visibility='public' where id=$1",[id]);}
async function candidate(db,phone='9876543211'){const c=(await value(db,"insert into public.candidates(full_name,mobile,whatsapp_number,profile_status,status) values('Synthetic Candidate',$1,$1,'active','new') returning id",[phone])).id;await db.query("select set_config('test.candidate',$1,false)",[c]);await db.exec("select set_config('test.role','candidate',false)");return c;}
test('same-day canonical submission is idempotent, private until review, with validated shift pay and correction ownership',async()=>{const {db,payload:p}=await setup();try{
 const key=crypto.randomUUID(),id=await submit(db,p,'company',key);assert.equal(await submit(db,p,'company',key),id);
 assert.equal((await db.query("select * from public.list_same_day_jobs('public')")).rows.length,0);
 assert.equal((await db.query("select * from public.list_same_day_jobs('owner')")).rows.length,1);
 await assert.rejects(submit(db,{...p,pay_amount:'400'},'company',key),/conflicts/);
 for(const change of [{pay_amount:'0'},{ends_at:'07:00'},{payment_time:'11:00'},{payment_time:'13:00'},{contact_phone:'123'},{job_role:''},{work_date:'2020-01-01'}])await assert.rejects(submit(db,{...p,...change}));
 await publish(db,id);assert.equal((await db.query("select * from public.list_same_day_jobs('public')")).rows.length,1);
 await assert.rejects(submit(db,p,'company',crypto.randomUUID(),id),/Only your draft/);
 await db.query("update public.employer_requirements set review_status='correction_required',requirement_stage='draft',requirement_visibility='private' where id=$1",[id]);
 await submit(db,{...p,pay_amount:'400'},'company',crypto.randomUUID(),id);
 assert.equal((await value(db,'select pay_amount from private.same_day_job_terms where requirement_id=$1',[id])).pay_amount,'400.00');
 }finally{await db.close();}});
test('contractor canonical routing and cross-employer access fail closed; public execution grants are narrow',async()=>{const {db,payload:p}=await setup();try{
 await db.exec("select set_config('test.role','contractor',false)");const id=await submit(db,p,'contractor');assert.ok(id);
 assert.equal((await value(db,'select count(*)::int n from public.requirement_contractors where requirement_id=$1',[id])).n,1);
 await db.exec("select set_config('test.role','company',false);select set_config('test.company','00000000-0000-0000-0000-000000000099',false)");
 assert.equal((await db.query("select * from public.list_same_day_jobs('owner')")).rows.length,0);
 await assert.rejects(db.query('select public.submit_same_day_job(null,$1,gen_random_uuid())',[p]));
 await assert.rejects(db.query("select * from public.list_same_day_jobs('admin')"),/Access denied/);
 const grants=await value(db,"select has_function_privilege('anon','public.list_same_day_jobs(text,integer,integer,text)','execute') public_read,has_function_privilege('anon','public.submit_same_day_job(text,jsonb,uuid,uuid)','execute') public_write,has_table_privilege('authenticated','private.same_day_work_status','update') direct_write");assert.deepEqual(grants,{public_read:true,public_write:false,direct_write:false});
 }finally{await db.close();}});
test('availability uses canonical applications once, seat limit and cross-owner payment permissions hold',async()=>{const {db,payload:p}=await setup();try{
 const id=await submit(db,p);await publish(db,id);const c=await candidate(db);const aid=(await value(db,'select public.apply_same_day_job($1) id',[id])).id;
 assert.equal((await value(db,'select public.apply_same_day_job($1) id',[id])).id,aid);
 await assert.rejects(db.query("select public.update_same_day_work($1,'confirm')",[aid]),/responsible employer/);
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");await db.query("select public.update_same_day_work($1,'confirm')",[aid]);
 assert.equal((await db.query("select * from public.list_same_day_jobs('public')")).rows.length,0);
 await candidate(db,'9876543212');await assert.rejects(db.query('select public.apply_same_day_job($1)',[id]),/not available/);
 await assert.rejects(db.query("select public.update_same_day_work($1,'received')",[aid]),/Only the candidate/);
 await db.query("select set_config('test.candidate',$1,false)",[c]);await assert.rejects(db.query("select public.update_same_day_work($1,'received')",[aid]),/record payment first/);
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");await db.query("select public.update_same_day_work($1,'cancel')",[aid]);
 assert.equal((await db.query("select * from public.list_same_day_jobs('public')")).rows.length,1);
 }finally{await db.close();}});
test('overlap protection, chronological attendance, separate employer payment and candidate receipt',async()=>{const {db,payload:p}=await setup();try{
 const j1=await submit(db,p),j2=await submit(db,p);await publish(db,j1);await publish(db,j2);const c=await candidate(db);const a1=(await value(db,'select public.apply_same_day_job($1) id',[j1])).id,a2=(await value(db,'select public.apply_same_day_job($1) id',[j2])).id;
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");await db.query("select public.update_same_day_work($1,'confirm')",[a1]);await assert.rejects(db.query("select public.update_same_day_work($1,'confirm')",[a2]),/overlapping/);
 await assert.rejects(db.query("select public.update_same_day_work($1,'attend')",[a1]),/Invalid work/);
 await db.query("update private.same_day_job_terms set work_date=(clock_timestamp() at time zone 'Asia/Kolkata')::date-1 where requirement_id=$1",[j1]);
 await db.query("select public.update_same_day_work($1,'attend')",[a1]);await db.query("select public.update_same_day_work($1,'complete')",[a1]);await db.query("select public.update_same_day_work($1,'paid','Synthetic UPI ref')",[a1]);
 let row=await value(db,'select * from private.same_day_work_status where application_id=$1',[a1]);assert.equal(row.payment_received_at,null);assert.ok(row.payment_reported_at);
 await db.query("select set_config('test.candidate',$1,false)",[c]);await db.exec("select set_config('test.role','candidate',false)");await db.query("select public.update_same_day_work($1,'received')",[a1]);row=await value(db,'select * from private.same_day_work_status where application_id=$1',[a1]);assert.ok(row.payment_received_at);
 }finally{await db.close();}});
test('Sanand shift alerts require separate preference plus existing WhatsApp consent; normal jobs remain unfiltered',async()=>{const {db,payload:p}=await setup();try{
 const id=await submit(db,p);await candidate(db);const cid=(await value(db,'select private.current_candidate_portal_id() id')).id;
 const contact=(await value(db,"insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version) values('+919876543211','9876543211',$1,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'synthetic-test') returning id",[cid])).id;
 assert.equal((await value(db,'select private.same_day_alert_eligible($1,$2) ok',[id,contact])).ok,false);
 await db.query('select public.set_same_day_preferences(true)');assert.equal((await value(db,'select private.same_day_alert_eligible($1,$2) ok',[id,contact])).ok,true);
 await db.query('select public.set_same_day_preferences(false)');assert.equal((await value(db,'select private.same_day_alert_eligible($1,$2) ok',[id,contact])).ok,false);
 const vars=(await value(db,'select private.registered_alert_variables($1) v',[id])).v;assert.match(vars.salary,/350.00 for the complete shift/);assert.match(vars.take_home,/same day at 18:00/);assert.match(vars.job_role,/Same-Day Pay/);
 assert.equal((await value(db,'select private.whatsapp_safe_flat_json($1) ok',[vars])).ok,true);
 assert.equal((await value(db,"select private.same_day_alert_eligible('00000000-0000-0000-0000-000000000002',$1) ok",[contact])).ok,true);
 }finally{await db.close();}});
test('real canonical alert worker selects only opted-in Sanand shift subscribers and rechecks withdrawal before provider boundary',async()=>{const {db,payload:p}=await setup();try{
 const id=await submit(db,p);const c=await candidate(db);const contact=(await value(db,"insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version) values('+919876543211','9876543211',$1,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'synthetic-test') returning id",[c])).id;
 await db.query('select public.set_same_day_preferences(true)');const c2=await candidate(db,'9876543212');await db.query("insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,marketing_consent_status,consent_source,consent_scope,consent_recorded_at,consent_policy_version) values('+919876543212','9876543212',$1,'resolved','opted_in','whatsapp_web','all_job_alerts',clock_timestamp(),'synthetic-test')",[c2]);
 const template=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v4.json','utf8'));await db.query('select public.console_sync_templates($1::jsonb)',[JSON.stringify([{...template,id:'1234567898',status:'APPROVED'}])]);
 await db.query('select public.admin_console_set_automatic_alerts(true,10)');await publish(db,id);
 const rows=(await db.query("select * from public.console_claim_registered_alerts('same-day-isolated')")).rows;assert.equal(rows.length,1);assert.match(rows[0].template_variables.job_role,/Same-Day Pay/);
 assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,true);
 await db.query("select set_config('test.candidate',$1,false)",[c]);await db.query('select public.set_same_day_preferences(false)');assert.equal((await value(db,'select private.whatsapp_vacancy_send_eligible($1) ok',[rows[0].message_id])).ok,false);
 await assert.rejects(db.query("select public.console_provider_boundary($1,'same-day-isolated','1234567891','1234567890')",[rows[0].message_id]));
 assert.equal((await value(db,'select count(*)::int n from public.whatsapp_campaign_recipients')).n,1);
 }finally{await db.close();}});
test('same-day wrapper works against retained Company and corrected Contractor vacancy functions, including correction resubmission',async()=>{const {db,payload:p}=await setup();try{
 await db.exec(`drop function public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text);drop function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text);
 create table public.companies(id uuid primary key,legal_name text,main_phone text,main_email text,city text,state text);
 insert into public.companies values('${company}','Synthetic Company','9876543210','test@example.invalid','Sanand','Gujarat');
 create table public.platform_users(user_id uuid primary key,display_name text,mobile text,email text);insert into public.platform_users values('00000000-0000-0000-0000-000000000001','Synthetic Owner','9876543210','test@example.invalid');
 create table public.contractors(id uuid primary key,owner_name text,agency_name text,main_phone text,main_email text);insert into public.contractors values('${contractor}','Synthetic Owner','Synthetic Agency','9876543210','test@example.invalid');
 alter table public.employer_requirements add column if not exists contact_person text,add column if not exists mobile text,add column if not exists email text,add column if not exists consent boolean,add column if not exists status text,add column if not exists created_by_user_id uuid,add column if not exists age_min integer,add column if not exists age_max integer,add column if not exists submitted_at timestamptz,add column if not exists updated_at timestamptz default clock_timestamp(),add column if not exists review_feedback text,add column if not exists reviewed_at timestamptz,add column if not exists reviewed_by uuid,add column if not exists published_at timestamptz,add column if not exists closed_at timestamptz;
 alter table public.requirement_contractors add column id uuid primary key default gen_random_uuid(),add column assigned_headcount integer,add column assignment_status text,add column submitted_at timestamptz,add column if not exists review_feedback text,add column reviewed_at timestamptz,add column reviewed_by uuid,add column closed_at timestamptz;
 alter table public.employer_requirements alter column requirement_code set default 'TEST_'||replace(gen_random_uuid()::text,'-','');`);
 const m39=fs.readFileSync('supabase/migrations/039_unified_vacancy_review_workflow.sql','utf8');const start=m39.indexOf('create function public.manage_company_portal_vacancy(');await db.exec(m39.slice(start,m39.indexOf('$$;',start)+3));
 const m40=fs.readFileSync('supabase/migrations/040_fix_contractor_vacancy_submit_ambiguity.sql','utf8');const a=m40.indexOf('create or replace function public.manage_contractor_portal_vacancy(');await db.exec(m40.slice(a,m40.indexOf('$$;',a)+3));
 const companyJob=await submit(db,p);assert.equal((await value(db,'select review_status from public.employer_requirements where id=$1',[companyJob])).review_status,'pending_review');
 await db.exec("select set_config('test.role','contractor',false)");const id=await submit(db,p,'contractor');assert.equal((await value(db,'select submission_status from public.requirement_contractors where requirement_id=$1',[id])).submission_status,'submitted');
 await db.query("update public.employer_requirements set review_status='correction_required' where id=$1;",[id]);await db.query("update public.requirement_contractors set submission_status='correction_required' where requirement_id=$1",[id]);await submit(db,{...p,pay_amount:'400'},'contractor',crypto.randomUUID(),id);
 assert.equal((await value(db,'select submission_status from public.requirement_contractors where requirement_id=$1',[id])).submission_status,'submitted');
 }finally{await db.close();}});
