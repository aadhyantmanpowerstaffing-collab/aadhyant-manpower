'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {setup:base}=require('./fixtures/web-registration-runtime-setup');
const migration=fs.readFileSync('supabase/migrations/20261104190000_candidate_whatsapp_otp_account.sql','utf8');
const uid='00000000-0000-0000-0000-000000000099';
async function setup(){const f=await base();await f.db.exec(`
alter table auth.users add column phone text,add column phone_confirmed_at timestamptz,add column is_anonymous boolean not null default false,add column banned_until timestamptz;
alter table public.candidates add column user_id uuid references auth.users(id),add column mobile_verified boolean not null default false;
create table public.platform_users(
 user_id uuid primary key references auth.users(id),
 account_type text not null check(account_type in ('company','contractor','candidate')),
 display_name text not null check(length(btrim(display_name)) between 1 and 160),
 mobile text check(mobile is null or mobile ~ '^[6-9][0-9]{9}
insert into auth.users(id,phone,phone_confirmed_at) values('${uid}','919876543210',clock_timestamp());
`);await f.db.exec(migration);return f;}
async function enable(f){await f.db.exec(`update private.candidate_phone_auth_config set enabled=true;select set_config('test.uid','${uid}',false);`);}
test('feature stays off until provider activation; existing registration behavior is preserved',async()=>{const f=await setup();try{assert.equal((await f.db.query('select public.get_candidate_phone_auth_status() as ready')).rows[0].ready,false);const result=await f.submit();assert.equal(result.status,'registered');assert.equal(result.portal_account_ready,undefined);assert.equal((await f.db.query('select count(*)::int n from public.platform_users')).rows[0].n,0);}finally{await f.db.close();}});
test('verified matching phone atomically creates portal ownership and one application; replay stays idempotent',async()=>{const f=await setup();try{await enable(f);const result=await f.submit();assert.equal(result.portal_account_ready,true);const c=(await f.db.query('select user_id,mobile_verified from public.candidates')).rows[0];assert.equal(c.user_id,uid);assert.equal(c.mobile_verified,true);assert.equal((await f.submit()).portal_account_ready,true);assert.equal((await f.db.query('select count(*)::int n from public.platform_users')).rows[0].n,1);assert.equal((await f.db.query('select count(*)::int n from public.candidate_applications')).rows[0].n,1);}finally{await f.db.close();}});
for(const mode of ['anonymous','unverified','wrong-number','banned','staff-profile','staff-role','company','orphan-portal','claimed'])test('phone account fails closed without partial registration: '+mode,async()=>{const f=await setup();try{await enable(f);
 if(mode==='anonymous')await f.db.exec("select set_config('test.uid','',false)");
 if(mode==='unverified')await f.db.exec(`update auth.users set phone_confirmed_at=null where id='${uid}'`);
 if(mode==='wrong-number')await f.db.exec(`update auth.users set phone='919999999999' where id='${uid}'`);
 if(mode==='banned')await f.db.exec(`update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='${uid}'`);
 if(mode==='staff-profile')await f.db.exec(`insert into public.staff_profiles values('${uid}')`);
 if(mode==='staff-role')await f.db.exec(`insert into public.staff_roles values('${uid}')`);
 if(mode==='company')await f.db.exec(`insert into public.platform_users(user_id,account_type,account_status) values('${uid}','company','active')`);
 if(mode==='orphan-portal')await f.db.exec(`insert into public.platform_users(user_id,account_type,display_name,mobile,account_status) values('${uid}','candidate','Synthetic Candidate','9876543210','active')`);
 if(mode==='claimed'){await f.db.exec("update private.candidate_phone_auth_config set enabled=false");await f.submit();await f.db.exec(`update private.candidate_phone_auth_config set enabled=true;update public.candidates set user_id='00000000-0000-0000-0000-000000000001'`);}
 await assert.rejects(()=>f.submit());if(mode!=='claimed')assert.equal((await f.db.query('select count(*)::int n from public.candidate_applications')).rows[0].n,0);
 }finally{await f.db.close();}});
test('auth hook ledger claims once, never stores OTPs, and is service-only',async()=>{const f=await setup();try{await enable(f);const args=['hook_synthetic',uid,'+919876543210'];const call=async()=>(await f.db.query('select public.claim_candidate_phone_auth_delivery($1,$2,$3) state',args)).rows[0].state;assert.equal(await call(),'send');assert.equal(await call(),'review');assert.equal((await f.db.query('select public.finish_candidate_phone_auth_delivery($1,$2,true) ok',args.slice(0,2))).rows[0].ok,true);assert.equal(await call(),'accepted');assert.equal((await f.db.query("select has_function_privilege('anon','public.claim_candidate_phone_auth_delivery(text,uuid,text)','execute') allowed")).rows[0].allowed,false);assert.equal((await f.db.query("select has_function_privilege('authenticated','private.bind_whatsapp_candidate_phone_account(text)','execute') allowed")).rows[0].allowed,false);}finally{await f.db.close();}});

test('all new privileged functions pin search_path and private auth tables expose no browser access',async()=>{
 const f=await setup();try{
 const functions=(await f.db.query("select proname,proconfig from pg_proc join pg_namespace n on n.oid=pronamespace where proname in ('get_candidate_phone_auth_status','claim_candidate_phone_auth_delivery','finish_candidate_phone_auth_delivery','bind_whatsapp_candidate_phone_account','submit_whatsapp_registration_form')")).rows;
 assert.equal(functions.length,5);for(const fn of functions)assert.ok(fn.proconfig.some(value=>value==='search_path=\"\"'),fn.proname);
 for(const role of ['anon','authenticated'])for(const table of ['candidate_phone_auth_config','candidate_phone_auth_deliveries']){
  const row=(await f.db.query("select has_table_privilege($1,$2,'SELECT,INSERT,UPDATE,DELETE') allowed",[role,'private.'+table])).rows[0];assert.equal(row.allowed,false);
 }
 }finally{await f.db.close();}
});
),
 email text,
 account_status text not null default 'pending' check(account_status in ('pending','active','suspended','rejected')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.admin_users(user_id uuid);create table public.staff_profiles(user_id uuid);create table public.staff_roles(user_id uuid);create table public.company_users(user_id uuid);create table public.contractor_users(user_id uuid);
insert into auth.users(id,phone,phone_confirmed_at) values('${uid}','919876543210',clock_timestamp());
`);await f.db.exec(migration);return f;}
async function enable(f){await f.db.exec(`update private.candidate_phone_auth_config set enabled=true;select set_config('test.uid','${uid}',false);`);}
test('feature stays off until provider activation; existing registration behavior is preserved',async()=>{const f=await setup();try{assert.equal((await f.db.query('select public.get_candidate_phone_auth_status() as ready')).rows[0].ready,false);const result=await f.submit();assert.equal(result.status,'registered');assert.equal(result.portal_account_ready,undefined);assert.equal((await f.db.query('select count(*)::int n from public.platform_users')).rows[0].n,0);}finally{await f.db.close();}});
test('verified matching phone atomically creates portal ownership and one application; replay stays idempotent',async()=>{const f=await setup();try{await enable(f);const result=await f.submit();assert.equal(result.portal_account_ready,true);const c=(await f.db.query('select user_id,mobile_verified from public.candidates')).rows[0];assert.equal(c.user_id,uid);assert.equal(c.mobile_verified,true);assert.equal((await f.submit()).portal_account_ready,true);assert.equal((await f.db.query('select count(*)::int n from public.platform_users')).rows[0].n,1);assert.equal((await f.db.query('select count(*)::int n from public.candidate_applications')).rows[0].n,1);}finally{await f.db.close();}});
for(const mode of ['anonymous','unverified','wrong-number','banned','staff-profile','staff-role','company','claimed'])test('phone account fails closed without partial registration: '+mode,async()=>{const f=await setup();try{await enable(f);
 if(mode==='anonymous')await f.db.exec("select set_config('test.uid','',false)");
 if(mode==='unverified')await f.db.exec(`update auth.users set phone_confirmed_at=null where id='${uid}'`);
 if(mode==='wrong-number')await f.db.exec(`update auth.users set phone='919999999999' where id='${uid}'`);
 if(mode==='banned')await f.db.exec(`update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='${uid}'`);
 if(mode==='staff-profile')await f.db.exec(`insert into public.staff_profiles values('${uid}')`);
 if(mode==='staff-role')await f.db.exec(`insert into public.staff_roles values('${uid}')`);
 if(mode==='company')await f.db.exec(`insert into public.platform_users(user_id,account_type,account_status) values('${uid}','company','active')`);
 if(mode==='claimed'){await f.db.exec("update private.candidate_phone_auth_config set enabled=false");await f.submit();await f.db.exec(`update private.candidate_phone_auth_config set enabled=true;update public.candidates set user_id='00000000-0000-0000-0000-000000000001'`);}
 await assert.rejects(()=>f.submit());if(mode!=='claimed')assert.equal((await f.db.query('select count(*)::int n from public.candidate_applications')).rows[0].n,0);
 }finally{await f.db.close();}});
test('auth hook ledger claims once, never stores OTPs, and is service-only',async()=>{const f=await setup();try{await enable(f);const args=['hook_synthetic',uid,'+919876543210'];const call=async()=>(await f.db.query('select public.claim_candidate_phone_auth_delivery($1,$2,$3) state',args)).rows[0].state;assert.equal(await call(),'send');assert.equal(await call(),'review');assert.equal((await f.db.query('select public.finish_candidate_phone_auth_delivery($1,$2,true) ok',args.slice(0,2))).rows[0].ok,true);assert.equal(await call(),'accepted');assert.equal((await f.db.query("select has_function_privilege('anon','public.claim_candidate_phone_auth_delivery(text,uuid,text)','execute') allowed")).rows[0].allowed,false);assert.equal((await f.db.query("select has_function_privilege('authenticated','private.bind_whatsapp_candidate_phone_account(text)','execute') allowed")).rows[0].allowed,false);}finally{await f.db.close();}});

test('all new privileged functions pin search_path and private auth tables expose no browser access',async()=>{
 const f=await setup();try{
 const functions=(await f.db.query("select proname,proconfig from pg_proc join pg_namespace n on n.oid=pronamespace where proname in ('get_candidate_phone_auth_status','claim_candidate_phone_auth_delivery','finish_candidate_phone_auth_delivery','bind_whatsapp_candidate_phone_account','submit_whatsapp_registration_form')")).rows;
 assert.equal(functions.length,5);for(const fn of functions)assert.ok(fn.proconfig.some(value=>value==='search_path=\"\"'),fn.proname);
 for(const role of ['anon','authenticated'])for(const table of ['candidate_phone_auth_config','candidate_phone_auth_deliveries']){
  const row=(await f.db.query("select has_table_privilege($1,$2,'SELECT,INSERT,UPDATE,DELETE') allowed",[role,'private.'+table])).rows[0];assert.equal(row.allowed,false);
 }
 }finally{await f.db.close();}
});


test('OTP delivery is limited to an active Candidate or matching unexpired private registration link',async()=>{
 const f=await setup();try{await enable(f);
  const args=['hook_pending',uid,'+919876543210'];
  assert.equal((await f.db.query('select public.claim_candidate_phone_auth_delivery($1,$2,$3) state',args)).rows[0].state,'send');
  await f.db.exec("update private.whatsapp_web_registrations set expires_at=clock_timestamp()-interval '1 hour'");
  await assert.rejects(()=>f.db.query('select public.claim_candidate_phone_auth_delivery($1,$2,$3)',args));
 }finally{await f.db.close();}
});

test('an already active matching Candidate Portal account may request OTP without a pending registration link',async()=>{
 const f=await setup();try{await enable(f);
  const result=await f.submit();assert.equal(result.portal_account_ready,true);
  await f.db.exec("update private.whatsapp_web_registrations set expires_at=clock_timestamp()-interval '1 hour'");
  const args=['hook_candidate_login',uid,'+919876543210'];
  assert.equal((await f.db.query('select public.claim_candidate_phone_auth_delivery($1,$2,$3) state',args)).rows[0].state,'send');
 }finally{await f.db.close();}
});



test('database claim enforces a 60-second cooldown even when a new Auth hook ID is used',async()=>{
 const f=await setup();try{await enable(f);
  await f.db.query("insert into private.candidate_phone_auth_deliveries(hook_id,user_id,state,created_at) values('hook_prior', $1,'accepted',clock_timestamp())",[uid]);
  await assert.rejects(()=>f.db.query("select public.claim_candidate_phone_auth_delivery('hook_too_soon',$1,'+919876543210')",[uid]));
  await f.db.exec("update private.candidate_phone_auth_deliveries set created_at=clock_timestamp()-interval '61 seconds' where hook_id='hook_prior'");
  assert.equal((await f.db.query("select public.claim_candidate_phone_auth_delivery('hook_after_cooldown',$1,'+919876543210') state",[uid])).rows[0].state,'send');
 }finally{await f.db.close();}
});
