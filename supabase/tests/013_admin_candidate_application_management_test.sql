-- Run only against isolated disposable Supabase with migrations through 013.
-- All fixtures and updates roll back.

\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('51000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r12-admin@test.local','x',now(),'{}','{}',now(),now()),
('51000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r12-company@test.local','x',now(),'{}','{}',now(),now()),
('51000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r12-partner@test.local','x',now(),'{}','{}',now(),now());
insert into public.admin_users(user_id) values('51000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('51000000-0000-0000-0000-000000000002','company','R12 Company','r12-company@test.local','active'),
('51000000-0000-0000-0000-000000000003','contractor','R12 Partner','r12-partner@test.local','active');

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,filled_positions,consent,job_location,requirement_stage,requirement_visibility,published_at)
values('52000000-0000-0000-0000-000000000001','R12 Company','R12 Contact','9876520001','Ahmedabad','R12 Fitter',10,1,true,'Ahmedabad','open','public',now());
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,total_experience,interview_available,consent)
values('53000000-0000-0000-0000-000000000001','R12 Candidate',25,'Male','9876520002','Kadi','Mahesana','Gujarat','ITI','Fitter','Experienced','3 years','Yes',true);
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status)
values('54000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000001','52000000-0000-0000-0000-000000000001','direct','interested');

create temporary table r12_candidate_before as select * from public.candidates where id='53000000-0000-0000-0000-000000000001';
create temporary table r12_requirement_before as select * from public.employer_requirements where id='52000000-0000-0000-0000-000000000001';
grant select on r12_candidate_before, r12_requirement_before to authenticated;

set local role anon;
do $$
declare denied boolean := false;
begin
  begin perform 1 from public.candidate_applications limit 1; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous read Candidate applications'; end if;
  if has_function_privilege('anon','public.admin_update_candidate_application(uuid,text,text)','EXECUTE') then raise exception 'Anonymous can execute Admin RPC'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000002',true);
do $$
begin
  if exists(select 1 from public.candidate_applications) then raise exception 'Company read Candidate applications'; end if;
  begin
    perform public.admin_update_candidate_application('54000000-0000-0000-0000-000000000001','screening','forbidden');
    raise exception 'Company used Admin RPC';
  exception when raise_exception then
    if sqlerrm='Company used Admin RPC' then raise; end if;
  end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000003',true);
do $$ begin
  if exists(select 1 from public.candidate_applications) then raise exception 'Staffing Partner read Candidate applications'; end if;
  begin perform public.admin_update_candidate_application('54000000-0000-0000-0000-000000000001','screening',null); raise exception 'Partner used Admin RPC';
  exception when raise_exception then if sqlerrm='Partner used Admin RPC' then raise; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);
do $$
declare old_applied timestamptz; result boolean;
begin
  if not exists(select 1 from public.candidate_applications where id='54000000-0000-0000-0000-000000000001') then raise exception 'Admin could not read application'; end if;
  select applied_at into old_applied from public.candidate_applications where id='54000000-0000-0000-0000-000000000001';
  result := public.admin_update_candidate_application('54000000-0000-0000-0000-000000000001','screening','R12 internal Admin note');
  if not result or not exists(select 1 from public.candidate_applications where id='54000000-0000-0000-0000-000000000001' and application_status='screening' and admin_notes='R12 internal Admin note' and updated_at is not null and applied_at=old_applied) then raise exception 'Admin update failed'; end if;

  begin perform public.admin_update_candidate_application('54000000-0000-0000-0000-000000000001','not_a_status',null); raise exception 'Invalid status accepted';
  exception when raise_exception then if sqlerrm='Invalid status accepted' then raise; end if; end;
  begin perform public.admin_update_candidate_application('54000000-0000-0000-0000-999999999999','interested',null); raise exception 'Unknown application accepted';
  exception when raise_exception then if sqlerrm='Unknown application accepted' then raise; end if; end;
  begin perform public.admin_update_candidate_application('54000000-0000-0000-0000-000000000001','interested',repeat('x',4001)); raise exception 'Oversized note accepted';
  exception when raise_exception then if sqlerrm='Oversized note accepted' then raise; end if; end;
end $$;
reset role;

do $$
begin
  if exists(select 1 from public.candidates c full join r12_candidate_before b using(id) where row(c.*) is distinct from row(b.*)) then raise exception 'Candidate master changed'; end if;
  if exists(select 1 from public.employer_requirements r full join r12_requirement_before b using(id) where row(r.*) is distinct from row(b.*)) then raise exception 'Requirement changed'; end if;
  if not exists(select 1 from pg_constraint where conrelid='public.candidate_applications'::regclass and conname='candidate_applications_candidate_id_requirement_id_key') then raise exception 'Unique Candidate/requirement constraint changed'; end if;
  if not exists(select 1 from pg_trigger where tgrelid='public.candidate_applications'::regclass and tgname='candidate_applications_set_updated_at' and tgenabled<>'D') then raise exception 'Application updated_at trigger missing or disabled'; end if;
  if to_regprocedure('public.get_public_job_requirements(integer,integer)') is null or to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null then raise exception 'R10/R11 function regression'; end if;
  if exists(select 1 from information_schema.parameters where specific_schema='public' and specific_name like 'get_public_job_requirements_%' and parameter_name='admin_notes') then raise exception 'R10 exposes Admin notes'; end if;
  if has_function_privilege('anon','public.admin_update_candidate_application(uuid,text,text)','EXECUTE') or not has_function_privilege('authenticated','public.admin_update_candidate_application(uuid,text,text)','EXECUTE') then raise exception 'R12 grants incorrect'; end if;
end $$;

rollback;
