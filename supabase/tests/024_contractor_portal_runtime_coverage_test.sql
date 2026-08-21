-- W5 focused runtime coverage. Synthetic fixtures only; every change rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('88000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-coverage-owner-a@test.local','x','{}','{}',now(),now()),
('88000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-coverage-owner-b@test.local','x','{}','{}',now(),now()),
('88000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-coverage-bootstrap@test.local','x','{}','{}',now(),now()),
('88000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-coverage-super@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('88000000-0000-0000-0000-000000000001','contractor','W5 Coverage Owner A','w5-coverage-owner-a@test.local','active'),
('88000000-0000-0000-0000-000000000002','contractor','W5 Coverage Owner B','w5-coverage-owner-b@test.local','active');
insert into public.contractors(id,agency_name,owner_name,main_phone,main_email,city,district,state,gstin,verification_status,account_status) values
('88000000-0000-0000-0001-000000000001','W5 Coverage Contractor A','Original Owner','9876500801','coverage-a@test.local','Chennai','Chennai','Tamil Nadu','33AAAAA0000A1Z5','verified','active'),
('88000000-0000-0000-0001-000000000002','W5 Coverage Contractor B','Tenant B Owner','9876500802','coverage-b@test.local','Pune','Pune','Maharashtra','27AAAAA0000A1Z5','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('88000000-0000-0000-0001-000000000001','88000000-0000-0000-0000-000000000001','owner','active'),
('88000000-0000-0000-0001-000000000002','88000000-0000-0000-0000-000000000002','owner','active');
insert into public.admin_users(user_id) values('88000000-0000-0000-0000-000000000006');
insert into public.staff_profiles(user_id,display_name,status) values('88000000-0000-0000-0000-000000000007','W5 Coverage Super Admin','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('88000000-0000-0000-0000-000000000007','super_admin','active','88000000-0000-0000-0000-000000000006');

set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-0000-0000-000000000001',true);
do $$
declare created record; profile_before record; profile_after record;
begin
  select * into profile_before from public.get_contractor_portal_profile();
  if profile_before.agency_name<>'W5 Coverage Contractor A' or not profile_before.can_update then raise exception 'Owner profile precondition failed';end if;
  if not public.update_contractor_portal_profile('Updated Synthetic Owner',profile_before.main_phone,'https://example.invalid',
    'Synthetic office',profile_before.city,profile_before.district,profile_before.state,'600001',array['Chennai'],250,array['Fitter']) then
    raise exception 'Owner profile update returned false';end if;
  select * into profile_after from public.get_contractor_portal_profile();
  if profile_after.owner_name<>'Updated Synthetic Owner' or profile_after.main_phone<>profile_before.main_phone
    or profile_after.agency_name<>profile_before.agency_name or profile_after.main_email<>profile_before.main_email then
    raise exception 'Owner profile persistence failed';end if;

  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Under Review Client',p_job_role=>'Fitter',p_job_location=>'Chennai',p_required_headcount=>2);
  perform set_config('w5.coverage_under_id',created.id::text,true);perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);
  begin perform public.review_contractor_vacancy(created.id,'start_review',null);raise exception 'Contractor started internal review';exception when raise_exception then if sqlerrm='Contractor started internal review' then raise;end if;end;

  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Rejected Client',p_job_role=>'Welder',p_job_location=>'Chennai',p_required_headcount=>3);
  perform set_config('w5.coverage_reject_id',created.id::text,true);perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);

  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Cancelled Client',p_job_role=>'Operator',p_job_location=>'Chennai',p_required_headcount=>4);
  perform set_config('w5.coverage_cancel_id',created.id::text,true);select * into created from public.manage_contractor_portal_vacancy(p_action=>'cancel',p_requirement_id=>created.id);
  if created.submission_status<>'cancelled' or created.requirement_stage<>'cancelled' then raise exception 'Allowed contractor cancellation failed';end if;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);raise exception 'Cancelled vacancy was resubmitted';exception when raise_exception then if sqlerrm='Cancelled vacancy was resubmitted' then raise;end if;end;

  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Closed Client',p_job_role=>'Assembler',p_job_location=>'Chennai',p_required_headcount=>5);
  perform set_config('w5.coverage_close_id',created.id::text,true);perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);

  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Metrics Client',p_job_role=>'Technician',p_job_location=>'Chennai',p_required_headcount=>10);
  perform set_config('w5.coverage_metrics_id',created.id::text,true);perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);
end $$;

select set_config('request.jwt.claim.sub','88000000-0000-0000-0000-000000000006',true);
do $$ declare reviewed record; rid uuid:=current_setting('w5.coverage_under_id')::uuid;begin
  select * into reviewed from public.review_contractor_vacancy(rid,'start_review',null);
  if reviewed.submission_status<>'under_review' then raise exception 'Bootstrap Admin start-review failed';end if;
  select * into reviewed from public.review_contractor_vacancy(rid,'approve','Bootstrap approved');
  if reviewed.submission_status<>'approved' or reviewed.requirement_stage<>'open' then raise exception 'Bootstrap Admin approval failed';end if;
end $$;

select set_config('request.jwt.claim.sub','88000000-0000-0000-0000-000000000007',true);
do $$ declare reviewed record; close_id uuid:=current_setting('w5.coverage_close_id')::uuid;begin
  select * into reviewed from public.review_contractor_vacancy(close_id,'start_review',null);
  if reviewed.submission_status<>'under_review' then raise exception 'Super Admin start-review failed';end if;
  select * into reviewed from public.review_contractor_vacancy(close_id,'approve','Super approved');
  if reviewed.submission_status<>'approved' then raise exception 'Super Admin approval failed';end if;
  select * into reviewed from public.review_contractor_vacancy(close_id,'close','Synthetic closure');
  if reviewed.submission_status<>'closed' or reviewed.requirement_stage<>'closed' or reviewed.requirement_visibility<>'private' then raise exception 'Super Admin close failed';end if;
  perform public.review_contractor_vacancy(current_setting('w5.coverage_reject_id')::uuid,'reject','Synthetic rejection');
  perform public.review_contractor_vacancy(current_setting('w5.coverage_metrics_id')::uuid,'approve','Metrics fixture approval');
end $$;

reset role;
do $$ begin
  if not exists(select 1 from public.requirement_contractors rc where rc.requirement_id=current_setting('w5.coverage_under_id')::uuid
    and rc.submission_status='approved' and rc.reviewed_by='88000000-0000-0000-0000-000000000006' and rc.reviewed_at is not null) then raise exception 'Bootstrap review attribution failed';end if;
  if not exists(select 1 from public.requirement_contractors rc where rc.requirement_id=current_setting('w5.coverage_reject_id')::uuid
    and rc.submission_status='rejected' and rc.reviewed_by='88000000-0000-0000-0000-000000000007' and rc.reviewed_at is not null) then raise exception 'Rejected lifecycle attribution failed';end if;
  if not exists(select 1 from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    where rc.requirement_id=current_setting('w5.coverage_close_id')::uuid and rc.submission_status='closed' and r.requirement_stage='closed' and r.requirement_visibility='private') then raise exception 'Closed canonical lifecycle failed';end if;
  if exists(select 1 from public.list_recruitment_requirements(null,'open',100,0) r where r.id=current_setting('w5.coverage_close_id')::uuid) then raise exception 'Closed vacancy remained recruitment-ready';end if;
  if not exists(select 1 from public.contractors c where c.id='88000000-0000-0000-0001-000000000001' and c.agency_name='W5 Coverage Contractor A'
    and c.main_email='coverage-a@test.local' and c.gstin='33AAAAA0000A1Z5' and c.verification_status='verified' and c.account_status='active') then
    raise exception 'Protected contractor profile fields changed';end if;
end $$;

insert into public.candidates(id,full_name,age,gender,mobile,whatsapp_number,current_location,district,state,highest_qualification,specialization,candidate_type,total_experience,interview_available,internal_notes,consent,status) values
('88000000-0000-0000-0002-000000000001','W5 Coverage Candidate One',25,'Female','9876500811','9876500811','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','2 years','Yes','Private note one',true,'new'),
('88000000-0000-0000-0002-000000000002','W5 Coverage Candidate Two',26,'Male','9876500812','9876500812','Chennai','Chennai','Tamil Nadu','Diploma','Mechanical','Experienced','3 years','Yes','Private note two',true,'new'),
('88000000-0000-0000-0002-000000000003','W5 Coverage Candidate Three',27,'Female','9876500813','9876500813','Chennai','Chennai','Tamil Nadu','ITI','Electrician','Experienced','4 years','Yes','Private note three',true,'new'),
('88000000-0000-0000-0002-000000000004','W5 Coverage Candidate Four',28,'Male','9876500814','9876500814','Chennai','Chennai','Tamil Nadu','Graduate','Science','Fresher','Fresher','Yes','Private note four',true,'new');
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by) values
('88000000-0000-0000-0003-000000000001','88000000-0000-0000-0002-000000000001',current_setting('w5.coverage_metrics_id')::uuid,'admin','selected','88000000-0000-0000-0000-000000000007'),
('88000000-0000-0000-0003-000000000002','88000000-0000-0000-0002-000000000002',current_setting('w5.coverage_metrics_id')::uuid,'admin','joining_pending','88000000-0000-0000-0000-000000000007'),
('88000000-0000-0000-0003-000000000003','88000000-0000-0000-0002-000000000003',current_setting('w5.coverage_metrics_id')::uuid,'admin','joined','88000000-0000-0000-0000-000000000007'),
('88000000-0000-0000-0003-000000000004','88000000-0000-0000-0002-000000000004',current_setting('w5.coverage_metrics_id')::uuid,'admin','screening','88000000-0000-0000-0000-000000000007');
insert into public.application_stage_history(id,application_id,from_stage,to_stage,actor_user_id,source,reason) values
('88000000-0000-0000-0006-000000000001','88000000-0000-0000-0003-000000000001','screening','selected','88000000-0000-0000-0000-000000000007','admin','Synthetic selected'),
('88000000-0000-0000-0006-000000000002','88000000-0000-0000-0003-000000000002','selected','joining_pending','88000000-0000-0000-0000-000000000007','admin','Synthetic joining pending'),
('88000000-0000-0000-0006-000000000003','88000000-0000-0000-0003-000000000003','joining_pending','joined','88000000-0000-0000-0000-000000000007','admin','Synthetic joined');
insert into public.interviews(id,application_id,interview_round,scheduled_at,mode,location,status,result,internal_notes,created_by) values
('88000000-0000-0000-0004-000000000001','88000000-0000-0000-0003-000000000001',1,now()+interval '1 day','onsite','Chennai','completed','selected','Private interview note','88000000-0000-0000-0000-000000000007'),
('88000000-0000-0000-0004-000000000002','88000000-0000-0000-0003-000000000001',2,now()+interval '2 days','video','Chennai','scheduled','pending','Private interview note','88000000-0000-0000-0000-000000000007'),
('88000000-0000-0000-0004-000000000003','88000000-0000-0000-0003-000000000002',1,now()+interval '3 days','onsite','Chennai','scheduled','pending','Private interview note','88000000-0000-0000-0000-000000000007');
insert into public.candidate_joinings(id,application_id,expected_joining_date,actual_joining_date,joining_status,internal_notes,created_by) values
('88000000-0000-0000-0005-000000000001','88000000-0000-0000-0003-000000000002',current_date+7,null,'confirmed','Private joining note','88000000-0000-0000-0000-000000000007'),
('88000000-0000-0000-0005-000000000002','88000000-0000-0000-0003-000000000003',current_date-2,current_date-1,'joined','Private joining note','88000000-0000-0000-0000-000000000007');

set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-0000-0000-000000000002',true);
do $$ declare profile record;begin
  select * into profile from public.get_contractor_portal_profile();if profile.agency_name<>'W5 Coverage Contractor B' then raise exception 'Contractor B profile isolation failed';end if;
  if (select count(*) from public.list_contractor_portal_applications())<>0 then raise exception 'Contractor B saw Contractor A applications';end if;
  if (select count(*) from public.list_contractor_portal_interviews())<>0 then raise exception 'Contractor B saw Contractor A interviews';end if;
  if (select count(*) from public.list_contractor_portal_joinings())<>0 then raise exception 'Contractor B saw Contractor A joinings';end if;
  begin perform public.get_contractor_portal_application('88000000-0000-0000-0003-000000000001');raise exception 'Contractor B read Contractor A application';exception when raise_exception then if sqlerrm='Contractor B read Contractor A application' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','88000000-0000-0000-0000-000000000001',true);
do $$ declare metrics record; detail jsonb;begin
  select * into metrics from public.get_contractor_dashboard_metrics();
  if metrics.total_openings<>12 or metrics.applications<>4 or metrics.interviews<>3 or metrics.selected<>1 or metrics.joining_pending<>1 or metrics.joined<>1 then
    raise exception 'Contractor dashboard distinct aggregate failed: %',row_to_json(metrics);end if;
  detail:=public.get_contractor_portal_application('88000000-0000-0000-0003-000000000001');
  if detail?'mobile' or detail?'whatsapp_number' or detail?'candidate_id' or detail?'auth_user_id' or detail?'internal_notes' or detail?'recruiter_notes' then
    raise exception 'Focused contractor privacy projection failed';end if;
  if (select count(*) from public.list_contractor_portal_applications())<>4 or (select count(*) from public.list_contractor_portal_interviews())<>3
    or (select count(*) from public.list_contractor_portal_joinings())<>2 then raise exception 'Focused contractor progress projection failed';end if;
  begin perform public.schedule_recruitment_interview('88000000-0000-0000-0003-000000000004',now()+interval '5 days','onsite','Chennai',null,null);raise exception 'Contractor scheduled interview';exception when raise_exception then if sqlerrm='Contractor scheduled interview' then raise;end if;end;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'cancel',p_requirement_id=>current_setting('w5.coverage_metrics_id')::uuid);raise exception 'Approved vacancy was cancelled by contractor';exception when raise_exception then if sqlerrm='Approved vacancy was cancelled by contractor' then raise;end if;end;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'update',p_requirement_id=>current_setting('w5.coverage_reject_id')::uuid,p_client_name=>'Regression',p_job_role=>'Welder',p_job_location=>'Chennai',p_required_headcount=>1);raise exception 'Rejected vacancy was edited';exception when raise_exception then if sqlerrm='Rejected vacancy was edited' then raise;end if;end;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'update',p_requirement_id=>current_setting('w5.coverage_close_id')::uuid,p_client_name=>'Regression',p_job_role=>'Assembler',p_job_location=>'Chennai',p_required_headcount=>1);raise exception 'Closed vacancy was edited';exception when raise_exception then if sqlerrm='Closed vacancy was edited' then raise;end if;end;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform public.review_contractor_vacancy(current_setting('w5.coverage_metrics_id')::uuid,'close',null);raise exception 'Anonymous reviewed contractor vacancy';
  exception when insufficient_privilege then null;when raise_exception then if sqlerrm='Anonymous reviewed contractor vacancy' then raise;end if;end;
end $$;

reset role;
select set_config('request.jwt.claim.sub','',true);
rollback;
