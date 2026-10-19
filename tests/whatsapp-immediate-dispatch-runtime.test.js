'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base,submit,publish,value}=require('./fixtures/same-day-runtime-setup');
async function setup(){const f=await base(),db=f.db;
 await db.exec(`create schema vault;create schema net;create schema cron;
 create table vault.secrets(id uuid default gen_random_uuid(),name text,secret text);
 create view vault.decrypted_secrets as select name,secret decrypted_secret from vault.secrets;
 create function vault.create_secret(text,text,text) returns uuid language plpgsql as $$declare id uuid;begin insert into vault.secrets(name,secret) values($2,$1) returning secrets.id into id;return id;end;$$;
 create table net.requests(id bigserial,url text,body jsonb,headers jsonb,timeout_milliseconds int);
 create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds int) returns bigint language plpgsql as $$declare rid bigint;begin insert into net.requests(url,body,headers,timeout_milliseconds) values($1,$2,$3,$4) returning id into rid;return rid;end;$$;
 create table cron.jobs(name text,schedule text,command text);
 create function cron.schedule(text,text,text) returns bigint language plpgsql as $$begin insert into cron.jobs values($1,$2,$3);return 1;end;$$;`);
 const sql=fs.readFileSync('supabase/migrations/20261019122406_immediate_registered_alert_dispatch.sql','utf8').replace(/^create extension if not exists (pg_net|pg_cron);$/gm,'');await db.exec(sql);await db.exec(fs.readFileSync('supabase/migrations/20261019123133_one_time_automatic_wake_credentials.sql','utf8'));return f;}
async function enable(db){const t=JSON.parse(fs.readFileSync('docs/whatsapp/registered-job-alert-template-v4.json','utf8'));await db.query('select public.console_sync_templates($1)',[JSON.stringify([{...t,id:'1234567898',status:'APPROVED'}])]);await db.query('select public.admin_console_set_automatic_alerts(true,100)');}
test('publication wakes fixed canonical worker transactionally; no draft/disabled or empty replay, no browser privileges',async()=>{const {db,payload}=await setup();try{
 const old=await submit(db,payload);await publish(db,old);assert.equal((await value(db,'select count(*)::int n from net.requests')).n,0);
 await enable(db);const id=await submit(db,payload);assert.equal((await value(db,'select count(*)::int n from net.requests')).n,0);await publish(db,id);
 const req=await value(db,'select url,body,timeout_milliseconds from net.requests');assert.deepEqual(req,{url:'https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/whatsapp-outbox-worker',body:{automatic:true},timeout_milliseconds:150000});
 assert.equal((await value(db,"select public.console_verify_automatic_wake(headers->>'x-whatsapp-wake-key') ok from net.requests")).ok,true);assert.equal((await value(db,"select public.console_verify_automatic_wake(headers->>'x-whatsapp-wake-key') ok from net.requests")).ok,false);assert.equal((await value(db,"select public.console_verify_automatic_wake(repeat('a',64)) ok")).ok,false);
 await publish(db,id);assert.equal((await value(db,'select count(*)::int n from net.requests')).n,1);
 assert.equal((await value(db,"select has_function_privilege('authenticated','private.wake_registered_alert_worker()','execute') browser,has_function_privilege('anon','public.console_verify_automatic_wake(text)','execute') anon,has_table_privilege('service_role','private.whatsapp_automatic_dispatch_state','select') direct")).browser,false);
 assert.equal((await value(db,"select schedule from cron.jobs where name='aadhyant-automatic-alert-drain'")).schedule,'* * * * *');
 }finally{await db.close();}});
test('minute fallback retries wake only, coalesces concurrent publications, preserves rollback and paused alerts',async()=>{const {db,payload}=await setup();try{
 await enable(db);const id=await submit(db,payload);
 await db.exec('begin');await publish(db,id);assert.equal((await value(db,'select count(*)::int n from net.requests')).n,1);await db.exec('rollback');assert.equal((await value(db,'select count(*)::int n from net.requests')).n,0);
 await publish(db,id);await db.exec('select private.wake_registered_alert_worker()');assert.equal((await value(db,'select count(*)::int n from net.requests')).n,1);
 // Synthetic pending work, never any real candidate or network provider.
 await db.query("update private.whatsapp_job_publications set outcome='template_unavailable',campaign_id=null where requirement_id=$1",[id]);await db.exec('update private.whatsapp_automatic_dispatch_state set last_requested_at=null');await db.exec('select private.wake_registered_alert_worker()');assert.equal((await value(db,'select count(*)::int n from net.requests')).n,2);
 await db.query('select public.admin_console_set_automatic_alerts(false,100)');await db.exec('update private.whatsapp_automatic_dispatch_state set last_requested_at=null;select private.wake_registered_alert_worker()');assert.equal((await value(db,'select count(*)::int n from net.requests')).n,2);
 }finally{await db.close();}});
