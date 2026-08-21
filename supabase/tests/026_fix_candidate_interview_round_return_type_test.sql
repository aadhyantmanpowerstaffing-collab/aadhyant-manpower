-- W6 focused checkpoint for the Candidate interview-round projection fix.
-- Synthetic and rollback-scoped.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89100000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-round-candidate-a@test.local','x','{}','{}',now(),now()),
('89100000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-round-candidate-b@test.local','x','{}','{}',now(),now()),
('89100000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-round-company@test.local','x','{}','{}',now(),now()),
('89100000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-round-contractor@test.local','x','{}','{}',now(),now()),
('89100000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-round-non-member@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('89100000-0000-0000-0000-000000000001','candidate','W6 Round Candidate A','9876500911','w6-round-candidate-a@test.local','active'),
('89100000-0000-0000-0000-000000000002','candidate','W6 Round Candidate B','9876500912','w6-round-candidate-b@test.local','active'),
('89100000-0000-0000-0000-000000000003','company','W6 Round Company',null,'w6-round-company@test.local','active'),
('89100000-0000-0000-0000-000000000004','contractor','W6 Round Contractor',null,'w6-round-contractor@test.local','active');

insert into public.contractors(id,agency_name,verification_status,account_status) values
('89100000-0000-0000-0005-000000000001','W6 Round Synthetic Contractor','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('89100000-0000-0000-0005-000000000001','89100000-0000-0000-0000-000000000004','owner','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,
  candidate_type,total_experience,interview_available,consent,status,user_id,profile_status,profile_completion_status,
  availability_status,aadhaar_fingerprint,aadhaar_last4,date_of_birth,pincode)
values
('89100000-0000-0000-0001-000000000001','W6 Round Candidate A',25,'Female','9876500911','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','3 years','Yes',true,'new','89100000-0000-0000-0000-000000000001','active','complete','open_to_opportunities',repeat('d',64),'1111','2001-01-01','600001'),
('89100000-0000-0000-0001-000000000002','W6 Round Candidate B',26,'Male','9876500912','Pune','Pune','Maharashtra','Diploma','Mechanical','Experienced','4 years','Yes',true,'new','89100000-0000-0000-0000-000000000002','active','complete','open_to_opportunities',repeat('e',64),'2222','2000-01-01','411001');

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,consent,status,requirement_code,job_location,filled_positions,requirement_visibility,requirement_stage,published_at)
values('89100000-0000-0000-0002-000000000001','W6 Round Employer','Synthetic Contact','9876500913','Chennai','Fitter',3,'ITI',true,'in_progress','AAD-2096-000026','Chennai',0,'public','open',now());

insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by,source_reference)
values('89100000-0000-0000-0003-000000000001','89100000-0000-0000-0001-000000000001','89100000-0000-0000-0002-000000000001','direct','interview','89100000-0000-0000-0000-000000000001','w6_round_checkpoint');
insert into public.interviews(id,application_id,interview_round,scheduled_at,mode,location,status,result,created_by)
values('89100000-0000-0000-0004-000000000001','89100000-0000-0000-0003-000000000001',2,now()+interval '2 days','onsite','Chennai','scheduled','pending','89100000-0000-0000-0000-000000000001');

do $$ begin
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='list_candidate_portal_interviews'
      and pg_get_function_identity_arguments(p.oid)='p_limit integer, p_offset integer'
      and p.prosecdef and p.provolatile='s'
      and exists(select 1 from unnest(p.proconfig)c where split_part(c,'=',1)='search_path' and btrim(split_part(c,'=',2),'"')='')) then
    raise exception 'Corrected Candidate interview RPC posture failed'; end if;
  if has_function_privilege('anon','public.list_candidate_portal_interviews(integer,integer)','execute') then
    raise exception 'Anonymous Candidate interview execution was granted'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','89100000-0000-0000-0000-000000000001',true);
do $$ declare projected record; begin
  select * into projected from public.list_candidate_portal_interviews();
  if projected.requirement_code<>'AAD-2096-000026' or projected.job_role<>'Fitter'
     or projected.interview_round<>'2' or projected.mode<>'onsite' or projected.location<>'Chennai'
     or projected.status<>'scheduled' or projected.result<>'pending' then
    raise exception 'Candidate interview text projection failed'; end if;
  if (select i.interview_round from public.interviews i where i.id='89100000-0000-0000-0004-000000000001') is not null then
    raise exception 'Candidate bypassed interview base-table RLS'; end if;
end $$;

select set_config('request.jwt.claim.sub','89100000-0000-0000-0000-000000000002',true);
do $$ begin
  if exists(select 1 from public.list_candidate_portal_interviews()) then raise exception 'Candidate B accessed Candidate A interview'; end if;
end $$;

select set_config('request.jwt.claim.sub','89100000-0000-0000-0000-000000000003',true);
do $$ begin
  begin perform public.list_candidate_portal_interviews();raise exception 'Company accessed Candidate interviews';exception when raise_exception then if sqlerrm='Company accessed Candidate interviews' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89100000-0000-0000-0000-000000000004',true);
do $$ begin
  begin perform public.list_candidate_portal_interviews();raise exception 'Contractor accessed Candidate interviews';exception when raise_exception then if sqlerrm='Contractor accessed Candidate interviews' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89100000-0000-0000-0000-000000000005',true);
do $$ begin
  begin perform public.list_candidate_portal_interviews();raise exception 'Non-member accessed Candidate interviews';exception when raise_exception then if sqlerrm='Non-member accessed Candidate interviews' then raise;end if;end;
end $$;

reset role;
set local role anon;
do $$ begin
  begin perform public.list_candidate_portal_interviews();raise exception 'Anonymous accessed Candidate interviews';exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Anonymous accessed Candidate interviews' then raise;end if;end;
end $$;
reset role;

do $$ begin
  if (select i.interview_round from public.interviews i where i.id='89100000-0000-0000-0004-000000000001')<>2
     or (select i.status from public.interviews i where i.id='89100000-0000-0000-0004-000000000001')<>'scheduled' then
    raise exception 'Read-only Candidate interview RPC mutated canonical state'; end if;
end $$;

rollback;
