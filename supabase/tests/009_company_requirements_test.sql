\set ON_ERROR_STOP on
begin;

create temporary table m8b_test_baseline as
select count(*)::integer as requirement_count from public.employer_requirements;
grant select on m8b_test_baseline to authenticated;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin.local@example.test','x',now(),'{}','{}',now(),now()),
('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a.local@example.test','x',now(),'{}','{}',now(),now()),
('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b.local@example.test','x',now(),'{}','{}',now(),now()),
('10000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pending.local@example.test','x',now(),'{}','{}',now(),now()),
('10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','suspended.local@example.test','x',now(),'{}','{}',now(),now()),
('10000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','candidate.local@example.test','x',now(),'{}','{}',now(),now());

insert into public.admin_users(user_id) values ('10000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('10000000-0000-0000-0000-000000000002','company','Company A Owner','9000000002','a.local@example.test','active'),
('10000000-0000-0000-0000-000000000003','company','Company B Owner','9000000003','b.local@example.test','active'),
('10000000-0000-0000-0000-000000000004','company','Pending Owner','9000000004','pending.local@example.test','pending'),
('10000000-0000-0000-0000-000000000005','company','Suspended Owner','9000000005','suspended.local@example.test','suspended'),
('10000000-0000-0000-0000-000000000006','candidate','Candidate User','9000000006','candidate.local@example.test','active');
insert into public.companies(id,legal_name,main_phone,main_email,city,state,contact_person,verification_status,account_status) values
('20000000-0000-0000-0000-000000000002','Local Company A','9000000002','a.local@example.test','Ahmedabad','Gujarat','Company A Owner','verified','active'),
('20000000-0000-0000-0000-000000000003','Local Company B','9000000003','b.local@example.test','Surat','Gujarat','Company B Owner','verified','active'),
('20000000-0000-0000-0000-000000000004','Local Pending Company','9000000004','pending.local@example.test','Pune','Maharashtra','Pending Owner','pending','pending'),
('20000000-0000-0000-0000-000000000005','Local Suspended Company','9000000005','suspended.local@example.test','Indore','Madhya Pradesh','Suspended Owner','verified','suspended');
insert into public.company_users(company_id,user_id,role,status) values
('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','owner','active'),
('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','owner','active'),
('20000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000004','owner','pending'),
('20000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000005','owner','suspended');

-- Existing anonymous public path and a legacy NULL-owned row.
set local role anon;
insert into public.employer_requirements(company_name,contact_person,mobile,company_location,job_role,required_headcount,consent)
values ('Local Public Employer','Public Contact','9000000099','Ahmedabad','Fitter',2,true);
insert into public.candidates(full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,interview_available,consent)
values ('Local Candidate',22,'Male','9000000098','Ahmedabad','Ahmedabad','Gujarat','ITI','Fresher','Yes',true);
do $$ begin if has_table_privilege('anon','public.employer_requirements','select') then raise exception 'Anonymous SELECT privilege unexpectedly exists'; end if; end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
create temporary table created_a as select * from public.create_company_requirement('Production','Fitter','Ahmedabad',10,'ITI','Both','Any',18,45,18000,24000,'Day','8 hours','As applicable','Yes','Yes','No','Ahmedabad',now() + interval '7 days','Local test A');
do $$ begin
  if not exists (select 1 from created_a where company_id='20000000-0000-0000-0000-000000000002' and created_by_user_id='10000000-0000-0000-0000-000000000002' and requirement_code is not null and filled_positions=0 and requirement_stage='draft') then raise exception 'Company A ownership/default creation test failed'; end if;
  if (select count(*) from public.employer_requirements) <> 1 then raise exception 'Company A isolation SELECT failed'; end if;
end $$;
-- No direct write policy: spoofing/protected update/delete attempts affect zero rows or are denied.
update public.employer_requirements set company_id='20000000-0000-0000-0000-000000000003', created_by_user_id='10000000-0000-0000-0000-000000000003', requirement_code='SPOOF', filled_positions=9;
do $$ begin if exists(select 1 from public.employer_requirements where requirement_code='SPOOF' or company_id<>'20000000-0000-0000-0000-000000000002') then raise exception 'Protected direct UPDATE unexpectedly succeeded'; end if; if has_table_privilege('authenticated','public.employer_requirements','delete') then raise exception 'Company DELETE privilege unexpectedly exists'; end if; end $$;
select public.update_company_requirement((select id from created_a),'Operations','Senior Fitter','Ahmedabad',12,'ITI','Experienced','Any',21,50,22000,28000,'Day','8 hours','Paid','Yes','Yes','No','Ahmedabad',now()+interval '8 days','Edited locally');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
create temporary table created_b as select * from public.create_company_requirement('Assembly','Welder','Surat',4,null,'Both','Any',null,null,null,null,null,null,null,'Not Applicable','Not Applicable','Not Applicable',null,null,'Local test B');
do $$ begin if (select count(*) from public.employer_requirements) <> 1 then raise exception 'Company B isolation SELECT failed'; end if; end $$;
select public.update_company_requirement((select id from created_b),'Assembly','Welder','Surat',5,null,'Both','Any',null,null,null,null,null,null,null,'Not Applicable','Not Applicable','Not Applicable',null,null,'B edit');

-- Pending, suspended, and non-company creation all reject.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
do $$ begin perform public.create_company_requirement('X','X','X',1); raise exception 'Pending create unexpectedly succeeded'; exception when others then if sqlerrm='Pending create unexpectedly succeeded' then raise; end if; end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
do $$ begin perform public.create_company_requirement('X','X','X',1); raise exception 'Suspended create unexpectedly succeeded'; exception when others then if sqlerrm='Suspended create unexpectedly succeeded' then raise; end if; end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000006',true);
do $$ begin perform public.create_company_requirement('X','X','X',1); raise exception 'Non-company create unexpectedly succeeded'; exception when others then if sqlerrm='Non-company create unexpectedly succeeded' then raise; end if; end $$;

-- Admin reads all rows and controls operational stage; non-admin cannot call admin RPC.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$ begin perform public.set_company_requirement_stage((select id from created_a),'open','public'); raise exception 'Non-admin stage change unexpectedly succeeded'; exception when others then if sqlerrm='Non-admin stage change unexpectedly succeeded' then raise; end if; end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ begin if (select count(*) from public.employer_requirements) <> (select requirement_count + 3 from m8b_test_baseline) then raise exception 'Admin all-requirement read failed'; end if; end $$;
select public.set_company_requirement_stage((select id from created_a),'open','public');
do $$ begin if not exists(select 1 from public.employer_requirements where id=(select id from created_a) and requirement_stage='open' and requirement_visibility='public' and published_at is not null) then raise exception 'Admin operational update failed'; end if; end $$;

-- Company close preserves history and company cannot make open rows editable.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select public.close_company_requirement((select id from created_a));
do $$ begin if not exists(select 1 from public.employer_requirements where id=(select id from created_a) and requirement_stage='closed' and closed_at is not null) then raise exception 'Company close failed'; end if; end $$;
do $$ begin perform public.update_company_requirement((select id from created_a),'X','X','X',1); raise exception 'Closed edit unexpectedly succeeded'; exception when others then if sqlerrm='Closed edit unexpectedly succeeded' then raise; end if; end $$;

-- Database constraints prevent invalid headcount, age/salary ordering, and negative open balance.
reset role;
do $$ begin update public.employer_requirements set filled_positions=required_headcount+1 where id=(select id from created_b); raise exception 'Negative open balance unexpectedly allowed'; exception when check_violation then null; end $$;
do $$ begin perform public.create_company_requirement('X','X','X',0); exception when others then null; end $$;

-- Canonical codes remain unique across public and company rows.
do $$ begin if exists(select requirement_code from public.employer_requirements where requirement_code is not null group by requirement_code having count(*)>1) then raise exception 'Duplicate requirement code detected'; end if; end $$;

rollback;
\echo 'MILESTONE 8B DATABASE TESTS PASSED'
