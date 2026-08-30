-- Batch D checkpoint: browser direct-write revocation and canonical RPC continuity.
\set ON_ERROR_STOP on
begin;

do $$
declare
  signature text;
begin
  if not has_table_privilege('authenticated','public.candidate_applications','select')
     or has_table_privilege('authenticated','public.candidate_applications','insert,update,delete')
     or not has_table_privilege('authenticated','public.candidate_joinings','select')
     or has_table_privilege('authenticated','public.candidate_joinings','insert,update,delete') then
    raise exception 'Checkpoint 037 target table privilege boundary is invalid';
  end if;
  if exists(
    select 1 from pg_attribute a
    where a.attrelid in ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass)
      and a.attnum>0 and not a.attisdropped
      and has_column_privilege('authenticated',a.attrelid,a.attnum,'update')
  ) then
    raise exception 'Checkpoint 037 authenticated column UPDATE remains';
  end if;
  if (select count(*) from pg_policy where polrelid in
      ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass))<>2
     or not exists(select 1 from pg_policy where polrelid='public.candidate_applications'::regclass
       and polname='M7 admins read applications' and polcmd='r')
     or not exists(select 1 from pg_policy where polrelid='public.candidate_joinings'::regclass
       and polname='M7 admins read joinings' and polcmd='r')
     or exists(select 1 from pg_policy where polrelid in
       ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass) and polcmd in ('a','w','d','*')) then
    raise exception 'Checkpoint 037 policy boundary is invalid';
  end if;
  if to_regprocedure('public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)') is null
     or has_function_privilege('authenticated','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or has_function_privilege('anon','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or exists(
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       where p.oid='public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)'::regprocedure
         and acl.grantee=0 and acl.privilege_type='EXECUTE'
     ) then
    raise exception 'Checkpoint 037 compatibility wrapper boundary is invalid';
  end if;

  foreach signature in array array[
    'public.create_recruitment_joining(uuid,date,text,text,uuid)',
    'public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid)',
    'public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid)',
    'public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)',
    'public.admin_update_candidate_application(uuid,text,text)'
  ] loop
    if not has_function_privilege('authenticated',signature,'execute')
       or has_function_privilege('anon',signature,'execute')
       or exists(
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
         where p.oid=to_regprocedure(signature) and acl.grantee=0 and acl.privilege_type='EXECUTE'
       ) then
      raise exception 'Checkpoint 037 canonical RPC grant is invalid for %',signature;
    end if;
  end loop;

  foreach signature in array array[
    'private.can_manage_joinings()',
    'private.can_correct_joinings()',
    'private.joining_application_status(text)',
    'private.validate_candidate_joining_dates()'
  ] loop
    if has_function_privilege('authenticated',signature,'execute')
       or has_function_privilege('anon',signature,'execute')
       or exists(
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
         where p.oid=to_regprocedure(signature) and acl.grantee=0 and acl.privilege_type='EXECUTE'
       ) then
      raise exception 'Checkpoint 037 private helper is browser-accessible: %',signature;
    end if;
  end loop;
end;
$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('97000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-bootstrap@test.invalid','x','{}','{}',now(),now()),
('97000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-recruiter@test.invalid','x','{}','{}',now(),now()),
('97000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-operations@test.invalid','x','{}','{}',now(),now()),
('97000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-admin@test.invalid','x','{}','{}',now(),now()),
('97000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-candidate@test.invalid','x','{}','{}',now(),now()),
('97000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-company@test.invalid','x','{}','{}',now(),now()),
('97000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bde-contractor@test.invalid','x','{}','{}',now(),now());

insert into public.admin_users(user_id) values('97000000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values
('97000000-0000-0000-0000-000000000002','Batch D E Recruiter','active'),
('97000000-0000-0000-0000-000000000003','Batch D E Operations','active'),
('97000000-0000-0000-0000-000000000004','Batch D E Admin','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('97000000-0000-0000-0000-000000000002','recruiter','active','97000000-0000-0000-0000-000000000001'),
('97000000-0000-0000-0000-000000000003','operations','active','97000000-0000-0000-0000-000000000001'),
('97000000-0000-0000-0000-000000000004','admin','active','97000000-0000-0000-0000-000000000001');

insert into public.companies(id,legal_name,trade_name,verification_status,account_status) values
('97000000-0000-0000-0005-000000000001','Batch D E Company Private Limited','Batch D E Company','verified','active');
insert into public.platform_users(user_id,account_type,display_name,account_status) values
('97000000-0000-0000-0000-000000000005','candidate','Batch D E Candidate Portal','active'),
('97000000-0000-0000-0000-000000000006','company','Batch D E Company Portal','active'),
('97000000-0000-0000-0000-000000000007','contractor','Batch D E Contractor Portal','active');
insert into public.company_users(company_id,user_id,role,status) values
('97000000-0000-0000-0005-000000000001','97000000-0000-0000-0000-000000000006','owner','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,
  specialization,candidate_type,interview_available,consent,status)
select ('97000000-0000-0000-0001-'||lpad(g::text,12,'0'))::uuid,'Batch D E Candidate '||g,24,'Female',
  '97'||lpad(g::text,8,'0'),'Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new'
from generate_series(1,4) g;

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,consent,status,requirement_code,company_id,job_location,requirement_stage,requirement_visibility)
values('97000000-0000-0000-0002-000000000001','Batch D E Company','Contact','9700000010','Chennai',
  'Direct-write guard',3,'ITI',true,'in_progress','BDE-REQ-001','97000000-0000-0000-0005-000000000001','Chennai','open','private');

insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by) values
('97000000-0000-0000-0003-000000000001','97000000-0000-0000-0001-000000000001','97000000-0000-0000-0002-000000000001','admin','selected','97000000-0000-0000-0000-000000000001'),
('97000000-0000-0000-0003-000000000002','97000000-0000-0000-0001-000000000002','97000000-0000-0000-0002-000000000001','admin','applied','97000000-0000-0000-0000-000000000001');

set local role authenticated;

-- Every browser identity, including administrators, is denied direct target writes.
do $$
declare
  actor uuid;
begin
  foreach actor in array array[
    '97000000-0000-0000-0000-000000000002'::uuid,
    '97000000-0000-0000-0000-000000000003'::uuid,
    '97000000-0000-0000-0000-000000000004'::uuid,
    '97000000-0000-0000-0000-000000000005'::uuid,
    '97000000-0000-0000-0000-000000000006'::uuid,
    '97000000-0000-0000-0000-000000000007'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    begin
      update public.candidate_applications set application_status='screening'
      where id='97000000-0000-0000-0003-000000000002';
      raise exception 'Direct application UPDATE succeeded for %',actor;
    exception when insufficient_privilege then null;
      when others then if sqlerrm like 'Direct application UPDATE succeeded%' then raise; else raise exception 'Unexpected application UPDATE result for %: %',actor,sqlerrm; end if;
    end;
    begin
      insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,created_by)
      values('97000000-0000-0000-0001-000000000003','97000000-0000-0000-0002-000000000001','admin','selected',actor);
      raise exception 'Direct application INSERT succeeded for %',actor;
    exception when insufficient_privilege then null;
      when others then if sqlerrm like 'Direct application INSERT succeeded%' then raise; else raise exception 'Unexpected application INSERT result for %: %',actor,sqlerrm; end if;
    end;
    begin
      insert into public.candidate_joinings(application_id,expected_joining_date,joining_status,created_by)
      values('97000000-0000-0000-0003-000000000001',current_date+5,'pending',actor);
      raise exception 'Direct joining INSERT succeeded for %',actor;
    exception when insufficient_privilege then null;
      when others then if sqlerrm like 'Direct joining INSERT succeeded%' then raise; else raise exception 'Unexpected joining INSERT result for %: %',actor,sqlerrm; end if;
    end;
  end loop;
end;
$$;

-- Company retains its scoped, contact-safe read projections after write revocation.
select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000006',true);
do $$
declare context_row record; application_row record;
begin
  select * into context_row from public.get_company_portal_context();
  if context_row.company_id<>'97000000-0000-0000-0005-000000000001'::uuid
     or (select count(*) from public.list_company_portal_requirements())<>1 then
    raise exception 'Company safe requirement projection failed';
  end if;
  select * into application_row from public.list_company_portal_applications(null,null,25,0)
  where application_id='97000000-0000-0000-0003-000000000001';
  if application_row.application_id is null
     or to_jsonb(application_row) ?| array['mobile','whatsapp_number','candidate_id','internal_notes'] then
    raise exception 'Company safe application projection failed';
  end if;
end;
$$;

-- Recruiter uses the approved application RPC while direct writes remain denied.
select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000002',true);
do $$
declare application_id uuid;
begin
  application_id:=public.create_recruitment_application(
    '97000000-0000-0000-0001-000000000003','97000000-0000-0000-0002-000000000001','manual',null);
  if application_id is null then raise exception 'Recruiter canonical application creation failed'; end if;
end;
$$;

-- Operations uses only the canonical joining lifecycle RPCs.
select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000003',true);
do $$
declare
  joining_id uuid;
  joining_row record;
  india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  joining_id:=public.create_recruitment_joining('97000000-0000-0000-0003-000000000001',india_today+3,null,null,
    '97000000-1000-0000-0000-000000000001');
  select * into joining_row from public.list_recruitment_joinings(null,100) where id=joining_id;
  perform public.transition_recruitment_joining(joining_id,joining_row.joining_status,joining_row.updated_at,'joined',
    joining_row.expected_joining_date,india_today,'BDE-EMP-1',null,'97000000-1000-0000-0000-000000000002');
  if (select count(*) from public.list_recruitment_joinings('joined',100) where id=joining_id)<>1 then
    raise exception 'Operations canonical joining lifecycle failed';
  end if;
  begin
    perform public.correct_recruitment_joining(joining_id,(select updated_at from public.list_recruitment_joinings(null,100) where id=joining_id),
      'left',india_today+3,india_today,'BDE-EMP-1','Correction denied','Operations must not correct',gen_random_uuid());
    raise exception 'Operations joining correction succeeded';
  exception when others then if sqlerrm='Operations joining correction succeeded' then raise; end if;
  end;
end;
$$;

-- The existing bootstrap-admin application RPC remains available without table writes.
select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000001',true);
do $$
begin
  if not public.admin_update_candidate_application('97000000-0000-0000-0003-000000000002','screening','Checkpoint 037') then
    raise exception 'Bootstrap Admin application RPC failed';
  end if;
end;
$$;

-- Staff Admin correction authority remains available through the canonical RPC.
select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000004',true);
do $$
declare joining_row record; admin_application_id uuid;
begin
  admin_application_id:=public.create_recruitment_application(
    '97000000-0000-0000-0001-000000000004','97000000-0000-0000-0002-000000000001','manual',null);
  if admin_application_id is null then raise exception 'Admin canonical application creation failed'; end if;
  select * into joining_row from public.list_recruitment_joinings('joined',100)
  where application_id='97000000-0000-0000-0003-000000000001';
  perform public.correct_recruitment_joining(joining_row.id,joining_row.updated_at,'left',joining_row.expected_joining_date,
    joining_row.actual_joining_date,joining_row.employee_code,'Checkpoint correction','Checkpoint 037 correction',
    '97000000-1000-0000-0000-000000000003');
  if (select count(*) from public.list_recruitment_joinings('left',100) where id=joining_row.id)<>1 then
    raise exception 'Admin canonical correction failed';
  end if;
end;
$$;

reset role;

-- Owner-controlled compatibility remains present without restoring browser execution.
select set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000001',true);
do $$
begin
  if not has_function_privilege(current_user,'public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute') then
    raise exception 'Migration owner compatibility execution disappeared';
  end if;
  begin
    perform public.upsert_recruitment_joining('97000000-0000-0000-0003-000000000002',current_date+4,null,'joined',null,'invalid direct state',gen_random_uuid());
    raise exception 'Owner compatibility wrapper bypassed Pending creation';
  exception when others then if sqlerrm='Owner compatibility wrapper bypassed Pending creation' then raise; end if;
  end;
end;
$$;

set local role anon;
do $$
begin
  begin
    insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status)
    values('97000000-0000-0000-0001-000000000003','97000000-0000-0000-0002-000000000001','public_interest','interested');
    raise exception 'Anonymous direct application INSERT succeeded';
  exception when insufficient_privilege then null;
    when others then if sqlerrm='Anonymous direct application INSERT succeeded' then raise; else raise exception 'Unexpected anonymous INSERT result: %',sqlerrm; end if;
  end;
  begin
    perform public.create_recruitment_joining('97000000-0000-0000-0003-000000000002',current_date+3,null,null,null);
    raise exception 'Anonymous canonical joining mutation succeeded';
  exception when insufficient_privilege then null;
    when others then if sqlerrm='Anonymous canonical joining mutation succeeded' then raise; else raise exception 'Unexpected anonymous RPC result: %',sqlerrm; end if;
  end;
end;
$$;
reset role;

select 'CHECKPOINT_037_BATCH_D_DIRECT_WRITE_HARDENING_PASS' as result;
rollback;

do $$
begin
  if exists(select 1 from public.candidates where id::text like '97000000-%')
     or exists(select 1 from public.employer_requirements where id::text like '97000000-%')
     or exists(select 1 from public.candidate_applications where id::text like '97000000-%')
     or exists(select 1 from public.candidate_joinings where id::text like '97000000-%')
     or exists(select 1 from public.audit_logs where correlation_id::text like '97000000-%') then
    raise exception 'Checkpoint 037 fixture residue remains after rollback';
  end if;
end;
$$;

select 'CHECKPOINT_037_ZERO_RESIDUE_PASS' as result;
