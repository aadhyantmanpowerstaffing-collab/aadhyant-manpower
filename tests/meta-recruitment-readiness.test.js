'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
async function fixture(t){const db=new PGlite();t.after(()=>db.close());await db.exec(`create schema private;create role anon;create role authenticated;create role service_role;
create table private.whatsapp_console_config(singleton boolean primary key,sender_ready boolean,phone_number_id text,business_account_id text,verified_at timestamptz,recruitment_templates_verified_at timestamptz,recruitment_updates_enabled boolean,interview_notifications_enabled boolean);
insert into private.whatsapp_console_config values(true,true,'1415347881659158','1386833723249335',clock_timestamp(),null,true,false);`);await db.exec(fs.readFileSync('supabase/migrations/20261103064104_direct_meta_recruitment_readiness.sql','utf8'));return db;}
const refresh="select public.console_refresh_recruitment_template_verification('1415347881659158','1386833723249335') ok";
test('service-only readiness refresh preserves activation and requires recent exact sender verification',async t=>{const db=await fixture(t);assert.equal((await db.query(refresh)).rows[0].ok,true);const cfg=(await db.query('select * from private.whatsapp_console_config')).rows[0];assert.ok(cfg.recruitment_templates_verified_at);assert.equal(cfg.recruitment_updates_enabled,true);assert.equal(cfg.interview_notifications_enabled,false);
assert.equal((await db.query("select public.console_refresh_recruitment_template_verification('9999999999','1386833723249335') ok")).rows[0].ok,false);
await db.exec("update private.whatsapp_console_config set verified_at=clock_timestamp()-interval '6 minutes'");assert.equal((await db.query(refresh)).rows[0].ok,false);});
test('paused recruitment and legacy sending cannot be enabled or claim-ready through verification',async t=>{const db=await fixture(t);for(const update of ['recruitment_updates_enabled=false','recruitment_updates_enabled=true,interview_notifications_enabled=true','interview_notifications_enabled=false,sender_ready=false']){await db.exec('update private.whatsapp_console_config set '+update);assert.equal((await db.query(refresh)).rows[0].ok,false);}assert.equal((await db.query('select recruitment_templates_verified_at from private.whatsapp_console_config')).rows[0].recruitment_templates_verified_at,null);});
test('browser roles have no readiness execution; service role has only the intended entry point',async t=>{const db=await fixture(t);for(const role of ['anon','authenticated'])assert.equal((await db.query("select has_function_privilege($1,'public.console_refresh_recruitment_template_verification(text,text)','EXECUTE') ok",[role])).rows[0].ok,false);assert.equal((await db.query("select has_function_privilege('service_role','public.console_refresh_recruitment_template_verification(text,text)','EXECUTE') ok")).rows[0].ok,true);const row=(await db.query("select proconfig from pg_proc where proname='console_refresh_recruitment_template_verification'")).rows[0];assert.ok(row.proconfig.some(x=>x==='search_path=\"\"'));});

test('database scheduler is dormant while paused, bounded when active and keeps credentials private',async t=>{
 const db=await fixture(t);await db.exec(`create schema vault;create schema net;create schema cron;
 create table private.whatsapp_automatic_dispatch_state(singleton boolean primary key,last_requested_at timestamptz,key_hash bytea);
 insert into private.whatsapp_automatic_dispatch_state values(true,null,null);
 create table vault.decrypted_secrets(name text,decrypted_secret text);
 insert into vault.decrypted_secrets values('aadhyant_automatic_dispatch_key','synthetic-secret-not-in-cron');
 create table private.test_requests(url text,body jsonb,headers jsonb);
 create table private.test_cron(name text,schedule text,command text);
 create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds integer) returns bigint language plpgsql as $$begin insert into private.test_requests values(url,body,headers);return 1;end;$$;
 create function cron.schedule(name text,schedule text,command text) returns bigint language plpgsql as $$begin insert into private.test_cron values(name,schedule,command);return 1;end;$$;`);
 await db.exec(fs.readFileSync('supabase/migrations/20261103064531_direct_recruitment_scheduler.sql','utf8'));
 await db.exec(fs.readFileSync('supabase/migrations/20261103071137_direct_recruitment_one_time_wake_fix.sql','utf8'));
 await db.exec(`create function public.console_verify_automatic_wake(p_key text) returns boolean language plpgsql security definer set search_path='' as $$begin update private.whatsapp_automatic_dispatch_state set key_hash=sha256(convert_to(gen_random_uuid()::text,'UTF8')) where singleton and key_hash=sha256(convert_to(p_key,'UTF8')) and last_requested_at>clock_timestamp()-interval '5 minutes';return found;end;$$;`);
 const run='select private.wake_direct_recruitment_worker() id';
 await db.exec('update private.whatsapp_console_config set recruitment_updates_enabled=false');assert.equal((await db.query(run)).rows[0].id,null);assert.equal((await db.query('select count(*) n from private.test_requests')).rows[0].n,0);
 await db.exec('update private.whatsapp_console_config set recruitment_updates_enabled=true');assert.equal((await db.query(run)).rows[0].id,1);assert.equal((await db.query(run)).rows[0].id,null);
 const request=(await db.query('select * from private.test_requests')).rows[0];assert.deepEqual(request.body,{kind:'recruitment_updates'});assert.match(request.headers['x-whatsapp-wake-key'],/^[a-f0-9]{64}$/);assert.equal((await db.query('select public.console_verify_automatic_wake($1) ok',[request.headers['x-whatsapp-wake-key']])).rows[0].ok,true);assert.equal((await db.query('select public.console_verify_automatic_wake($1) ok',[request.headers['x-whatsapp-wake-key']])).rows[0].ok,false);
 const job=(await db.query('select * from private.test_cron')).rows[0];assert.equal(job.schedule,'*/5 * * * *');assert.doesNotMatch(job.command,/synthetic-secret|https|wake-key/);
 for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query("select has_function_privilege($1,'private.wake_direct_recruitment_worker()','EXECUTE') ok",[role])).rows[0].ok,false);
 await db.exec('update private.whatsapp_automatic_dispatch_state set recruitment_last_requested_at=null,last_requested_at=null;delete from vault.decrypted_secrets');assert.equal((await db.query(run)).rows[0].id,1);
});

test('job alerts and recruitment keep independent simultaneous single-use wake credentials',async t=>{
 const db=await fixture(t);await db.exec(`create schema net;
 create table private.whatsapp_automatic_dispatch_state(singleton boolean primary key,key_hash bytea,last_requested_at timestamptz,recruitment_last_requested_at timestamptz,recruitment_last_request_id bigint,recruitment_last_error text);
 insert into private.whatsapp_automatic_dispatch_state values(true,sha256(convert_to(repeat('b',64),'UTF8')),clock_timestamp(),null,null,null);
 create table private.isolated_requests(headers jsonb);
 create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds integer) returns bigint language plpgsql as $$begin insert into private.isolated_requests values(headers);return 1;end;$$;`);
 await db.exec(fs.readFileSync('supabase/migrations/20261103073032_separate_recruitment_wake_credentials.sql','utf8'));
 const base=fs.readFileSync('supabase/migrations/20261019123133_one_time_automatic_wake_credentials.sql','utf8');await db.exec(base.slice(base.indexOf('create or replace function public.console_verify_automatic_wake'),base.indexOf('create or replace function private.wake_registered_alert_worker')));
 assert.equal((await db.query('select private.wake_direct_recruitment_worker() id')).rows[0].id,1);
 const nonce=(await db.query('select headers from private.isolated_requests')).rows[0].headers['x-whatsapp-wake-key'];
 assert.notEqual(nonce,'b'.repeat(64));assert.equal((await db.query('select public.console_verify_recruitment_wake($1) ok',['b'.repeat(64)])).rows[0].ok,false);
 assert.equal((await db.query('select public.console_verify_automatic_wake($1) ok',['b'.repeat(64)])).rows[0].ok,true);
 assert.equal((await db.query('select public.console_verify_recruitment_wake($1) ok',[nonce])).rows[0].ok,true);assert.equal((await db.query('select public.console_verify_recruitment_wake($1) ok',[nonce])).rows[0].ok,false);
 await db.exec("update private.whatsapp_automatic_dispatch_state set recruitment_key_hash=sha256(convert_to(repeat('c',64),'UTF8')),recruitment_last_requested_at=clock_timestamp()-interval '6 minutes'");assert.equal((await db.query('select public.console_verify_recruitment_wake($1) ok',['c'.repeat(64)])).rows[0].ok,false);
 for(const value of [null,'bad','A'.repeat(64)])assert.equal((await db.query('select public.console_verify_recruitment_wake($1) ok',[value])).rows[0].ok,false);
 for(const role of ['anon','authenticated'])assert.equal((await db.query("select has_function_privilege($1,'public.console_verify_recruitment_wake(text)','EXECUTE') ok",[role])).rows[0].ok,false);
 assert.equal((await db.query("select has_function_privilege('service_role','public.console_verify_recruitment_wake(text)','EXECUTE') ok")).rows[0].ok,true);
});
