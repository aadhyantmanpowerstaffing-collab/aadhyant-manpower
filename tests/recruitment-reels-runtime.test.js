'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base}=require('./fixtures/full-job-runtime-setup');
const {value,requirement}=require('./fixtures/whatsapp-console-runtime-helpers');
async function setup(){const {db}=await base();
for(const f of ['20261016124516_readable_whatsapp_job_layout.sql','20261016131116_concise_registered_job_alerts.sql'])await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
await db.exec("create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);alter table public.employer_requirements add column created_at timestamptz default now();");
await db.exec(fs.readFileSync('supabase/migrations/20261023172336_recruitment_reel_automation.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261024120849_poster_reel_drafts.sql','utf8'));
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

const posterPayload={title:'नौकरी का अवसर',text:'साणंद में भर्ती। वेतन 20000 रुपये। ड्यूटी आठ घंटे।',poster:Buffer.from([255,216,255,...Array(100).fill(1)]).toString('base64')};
const posterRequest='11111111-1111-4111-8111-111111111111';
const queuePoster=(db,id=posterRequest,review=true,p=posterPayload)=>value(db,'select public.admin_queue_poster_reel($1,$2,$3,$4,$5) id',[id,p.title,p.text,p.poster,review]);
test('poster media requires Admin review, bounded Hindi and JPEG data; private queue remains closed to clients',async()=>{const db=await setup();try{
await db.exec('update private.reel_config set enabled=true;');
for(const review of [false,null])await assert.rejects(queuePoster(db,posterRequest,review),/Review/);
for(const p of [{...posterPayload,text:'English only announcement'},{...posterPayload,text:'अ'.repeat(1801)},{...posterPayload,title:''},{...posterPayload,poster:'x'.repeat(900001)},{...posterPayload,poster:Buffer.alloc(101).toString('base64')}])await assert.rejects(queuePoster(db,posterRequest,true,p));
assert.equal((await value(db,"select has_function_privilege('anon','public.admin_queue_poster_reel(uuid,text,text,text,boolean)','execute') ok")).ok,false);
assert.equal((await value(db,"select has_function_privilege('authenticated','private.reel_current_payload(uuid)','execute') ok")).ok,false);
assert.equal((await value(db,"select has_table_privilege('authenticated','private.requirement_reels','insert') ok")).ok,false);
await db.exec("select set_config('test.admin','no',false)");await assert.rejects(queuePoster(db),/Admin/);
await db.exec("select set_config('test.admin','yes',false);select set_config('test.uid','',false)");await assert.rejects(queuePoster(db),/Admin/);
}finally{await db.close();}});
test('reviewed poster uses existing queue idempotently, never creates a vacancy or message, and survives unrelated job changes',async()=>{const db=await setup();try{
await db.exec('update private.reel_config set enabled=true;');
const before=(await value(db,'select count(*)::int n from public.employer_requirements')).n;
const messages=(await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n;
const {id}=await queuePoster(db);assert.equal((await queuePoster(db)).id,id);
await assert.rejects(queuePoster(db,posterRequest,true,{...posterPayload,text:posterPayload.text+' नई जानकारी।'}),/different/);
let claimed=(await value(db,"select public.reel_worker_claim('poster:1') j")).j;
assert.equal(claimed.id,id);assert.equal(claimed.payload.poster,posterPayload.poster);assert.equal(claimed.payload.phone,'9586785800');
await db.query("update public.employer_requirements set requirement_stage='closed' where id=$1",[requirement]);
assert.equal((await value(db,"select public.reel_worker_check($1,$2,'poster:1') ok",[id,claimed.claim])).ok,true);
assert.equal((await value(db,"select public.reel_worker_finish($1,$2,'poster:1',true) ok",[id,claimed.claim])).ok,true);
assert.ok((await value(db,'select public.admin_reel_object($1) path',[id])).path.endsWith('.mp4'));
const listing=(await value(db,'select public.admin_reels() j')).j.jobs.find(j=>j.id===id);assert.equal(listing.is_poster,true);assert.equal(listing.requirement_code,'POSTER');assert.equal(listing.payload,undefined);
assert.equal((await value(db,'select count(*)::int n from public.employer_requirements')).n,before);assert.equal((await value(db,'select count(*)::int n from public.whatsapp_outbound_messages')).n,messages);
await db.query("update private.requirement_reels set payload=jsonb_set(payload,'{text}','\"बदला हुआ पाठ\"') where id=$1",[id]);assert.equal((await value(db,'select public.admin_reel_object($1) path',[id])).path,null);
}finally{await db.close();}});
test('poster queue respects pause, quota, bounded retries and reviewer/source constraints',async()=>{const db=await setup();try{
await assert.rejects(queuePoster(db),/paused/);
await db.exec('update private.reel_config set enabled=true,daily_limit=1;');const {id}=await queuePoster(db);
await assert.rejects(queuePoster(db,'22222222-2222-4222-8222-222222222222'),/limit/);
await db.exec('update private.reel_config set daily_limit=30;');
for(let i=0;i<3;i++){const j=(await value(db,"select public.reel_worker_claim('poster:1') j")).j;assert.ok(j);assert.equal((await value(db,"select public.reel_worker_finish($1,$2,'poster:1',false) ok",[j.id,j.claim])).ok,true);}
assert.equal((await value(db,'select state from private.requirement_reels where id=$1',[id])).state,'failed');
await db.query('select public.admin_retry_poster_reel($1)',[id]);assert.equal((await value(db,'select state,attempts from private.requirement_reels where id=$1',[id])).attempts,0);
await assert.rejects(db.query('update private.requirement_reels set requirement_id=$1 where id=$2',[requirement,id]),/reel_source_check/);
}finally{await db.close();}});
