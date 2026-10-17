'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const read=p=>fs.readFileSync(p,'utf8');
const legacy=read('supabase/migrations/012_candidate_requirement_interest.sql');
const legacyFunction=legacy.slice(legacy.indexOf('create function public.register_candidate_requirement_interest('),legacy.indexOf('revoke all on function public.register_candidate_requirement_interest'));
const review=read('supabase/migrations/039_unified_vacancy_review_workflow.sql');
const helpers=review.slice(review.indexOf('create function private.normalized_vacancy_review_status('),review.indexOf('create function private.can_review_vacancies('));
const correction=read('supabase/migrations/20261017041450_public_interest_review_guard.sql');
const job='00000000-0000-0000-0000-000000000001';
const profile={full_name:'Synthetic Test',mobile:'9876543210',age:25,consent:true};
async function setup(fixed=true){
 const db=new PGlite();
 await db.exec(`create schema private;create role anon;create role authenticated;
 create table public.employer_requirements(id uuid primary key,requirement_code text,requirement_stage text,requirement_visibility text,review_status text,required_headcount integer,filled_positions integer);
 create table public.requirement_contractors(id uuid primary key default gen_random_uuid(),requirement_id uuid,origin_type text,submission_status text);
 create table public.candidates(id uuid primary key default gen_random_uuid(),full_name text,age integer,gender text,mobile text,whatsapp_number text,current_location text,district text,state text,highest_qualification text,specialization text,candidate_type text,total_experience text,previous_job_role text,interview_available text,preferred_job_location text,additional_information text,consent boolean);
 create table public.candidate_applications(candidate_id uuid,requirement_id uuid,source_type text,application_status text,unique(candidate_id,requirement_id));`);
 await db.exec(helpers+legacyFunction);
 await db.exec('revoke all on function public.register_candidate_requirement_interest(text,jsonb) from public; grant execute on function public.register_candidate_requirement_interest(text,jsonb) to anon;');
 if(fixed)await db.exec(correction);
 await db.query("insert into public.employer_requirements values($1,'AAD-2026-000001','open','public','pending_review',10,0)",[job]);return db;
}
const submit=db=>db.query("select public.register_candidate_requirement_interest('AAD-2026-000001',$1::jsonb) result",[JSON.stringify(profile)]);
test('legacy endpoint reproduces missing approval check in isolated database',async()=>{const db=await setup(false);try{assert.equal((await submit(db)).rows[0].result,'registered');}finally{await db.close();}});
test('public interest rejects unapproved, private, closed, filled and ambiguous vacancies without writing',async()=>{const db=await setup();try{
 for(const status of ['pending_review','draft','correction_required','rejected','closed',null]){
  await db.query('update public.employer_requirements set review_status=$1',[status]);await assert.rejects(submit(db),/Opportunity is not available/);
 }
 await db.exec("update public.employer_requirements set review_status='approved',requirement_visibility='private'");await assert.rejects(submit(db),/Opportunity is not available/);
 await db.exec("update public.employer_requirements set requirement_visibility='public',requirement_stage='closed'");await assert.rejects(submit(db),/Opportunity is not available/);
 await db.exec("update public.employer_requirements set requirement_stage='open',filled_positions=10");await assert.rejects(submit(db),/Opportunity is not available/);
 await db.exec("update public.employer_requirements set filled_positions=0");
 await db.query("insert into public.requirement_contractors(requirement_id,origin_type,submission_status) values($1,'contractor_submission','submitted')",[job]);await assert.rejects(submit(db),/Opportunity is not available/);
 await db.exec("update public.requirement_contractors set submission_status='approved'");
 await db.query("insert into public.requirement_contractors(requirement_id,origin_type,submission_status) values($1,'contractor_submission','approved')",[job]);await assert.rejects(submit(db),/Opportunity is not available/);
 assert.equal((await db.query('select count(*)::int n from public.candidates')).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from public.candidate_applications')).rows[0].n,0);
 }finally{await db.close();}});
test('approved public interest and duplicate response preserve existing API and privileges',async()=>{const db=await setup();try{
 await db.exec("update public.employer_requirements set review_status='approved'");
 assert.equal((await submit(db)).rows[0].result,'registered');assert.equal((await submit(db)).rows[0].result,'already_registered');
 assert.equal((await db.query('select count(*)::int n from public.candidate_applications')).rows[0].n,1);
 const g=(await db.query("select has_function_privilege('anon','public.register_candidate_requirement_interest(text,jsonb)','execute') a,has_function_privilege('authenticated','public.register_candidate_requirement_interest(text,jsonb)','execute') b")).rows[0];assert.equal(g.a,true);assert.equal(g.b,false);
 }finally{await db.close();}});
