-- W6 broad Candidate Portal runtime coverage. Synthetic and rollback-scoped.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89300000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-candidate-a@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-candidate-b@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-unlinked@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-admin@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-recruiter@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-operations@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-company@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-broad-contractor@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('89300000-0000-0000-0000-000000000001','candidate','W6 Broad Candidate A','9876500931','w6-broad-candidate-a@test.local','active'),
('89300000-0000-0000-0000-000000000002','candidate','W6 Broad Candidate B','9876500932','w6-broad-candidate-b@test.local','active'),
('89300000-0000-0000-0000-000000000007','company','W6 Broad Company',null,'w6-broad-company@test.local','active'),
('89300000-0000-0000-0000-000000000008','contractor','W6 Broad Contractor',null,'w6-broad-contractor@test.local','active');
insert into public.admin_users(user_id) values('89300000-0000-0000-0000-000000000004');
insert into public.staff_profiles(user_id,display_name,status) values
('89300000-0000-0000-0000-000000000005','W6 Broad Recruiter','active'),
('89300000-0000-0000-0000-000000000006','W6 Broad Operations','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('89300000-0000-0000-0000-000000000005','recruiter','active','89300000-0000-0000-0000-000000000004'),
('89300000-0000-0000-0000-000000000006','operations','active','89300000-0000-0000-0000-000000000004');
insert into public.companies(id,legal_name,verification_status,account_status) values
('89300000-0000-0000-0005-000000000001','W6 Broad Synthetic Company','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
('89300000-0000-0000-0005-000000000001','89300000-0000-0000-0000-000000000007','owner','active');
insert into public.contractors(id,agency_name,verification_status,account_status) values
('89300000-0000-0000-0006-000000000001','W6 Broad Synthetic Contractor','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('89300000-0000-0000-0006-000000000001','89300000-0000-0000-0000-000000000008','owner','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,
  candidate_type,total_experience,interview_available,consent,status,user_id,profile_status,profile_completion_status,
  availability_status,aadhaar_fingerprint,aadhaar_last4,date_of_birth,pincode,mobile_verified)
values
('89300000-0000-0000-0001-000000000001','W6 Broad Candidate A',25,'Female','9876500931','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','3 years','Yes',true,'new','89300000-0000-0000-0000-000000000001','active','complete','open_to_opportunities',repeat('a',64),'7777','2001-01-01','600001',true),
('89300000-0000-0000-0001-000000000002','W6 Broad Candidate B',26,'Male','9876500932','Pune','Pune','Maharashtra','Diploma','Mechanical','Experienced','4 years','Yes',true,'new','89300000-0000-0000-0000-000000000002','active','complete','open_to_opportunities',repeat('b',64),'8888','2000-01-01','411001',false);
insert into public.candidate_preferences(candidate_id,preferred_locations,preferred_job_roles,source) values
('89300000-0000-0000-0001-000000000001',array['Chennai'],array['Fitter'],'candidate'),
('89300000-0000-0000-0001-000000000002',array['Pune'],array['Technician'],'candidate');

do $$ begin
  if not exists(select 1 from pg_constraint c where c.conrelid='public.candidates'::regclass
      and c.conname='candidates_user_id_key' and c.contype='u') then
    raise exception 'Candidate Auth linkage uniqueness is missing';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000003',true);
do $$ begin
  begin perform public.get_candidate_portal_context();raise exception 'Unlinked Auth resolved Candidate context';
  exception when raise_exception then if sqlerrm='Unlinked Auth resolved Candidate context' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; begin
  if not public.update_candidate_portal_profile('W6 Broad Candidate A','9876500931','555566667777','2001-01-01','Female',
    'Chennai','Chennai','Tamil Nadu','600001','ITI','Fitter','Experienced','3 years','Fitter','Yes',
    array['Chennai'],array['Fitter'],18000,26000,'day',true,null) then raise exception 'Candidate A profile update failed';end if;
  select * into ctx from public.get_candidate_portal_context();
  if ctx.profile_completion>=100 then raise exception 'Profile without Resume reported complete percentage';end if;
end $$;

select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000002',true);
do $$ declare message text; begin
  begin
    perform public.update_candidate_portal_profile('W6 Broad Candidate B','9876500932','5555 6666 7777','2000-01-01','Male',
      'Pune','Pune','Maharashtra','411001','Diploma','Mechanical','Experienced','4 years','Technician','Yes',
      array['Pune'],array['Technician'],20000,30000,'day',true,null);
    raise exception 'Duplicate Aadhaar fingerprint was accepted';
  exception when raise_exception then
    message:=sqlerrm;
    if message='Duplicate Aadhaar fingerprint was accepted' or message ilike '%Candidate A%' or message ilike '%89300000%' then raise;end if;
  end;
end $$;
reset role;

do $$ begin
  if (select count(*) from public.candidates c where c.aadhaar_fingerprint=encode(extensions.digest('555566667777','sha256'),'hex'))<>1
     or exists(select 1 from public.candidates c where to_jsonb(c)::text like '%555566667777%')
     or exists(select 1 from public.audit_logs l where l.metadata::text like '%555566667777%') then
    raise exception 'Duplicate Aadhaar privacy/integrity failed';
  end if;
end $$;

insert into public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes,verification_status,active)
values('89300000-0000-0000-0003-000000000001','89300000-0000-0000-0001-000000000001','resume',
 '89300000-0000-0000-0000-000000000001/89300000-0000-0000-0004-000000000001/resume.pdf','resume.pdf','application/pdf',1024,'uploaded',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; begin select * into ctx from public.get_candidate_portal_context();if ctx.profile_completion<>100 then raise exception 'Active Resume did not complete profile';end if;end $$;
reset role;
update public.candidate_documents set active=false,replaced_at=now() where id='89300000-0000-0000-0003-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; begin select * into ctx from public.get_candidate_portal_context();if ctx.profile_completion>=100 then raise exception 'Inactive Resume did not reduce completion';end if;end $$;
reset role;
insert into public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes,verification_status,active)
values('89300000-0000-0000-0003-000000000002','89300000-0000-0000-0001-000000000001','resume',
 '89300000-0000-0000-0000-000000000001/89300000-0000-0000-0004-000000000002/resume.pdf','resume-v2.pdf','application/pdf',2048,'uploaded',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; begin select * into ctx from public.get_candidate_portal_context();if ctx.profile_completion<>100 then raise exception 'Replacement Resume did not restore completion';end if;end $$;
reset role;

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
 qualification,consent,status,requirement_code,job_location,filled_positions,requirement_visibility,requirement_stage,published_at)
values
('89300000-0000-0000-0002-000000000001','W6 Eligible','Synthetic','9876500941','Chennai','Eligible Fitter',5,'ITI',true,'in_progress','AAD-2097-000001','Chennai',0,'public','open',now()),
('89300000-0000-0000-0002-000000000002','W6 Review','Synthetic','9876500942','Chennai','Under Review',5,'ITI',true,'new','AAD-2097-000002','Chennai',0,'private','draft',null),
('89300000-0000-0000-0002-000000000003','W6 Correction','Synthetic','9876500943','Chennai','Correction Required',5,'ITI',true,'new','AAD-2097-000003','Chennai',0,'private','draft',null),
('89300000-0000-0000-0002-000000000004','W6 Rejected','Synthetic','9876500944','Chennai','Rejected',5,'ITI',true,'closed','AAD-2097-000004','Chennai',0,'private','cancelled',null),
('89300000-0000-0000-0002-000000000005','W6 Closed','Synthetic','9876500945','Chennai','Closed',5,'ITI',true,'closed','AAD-2097-000005','Chennai',0,'private','closed',null),
('89300000-0000-0000-0002-000000000006','W6 Filled','Synthetic','9876500946','Chennai','Filled',5,'ITI',true,'closed','AAD-2097-000006','Chennai',5,'public','filled',now()),
('89300000-0000-0000-0002-000000000007','W6 Zero','Synthetic','9876500947','Chennai','Zero Openings',5,'ITI',true,'in_progress','AAD-2097-000007','Chennai',5,'public','open',now()),
('89300000-0000-0000-0002-000000000008','W6 Application Target','Synthetic','9876500948','Chennai','Application Target Fitter',5,'ITI',true,'in_progress','AAD-2097-000008','Chennai',0,'public','open',now()),
('89300000-0000-0000-0002-000000000009','W6 Joining Target','Synthetic','9876500949','Chennai','Joining Target Fitter',5,'ITI',true,'in_progress','AAD-2097-000009','Chennai',0,'public','open',now());

-- The visible opportunity fixture must satisfy the canonical Migration 039 boundary.
update public.employer_requirements
set source_type='employer_portal',review_status='approved'
where id='89300000-0000-0000-0002-000000000001'
  and requirement_code='AAD-2097-000001'
  and requirement_stage='open'
  and requirement_visibility='public'
  and filled_positions<required_headcount;

-- A dedicated application/interview fixture must satisfy the same boundary.
update public.employer_requirements
set source_type='employer_portal',review_status='approved'
where id='89300000-0000-0000-0002-000000000008'
  and requirement_code='AAD-2097-000008'
  and requirement_stage='open'
  and requirement_visibility='public'
  and filled_positions<required_headcount;

-- The selected/joining privacy fixture also needs its own eligible vacancy;
-- keep AAD-2097-000005 closed/private as an opportunity negative control.
update public.employer_requirements
set source_type='employer_portal',review_status='approved'
where id='89300000-0000-0000-0002-000000000009'
  and requirement_code='AAD-2097-000009'
  and requirement_stage='open'
  and requirement_visibility='public'
  and filled_positions<required_headcount;

insert into public.requirement_contractors(id,requirement_id,contractor_id,assigned_headcount,assignment_status,origin_type,submission_status)
values
('89300000-0000-0000-0006-000000000011','89300000-0000-0000-0002-000000000002','89300000-0000-0000-0006-000000000001',5,'assigned','contractor_submission','under_review'),
('89300000-0000-0000-0006-000000000012','89300000-0000-0000-0002-000000000003','89300000-0000-0000-0006-000000000001',5,'assigned','contractor_submission','correction_required'),
('89300000-0000-0000-0006-000000000013','89300000-0000-0000-0002-000000000004','89300000-0000-0000-0006-000000000001',5,'cancelled','contractor_submission','rejected');

set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ begin
  if (select count(*) from public.list_candidate_job_opportunities(null,50,0) o
       where o.requirement_code='AAD-2097-000001'
         and o.job_role='Eligible Fitter'
         and o.job_location='Chennai'
         and o.open_positions=5
         and o.qualification='ITI'
         and not o.already_applied)<>1
     or exists(select 1 from public.list_candidate_job_opportunities(null,50,0) o where o.requirement_code in
       ('AAD-2097-000002','AAD-2097-000003','AAD-2097-000004','AAD-2097-000005','AAD-2097-000006','AAD-2097-000007')) then
    raise exception 'Opportunity exclusion matrix failed';
  end if;
end $$;

do $$ begin
  if not public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',false,'123456789012',false,'1234567890') then raise exception 'False UAN/ESIC normalization failed';end if;
  if exists(select 1 from public.get_candidate_onboarding_details() o where o.uan_masked is not null or o.esic_ip_masked is not null) then raise exception 'False UAN/ESIC retained supplied numbers';end if;
  begin perform public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',true,null,false,null);raise exception 'Missing UAN accepted';exception when raise_exception then if sqlerrm='Missing UAN accepted' then raise;end if;end;
  begin perform public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',true,'123',false,null);raise exception 'Malformed UAN accepted';exception when raise_exception then if sqlerrm='Malformed UAN accepted' then raise;end if;end;
  begin perform public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',false,null,true,null);raise exception 'Missing ESIC accepted';exception when raise_exception then if sqlerrm='Missing ESIC accepted' then raise;end if;end;
  begin perform public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',false,null,true,'123');raise exception 'Malformed ESIC accepted';exception when raise_exception then if sqlerrm='Malformed ESIC accepted' then raise;end if;end;
  if not public.update_candidate_onboarding_details('W6 Candidate A','Synthetic Bank','123456789012','SBIN0001234',true,'123456789012',true,'1234567890') then raise exception 'Valid UAN/ESIC combination failed';end if;
end $$;
reset role;

insert into public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes,verification_status,active) values
('89300000-0000-0000-0003-000000000003','89300000-0000-0000-0001-000000000001','aadhaar','89300000-0000-0000-0000-000000000001/89300000-0000-0000-0004-000000000003/aadhaar.pdf','aadhaar.pdf','application/pdf',1024,'uploaded',true),
('89300000-0000-0000-0003-000000000004','89300000-0000-0000-0001-000000000001','candidate_photo','89300000-0000-0000-0000-000000000001/89300000-0000-0000-0004-000000000004/photo.png','photo.png','image/png',1024,'uploaded',true),
('89300000-0000-0000-0003-000000000005','89300000-0000-0000-0001-000000000001','bank_proof','89300000-0000-0000-0000-000000000001/89300000-0000-0000-0004-000000000005/bank.pdf','bank.pdf','application/pdf',1024,'uploaded',true);

set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000004',true);
do $$ begin
  perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000003','under_verification',null);
  perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000003','verified',null);
  perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000004','under_verification',null);
  perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000005','under_verification',null);
  perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000005','reupload_required','Upload a clearer synthetic bank proof.');
  begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'short');raise exception 'Short override reason accepted';exception when raise_exception then if sqlerrm='Short override reason accepted' then raise;end if;end;
  if not public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Synthetic documentation exception for broad checkpoint.') then raise exception 'Admin override failed';end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ begin
  if (select count(*) from public.get_candidate_joining_document_checklist() c where c.required)<>6
     or (select count(*) from public.get_candidate_joining_document_checklist() c where c.required and c.complete)<>4
     or (select count(*) from public.get_candidate_joining_document_checklist() c where c.required and not c.complete)<>2
     or not exists(select 1 from public.get_candidate_joining_document_checklist() c where c.document_type='candidate_photo' and c.verification_status='under_verification' and not c.complete)
     or not exists(select 1 from public.get_candidate_joining_document_checklist() c where c.document_type='bank_proof' and c.verification_status='reupload_required' and not c.complete) then
    raise exception 'Partial joining checklist invariants failed';end if;
  if not (select documentation_override_approved from public.get_candidate_onboarding_details()) then raise exception 'Override projection missing';end if;
end $$;
reset role;

-- Valid canonical mutation targets ensure the authorization checks below precede any other rejection.
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,source_reference) values
('89300000-0000-0000-000a-000000000001','89300000-0000-0000-0001-000000000001','89300000-0000-0000-0002-000000000001','direct','applied','broad_checkpoint'),
('89300000-0000-0000-000a-000000000002','89300000-0000-0000-0001-000000000001','89300000-0000-0000-0002-000000000009','direct','selected','broad_checkpoint'),
('89300000-0000-0000-000a-000000000003','89300000-0000-0000-0001-000000000001','89300000-0000-0000-0002-000000000008','direct','interview','broad_checkpoint');
insert into public.interviews(id,application_id,interview_round,scheduled_at,mode,location,status,created_by) values
('89300000-0000-0000-000b-000000000001','89300000-0000-0000-000a-000000000003',1,now()+interval '2 days','video','Synthetic Room','scheduled','89300000-0000-0000-0000-000000000004');
insert into public.candidate_joinings(id,application_id,expected_joining_date,joining_status,created_by) values
('89300000-0000-0000-000c-000000000001','89300000-0000-0000-000a-000000000002',current_date+5,'confirmed','89300000-0000-0000-0000-000000000004');

-- Repeat valid internal mutation calls as Candidate now that targets exist.
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ begin
  begin perform public.transition_recruitment_application('89300000-0000-0000-000a-000000000001','screening','Synthetic',null,null);raise exception 'Candidate transitioned own application';exception when raise_exception then if sqlerrm='Candidate transitioned own application' then raise;end if;end;
  begin perform public.schedule_recruitment_interview('89300000-0000-0000-000a-000000000001',now()+interval '3 days','video','Synthetic Room',null,null);raise exception 'Candidate scheduled interview';exception when raise_exception then if sqlerrm='Candidate scheduled interview' then raise;end if;end;
  begin perform public.reschedule_recruitment_interview('89300000-0000-0000-000b-000000000001',now()+interval '4 days','video','Synthetic Room',null,null);raise exception 'Candidate rescheduled interview';exception when raise_exception then if sqlerrm='Candidate rescheduled interview' then raise;end if;end;
  begin perform public.update_recruitment_interview('89300000-0000-0000-000b-000000000001','completed','selected','Synthetic result',null);raise exception 'Candidate finalized interview';exception when raise_exception then if sqlerrm='Candidate finalized interview' then raise;end if;end;
  begin perform public.upsert_recruitment_joining('89300000-0000-0000-000a-000000000002',current_date+5,null,'confirmed',null,null,null);raise exception 'Candidate updated joining';
  exception when insufficient_privilege then null;
    when others then if sqlerrm='Candidate updated joining' then raise;else raise exception 'Unexpected Candidate joining-update denial: %',sqlerrm;end if;end;
  begin perform public.upsert_recruitment_joining('89300000-0000-0000-000a-000000000002',current_date+5,current_date,'joined','SYN-001',null,null);raise exception 'Candidate marked self Joined';
  exception when insufficient_privilege then null;
    when others then if sqlerrm='Candidate marked self Joined' then raise;else raise exception 'Unexpected Candidate joined-transition denial: %',sqlerrm;end if;end;
end $$;

select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000002',true);
do $$ declare profile record; begin
  select * into profile from public.get_candidate_portal_profile();
  if profile.full_name<>'W6 Broad Candidate B' or exists(select 1 from public.get_candidate_onboarding_details())
     or exists(select 1 from public.list_candidate_portal_documents())
     or exists(select 1 from public.list_candidate_portal_applications())
     or exists(select 1 from public.list_candidate_portal_interviews())
     or exists(select 1 from public.list_candidate_portal_joinings()) then raise exception 'Cross-Candidate privacy failed';end if;
end $$;

select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000005',true);
do $$ begin begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Recruiter synthetic override reason.');raise exception 'Recruiter approved override';exception when raise_exception then if sqlerrm='Recruiter approved override' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000006',true);
do $$ begin begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Operations synthetic override reason.');raise exception 'Operations approved override';exception when raise_exception then if sqlerrm='Operations approved override' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ begin begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Candidate synthetic override reason.');raise exception 'Candidate approved override';exception when raise_exception then if sqlerrm='Candidate approved override' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000007',true);
do $$ begin begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Company synthetic override reason.');raise exception 'Company approved override';exception when raise_exception then if sqlerrm='Company approved override' then raise;end if;end;begin perform public.get_candidate_portal_context();raise exception 'Company accessed Candidate privacy projection';exception when raise_exception then if sqlerrm='Company accessed Candidate privacy projection' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000008',true);
do $$ begin begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Contractor synthetic override reason.');raise exception 'Contractor approved override';exception when raise_exception then if sqlerrm='Contractor approved override' then raise;end if;end;begin perform public.get_candidate_portal_context();raise exception 'Contractor accessed Candidate privacy projection';exception when raise_exception then if sqlerrm='Contractor accessed Candidate privacy projection' then raise;end if;end;end $$;
reset role;
set local role anon;
do $$ begin begin perform public.admin_set_candidate_documentation_override('89300000-0000-0000-0001-000000000001',true,'Anonymous synthetic override reason.');raise exception 'Anonymous approved override';exception when insufficient_privilege then null;when raise_exception then if sqlerrm='Anonymous approved override' then raise;end if;end;end $$;
reset role;

-- Complete the two remaining required documents without changing override semantics.
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000004',true);
do $$ begin
  perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000004','verified',null);
end $$;
reset role;
update public.candidate_documents set active=false,replaced_at=now() where id='89300000-0000-0000-0003-000000000005';
insert into public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes,verification_status,active) values
('89300000-0000-0000-0003-000000000006','89300000-0000-0000-0001-000000000001','bank_proof','89300000-0000-0000-0000-000000000001/89300000-0000-0000-0004-000000000006/bank.pdf','bank-v2.pdf','application/pdf',1024,'uploaded',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000004',true);
do $$ begin perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000006','under_verification',null);perform public.admin_review_candidate_document('89300000-0000-0000-0003-000000000006','verified',null);end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ begin
  if (select count(*) from public.get_candidate_joining_document_checklist() c where c.required and c.complete)<>6 then raise exception 'Complete checklist exact count failed';end if;
end $$;
reset role;
update public.candidate_joinings set joining_status='joined',actual_joining_date=current_date where id='89300000-0000-0000-000c-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ begin if (select count(*) from public.get_candidate_joining_document_checklist() c where c.required and c.complete)<>6 then raise exception 'Joined status fabricated checklist state';end if;end $$;
reset role;

do $$ begin
  if not exists(select 1 from public.candidate_onboarding_details o where o.candidate_id='89300000-0000-0000-0001-000000000001'
      and o.documentation_override_approved and o.documentation_override_by='89300000-0000-0000-0000-000000000004'
      and o.documentation_override_at is not null) then raise exception 'Override attribution failed';end if;
  if (select count(*) from public.audit_logs l where l.action='candidate.documentation_override_approved'
      and l.actor_user_id='89300000-0000-0000-0000-000000000004' and l.entity_id='89300000-0000-0000-0001-000000000001')<>1 then raise exception 'Override audit failed';end if;
  if not exists(select 1 from public.candidate_documents d where d.id='89300000-0000-0000-0003-000000000003'
      and d.review_started_by='89300000-0000-0000-0000-000000000004' and d.review_started_at is not null
      and d.reviewed_by='89300000-0000-0000-0000-000000000004' and d.reviewed_at is not null
      and d.verified_by='89300000-0000-0000-0000-000000000004' and d.verified_at is not null) then raise exception 'Verifier attribution failed';end if;
  if pg_get_function_result('public.list_candidate_portal_documents()'::regprocedure) ~* 'review_started|reviewed_by|verified_by|storage_object' then raise exception 'Candidate document projection exposes internal attribution/path';end if;
  if exists(select 1 from public.audit_logs l where l.actor_user_id::text like '89300000-%' and
      (l.metadata::text like '%555566667777%' or l.metadata::text like '%123456789012%' or l.metadata::text ilike '%storage%' or l.metadata::text ilike '%signed%')) then raise exception 'Sensitive Candidate data leaked to audit metadata';end if;
  if exists(select 1 from public.candidates c where c.id='89300000-0000-0000-0001-000000000001' and to_jsonb(c)::text like '%555566667777%') then raise exception 'Plaintext Aadhaar persisted';end if;
end $$;

rollback;
