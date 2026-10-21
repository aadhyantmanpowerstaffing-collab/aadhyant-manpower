'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const migration=fs.readFileSync('supabase/migrations/20261021052156_contractor_full_profile_self_service.sql','utf8');
const foundation=fs.readFileSync('supabase/migrations/007_platform_roles_architecture.sql','utf8');
const portal=fs.readFileSync('supabase/migrations/021_contractor_portal_foundation.sql','utf8');
const audit=fs.readFileSync('supabase/migrations/016_web_platform_schema_foundation.sql','utf8');
const uid='00000000-0000-0000-0000-000000000001',cid='00000000-0000-0000-0000-000000000002',other='00000000-0000-0000-0000-000000000003';
const table=(source,name)=>source.slice(source.indexOf(`create table ${name}`),source.indexOf('\n);',source.indexOf(`create table ${name}`))+4);
const func=name=>{const start=portal.indexOf(`create function ${name}(`);return portal.slice(start,portal.indexOf('$$;',start)+3)};
const payload={agency_name:'New Agency',owner_name:'New Owner',main_phone:'9876543210',main_email:'NEW@example.test',website:'https://example.test',address:'New address',city:'Sanand',district:'Ahmedabad',state:'Gujarat',pincode:'382170',operating_locations:['Sanand'],workforce_capacity:400,manpower_categories:['Operator'],gstin:'24ANEPV4011H1Z8',esic_code:'ESI-123',epfo_code:'PF-123',labour_license_number:'LIC-123'};
async function setup(){
 const db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create table public.platform_users(user_id uuid primary key,account_type text,account_status text);`);
 await db.exec(table(foundation,'if not exists public.contractors'));
 await db.exec(table(foundation,'if not exists public.contractor_users'));
 await db.exec(table(audit,'public.audit_logs'));
 await db.exec('alter table public.contractors add column website text,add column pincode text,add column manpower_categories text[];');
 for(const n of ['private.current_contractor_portal_id','private.can_edit_contractor_profile','public.get_contractor_portal_profile','public.update_contractor_portal_profile'])await db.exec(func(n));
 await db.exec(migration);
 await db.query('insert into auth.users values($1)',[uid]);
 await db.query("insert into public.platform_users values($1,'contractor','active')",[uid]);
 await db.query("insert into public.contractors(id,agency_name,verification_status,account_status) values($1,'Original','verified','active'),($2,'Other Tenant','verified','active')",[cid,other]);
 await db.query("insert into public.contractor_users(contractor_id,user_id,role,status) values($1,$2,'owner','active')",[cid,uid]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);return db;
}
const save=(db,p=payload)=>db.query('select public.update_contractor_portal_profile($1::jsonb) ok',[JSON.stringify(p)]);
test('all own business fields save atomically, identity changes reset verification and audit contains no field values',async()=>{const db=await setup();try{
 assert.equal((await save(db)).rows[0].ok,true);
 const r=(await db.query('select * from public.get_contractor_portal_profile()')).rows[0];
 for(const k of Object.keys(payload))assert.deepEqual(r[k],k==='main_email'?'new@example.test':payload[k]);
 assert.equal(r.verification_status,'pending');assert.equal(r.account_status,'active');
 const a=(await db.query('select metadata from public.audit_logs')).rows[0].metadata;
 assert.equal(a.identity_review_required,true);assert.ok(a.changed_fields.includes('agency_name'));
 assert.ok(!JSON.stringify(a).includes(payload.main_phone));
 assert.equal((await db.query('select agency_name from public.contractors where id=$1',[other])).rows[0].agency_name,'Other Tenant');
 }finally{await db.close()}});
test('invalid fields and ownership/status injection roll back without partial profile changes',async()=>{const db=await setup();try{
 for(const patch of [{main_phone:'123'},{main_email:'bad'},{gstin:'bad'},{pincode:'xx'},{workforce_capacity:-1},{operating_locations:[null]},{website:'javascript:alert(1)'},{account_status:'active'},{verification_status:'verified'},{id:other}]){
  await assert.rejects(save(db,{...payload,...patch}));
  assert.equal((await db.query('select agency_name from public.contractors where id=$1',[cid])).rows[0].agency_name,'Original');
 }
 assert.equal((await db.query('select count(*)::int n from public.audit_logs')).rows[0].n,0);
 }finally{await db.close()}});
test('anonymous, suspended, recruiter and unlinked accounts cannot update; legitimate contact edits retain verification',async()=>{const db=await setup();try{
 for(const role of ['recruiter','coordinator']){await db.query('update public.contractor_users set role=$1',[role]);await assert.rejects(save(db),/management access/)}
 await db.exec("update public.contractor_users set role='owner',status='suspended'");await assert.rejects(save(db),/management access/);
 await db.exec("update public.contractor_users set status='active';select set_config('request.jwt.claim.sub','',false)");await assert.rejects(save(db),/management access/);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
 await save(db);await db.exec("update public.contractors set verification_status='verified'");
 await save(db,{...payload,main_phone:'9876543211'});
 assert.equal((await db.query('select verification_status from public.get_contractor_portal_profile()')).rows[0].verification_status,'verified');
 const grants=(await db.query("select has_function_privilege('anon','public.update_contractor_portal_profile(jsonb)','execute') a,has_function_privilege('authenticated','public.update_contractor_portal_profile(jsonb)','execute') b")).rows[0];assert.deepEqual(grants,{a:false,b:true});
 }finally{await db.close()}});
