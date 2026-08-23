-- W6 Candidate Portal foundation checkpoint. Synthetic and rollback-scoped.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-candidate-a@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-candidate-b@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-company@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-admin@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-recruiter@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-onboarding@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-contractor@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-non-member@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-inactive@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-operations@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-super-admin@test.local','x','{}','{}',now(),now()),
('89000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-admin-role@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('89000000-0000-0000-0000-000000000001','candidate','W6 Candidate A','9876500901','w6-candidate-a@test.local','active'),
('89000000-0000-0000-0000-000000000002','candidate','W6 Candidate B','9876500902','w6-candidate-b@test.local','active'),
('89000000-0000-0000-0000-000000000003','company','W6 Company User',null,'w6-company@test.local','active'),
('89000000-0000-0000-0000-000000000007','contractor','W6 Contractor User',null,'w6-contractor@test.local','active'),
('89000000-0000-0000-0000-000000000009','candidate','W6 Inactive Candidate','9876500909','w6-inactive@test.local','active');
insert into public.admin_users(user_id) values('89000000-0000-0000-0000-000000000004');
insert into public.staff_profiles(user_id,display_name,status) values
('89000000-0000-0000-0000-000000000005','W6 Recruiter','active'),
('89000000-0000-0000-0000-000000000010','W6 Operations','active'),
('89000000-0000-0000-0000-000000000011','W6 Super Admin','active'),
('89000000-0000-0000-0000-000000000012','W6 Admin Role','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('89000000-0000-0000-0000-000000000005','recruiter','active','89000000-0000-0000-0000-000000000004'),
('89000000-0000-0000-0000-000000000010','operations','active','89000000-0000-0000-0000-000000000004'),
('89000000-0000-0000-0000-000000000011','super_admin','active','89000000-0000-0000-0000-000000000004'),
('89000000-0000-0000-0000-000000000012','admin','active','89000000-0000-0000-0000-000000000004');
insert into public.contractors(id,agency_name,verification_status,account_status) values
('89000000-0000-0000-0005-000000000001','W6 Synthetic Contractor','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('89000000-0000-0000-0005-000000000001','89000000-0000-0000-0000-000000000007','owner','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,
  candidate_type,total_experience,interview_available,consent,status,user_id,profile_status,profile_completion_status,
  availability_status,aadhaar_fingerprint,aadhaar_last4,date_of_birth,pincode)
values
('89000000-0000-0000-0001-000000000001','W6 Candidate A',25,'Female','9876500901','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','3 years','Yes',true,'new','89000000-0000-0000-0000-000000000001','active','complete','open_to_opportunities',repeat('a',64),'1111','2001-01-01','600001'),
('89000000-0000-0000-0001-000000000002','W6 Candidate B',26,'Male','9876500902','Pune','Pune','Maharashtra','Diploma','Mechanical','Experienced','4 years','Yes',true,'new','89000000-0000-0000-0000-000000000002','active','complete','open_to_opportunities',repeat('b',64),'2222','2000-01-01','411001'),
('89000000-0000-0000-0001-000000000009','W6 Inactive Candidate',27,'Female','9876500909','Delhi','Delhi','Delhi','Graduate','General','Fresher','0 years','No',true,'new','89000000-0000-0000-0000-000000000009','inactive','incomplete','not_available',repeat('c',64),'9999','1999-01-01','110001');
insert into public.candidate_preferences(candidate_id,preferred_locations,preferred_job_roles,source) values
('89000000-0000-0000-0001-000000000001',array['Chennai'],array['Fitter'],'candidate'),
('89000000-0000-0000-0001-000000000002',array['Pune'],array['Technician'],'candidate');

-- Registration/onboarding is exercised through the public RPC, including mandatory-field rejection.
set local role authenticated;
select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000006',true);
do $$ declare created_id uuid; ctx record; begin
  if not public.get_candidate_onboarding_eligibility() then raise exception 'Unlinked Auth user was not eligible for onboarding'; end if;
  begin perform public.create_candidate_portal_profile('Invalid Candidate','12345','1234','2000-01-01','Female','Chennai','Chennai','Tamil Nadu','600001','ITI','Fitter','Fresher',true);raise exception 'Invalid Mobile/Aadhaar was accepted';exception when raise_exception then if sqlerrm='Invalid Mobile/Aadhaar was accepted' then raise;end if;end;
  created_id:=public.create_candidate_portal_profile('W6 Onboarding Candidate','9876500906','444455556666','2000-01-01','Female','Chennai','Chennai','Tamil Nadu','600001','ITI','Fitter','Fresher',true);
  select * into ctx from public.get_candidate_portal_context();
  if ctx.candidate_id<>created_id or ctx.aadhaar_masked<>'XXXX XXXX 6666' or ctx.mobile_verified then raise exception 'Candidate onboarding linkage/masking/verification semantics failed'; end if;
  if public.get_candidate_onboarding_eligibility() then raise exception 'Linked Candidate remained onboarding-eligible'; end if;
end $$;
reset role;

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,consent,status,requirement_code,job_location,filled_positions,requirement_visibility,requirement_stage,published_at)
values
('89000000-0000-0000-0002-000000000001','W6 Open Employer','Synthetic Contact','9876500910','Chennai','Fitter',5,'ITI',true,'in_progress','AAD-2096-000001','Chennai',0,'public','open',now()),
('89000000-0000-0000-0002-000000000002','W6 Private Employer','Synthetic Contact','9876500911','Chennai','Private Role',5,'ITI',true,'new','AAD-2096-000002','Chennai',0,'private','draft',null),
('89000000-0000-0000-0002-000000000003','W6 Contractor Pending','Synthetic Contact','9876500912','Chennai','Pending Role',5,'ITI',true,'new','AAD-2096-000003','Chennai',0,'private','draft',null);
insert into public.requirement_contractors(id,requirement_id,contractor_id,assigned_headcount,assignment_status,origin_type,submission_status)
values('89000000-0000-0000-0006-000000000001','89000000-0000-0000-0002-000000000003','89000000-0000-0000-0005-000000000001',5,'assigned','contractor_submission','submitted');

insert into public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes,verification_status,active)
values('89000000-0000-0000-0003-000000000001','89000000-0000-0000-0001-000000000001','resume','89000000-0000-0000-0000-000000000001/89000000-0000-0000-0004-000000000001/resume.pdf','resume.pdf','application/pdf',1024,'uploaded',true);
insert into storage.objects(id,bucket_id,name,owner,metadata) values
('89000000-0000-0000-0007-000000000001','candidate-private','89000000-0000-0000-0000-000000000001/89000000-0000-0000-0004-000000000002/pan.pdf','89000000-0000-0000-0000-000000000001','{"mimetype":"application/pdf","size":2048}'::jsonb),
('89000000-0000-0000-0007-000000000002','candidate-private','89000000-0000-0000-0000-000000000001/89000000-0000-0000-0004-000000000003/pan.pdf','89000000-0000-0000-0000-000000000001','{"mimetype":"application/pdf","size":3072}'::jsonb);

do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('private','public') and p.proname in ('current_candidate_portal_id','can_verify_candidate_documents',
    'get_candidate_onboarding_eligibility','create_candidate_portal_profile','get_candidate_portal_context','get_candidate_portal_profile','update_candidate_portal_profile',
    'get_candidate_dashboard_metrics','list_candidate_job_opportunities','apply_candidate_job','list_candidate_portal_applications',
    'list_candidate_portal_interviews','list_candidate_portal_joinings','list_candidate_portal_documents','register_candidate_document',
    'get_candidate_document_access','get_candidate_joining_document_checklist','admin_list_candidate_documents',
    'get_candidate_onboarding_details','update_candidate_onboarding_details','admin_get_candidate_document_access','admin_review_candidate_document','admin_set_candidate_documentation_override')
    and p.prosecdef and exists(select 1 from unnest(p.proconfig)c where split_part(c,'=',1)='search_path' and btrim(split_part(c,'=',2),'"')=''))<>23 then
    raise exception 'W6 SECURITY DEFINER/search_path posture failed'; end if;
  if has_function_privilege('anon','public.get_candidate_portal_context()','execute')
     or has_function_privilege('anon','public.admin_review_candidate_document(uuid,text,text)','execute')
     or has_function_privilege('authenticated','private.current_candidate_portal_id()','execute')
     or has_function_privilege('authenticated','private.can_verify_candidate_documents()','execute') then raise exception 'W6 execute boundary failed'; end if;
  if (select b.public from storage.buckets b where b.id='candidate-private') then raise exception 'Candidate document bucket is public'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; profile record; onboarding record; app uuid; first_doc uuid; replacement_doc uuid; begin
  select * into ctx from public.get_candidate_portal_context();
  if ctx.candidate_id<>'89000000-0000-0000-0001-000000000001' or ctx.aadhaar_masked<>'XXXX XXXX 1111' then raise exception 'Candidate A context/masking failed'; end if;
  select * into profile from public.get_candidate_portal_profile();
  if profile.mobile<>'9876500901' or profile.aadhaar_masked<>'XXXX XXXX 1111' then raise exception 'Candidate A profile failed'; end if;
  if not public.update_candidate_portal_profile('W6 Candidate A Updated','9876500901','111122223333','2001-01-01','Female','Chennai','Chennai','Tamil Nadu','600001','ITI','Fitter','Experienced','3 years','Fitter','Yes',array['Chennai','Sriperumbudur'],array['Fitter'],18000,26000,'day',true,current_date+7) then raise exception 'Candidate profile update failed'; end if;
  select * into profile from public.get_candidate_portal_profile();
  if profile.full_name<>'W6 Candidate A Updated' or profile.aadhaar_masked<>'XXXX XXXX 3333' or profile.preferred_locations<>array['Chennai','Sriperumbudur'] then raise exception 'Candidate profile/preferences persistence failed'; end if;
  if not public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',true,'123456789012',true,'1234567890') then raise exception 'Joining onboarding update failed'; end if;
  select * into onboarding from public.get_candidate_onboarding_details();
  if onboarding.bank_account_masked<>'XXXX XXXX 9012' or onboarding.uan_masked<>'XXXXXXXX9012' or onboarding.esic_ip_masked not like '%7890' then raise exception 'Bank/PF/ESIC masking failed'; end if;
  first_doc:=public.register_candidate_document('pan','89000000-0000-0000-0000-000000000001/89000000-0000-0000-0004-000000000002/pan.pdf','pan.pdf','application/pdf',2048);
  replacement_doc:=public.register_candidate_document('pan','89000000-0000-0000-0000-000000000001/89000000-0000-0000-0004-000000000003/pan.pdf','pan-updated.pdf','application/pdf',3072);
  perform set_config('w6.replacement_document_id',replacement_doc::text,true);
  if first_doc=replacement_doc or exists(select 1 from public.list_candidate_portal_documents() d where d.document_id=first_doc) or not exists(select 1 from public.get_candidate_document_access(replacement_doc)) then raise exception 'Document replacement/access contract failed'; end if;
  if (select count(*) from public.list_candidate_job_opportunities(null,25,0))<>1 then raise exception 'Recruitment-ready opportunity filter failed'; end if;
  app:=public.apply_candidate_job('AAD-2096-000001');perform set_config('w6.application_id',app::text,true);
  begin perform public.apply_candidate_job('AAD-2096-000001');raise exception 'Duplicate application was accepted';exception when raise_exception then if sqlerrm='Duplicate application was accepted' then raise;end if;end;
  if (select count(*) from public.list_candidate_portal_applications())<>1 then raise exception 'Own application projection failed'; end if;
  if (select count(*) from public.list_candidate_portal_documents())<>2 then raise exception 'Own document projection failed'; end if;
  if (select count(*) from public.get_candidate_joining_document_checklist())<9 then raise exception 'Joining checklist projection failed'; end if;
  if exists(select 1 from public.candidates c where c.id='89000000-0000-0000-0001-000000000001') then raise exception 'Candidate bypassed base-table RLS'; end if;
  begin perform public.apply_candidate_job('AAD-2096-000002');raise exception 'Candidate applied to private Draft';exception when raise_exception then if sqlerrm='Candidate applied to private Draft' then raise;end if;end;
  begin perform public.admin_review_candidate_document('89000000-0000-0000-0003-000000000001','verified',null);raise exception 'Candidate verified own document';exception when raise_exception then if sqlerrm='Candidate verified own document' then raise;end if;end;
  begin perform public.list_recruitment_candidates();raise exception 'Candidate accessed Candidate Master';exception when raise_exception then if sqlerrm='Candidate accessed Candidate Master' then raise;end if;end;
  begin perform public.get_company_portal_context();raise exception 'Candidate accessed Company Portal';exception when raise_exception then if sqlerrm='Candidate accessed Company Portal' then raise;end if;end;
  begin perform public.get_contractor_portal_context();raise exception 'Candidate accessed Contractor Portal';exception when raise_exception then if sqlerrm='Candidate accessed Contractor Portal' then raise;end if;end;
end $$;

reset role;
insert into public.interviews(id,application_id,interview_round,scheduled_at,mode,location,status,result,created_by) values
('89000000-0000-0000-0008-000000000001',current_setting('w6.application_id')::uuid,1,now()+interval '2 days','onsite','Chennai','scheduled',null,'89000000-0000-0000-0000-000000000004');
insert into public.candidate_joinings(id,application_id,expected_joining_date,joining_status,created_by) values
('89000000-0000-0000-0009-000000000001',current_setting('w6.application_id')::uuid,current_date+10,'confirmed','89000000-0000-0000-0000-000000000004');
set local role authenticated;
select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000001',true);
do $$ begin
  if (select count(*) from public.list_candidate_portal_interviews())<>1 then raise exception 'Own interview projection failed'; end if;
  if (select count(*) from public.list_candidate_portal_joinings())<>1 then raise exception 'Own joining projection failed'; end if;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000002',true);
do $$ begin
  if (select count(*) from public.list_candidate_portal_applications())<>0
     or (select count(*) from public.list_candidate_portal_documents())<>0
     or (select count(*) from public.list_candidate_portal_interviews())<>0
     or (select count(*) from public.list_candidate_portal_joinings())<>0 then raise exception 'Cross-candidate projection leaked'; end if;
  if exists(select 1 from public.get_candidate_document_access('89000000-0000-0000-0003-000000000001')) then raise exception 'Candidate B accessed Candidate A document'; end if;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000003',true);
do $$ begin
  if public.get_candidate_onboarding_eligibility() then raise exception 'Company user was eligible for Candidate onboarding'; end if;
  begin perform public.get_candidate_portal_context();raise exception 'Company user accessed Candidate Portal';exception when raise_exception then if sqlerrm='Company user accessed Candidate Portal' then raise;end if;end;
  begin perform public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001');raise exception 'Company user accessed Candidate documents';exception when raise_exception then if sqlerrm='Company user accessed Candidate documents' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000007',true);
do $$ begin
  if public.get_candidate_onboarding_eligibility() then raise exception 'Contractor user was eligible for Candidate onboarding'; end if;
  begin perform public.get_candidate_portal_context();raise exception 'Contractor user accessed Candidate Portal';exception when raise_exception then if sqlerrm='Contractor user accessed Candidate Portal' then raise;end if;end;
  begin perform public.admin_get_candidate_document_access('89000000-0000-0000-0003-000000000001');raise exception 'Contractor accessed Candidate document';exception when raise_exception then if sqlerrm='Contractor accessed Candidate document' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000008',true);
do $$ begin
  begin perform public.get_candidate_portal_context();raise exception 'Non-member accessed Candidate Portal';exception when raise_exception then if sqlerrm='Non-member accessed Candidate Portal' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000009',true);
do $$ begin
  begin perform public.get_candidate_portal_context();raise exception 'Inactive Candidate accessed Candidate Portal';exception when raise_exception then if sqlerrm='Inactive Candidate accessed Candidate Portal' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000005',true);
do $$ begin
  if public.get_candidate_onboarding_eligibility() then raise exception 'Internal staff was eligible for Candidate onboarding'; end if;
  begin perform public.get_candidate_portal_context();raise exception 'Internal staff accessed Candidate Portal';exception when raise_exception then if sqlerrm='Internal staff accessed Candidate Portal' then raise;end if;end;
  begin perform public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001');raise exception 'Recruiter accessed identity documents';exception when raise_exception then if sqlerrm='Recruiter accessed identity documents' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000010',true);
do $$ begin
  begin perform public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001');raise exception 'Operations accessed identity documents';exception when raise_exception then if sqlerrm='Operations accessed identity documents' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000011',true);
do $$ begin
  if (select count(*) from public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001'))<>2 then raise exception 'Super Admin document authority failed'; end if;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000012',true);
do $$ begin
  if (select count(*) from public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001'))<>2 then raise exception 'Admin role document authority failed'; end if;
end $$;

select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000004',true);
do $$ begin
  if public.get_candidate_onboarding_eligibility() then raise exception 'Internal Admin was eligible for Candidate onboarding'; end if;
  if (select count(*) from public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001'))<>2 then raise exception 'Admin document inventory failed'; end if;
  begin perform public.admin_review_candidate_document('89000000-0000-0000-0003-000000000001','verified',null);
    raise exception 'Direct uploaded document verification was accepted';
  exception when raise_exception then if sqlerrm='Direct uploaded document verification was accepted' then raise; end if; end;
  if not public.admin_review_candidate_document('89000000-0000-0000-0003-000000000001','under_verification',null) then raise exception 'Admin document review start failed'; end if;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.candidate_documents d where d.id='89000000-0000-0000-0003-000000000001'
      and d.verification_status='under_verification' and d.review_started_at is not null
      and d.review_started_by='89000000-0000-0000-0000-000000000004'
      and d.reviewed_at is null and d.reviewed_by is null and d.verified_at is null and d.verified_by is null) then
    raise exception 'Admin document review-start attribution failed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','89000000-0000-0000-0000-000000000004',true);
do $$ declare reviewed record; begin
  if not public.admin_review_candidate_document('89000000-0000-0000-0003-000000000001','verified',null) then raise exception 'Admin document verification failed'; end if;
  if not public.admin_review_candidate_document(current_setting('w6.replacement_document_id')::uuid,'under_verification',null) then raise exception 'Admin replacement document review start failed'; end if;
  if not public.admin_review_candidate_document(current_setting('w6.replacement_document_id')::uuid,'reupload_required','Upload a clearer synthetic document image.') then raise exception 'Admin document review failed'; end if;
  select * into reviewed from public.admin_list_candidate_documents('89000000-0000-0000-0001-000000000001') d
    where d.document_id=current_setting('w6.replacement_document_id')::uuid;
  if reviewed.verification_status<>'reupload_required' or reviewed.verification_feedback is null then raise exception 'Document review persistence failed'; end if;
  if not public.admin_set_candidate_documentation_override('89000000-0000-0000-0001-000000000001',true,'Synthetic operational exception approved for checkpoint.') then raise exception 'Documentation override failed'; end if;
end $$;

reset role;
do $$ begin
  if not exists(select 1 from public.candidate_documents d where d.id='89000000-0000-0000-0003-000000000001'
      and d.verification_status='verified' and d.review_started_at is not null
      and d.review_started_by='89000000-0000-0000-0000-000000000004'
      and d.reviewed_at is not null and d.reviewed_by='89000000-0000-0000-0000-000000000004'
      and d.verified_at=d.reviewed_at and d.verified_by=d.reviewed_by) then
    raise exception 'Admin final document verification attribution failed'; end if;
  if not exists(select 1 from public.candidate_documents d where d.id=current_setting('w6.replacement_document_id')::uuid
      and d.verification_status='reupload_required' and d.review_started_at is not null
      and d.review_started_by='89000000-0000-0000-0000-000000000004'
      and d.reviewed_at is not null and d.reviewed_by='89000000-0000-0000-0000-000000000004'
      and d.verified_at is null and d.verified_by is null) then
    raise exception 'Admin re-upload review attribution failed'; end if;
end $$;
set local role anon;
do $$ begin
  begin perform public.get_candidate_portal_context();raise exception 'Anonymous accessed Candidate Portal';exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Anonymous accessed Candidate Portal' then raise;end if;end;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.candidate_applications a where a.id=current_setting('w6.application_id')::uuid and a.candidate_id='89000000-0000-0000-0001-000000000001' and a.requirement_id='89000000-0000-0000-0002-000000000001')<>1 then raise exception 'Canonical application integrity failed'; end if;
  if exists(select 1 from public.candidate_applications a where a.requirement_id='89000000-0000-0000-0002-000000000002') then raise exception 'Private requirement received an application'; end if;
  if exists(select 1 from public.candidate_applications a where a.requirement_id='89000000-0000-0000-0002-000000000003') then raise exception 'Unapproved Contractor requirement received an application'; end if;
  if (select c.aadhaar_last4 from public.candidates c where c.id='89000000-0000-0000-0001-000000000001')<>'3333'
     or (select length(c.aadhaar_fingerprint) from public.candidates c where c.id='89000000-0000-0000-0001-000000000001')<>64
     or exists(select 1 from public.candidates c where c.id='89000000-0000-0000-0001-000000000001' and c.aadhaar_fingerprint='111122223333') then raise exception 'Aadhaar fingerprint privacy failed'; end if;
  if (select o.bank_account_last4 from public.candidate_onboarding_details o where o.candidate_id='89000000-0000-0000-0001-000000000001')<>'9012'
     or exists(select 1 from public.candidate_onboarding_details o where o.candidate_id='89000000-0000-0000-0001-000000000001' and o.bank_account_fingerprint='123456789012') then raise exception 'Bank fingerprint privacy failed'; end if;
  if (select count(*) from pg_policies p where p.schemaname='storage' and p.tablename='objects' and p.policyname like 'Candidate % private uploads')<>4 then raise exception 'Candidate private storage policy posture failed'; end if;
  if exists(select 1 from public.audit_logs l where l.entity_type in ('candidate','candidate_document','candidate_application')
    and (l.metadata::text like '%111122223333%' or l.metadata::text like '%123456789012%' or l.metadata::text like '%9876500901%')) then raise exception 'Sensitive value leaked to audit metadata'; end if;
end $$;

rollback;
