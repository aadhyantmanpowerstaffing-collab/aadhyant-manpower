'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base}=require('./fixtures/full-job-runtime-setup');
const {value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
async function setup(){const {db}=await base();
for(const f of ['20261016124516_readable_whatsapp_job_layout.sql','20261016131116_concise_registered_job_alerts.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);alter table public.employer_requirements add column created_at timestamptz default now();");
await db.exec(fs.readFileSync('supabase/migrations/20261023172336_recruitment_reel_automation.sql','utf8'));
return db;}
test('automatic media queue is gated, canonical, private, idempotent and fresh through upload completion',async()=>{const db=await setup();try{
await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);assert.equal((await value(db,'select count(*)::int n from private.requirement_reels')).n,0);
await db.exec('update private.reel_config set enabled=true;');await db.query('select public.admin_queue_reel($1)',[requirement]);await db.query('select public.admin_queue_reel($1)',[requirement]);assert.equal((await value(db,'select count(*)::int n from private.requirement_reels')).n,1);
let j=(await value(db,"select public.reel_worker_claim('1:1') j")).j;assert.ok(j.payload.text.includes('कंपनी:'));assert.equal(j.payload.phone,'9586785800');assert.equal(j.payload.email,undefined);assert.equal((await value(db,"select public.reel_worker_claim('2:1') j")).j,null);
assert.equal((await value(db,"select public.reel_worker_finish($1,$2,'other',true) ok",[j.id,j.claim])).ok,false);
await db.query("update public.employer_requirements set job_role='Changed role' where id=$1",[requirement]);assert.equal((await value(db,"select public.reel_worker_check($1,$2,'1:1') ok",[j.id,j.claim])).ok,false);
j=(await value(db,"select public.reel_worker_claim('2:1') j")).j;assert.ok(j.payload.text.includes('Changed role'));assert.equal((await value(db,"select public.reel_worker_finish($1,$2,'2:1',true) ok",[j.id,j.claim])).ok,true);assert.ok((await value(db,'select public.admin_reel_object($1) p',[j.id])).p.endsWith('.mp4'));
await db.query("update public.employer_requirements set requirement_stage='closed' where id=$1",[requirement]);assert.equal((await value(db,'select public.admin_reel_object($1) p',[j.id])).p,null);
assert.equal((await value(db,"select has_function_privilege('anon','public.admin_reels(uuid)','execute') ok")).ok,false);assert.equal((await value(db,"select has_function_privilege('authenticated','public.reel_worker_claim(text)','execute') ok")).ok,false);
await db.exec("select set_config('test.admin','no',false)");await assert.rejects(db.query('select public.admin_reels()'),/Admin/);
}finally{await db.close();}});
test('expired lease retries are bounded, stale claims cannot finish, and failures do not block canonical saves',async()=>{const db=await setup();try{
await db.exec('update private.reel_config set enabled=true;');await db.query("update public.employer_requirements set review_status='approved' where id=$1",[requirement]);
for(let i=1;i<=3;i++){const j=(await value(db,"select public.reel_worker_claim('1:1') j")).j;assert.ok(j);await db.query("update private.requirement_reels set lease_until=clock_timestamp()-interval '1 minute' where id=$1",[j.id]);assert.equal((await value(db,"select public.reel_worker_finish($1,$2,'1:1',true) ok",[j.id,j.claim])).ok,false);}
assert.equal((await value(db,"select public.reel_worker_claim('1:1') j")).j,null);assert.equal((await value(db,'select state from private.requirement_reels')).state,'failed');
await db.query('select public.admin_queue_reel($1)',[requirement]);assert.equal((await value(db,'select attempts from private.requirement_reels')).attempts,0);
await db.exec("create or replace function private.reel_payload(p_requirement_id uuid) returns jsonb language plpgsql as $$begin raise exception 'Renderer snapshot unavailable';end;$$;");await db.query("update public.employer_requirements set job_role='Still saved' where id=$1",[requirement]);assert.equal((await value(db,'select job_role from public.employer_requirements where id=$1',[requirement])).job_role,'Still saved');
}finally{await db.close();}});
