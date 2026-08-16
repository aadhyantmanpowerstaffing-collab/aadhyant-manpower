\set ON_ERROR_STOP on
begin;
create temporary table m8c_baseline as select count(*)::integer n from public.requirement_contractors;
grant select on m8c_baseline to authenticated;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('31000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-admin@test.local','x',now(),'{}','{}',now(),now()),
('31000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-company-a@test.local','x',now(),'{}','{}',now(),now()),
('31000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-company-b@test.local','x',now(),'{}','{}',now(),now()),
('31000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-contractor-a@test.local','x',now(),'{}','{"onboarding_type":"contractor","agency_name":"M8C Contractor A","contact_person":"Owner A","mobile":"9000000101","city":"Ahmedabad","state":"Gujarat","workforce_capacity":"100","operating_locations":["Gujarat"],"manpower_categories":["Industrial"],"consent":true}',now(),now()),
('31000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-contractor-b@test.local','x',now(),'{}','{"onboarding_type":"contractor","agency_name":"M8C Contractor B","contact_person":"Owner B","mobile":"9000000102","city":"Surat","state":"Gujarat","consent":true}',now(),now()),
('31000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-pending@test.local','x',now(),'{}','{"onboarding_type":"contractor","agency_name":"M8C Pending","contact_person":"Pending","mobile":"9000000103","city":"Kadi","state":"Gujarat","consent":true}',now(),now()),
('31000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-suspended@test.local','x',now(),'{}','{"onboarding_type":"contractor","agency_name":"M8C Suspended","contact_person":"Suspended","mobile":"9000000104","city":"Kadi","state":"Gujarat","consent":true}',now(),now()),
('31000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m8c-candidate@test.local','x',now(),'{}','{}',now(),now());

insert into public.admin_users(user_id) values('31000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('31000000-0000-0000-0000-000000000002','company','Company A','9000000201','m8c-company-a@test.local','active'),
('31000000-0000-0000-0000-000000000003','company','Company B','9000000202','m8c-company-b@test.local','active'),
('31000000-0000-0000-0000-000000000008','candidate','Candidate','9000000208','m8c-candidate@test.local','active');
insert into public.companies(id,legal_name,main_phone,main_email,city,state,verification_status,account_status) values
('32000000-0000-0000-0000-000000000001','M8C Company A','9000000201','m8c-company-a@test.local','Ahmedabad','Gujarat','verified','active'),
('32000000-0000-0000-0000-000000000002','M8C Company B','9000000202','m8c-company-b@test.local','Surat','Gujarat','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
('32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000002','owner','active'),
('32000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000003','owner','active');
update public.contractors set account_status='active',verification_status='verified' where main_email in ('m8c-contractor-a@test.local','m8c-contractor-b@test.local');
update public.platform_users set account_status='active' where email in ('m8c-contractor-a@test.local','m8c-contractor-b@test.local');
update public.contractor_users cu set status='active' from public.platform_users pu where pu.user_id=cu.user_id and pu.email in ('m8c-contractor-a@test.local','m8c-contractor-b@test.local');
update public.contractors set account_status='suspended' where main_email='m8c-suspended@test.local';
update public.platform_users set account_status='suspended' where email='m8c-suspended@test.local';
update public.contractor_users cu set status='suspended' from public.platform_users pu where pu.user_id=cu.user_id and pu.email='m8c-suspended@test.local';

do $$ begin if not exists(select 1 from public.platform_users pu join public.contractor_users cu on cu.user_id=pu.user_id join public.contractors c on c.id=cu.contractor_id where pu.email='m8c-pending@test.local' and pu.account_type='contractor' and pu.account_status='pending' and cu.role='owner' and cu.status='pending' and c.account_status='pending') then raise exception 'Contractor onboarding failed'; end if; end $$;

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,filled_positions,consent,status,company_id,created_by_user_id,department,job_location,requirement_stage,requirement_visibility)
values('33000000-0000-0000-0000-000000000001','M8C Company A','Company A','9000000201','Ahmedabad','Fitter',100,10,true,'in_progress','32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000002','Production','Ahmedabad','open','public'),
('33000000-0000-0000-0000-000000000002','M8C Company B','Company B','9000000202','Surat','Welder',50,0,true,'in_progress','32000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000003','Assembly','Surat','open','public'),
('33000000-0000-0000-0000-000000000003','M8C Company A','Company A','9000000201','Ahmedabad','Closed Role',10,0,true,'closed','32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000002','Production','Ahmedabad','closed','private');

set local role authenticated; select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
create temporary table assign_a as select * from public.assign_requirement_contractor('33000000-0000-0000-0000-000000000001',(select id from public.contractors where main_email='m8c-contractor-a@test.local'),40,'A target');
do $$ begin perform public.assign_requirement_contractor('33000000-0000-0000-0000-000000000001',(select id from public.contractors where main_email='m8c-pending@test.local'),10,null);raise exception 'Pending assignment succeeded';exception when others then if sqlerrm='Pending assignment succeeded' then raise;end if;end $$;
do $$ begin perform public.assign_requirement_contractor('33000000-0000-0000-0000-000000000001',(select id from public.contractors where main_email='m8c-suspended@test.local'),10,null);raise exception 'Suspended assignment succeeded';exception when others then if sqlerrm='Suspended assignment succeeded' then raise;end if;end $$;
do $$ begin perform public.assign_requirement_contractor('33000000-0000-0000-0000-000000000003',(select id from public.contractors where main_email='m8c-contractor-b@test.local'),10,null);raise exception 'Closed assignment succeeded';exception when others then if sqlerrm='Closed assignment succeeded' then raise;end if;end $$;
do $$ begin perform public.assign_requirement_contractor('33000000-0000-0000-0000-000000000001',(select id from public.contractors where main_email='m8c-contractor-b@test.local'),0,null);raise exception 'Zero assignment succeeded';exception when others then if sqlerrm='Zero assignment succeeded' then raise;end if;end $$;
do $$ begin perform public.assign_requirement_contractor('33000000-0000-0000-0000-000000000001',(select id from public.contractors where main_email='m8c-contractor-b@test.local'),51,null);raise exception 'Over allocation succeeded';exception when others then if sqlerrm='Over allocation succeeded' then raise;end if;end $$;
create temporary table assign_b as select * from public.assign_requirement_contractor('33000000-0000-0000-0000-000000000001',(select id from public.contractors where main_email='m8c-contractor-b@test.local'),30,'B target');

select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000004',true);
do $$ begin if (select count(*) from public.requirement_contractors)<>1 or (select count(*) from public.employer_requirements)<>1 then raise exception 'Contractor A read isolation failed';end if;end $$;
select public.respond_requirement_assignment((select id from assign_a),'accepted',null);
do $$ begin if not exists(select 1 from public.requirement_contractors where id=(select id from assign_a) and assignment_status='accepted' and accepted_at is not null) then raise exception 'Accept failed';end if;end $$;
update public.requirement_contractors set assigned_headcount=99,contractor_id=(select contractor_id from assign_b),requirement_id='33000000-0000-0000-0000-000000000002';
do $$ begin if exists(select 1 from public.requirement_contractors where id=(select id from assign_a) and assigned_headcount=99) then raise exception 'Protected update succeeded';end if;if has_table_privilege('authenticated','public.requirement_contractors','delete') then raise exception 'Delete privilege exists';end if;end $$;
do $$ begin perform public.respond_requirement_assignment((select id from assign_a),'declined','late');raise exception 'Invalid transition succeeded';exception when others then if sqlerrm='Invalid transition succeeded' then raise;end if;end $$;

select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000005',true);
do $$ begin perform public.respond_requirement_assignment((select id from assign_a),'declined','cross tenant');raise exception 'Cross response succeeded';exception when others then if sqlerrm='Cross response succeeded' then raise;end if;end $$;
select public.respond_requirement_assignment((select id from assign_b),'declined','capacity unavailable');
do $$ begin if not exists(select 1 from public.requirement_contractors where id=(select id from assign_b) and assignment_status='declined' and declined_at is not null) then raise exception 'Decline failed';end if;end $$;

select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
do $$ begin if (select count(*) from public.requirement_contractors)<>(select n+2 from m8c_baseline) then raise exception 'Admin assignment read failed';end if;end $$;
select public.set_requirement_assignment_status((select id from assign_a),'active');
select public.set_requirement_assignment_status((select id from assign_a),'completed');
do $$ begin if not exists(select 1 from public.requirement_contractors where id=(select id from assign_a) and assignment_status='completed' and closed_at is not null) then raise exception 'Admin lifecycle failed';end if;end $$;

select set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000004',true);
do $$ begin perform public.set_requirement_assignment_status((select id from assign_a),'cancelled');raise exception 'Non-admin lifecycle succeeded';exception when others then if sqlerrm='Non-admin lifecycle succeeded' then raise;end if;end $$;

reset role; set local role anon;
insert into public.employer_requirements(company_name,contact_person,mobile,company_location,job_role,required_headcount,consent) values('M8C Public','Public','9000000301','Kadi','Operator',2,true);
insert into public.candidates(full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,interview_available,consent) values('M8C Candidate',22,'Male','9000000302','Kadi','Mahesana','Gujarat','ITI','Fresher','Yes',true);

rollback;
\echo 'MILESTONE 8C DATABASE TESTS PASSED'
