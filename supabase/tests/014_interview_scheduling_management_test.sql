-- Run only against isolated disposable Supabase with migrations through 014.
-- All fixtures and workflow changes roll back.

\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('61000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r13-admin@test.local','x','{}','{}',now(),now()),
('61000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r13-company@test.local','x','{}','{}',now(),now()),
('61000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r13-partner@test.local','x','{}','{}',now(),now());
insert into public.admin_users(user_id) values('61000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('61000000-0000-0000-0000-000000000002','company','R13 Company','r13-company@test.local','active'),
('61000000-0000-0000-0000-000000000003','contractor','R13 Partner','r13-partner@test.local','active');

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,filled_positions,consent,job_location,requirement_stage,requirement_visibility,published_at)
values('62000000-0000-0000-0000-000000000001','R13 Company','R13 Contact','9876530001','Ahmedabad','R13 Operator',10,1,true,'Ahmedabad','open','public',now());
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,interview_available,consent) values
('63000000-0000-0000-0000-000000000001','R13 Candidate',26,'Male','9876530002','Kadi','Mahesana','Gujarat','ITI','Experienced','Yes',true),
('63000000-0000-0000-0000-000000000002','R13 Terminal Candidate',27,'Female','9876530003','Sanand','Ahmedabad','Gujarat','Diploma','Experienced','Yes',true);
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status) values
('64000000-0000-0000-0000-000000000001','63000000-0000-0000-0000-000000000001','62000000-0000-0000-0000-000000000001','direct','interested'),
('64000000-0000-0000-0000-000000000002','63000000-0000-0000-0000-000000000002','62000000-0000-0000-0000-000000000001','direct','selected');

create temporary table r13_candidate_before as select * from public.candidates where id='63000000-0000-0000-0000-000000000001';
create temporary table r13_requirement_before as select * from public.employer_requirements where id='62000000-0000-0000-0000-000000000001';
create temporary table r13_application_identity_before as select id,candidate_id,requirement_id,applied_at from public.candidate_applications where id='64000000-0000-0000-0000-000000000001';

set local role anon;
do $$ declare denied boolean := false; begin
  begin perform 1 from public.interviews limit 1; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous read interviews'; end if;
  if has_function_privilege('anon','public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)','EXECUTE')
     or has_function_privilege('anon','public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)','EXECUTE')
     or has_function_privilege('anon','public.admin_update_candidate_interview(uuid,text,text,text)','EXECUTE') then
    raise exception 'Anonymous can execute R13 RPC';
  end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000002',true);
do $$ begin
  if exists(select 1 from public.interviews) then raise exception 'Company read interviews'; end if;
  begin perform public.admin_schedule_candidate_interview('64000000-0000-0000-0000-000000000001',now()+interval '1 day','onsite',null,null,null,null,null); raise exception 'Company scheduled interview';
  exception when raise_exception then if sqlerrm='Company scheduled interview' then raise; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000003',true);
do $$ begin
  if exists(select 1 from public.interviews) then raise exception 'Partner read interviews'; end if;
  begin perform public.admin_schedule_candidate_interview('64000000-0000-0000-0000-000000000001',now()+interval '1 day','video',null,'https://example.test/interview',null,null,null); raise exception 'Partner scheduled interview';
  exception when raise_exception then if sqlerrm='Partner scheduled interview' then raise; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-0000-0000-000000000001',true);
do $$
declare first_id uuid; replacement_id uuid; second_round_id uuid; cancelled_id uuid; old_applied timestamptz; terminal_status text;
begin
  select applied_at into old_applied from public.candidate_applications where id='64000000-0000-0000-0000-000000000001';
  first_id := public.admin_schedule_candidate_interview(
    '64000000-0000-0000-0000-000000000001', now()+interval '1 day', 'onsite',
    'Plant Gate 2', null, 'R13 Coordinator', '9876530099', 'Bring identification.'
  );
  if not exists(select 1 from public.interviews where id=first_id and application_id='64000000-0000-0000-0000-000000000001' and interview_round=1 and status='scheduled' and mode='onsite' and created_by='61000000-0000-0000-0000-000000000001') then raise exception 'First interview was not persisted'; end if;
  if not exists(select 1 from public.candidate_applications where id='64000000-0000-0000-0000-000000000001' and application_status='interview' and applied_at=old_applied) then raise exception 'Application did not advance safely'; end if;

  begin perform public.admin_schedule_candidate_interview('64000000-0000-0000-0000-000000000001',now()+interval '1 day','phone',null,null,null,null,null); raise exception 'Duplicate current interview accepted';
  exception when raise_exception then if sqlerrm='Duplicate current interview accepted' then raise; end if; end;

  replacement_id := public.admin_reschedule_candidate_interview(first_id,now()+interval '2 days','video',null,'https://example.test/r13','R13 Coordinator','9876530099','Join five minutes early.');
  if not exists(select 1 from public.interviews where id=first_id and status='rescheduled')
     or not exists(select 1 from public.interviews where id=replacement_id and supersedes_interview_id=first_id and interview_round=1 and status='scheduled') then raise exception 'Reschedule history was not preserved'; end if;

  if not public.admin_update_candidate_interview(replacement_id,'absent',null,'Candidate did not attend.') then raise exception 'No-show update failed'; end if;
  second_round_id := public.admin_schedule_candidate_interview('64000000-0000-0000-0000-000000000001',now()+interval '3 days','phone',null,null,'R13 Coordinator','9876530099',null);
  if not exists(select 1 from public.interviews where id=second_round_id and interview_round=2 and status='scheduled') then raise exception 'Second round number incorrect'; end if;
  if not public.admin_update_candidate_interview(second_round_id,'completed','pending','Interview completed.') then raise exception 'Completion failed'; end if;

  begin perform public.admin_update_candidate_interview(second_round_id,'not_valid',null,null); raise exception 'Invalid status accepted';
  exception when raise_exception then if sqlerrm='Invalid status accepted' then raise; end if; end;
  begin perform public.admin_update_candidate_interview(second_round_id,'completed',null,repeat('x',4001)); raise exception 'Oversized result note accepted';
  exception when raise_exception then if sqlerrm='Oversized result note accepted' then raise; end if; end;
  foreach terminal_status in array array['selected','rejected','joining_pending','joined','left','cancelled'] loop
    perform public.admin_update_candidate_application('64000000-0000-0000-0000-000000000002',terminal_status,null);
    begin perform public.admin_schedule_candidate_interview('64000000-0000-0000-0000-000000000002',now()+interval '1 day','onsite',null,null,null,null,null); raise exception 'Terminal application scheduled';
    exception when raise_exception then if sqlerrm='Terminal application scheduled' then raise; end if; end;
  end loop;

  if not public.admin_update_candidate_application('64000000-0000-0000-0000-000000000001','interview','R12 still works') then raise exception 'R12 RPC regression'; end if;
  cancelled_id := public.admin_schedule_candidate_interview('64000000-0000-0000-0000-000000000001',now()+interval '4 days','other','Reception',null,null,null,null);
  if not public.admin_update_candidate_interview(cancelled_id,'cancelled',null,'Cancelled by Admin.') then raise exception 'Cancellation failed'; end if;
end $$;
reset role;

do $$ begin
  if exists(select 1 from public.candidates c join r13_candidate_before b using(id) where to_jsonb(c) is distinct from to_jsonb(b)) then raise exception 'Candidate master changed'; end if;
  if exists(select 1 from public.employer_requirements r join r13_requirement_before b using(id) where to_jsonb(r) is distinct from to_jsonb(b)) then raise exception 'Requirement changed'; end if;
  if exists(select 1 from public.candidate_applications a join r13_application_identity_before b using(id) where a.candidate_id<>b.candidate_id or a.requirement_id<>b.requirement_id or a.applied_at<>b.applied_at) then raise exception 'Application identity changed'; end if;
  if (select count(*) from public.interviews where application_id='64000000-0000-0000-0000-000000000001' and status='scheduled') <> 0 then raise exception 'Unexpected current interview remained'; end if;
  if to_regprocedure('public.get_public_job_requirements(integer,integer)') is null or to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null then raise exception 'R10/R11 regression'; end if;
  if not exists(select 1 from pg_constraint where conrelid='public.candidate_applications'::regclass and conname='candidate_applications_candidate_id_requirement_id_key') then raise exception 'Application unique constraint changed'; end if;
  if has_table_privilege('authenticated','public.interviews','INSERT') or has_table_privilege('authenticated','public.interviews','UPDATE') then raise exception 'Direct interview mutation remains granted'; end if;
end $$;

rollback;
