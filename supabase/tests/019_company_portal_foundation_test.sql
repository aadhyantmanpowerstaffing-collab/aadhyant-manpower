\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('83000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-company-a@test.local','x','{}','{}',now(),now()),
('83000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-company-b@test.local','x','{}','{}',now(),now()),
('83000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-company-viewer@test.local','x','{}','{}',now(),now()),
('83000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-company-inactive@test.local','x','{}','{}',now(),now()),
('83000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-contractor@test.local','x','{}','{}',now(),now()),
('83000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-recruiter@test.local','x','{}','{}',now(),now()),
('83000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w4-nonmember@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('83000000-0000-0000-0000-000000000001','company','Company A HR','w4-company-a@test.local','active'),
('83000000-0000-0000-0000-000000000002','company','Company B HR','w4-company-b@test.local','active'),
('83000000-0000-0000-0000-000000000003','company','Company A Viewer','w4-company-viewer@test.local','active'),
('83000000-0000-0000-0000-000000000004','company','Inactive HR','w4-company-inactive@test.local','active'),
('83000000-0000-0000-0000-000000000005','contractor','Contractor User','w4-contractor@test.local','active');

insert into public.companies(id,legal_name,industry,main_phone,main_email,city,state,contact_person,verification_status,account_status) values
('83000000-0000-0000-0001-000000000001','W4 Company A','Manufacturing','9876543210','company-a@test.local','Chennai','Tamil Nadu','Company A HR','verified','active'),
('83000000-0000-0000-0001-000000000002','W4 Company B','Logistics','9876543211','company-b@test.local','Pune','Maharashtra','Company B HR','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
('83000000-0000-0000-0001-000000000001','83000000-0000-0000-0000-000000000001','hr_admin','active'),
('83000000-0000-0000-0001-000000000002','83000000-0000-0000-0000-000000000002','owner','active'),
('83000000-0000-0000-0001-000000000001','83000000-0000-0000-0000-000000000003','viewer','active'),
('83000000-0000-0000-0001-000000000001','83000000-0000-0000-0000-000000000004','recruiter','suspended');
insert into public.contractors(id,agency_name,verification_status,account_status) values
('83000000-0000-0000-0002-000000000001','W4 Contractor','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('83000000-0000-0000-0002-000000000001','83000000-0000-0000-0000-000000000005','manager','active');
insert into public.staff_profiles(user_id,display_name,status) values('83000000-0000-0000-0000-000000000006','W4 Recruiter','active');
insert into public.staff_roles(user_id,role,status,granted_by) values('83000000-0000-0000-0000-000000000006','recruiter','active',null);

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,consent,status,requirement_code,company_id,created_by_user_id,department,job_location,filled_positions,
  requirement_visibility,requirement_stage)
values
('83000000-0000-0000-0003-000000000001','W4 Company A','Company A HR','9876543210','Chennai','Fitter',5,'ITI',true,'in_progress','W4-A-001','83000000-0000-0000-0001-000000000001','83000000-0000-0000-0000-000000000001','Production','Chennai',0,'private','open'),
('83000000-0000-0000-0003-000000000002','W4 Company B','Company B HR','9876543211','Pune','Operator',3,'12th',true,'in_progress','W4-B-001','83000000-0000-0000-0001-000000000002','83000000-0000-0000-0000-000000000002','Operations','Pune',0,'private','open');
insert into public.candidates(id,full_name,age,gender,mobile,whatsapp_number,current_location,district,state,highest_qualification,specialization,
  candidate_type,total_experience,interview_available,internal_notes,consent,status)
values
('83000000-0000-0000-0004-000000000001','W4 Candidate A',28,'Male','9876500001','9876500001','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','2 years','Yes','Internal secret A',true,'active'),
('83000000-0000-0000-0004-000000000002','W4 Candidate B',26,'Female','9876500002','9876500002','Pune','Pune','Maharashtra','12th','Operator','Fresher',null,'Yes','Internal secret B',true,'active'),
('83000000-0000-0000-0004-000000000003','W4 Candidate A2',31,'Other / Prefer not to say','9876500003','9876500003','Chennai','Chennai','Tamil Nadu','Diploma','Quality','Experienced','1 year','Yes','Internal secret A2',true,'active');
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by) values
('83000000-0000-0000-0005-000000000001','83000000-0000-0000-0004-000000000001','83000000-0000-0000-0003-000000000001','admin','selected','83000000-0000-0000-0000-000000000006'),
('83000000-0000-0000-0005-000000000002','83000000-0000-0000-0004-000000000002','83000000-0000-0000-0003-000000000002','admin','interview','83000000-0000-0000-0000-000000000006'),
('83000000-0000-0000-0005-000000000003','83000000-0000-0000-0004-000000000003','83000000-0000-0000-0003-000000000001','admin','screening','83000000-0000-0000-0000-000000000006');
insert into public.interviews(id,application_id,interview_round,scheduled_at,mode,location,status,created_by) values
('83000000-0000-0000-0006-000000000001','83000000-0000-0000-0005-000000000001',1,now()+interval '2 days','onsite','Chennai','scheduled','83000000-0000-0000-0000-000000000006'),
('83000000-0000-0000-0006-000000000002','83000000-0000-0000-0005-000000000002',1,now()+interval '3 days','video',null,'scheduled','83000000-0000-0000-0000-000000000006');
insert into public.candidate_joinings(id,application_id,expected_joining_date,joining_status,created_by) values
('83000000-0000-0000-0007-000000000001','83000000-0000-0000-0005-000000000001',current_date+7,'confirmed','83000000-0000-0000-0000-000000000006');

do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname in ('private','public') and p.proname in (
        'current_company_portal_id','can_manage_company_portal','can_administer_company_profile','get_company_portal_context',
        'get_company_dashboard_metrics','get_company_profile','update_company_profile','list_company_portal_requirements',
        'get_company_portal_requirement','manage_company_portal_requirement','list_company_portal_applications',
        'get_company_portal_application','list_company_portal_interviews','list_company_portal_joinings')
      and p.prosecdef and exists(select 1 from unnest(p.proconfig) c where split_part(c,'=',1)='search_path'
        and btrim(split_part(c,'=',2),'"')=''))<>14 then raise exception 'W4 function security configuration failed'; end if;
  if has_function_privilege('anon','public.get_company_portal_context()','EXECUTE')
     or has_function_privilege('authenticated','private.current_company_portal_id(boolean)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_company_requirements()','EXECUTE')
     or not has_function_privilege('authenticated','public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)','EXECUTE') then
    raise exception 'W4 execute boundary failed';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; metrics record; profile record; own_requirement jsonb; app jsonb; created record; begin
  select * into ctx from public.get_company_portal_context();
  if ctx.company_name<>'W4 Company A' or not ctx.can_manage_requirements or not ctx.can_update_profile then raise exception 'Company A context failed'; end if;
  select * into profile from public.get_company_profile();
  if profile.legal_name<>'W4 Company A' or not profile.can_update then raise exception 'Company A profile failed'; end if;
  select * into metrics from public.get_company_dashboard_metrics();
  if metrics.active_requirements<>1 or metrics.total_openings<>5 or metrics.applications<>2
     or metrics.screening<>1 or metrics.selected<>1 then raise exception 'Company A dashboard scope failed'; end if;
  if (select count(*) from public.list_company_portal_requirements())<>1
     or (select count(*) from public.list_company_portal_applications())<>2
     or (select count(*) from public.list_company_portal_interviews())<>1
     or (select count(*) from public.list_company_portal_joinings())<>1 then raise exception 'Company A projection scope failed'; end if;
  own_requirement:=public.get_company_portal_requirement('83000000-0000-0000-0003-000000000001');
  if own_requirement->>'requirement_code'<>'W4-A-001' then raise exception 'Company A requirement detail failed'; end if;
  app:=public.get_company_portal_application('83000000-0000-0000-0005-000000000001');
  if app ? 'mobile' or app ? 'whatsapp_number' or app ? 'internal_notes' or app::text like '%Internal secret%' then raise exception 'Company candidate PII leaked'; end if;
  begin perform public.get_company_portal_requirement('83000000-0000-0000-0003-000000000002');raise exception 'Cross-company requirement read succeeded';
  exception when raise_exception then if sqlerrm='Cross-company requirement read succeeded' then raise;end if;end;
  begin perform public.get_company_portal_application('83000000-0000-0000-0005-000000000002');raise exception 'Cross-company application read succeeded';
  exception when raise_exception then if sqlerrm='Cross-company application read succeeded' then raise;end if;end;
  begin perform public.list_recruitment_candidates();raise exception 'Company user accessed W3 Candidate Master';
  exception when raise_exception then if sqlerrm='Company user accessed W3 Candidate Master' then raise;end if;end;
  begin perform public.schedule_recruitment_interview('83000000-0000-0000-0005-000000000001',now()+interval '4 days','onsite');raise exception 'Company user scheduled an internal interview';
  exception when raise_exception then if sqlerrm='Company user scheduled an internal interview' then raise;end if;end;
  begin perform public.upsert_recruitment_joining('83000000-0000-0000-0005-000000000001',current_date+10,null,'pending');raise exception 'Company user mutated internal joining';
  exception when raise_exception then if sqlerrm='Company user mutated internal joining' then raise;end if;end;
  perform public.update_company_profile('W4 Trade','Manufacturing',null,'9876543210','Address','Chennai','Chennai','Tamil Nadu','600001','Company A HR','51-200');
  select * into created from public.manage_company_portal_requirement('create',null,'Quality','Inspector','Chennai',2,'Diploma','Both','Any',18,50,15000,22000,null,null,null,'Yes','Yes','No',null,null,'Synthetic test');
  if created.requirement_stage<>'draft' then raise exception 'Company requirement create lifecycle failed';end if;
  begin perform public.manage_company_portal_requirement('create',null,'Quality','Inspector','Chennai',2,'Diploma','Both','Any',15,50,15000,22000,null,null,null,'Yes','Yes','No',null,null,'Synthetic test');raise exception 'Invalid age criteria succeeded';
  exception when raise_exception then if sqlerrm='Invalid age criteria succeeded' then raise;end if;end;
  begin perform public.manage_company_portal_requirement('create',null,'Quality','Inspector','Chennai',2,'Diploma','Both','Any',18,50,-1,22000,null,null,null,'Yes','Yes','No',null,null,'Synthetic test');raise exception 'Negative salary succeeded';
  exception when raise_exception then if sqlerrm='Negative salary succeeded' then raise;end if;end;
  begin perform public.manage_company_portal_requirement('create',null,'Quality','Inspector','Chennai',2,repeat('Q',201),'Both','Any',18,50,15000,22000,null,null,null,'Yes','Yes','No',null,null,'Synthetic test');raise exception 'Oversized requirement field succeeded';
  exception when raise_exception then if sqlerrm='Oversized requirement field succeeded' then raise;end if;end;
  if exists(select 1 from public.employer_requirements) then raise exception 'Company direct requirement table read was not hidden';end if;
end $$;

select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000003',true);
do $$ declare ctx record; begin
  select * into ctx from public.get_company_portal_context();if ctx.can_manage_requirements or ctx.can_update_profile then raise exception 'Company viewer received mutation access';end if;
  if (select count(*) from public.list_company_portal_requirements())<>2 then raise exception 'Company viewer read failed';end if;
  begin perform public.manage_company_portal_requirement('close','83000000-0000-0000-0003-000000000001');raise exception 'Company viewer mutated requirement';
  exception when raise_exception then if sqlerrm='Company viewer mutated requirement' then raise;end if;end;
  begin perform public.manage_company_requirement('close','83000000-0000-0000-0003-000000000001');raise exception 'Company viewer bypassed W4 through legacy mutation';
  exception when raise_exception then if sqlerrm='Company viewer bypassed W4 through legacy mutation' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000002',true);
do $$ begin
  if (select count(*) from public.list_company_portal_requirements())<>1 then raise exception 'Company B own scope failed';end if;
  begin perform public.get_company_portal_requirement('83000000-0000-0000-0003-000000000001');raise exception 'Company B read Company A';
  exception when raise_exception then if sqlerrm='Company B read Company A' then raise;end if;end;
end $$;

do $$ declare actor text; begin
  foreach actor in array array['83000000-0000-0000-0000-000000000004','83000000-0000-0000-0000-000000000005',
    '83000000-0000-0000-0000-000000000006','83000000-0000-0000-0000-000000000007',''] loop
    perform set_config('request.jwt.claim.sub',actor,true);
    begin perform public.get_company_dashboard_metrics();raise exception 'Unauthorized Company Portal access succeeded for %',actor;
    exception when raise_exception then if sqlerrm like 'Unauthorized Company Portal access succeeded%' then raise;end if;end;
  end loop;
end $$;
reset role;

do $$
begin
  if to_regprocedure('public.get_recruitment_dashboard()') is null
     or to_regprocedure('public.list_internal_staff()') is null
     or to_regprocedure('public.get_public_job_requirements()') is null
     or to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null then
    raise exception 'W2/W3/public regression contract disappeared';
  end if;
end;
$$;

rollback;
