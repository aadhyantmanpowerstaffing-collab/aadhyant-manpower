-- Batch D rollback checkpoint: joining lifecycle and fulfillment hardening.
begin;

do $$
begin
  if to_regprocedure('public.create_recruitment_joining(uuid,date,text,text,uuid)') is null
     or to_regprocedure('public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid)') is null
     or to_regprocedure('public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid)') is null
     or to_regprocedure('public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)') is null then
    raise exception 'Batch D joining RPCs are missing';
  end if;
  if not has_function_privilege('authenticated','public.create_recruitment_joining(uuid,date,text,text,uuid)','execute')
     or has_function_privilege('anon','public.create_recruitment_joining(uuid,date,text,text,uuid)','execute')
     or has_function_privilege('anon','public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)','execute') then
    raise exception 'Batch D function grant matrix is invalid';
  end if;
  if to_regprocedure('public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)') is null
     or has_function_privilege('authenticated','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or has_function_privilege('anon','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute') then
    raise exception 'Batch D compatibility wrapper boundary is invalid';
  end if;
  if not has_table_privilege('authenticated','public.candidate_applications','select')
     or has_table_privilege('authenticated','public.candidate_applications','insert,update,delete')
     or not has_table_privilege('authenticated','public.candidate_joinings','select')
     or has_table_privilege('authenticated','public.candidate_joinings','insert,update,delete')
     or exists(select 1 from pg_attribute a where a.attrelid='public.candidate_applications'::regclass
       and a.attnum>0 and not a.attisdropped
       and has_column_privilege('authenticated','public.candidate_applications',a.attname,'update'))
     or exists(select 1 from pg_attribute a where a.attrelid='public.candidate_joinings'::regclass
       and a.attnum>0 and not a.attisdropped
       and has_column_privilege('authenticated','public.candidate_joinings',a.attname,'update')) then
    raise exception 'Batch D direct-write privilege boundary is invalid';
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='candidate_applications' and policyname='M7 admins read applications' and cmd='SELECT')
     or not exists(select 1 from pg_policies where schemaname='public' and tablename='candidate_joinings' and policyname='M7 admins read joinings' and cmd='SELECT')
     or exists(select 1 from pg_policies where schemaname='public' and tablename in ('candidate_applications','candidate_joinings')
       and cmd in ('INSERT','UPDATE','DELETE','ALL')) then
    raise exception 'Batch D direct-write policy boundary is invalid';
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.candidate_joinings'::regclass and conname='candidate_joinings_actual_date_state_check')
     or not exists(select 1 from pg_trigger where tgrelid='public.candidate_joinings'::regclass and tgname='candidate_joinings_validate_dates' and tgenabled<>'D') then
    raise exception 'Batch D joining date enforcement is missing';
  end if;
  if pg_get_functiondef('public.create_recruitment_joining(uuid,date,text,text,uuid)'::regprocedure) not ilike '%security definer%'
     or pg_get_functiondef('public.create_recruitment_joining(uuid,date,text,text,uuid)'::regprocedure) not ilike '%search_path to ''''%'
     or pg_get_functiondef('public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)'::regprocedure) not ilike '%private.can_correct_joinings%'
     or pg_get_functiondef('public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)'::regprocedure) ilike '%can_manage_joinings%' then
    raise exception 'Batch D security-definer posture is invalid';
  end if;
end;
$$;

create temporary table batch_d_baseline as
select (select count(*) from public.employer_requirements) requirements,
       (select count(*) from public.candidates) candidates,
       (select count(*) from public.candidate_applications) applications,
       (select count(*) from public.candidate_joinings) joinings,
       (select count(*) from public.audit_logs) audits;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('96000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-bootstrap@test.invalid','x','{}','{}',now(),now()),
('96000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-operations@test.invalid','x','{}','{}',now(),now()),
('96000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-recruiter@test.invalid','x','{}','{}',now(),now()),
('96000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-admin@test.invalid','x','{}','{}',now(),now()),
('96000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-candidate@test.invalid','x','{}','{}',now(),now()),
('96000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-company@test.invalid','x','{}','{}',now(),now()),
('96000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','batch-d-contractor@test.invalid','x','{}','{}',now(),now());

insert into public.admin_users(user_id) values('96000000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values
('96000000-0000-0000-0000-000000000002','Batch D Operations','active'),
('96000000-0000-0000-0000-000000000003','Batch D Recruiter','active'),
('96000000-0000-0000-0000-000000000004','Batch D Admin','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('96000000-0000-0000-0000-000000000002','operations','active','96000000-0000-0000-0000-000000000001'),
('96000000-0000-0000-0000-000000000003','recruiter','active','96000000-0000-0000-0000-000000000001'),
('96000000-0000-0000-0000-000000000004','admin','active','96000000-0000-0000-0000-000000000001');

insert into public.companies(id,legal_name,trade_name,verification_status,account_status) values
('96000000-0000-0000-0001-000000000001','Batch D Company Private Limited','Batch D Company','verified','active');
insert into public.platform_users(user_id,account_type,display_name,account_status) values
('96000000-0000-0000-0000-000000000005','candidate','Batch D Candidate Portal','active'),
('96000000-0000-0000-0000-000000000006','company','Batch D Company Portal','active'),
('96000000-0000-0000-0000-000000000007','contractor','Batch D Contractor Portal','active');
insert into public.company_users(company_id,user_id,role,status) values
('96000000-0000-0000-0001-000000000001','96000000-0000-0000-0000-000000000006','owner','active');
insert into public.contractors(id,agency_name,verification_status,account_status) values
('96000000-0000-0000-0001-000000000002','Batch D Contractor','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('96000000-0000-0000-0001-000000000002','96000000-0000-0000-0000-000000000007','owner','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,interview_available,consent,status,user_id,profile_status)
select ('96000000-0000-0000-0002-'||lpad(g::text,12,'0'))::uuid,'Batch D Candidate '||g,24,'Female','98'||lpad(g::text,8,'0'),
  'Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new',
  case when g=1 then '96000000-0000-0000-0000-000000000005'::uuid else null end,'active'
from generate_series(1,30) g;

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,filled_positions,
  qualification,consent,status,requirement_code,company_id,job_location,requirement_stage,requirement_visibility,published_at)
values
('96000000-0000-0000-0003-000000000001','Batch D Company','Contact','9876500001','Chennai','Main Lifecycle',20,0,'ITI',true,'in_progress','BDD-REQ-MAIN','96000000-0000-0000-0001-000000000001','Chennai','open','private',now()),
('96000000-0000-0000-0003-000000000002','Batch D Company','Contact','9876500002','Chennai','Final Slot',1,0,'ITI',true,'in_progress','BDD-REQ-FULL','96000000-0000-0000-0001-000000000001','Chennai','open','public',now()),
('96000000-0000-0000-0003-000000000003','Batch D Company','Contact','9876500003','Chennai','On Hold',2,0,'ITI',true,'in_progress','BDD-REQ-HOLD','96000000-0000-0000-0001-000000000001','Chennai','open','private',now()),
('96000000-0000-0000-0003-000000000004','Batch D Company','Contact','9876500004','Chennai','Draft Gate',2,0,'ITI',true,'new','BDD-REQ-DRAFT','96000000-0000-0000-0001-000000000001','Chennai','draft','private',null),
('96000000-0000-0000-0003-000000000005','Batch D Company','Contact','9876500005','Chennai','Closed Gate',2,0,'ITI',true,'closed','BDD-REQ-CLOSED','96000000-0000-0000-0001-000000000001','Chennai','closed','private',now()),
('96000000-0000-0000-0003-000000000006','Batch D Company','Contact','9876500006','Chennai','Cancelled Gate',2,0,'ITI',true,'closed','BDD-REQ-CANCEL','96000000-0000-0000-0001-000000000001','Chennai','cancelled','private',now());

insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by)
select ('96000000-0000-0000-0004-'||lpad(g::text,12,'0'))::uuid,
       ('96000000-0000-0000-0002-'||lpad(g::text,12,'0'))::uuid,
       case when g between 1 and 20 then '96000000-0000-0000-0003-000000000001'::uuid
            when g between 21 and 22 then '96000000-0000-0000-0003-000000000002'::uuid
            when g between 23 and 24 then '96000000-0000-0000-0003-000000000003'::uuid
            when g=25 then '96000000-0000-0000-0003-000000000004'::uuid
            when g=26 then '96000000-0000-0000-0003-000000000005'::uuid
            when g=28 then '96000000-0000-0000-0003-000000000002'::uuid
            else '96000000-0000-0000-0003-000000000006'::uuid end,
       'admin','selected','96000000-0000-0000-0000-000000000001'
from generate_series(1,28) g;

-- The retained wrapper remains owner-controlled compatibility only; browser execution stays revoked.
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000001',true);
do $$
declare
  india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
  message text;
begin
  foreach message in array array['confirmed','deferred','joined','no_show','cancelled','left'] loop
    begin
      perform public.upsert_recruitment_joining('96000000-0000-0000-0004-000000000008',india_today+5,
        case when message in ('joined','left') then india_today else null end,message,null,'reason',gen_random_uuid());
      raise exception 'Direct % creation succeeded',message;
    exception when others then
      if sqlerrm='Direct '||message||' creation succeeded' then raise; end if;
    end;
  end loop;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000001',true);

-- Approved lifecycle edges, date behavior, reasons, idempotency, and fulfillment.
do $$
declare
  india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
  j uuid; row_before public.candidate_joinings%rowtype; row_after public.candidate_joinings%rowtype;
  counter_before integer; audit_before bigint; target uuid;
begin
  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000001',india_today+7,null,null,'96000000-1000-0000-0000-000000000001');
  select count(*) into audit_before from public.audit_logs where correlation_id='96000000-1000-0000-0000-000000000001';
  target:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000001',india_today+7,null,null,'96000000-1000-0000-0000-000000000001');
  if target<>j or (select count(*) from public.audit_logs where correlation_id='96000000-1000-0000-0000-000000000001')<>audit_before then
    raise exception 'Joining creation retry was not idempotent';
  end if;
  select * into row_before from public.candidate_joinings where id=j;
  begin update public.candidate_joinings set expected_joining_date=null where id=j; raise exception 'Active joining expected-date trigger bypassed';
  exception when others then if sqlerrm='Active joining expected-date trigger bypassed' then raise; end if; end;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'confirmed',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000002');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'confirmed',row_before.updated_at,'deferred',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000003');

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000002',india_today+7,null,null,'96000000-1000-0000-0000-000000000004');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'deferred',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000005');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'deferred',row_before.updated_at,'confirmed',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000006');

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000003',india_today+1,'EMP-003',null,'96000000-1000-0000-0000-000000000007');
  select * into row_before from public.candidate_joinings where id=j; select count(*) into audit_before from public.audit_logs;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'joined',row_before.expected_joining_date,india_today,'EMP-003',null,'96000000-1000-0000-0000-000000000008');
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'joined',row_before.expected_joining_date,india_today,'EMP-003',null,'96000000-1000-0000-0000-000000000008');
  if (select filled_positions from public.employer_requirements where requirement_code='BDD-REQ-MAIN')<>1
     or (select count(*) from public.audit_logs)<>audit_before+3 then raise exception 'Joined retry changed fulfillment or audit twice'; end if;
  select * into row_before from public.candidate_joinings where id=j; select count(*) into audit_before from public.audit_logs;
  begin perform public.transition_recruitment_joining(j,'joined',row_before.updated_at,'left',row_before.expected_joining_date,null,'EMP-003',null,gen_random_uuid());raise exception 'Left without reason succeeded';
  exception when others then if sqlerrm='Left without reason succeeded' then raise; end if; end;
  perform public.transition_recruitment_joining(j,'joined',row_before.updated_at,'left',row_before.expected_joining_date,null,'EMP-003','Candidate left','96000000-1000-0000-0000-000000000009');
  perform public.transition_recruitment_joining(j,'joined',row_before.updated_at,'left',row_before.expected_joining_date,null,'EMP-003','Candidate left','96000000-1000-0000-0000-000000000009');
  select * into row_after from public.candidate_joinings where id=j;
  if row_after.actual_joining_date<>india_today or (select filled_positions from public.employer_requirements where requirement_code='BDD-REQ-MAIN')<>0
     or (select count(*) from public.audit_logs)<>audit_before+3 then raise exception 'Left retry/date/counter assertion failed'; end if;

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000004',india_today+2,null,null,'96000000-1000-0000-0000-000000000010');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'no_show',row_before.expected_joining_date,null,null,'Did not report','96000000-1000-0000-0000-000000000011');
  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000005',india_today+2,null,null,'96000000-1000-0000-0000-000000000012');
  select * into row_before from public.candidate_joinings where id=j;
  begin perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'cancelled',row_before.expected_joining_date,null,null,null,gen_random_uuid());raise exception 'Cancelled without reason succeeded';
  exception when others then if sqlerrm='Cancelled without reason succeeded' then raise; end if; end;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'cancelled',row_before.expected_joining_date,null,null,'Placement withdrawn','96000000-1000-0000-0000-000000000013');

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000006',india_today+4,null,null,'96000000-1000-0000-0000-000000000014');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'confirmed',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000015');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'confirmed',row_before.updated_at,'joined',row_before.expected_joining_date,india_today,null,null,'96000000-1000-0000-0000-000000000016');

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000007',india_today+5,null,null,'96000000-1000-0000-0000-000000000017');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'deferred',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000018');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'deferred',row_before.updated_at,'joined',row_before.expected_joining_date,india_today-10,null,null,'96000000-1000-0000-0000-000000000019');
  if (select actual_joining_date<expected_joining_date from public.candidate_joinings where id=j) is not true then raise exception 'Historical actual-before-expected date was rejected'; end if;

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000008',india_today+5,null,null,'96000000-1000-0000-0000-000000000020');
  select * into row_before from public.candidate_joinings where id=j;
  perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'deferred',row_before.expected_joining_date,null,null,null,'96000000-1000-0000-0000-000000000021');
  select * into row_before from public.candidate_joinings where id=j;
  begin perform public.transition_recruitment_joining(j,'deferred',row_before.updated_at,'pending',row_before.expected_joining_date,null,null,null,gen_random_uuid());raise exception 'Deferred to Pending succeeded';
  exception when others then if sqlerrm='Deferred to Pending succeeded' then raise; end if; end;

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000009',india_today+5,null,null,'96000000-1000-0000-0000-000000000022');
  select * into row_before from public.candidate_joinings where id=j;
  begin perform public.transition_recruitment_joining(j,'confirmed',row_before.updated_at,'joined',row_before.expected_joining_date,india_today,null,null,gen_random_uuid());raise exception 'Stale status succeeded';
  exception when others then if sqlerrm='Stale status succeeded' then raise; end if; end;
  begin perform public.transition_recruitment_joining(j,'pending',row_before.updated_at-interval '1 second','joined',row_before.expected_joining_date,india_today,null,null,gen_random_uuid());raise exception 'Stale updated_at succeeded';
  exception when others then if sqlerrm='Stale updated_at succeeded' then raise; end if; end;

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000010',india_today+5,null,null,'96000000-1000-0000-0000-000000000023');
  select * into row_before from public.candidate_joinings where id=j;
  begin perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'joined',row_before.expected_joining_date,null,null,null,gen_random_uuid());raise exception 'Joined without actual date succeeded';
  exception when others then if sqlerrm='Joined without actual date succeeded' then raise; end if; end;
  begin perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'joined',row_before.expected_joining_date,india_today+1,null,null,gen_random_uuid());raise exception 'Future actual date succeeded';
  exception when others then if sqlerrm='Future actual date succeeded' then raise; end if; end;

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000011',india_today+5,null,null,'96000000-1000-0000-0000-000000000024');
  select * into row_before from public.candidate_joinings where id=j;
  begin perform public.transition_recruitment_joining(j,'pending',row_before.updated_at,'no_show',row_before.expected_joining_date,null,null,null,gen_random_uuid());raise exception 'No Show without reason succeeded';
  exception when others then if sqlerrm='No Show without reason succeeded' then raise; end if; end;

  begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000001',india_today+5,null,null,gen_random_uuid());raise exception 'Duplicate joining succeeded';
  exception when others then if sqlerrm='Duplicate joining succeeded' then raise; end if; end;
  begin
    select id into target from public.candidate_joinings where application_id='96000000-0000-0000-0004-000000000004';
    select * into row_before from public.candidate_joinings where id=target;
    perform public.transition_recruitment_joining(target,'no_show',row_before.updated_at,'cancelled',row_before.expected_joining_date,null,null,'Cannot change terminal',gen_random_uuid());
    raise exception 'Terminal-state transition succeeded';
  exception when others then if sqlerrm='Terminal-state transition succeeded' then raise; end if; end;

  if (select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id='96000000-0000-0000-0003-000000000001' and j.joining_status='joined')<>2
     or (select filled_positions from public.employer_requirements where id='96000000-0000-0000-0003-000000000001')<>2 then
    raise exception 'Main requirement occupancy mismatch';
  end if;
  if exists(select 1 from public.candidates where id::text like '96000000-0000-0000-0002-%' and status<>'new') then raise exception 'Candidate-wide status was synchronized'; end if;
end;
$$;

-- Requirement gates, full-headcount lifecycle, explicit reopening, and final-slot protection.
do $$
declare india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date; j1 uuid; j2 uuid; r public.candidate_joinings%rowtype;
begin
  j1:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000021',india_today+3,null,null,'96000000-2000-0000-0000-000000000001');
  j2:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000022',india_today+3,null,null,'96000000-2000-0000-0000-000000000002');
  select * into r from public.candidate_joinings where id=j1;
  perform public.transition_recruitment_joining(j1,'pending',r.updated_at,'joined',r.expected_joining_date,india_today,null,null,'96000000-2000-0000-0000-000000000003');
  if not exists(select 1 from public.employer_requirements where requirement_code='BDD-REQ-FULL' and filled_positions=1 and requirement_stage='filled' and requirement_visibility='private' and status='fulfilled' and closed_at is not null) then raise exception 'Full-headcount lifecycle failed'; end if;
  if not exists(select 1 from public.audit_logs where action='recruitment.requirement_lifecycle_changed'
    and correlation_id='96000000-2000-0000-0000-000000000003' and metadata->>'automatic'='true'
    and metadata->'old'->>'requirement_stage'='open' and metadata->'new'->>'requirement_stage'='filled') then
    raise exception 'Automatic full-headcount lifecycle audit failed';
  end if;
  if exists(select 1 from public.get_public_job_requirements(50,0) where requirement_code='BDD-REQ-FULL') then
    raise exception 'Full requirement remained in the public opportunity projection';
  end if;
  begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000028',india_today+3,null,null,gen_random_uuid());raise exception 'Filled requirement creation succeeded';
  exception when others then if sqlerrm='Filled requirement creation succeeded' then raise;end if;end;
  begin perform public.set_company_requirement_stage('96000000-0000-0000-0003-000000000002','open','public');raise exception 'Zero-capacity reopen succeeded';exception when others then if sqlerrm='Zero-capacity reopen succeeded' then raise;end if;end;
  select * into r from public.candidate_joinings where id=j2;
  begin perform public.transition_recruitment_joining(j2,'pending',r.updated_at,'joined',r.expected_joining_date,india_today,null,null,gen_random_uuid());raise exception 'Final-slot overfill succeeded';exception when others then if sqlerrm='Final-slot overfill succeeded' then raise;end if;end;
  begin perform public.correct_recruitment_joining(j2,r.updated_at,'joined',r.expected_joining_date,india_today,null,null,'Attempted overfill',gen_random_uuid());raise exception 'Correction overfill succeeded';exception when others then if sqlerrm='Correction overfill succeeded' then raise;end if;end;
  select * into r from public.candidate_joinings where id=j1;
  perform public.transition_recruitment_joining(j1,'joined',r.updated_at,'left',r.expected_joining_date,null,null,'Left after joining','96000000-2000-0000-0000-000000000004');
  if not exists(select 1 from public.employer_requirements where requirement_code='BDD-REQ-FULL' and filled_positions=0 and requirement_stage='filled' and requirement_visibility='private' and status='fulfilled') then raise exception 'Left reopened or republished requirement'; end if;
  select * into r from public.candidate_joinings where id=j2;
  begin perform public.transition_recruitment_joining(j2,'pending',r.updated_at,'joined',r.expected_joining_date,india_today,null,null,gen_random_uuid());raise exception 'Filled requirement with remaining capacity accepted Joined';exception when others then if sqlerrm='Filled requirement with remaining capacity accepted Joined' then raise;end if;end;
  perform public.set_company_requirement_stage('96000000-0000-0000-0003-000000000002','open','public');
  if not exists(select 1 from public.employer_requirements where requirement_code='BDD-REQ-FULL' and requirement_stage='open' and requirement_visibility='public' and filled_positions=0) then raise exception 'Explicit capacity-backed reopen failed'; end if;

  j1:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000023',india_today+4,null,null,'96000000-2000-0000-0000-000000000005');
  perform public.set_company_requirement_stage('96000000-0000-0000-0003-000000000003','on_hold','private');
  begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000024',india_today+4,null,null,gen_random_uuid());raise exception 'On Hold creation succeeded';exception when others then if sqlerrm='On Hold creation succeeded' then raise;end if;end;
  select * into r from public.candidate_joinings where id=j1;
  perform public.transition_recruitment_joining(j1,'pending',r.updated_at,'confirmed',r.expected_joining_date,null,null,null,'96000000-2000-0000-0000-000000000006');
  select * into r from public.candidate_joinings where id=j1;
  perform public.transition_recruitment_joining(j1,'confirmed',r.updated_at,'joined',r.expected_joining_date,india_today,null,null,'96000000-2000-0000-0000-000000000007');

  begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000025',india_today+4,null,null,gen_random_uuid());raise exception 'Draft creation succeeded';exception when others then if sqlerrm='Draft creation succeeded' then raise;end if;end;
  begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000026',india_today+4,null,null,gen_random_uuid());raise exception 'Closed creation succeeded';exception when others then if sqlerrm='Closed creation succeeded' then raise;end if;end;
  begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000027',india_today+4,null,null,gen_random_uuid());raise exception 'Cancelled creation succeeded';exception when others then if sqlerrm='Cancelled creation succeeded' then raise;end if;end;
end;
$$;

-- Application ownership, strict legacy application RPC, detail updates, and correction behavior.
do $$
declare india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date; j uuid; r public.candidate_joinings%rowtype; before_count integer; audit_before bigint;
begin
  begin perform public.admin_update_candidate_application('96000000-0000-0000-0004-000000000013','joining_pending','Bypass');raise exception 'Legacy Admin joining stage bypass succeeded';exception when others then if sqlerrm='Legacy Admin joining stage bypass succeeded' then raise;end if;end;
  perform public.admin_update_candidate_application('96000000-0000-0000-0004-000000000013','selected','Safe notes-only update');

  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000012',india_today+8,null,null,'96000000-3000-0000-0000-000000000001');
  select * into r from public.candidate_joinings where id=j;
  select count(*) into audit_before from public.audit_logs;
  perform public.update_recruitment_joining_details(j,'pending',r.updated_at,india_today+9,'EMP-012','Details updated','96000000-3000-0000-0000-000000000002');
  perform public.update_recruitment_joining_details(j,'pending',r.updated_at,india_today+9,'EMP-012','Details updated','96000000-3000-0000-0000-000000000002');
  if (select count(*) from public.audit_logs)<>audit_before+1 then raise exception 'Detail-update retry duplicated audit'; end if;
  select * into r from public.candidate_joinings where id=j; select filled_positions into before_count from public.employer_requirements where id='96000000-0000-0000-0003-000000000001';
  select count(*) into audit_before from public.audit_logs;
  perform public.correct_recruitment_joining(j,r.updated_at,'joined',india_today+9,india_today-1,'EMP-012A','Corrected placement','Historical joining correction','96000000-3000-0000-0000-000000000003');
  perform public.correct_recruitment_joining(j,r.updated_at,'joined',india_today+9,india_today-1,'EMP-012A','Corrected placement','Historical joining correction','96000000-3000-0000-0000-000000000003');
  if (select filled_positions from public.employer_requirements where id='96000000-0000-0000-0003-000000000001')<>before_count+1
     or (select count(*) from public.audit_logs)<>audit_before+3
     or not exists(select 1 from public.candidate_applications where id='96000000-0000-0000-0004-000000000012' and application_status='joined') then raise exception 'Joined correction synchronization/retry failed'; end if;
  select * into r from public.candidate_joinings where id=j;
  perform public.correct_recruitment_joining(j,r.updated_at,'pending',india_today+10,null,'EMP-012B','Returned to active','Correct invalid Joined state','96000000-3000-0000-0000-000000000004');
  if (select filled_positions from public.employer_requirements where id='96000000-0000-0000-0003-000000000001')<>before_count
     or not exists(select 1 from public.candidate_applications where id='96000000-0000-0000-0004-000000000012' and application_status='joining_pending') then raise exception 'Correction occupancy decrement failed'; end if;
  select * into r from public.candidate_joinings where id=j;
  begin perform public.correct_recruitment_joining(j,r.updated_at,'joined',r.expected_joining_date,india_today+1,r.employee_code,r.remarks,'Future correction',gen_random_uuid());raise exception 'Future corrected date succeeded';exception when others then if sqlerrm='Future corrected date succeeded' then raise;end if;end;
  begin perform public.correct_recruitment_joining(j,r.updated_at,'joined',r.expected_joining_date,india_today,r.employee_code,r.remarks,'',gen_random_uuid());raise exception 'Correction without reason succeeded';exception when others then if sqlerrm='Correction without reason succeeded' then raise;end if;end;
  if exists(select 1 from public.candidate_applications where id='96000000-0000-0000-0004-000000000014' and application_status<>'selected') then raise exception 'Unrelated application changed'; end if;
end;
$$;

-- Atomic rollback after the counter update but before application synchronization.
reset role;
create function private.batch_d_checkpoint_reject_application()
returns trigger language plpgsql set search_path='' as $$ begin
  if new.id='96000000-0000-0000-0004-000000000015'::uuid and new.application_status='joined' then raise exception 'Injected application synchronization failure'; end if;
  return new;
end $$;
create trigger batch_d_checkpoint_reject_application before update on public.candidate_applications
for each row execute function private.batch_d_checkpoint_reject_application();
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000001',true);
do $$
declare india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date; j uuid; r public.candidate_joinings%rowtype; before_count integer;
begin
  j:=public.create_recruitment_joining('96000000-0000-0000-0004-000000000015',india_today+2,null,null,'96000000-4000-0000-0000-000000000001');
  select * into r from public.candidate_joinings where id=j;
  select filled_positions into before_count from public.employer_requirements where id='96000000-0000-0000-0003-000000000001';
  begin perform public.transition_recruitment_joining(j,'pending',r.updated_at,'joined',r.expected_joining_date,india_today,null,null,'96000000-4000-0000-0000-000000000002');raise exception 'Injected failure did not abort';
  exception when others then if sqlerrm='Injected failure did not abort' then raise; end if; end;
  if (select filled_positions from public.employer_requirements where id='96000000-0000-0000-0003-000000000001')<>before_count
     or not exists(select 1 from public.candidate_joinings where id=j and joining_status='pending')
     or not exists(select 1 from public.candidate_applications where id='96000000-0000-0000-0004-000000000015' and application_status='joining_pending') then
    raise exception 'Atomic rollback after injected failure failed';
  end if;
end;
$$;
reset role;
drop trigger batch_d_checkpoint_reject_application on public.candidate_applications;
drop function private.batch_d_checkpoint_reject_application();

-- Correction authorization and normal joining mutation boundaries.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000002',true);
do $$ declare r public.candidate_joinings%rowtype; begin select * into r from public.candidate_joinings where application_id='96000000-0000-0000-0004-000000000012';begin perform public.correct_recruitment_joining(r.id,r.updated_at,r.joining_status,r.expected_joining_date,r.actual_joining_date,r.employee_code,r.remarks,'Operations correction',gen_random_uuid());raise exception 'Operations correction bypassed';exception when others then if sqlerrm='Operations correction bypassed' then raise;end if;end;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000003',true);
do $$ declare r public.candidate_joinings%rowtype; begin select * into r from public.candidate_joinings where application_id='96000000-0000-0000-0004-000000000012';begin perform public.correct_recruitment_joining(r.id,r.updated_at,r.joining_status,r.expected_joining_date,r.actual_joining_date,r.employee_code,r.remarks,'Recruiter correction',gen_random_uuid());raise exception 'Recruiter correction bypassed';exception when others then if sqlerrm='Recruiter correction bypassed' then raise;end if;end;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000005',true);
do $$ declare r public.candidate_joinings%rowtype; begin select * into r from public.candidate_joinings where application_id='96000000-0000-0000-0004-000000000012';begin perform public.correct_recruitment_joining(r.id,r.updated_at,r.joining_status,r.expected_joining_date,r.actual_joining_date,r.employee_code,r.remarks,'Candidate correction',gen_random_uuid());raise exception 'Candidate correction bypassed';exception when others then if sqlerrm='Candidate correction bypassed' then raise;end if;end;begin perform public.create_recruitment_joining('96000000-0000-0000-0004-000000000014',current_date+2,null,null,gen_random_uuid());raise exception 'Candidate joining write bypassed';exception when others then if sqlerrm='Candidate joining write bypassed' then raise;end if;end;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000006',true);
do $$ declare r public.candidate_joinings%rowtype; begin select * into r from public.candidate_joinings where application_id='96000000-0000-0000-0004-000000000012';begin perform public.correct_recruitment_joining(r.id,r.updated_at,r.joining_status,r.expected_joining_date,r.actual_joining_date,r.employee_code,r.remarks,'Company correction',gen_random_uuid());raise exception 'Company correction bypassed';exception when others then if sqlerrm='Company correction bypassed' then raise;end if;end;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000007',true);
do $$ declare r public.candidate_joinings%rowtype; begin select * into r from public.candidate_joinings where application_id='96000000-0000-0000-0004-000000000012';begin perform public.correct_recruitment_joining(r.id,r.updated_at,r.joining_status,r.expected_joining_date,r.actual_joining_date,r.employee_code,r.remarks,'Contractor correction',gen_random_uuid());raise exception 'Contractor correction bypassed';exception when others then if sqlerrm='Contractor correction bypassed' then raise;end if;end;end $$;
reset role;

-- Staff Admin correction succeeds; portal joining projections remain audit-free.
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000004',true);
do $$ declare r record; begin
  select * into r from public.list_recruitment_joinings(null,100)
  where application_id='96000000-0000-0000-0004-000000000012';
  perform public.correct_recruitment_joining(r.id,r.updated_at,r.joining_status,r.expected_joining_date,null,'EMP-ADMIN','Admin corrected remarks','Approved Admin correction','96000000-5000-0000-0000-000000000001');
end $$;
reset role;

do $$
begin
  if not exists(select 1 from public.audit_logs where action='recruitment.joining_corrected' and correlation_id='96000000-5000-0000-0000-000000000001' and metadata->>'reason'='Approved Admin correction' and metadata->'old' is not null and metadata->'new' is not null) then raise exception 'Rich correction audit missing'; end if;
  if not exists(select 1 from public.audit_logs where action='recruitment.joining_fulfillment_changed' and metadata ? 'counter_delta' and metadata ? 'old_requirement_stage' and metadata ? 'new_requirement_stage') then raise exception 'Fulfillment audit missing'; end if;
  if not exists(select 1 from public.audit_logs where action='recruitment.requirement_lifecycle_changed') then raise exception 'Requirement lifecycle audit missing'; end if;
  if not exists(select 1 from public.application_stage_history where correlation_id is not null and to_stage in ('joining_pending','joined','left','cancelled')) then raise exception 'Application stage history correlation missing'; end if;
  if pg_get_functiondef('public.list_company_portal_joinings(integer,integer)'::regprocedure) ilike '%audit_logs%'
     or pg_get_functiondef('public.list_candidate_portal_joinings(integer,integer)'::regprocedure) ilike '%audit_logs%'
     or pg_get_functiondef('public.list_contractor_portal_joinings(integer,integer)'::regprocedure) ilike '%audit_logs%' then raise exception 'Internal joining audit leaked into a portal projection'; end if;
end;
$$;

rollback;

do $$
begin
  if exists(select 1 from auth.users where id::text like '96000000-%')
     or exists(select 1 from public.employer_requirements where requirement_code like 'BDD-REQ-%')
     or exists(select 1 from public.candidates where id::text like '96000000-%') then
    raise exception 'Batch D checkpoint residue remains after rollback';
  end if;
end;
$$;

select 'CHECKPOINT_036_BATCH_D_PASS' as result;
