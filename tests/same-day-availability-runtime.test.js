'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base,submit,publish,candidate,value}=require('./fixtures/same-day-runtime-setup');
async function setup(){const f=await base();await f.db.exec("create table public.platform_users(user_id uuid primary key,account_type text,account_status text);insert into public.platform_users values(auth.uid(),'candidate','active');alter table public.candidates add column user_id uuid default auth.uid();");await f.db.exec(fs.readFileSync('supabase/migrations/20261017065604_same_day_capacity_and_availability.sql','utf8'));return f;}
test('live capacity counts confirmations only, retains full cards, blocks full applications and releases cancellation',async()=>{
 const {db,payload}=await setup();try{
 const id=await submit(db,payload);await publish(db,id);await candidate(db);const aid=(await value(db,'select public.apply_same_day_job($1) id',[id])).id;
 let j=(await value(db,"select public.list_same_day_jobs('public') j")).j;assert.equal(j.confirmed_count,0);assert.equal(j.remaining_places,1);
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");await db.query("select public.update_same_day_work($1,'confirm')",[aid]);
 j=(await value(db,"select public.list_same_day_jobs('public') j")).j;assert.equal(j.confirmed_count,1);assert.equal(j.remaining_places,0);
 await candidate(db,'9876543212');await assert.rejects(db.query('select public.apply_same_day_job($1)',[id]),/not available/);
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");await db.query("select public.update_same_day_work($1,'cancel')",[aid]);
 j=(await value(db,"select public.list_same_day_jobs('public') j")).j;assert.equal(j.remaining_places,1);
 await db.query("update public.employer_requirements set requirement_visibility='private' where id=$1",[id]);assert.equal((await db.query("select public.list_same_day_jobs('public')")).rows.length,0);
 }finally{await db.close();}
});
test('dated availability uses own identity, expires by IST date and remains separate from applications and alerts',async()=>{
 const {db}=await setup();try{
 const c=await candidate(db);const ctx=(await value(db,'select public.get_same_day_availability() j')).j;assert.deepEqual(ctx.available_dates,[]);
 let r=(await value(db,'select public.save_same_day_availability($1::date[],$2) j',[[ctx.today,ctx.tomorrow],'Sanand GIDC'])).j;assert.equal(r.available_dates.length,2);
 assert.equal((await value(db,'select count(*)::int n from public.candidate_applications')).n,0);assert.equal((await value(db,'select count(*)::int n from private.same_day_preferences')).n,0);
 await candidate(db,'9876543212');assert.deepEqual((await value(db,'select public.get_same_day_availability() j')).j.available_dates,[]);
 await db.query("select set_config('test.candidate',$1,false)",[c]);await db.query("update private.same_day_candidate_availability set available_dates=array[(statement_timestamp() at time zone 'Asia/Kolkata')::date-1] where candidate_id=$1",[c]);
 assert.deepEqual((await value(db,'select public.get_same_day_availability() j')).j.available_dates,[]);
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");assert.equal((await db.query('select public.list_same_day_available_candidates($1)',[ctx.today])).rows.length,0);
 }finally{await db.close();}
});
test('availability is explicit, withdrawable, validated and disclosed only to active employers without contact data',async()=>{
 const {db}=await setup();try{
 const c=await candidate(db);const ctx=(await value(db,'select public.get_same_day_availability() j')).j;
 for(const dates of [null,['2020-01-01'],[null],[ctx.today,ctx.today,ctx.today]])await assert.rejects(db.query("select public.save_same_day_availability($1::date[],'Sanand')",[dates]));
 await assert.rejects(db.query("select public.save_same_day_availability($1::date[],'')",[[ctx.today]]));
 await db.query("select public.save_same_day_availability($1::date[],'Sanand')",[[ctx.today]]);
 await assert.rejects(db.query('select public.list_same_day_available_candidates($1)',[ctx.today]),/employer/);
 await db.exec("select set_config('test.role','company',false);select set_config('test.candidate','',false)");
 const rows=(await db.query('select public.list_same_day_available_candidates($1) j',[ctx.today])).rows;assert.equal(rows.length,1);assert.deepEqual(Object.keys(rows[0].j).sort(),['available_date','candidate_name','local_area']);
 await assert.rejects(db.query('select public.list_same_day_available_candidates($1,101)',[ctx.today]));
 await db.exec("update public.platform_users set account_status='inactive'");assert.equal((await db.query('select public.list_same_day_available_candidates($1)',[ctx.today])).rows.length,0);await db.exec("update public.platform_users set account_status='active'");
 await db.exec("select set_config('test.role','candidate',false)");await db.query("select set_config('test.candidate',$1,false)",[c]);await db.query("select public.save_same_day_availability('{}','')");
 await db.exec("select set_config('test.role','admin',false);select set_config('test.candidate','',false)");assert.equal((await db.query('select public.list_same_day_available_candidates($1)',[ctx.today])).rows.length,0);
 const g=await value(db,"select has_function_privilege('anon','public.get_same_day_availability()','execute') a,has_function_privilege('anon','public.save_same_day_availability(date[],text)','execute') b,has_function_privilege('anon','public.list_same_day_available_candidates(date,integer,integer)','execute') c,has_table_privilege('authenticated','private.same_day_candidate_availability','select') d,has_table_privilege('authenticated','private.same_day_candidate_availability','update') e");assert.deepEqual(g,{a:false,b:false,c:false,d:false,e:false});
 const security=await value(db,"select (select relrowsecurity from pg_class where oid='private.same_day_candidate_availability'::regclass) rls, bool_and(prosecdef and 'search_path=\"\"'=any(proconfig)) secured from pg_proc where oid in ('public.get_same_day_availability()'::regprocedure,'public.save_same_day_availability(date[],text)'::regprocedure,'public.list_same_day_available_candidates(date,integer,integer)'::regprocedure)");assert.deepEqual(security,{rls:true,secured:true});
 await assert.rejects(db.query('select public.get_same_day_availability()'),/Candidate/);
 }finally{await db.close();}
});

test('public and Candidate shift cards exclude supervisor identity and mobile while owner and Admin retain private coordination',async()=>{
 const {db,payload}=await setup();try{
 const id=await submit(db,payload);await publish(db,id);
 await db.exec(fs.readFileSync('supabase/migrations/20261019051702_same_day_private_supervisor_contact.sql','utf8'));
 for(const role of ['company','contractor','candidate','anonymous']){
  await db.query("select set_config('test.role',$1,false)",[role]);
  const j=(await value(db,"select public.list_same_day_jobs('public') j")).j;
  assert.equal('contact_phone' in j.terms,false);assert.equal('contact_name' in j.terms,false);
  assert.equal(JSON.stringify(j).includes(payload.contact_phone),false);
  assert.equal(j.terms.pay_amount,350);assert.equal(j.job_role,payload.job_role);
 }
 await db.exec("select set_config('test.role','company',false)");
 const owner=(await value(db,"select public.list_same_day_jobs('owner') j")).j;assert.equal(owner.terms.contact_phone,payload.contact_phone);
 await db.exec("select set_config('test.role','admin',false)");
 const admin=(await value(db,"select public.list_same_day_jobs('admin') j")).j;assert.equal(admin.terms.contact_phone,payload.contact_phone);
 await db.exec("select set_config('test.role','candidate',false)");
 assert.equal((await db.query("select public.list_same_day_jobs('owner')")).rows.length,0);
 await assert.rejects(db.query("select public.list_same_day_jobs('admin')"),/Access denied/);
 }finally{await db.close();}
});
