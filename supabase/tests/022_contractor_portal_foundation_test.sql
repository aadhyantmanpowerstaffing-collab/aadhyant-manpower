\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('86000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-owner-a@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-owner-b@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-coordinator@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-inactive@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-company@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-admin@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-nonmember@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-manager@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-contractor-recruiter@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-staff-recruiter@test.local','x','{}','{}',now(),now()),
('86000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-staff-operations@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('86000000-0000-0000-0000-000000000001','contractor','W5 Owner A','w5-owner-a@test.local','active'),
('86000000-0000-0000-0000-000000000002','contractor','W5 Owner B','w5-owner-b@test.local','active'),
('86000000-0000-0000-0000-000000000003','contractor','W5 Coordinator','w5-coordinator@test.local','active'),
('86000000-0000-0000-0000-000000000004','contractor','W5 Inactive','w5-inactive@test.local','active'),
('86000000-0000-0000-0000-000000000005','company','W5 Company User','w5-company@test.local','active'),
('86000000-0000-0000-0000-000000000008','contractor','W5 Manager','w5-manager@test.local','active'),
('86000000-0000-0000-0000-000000000009','contractor','W5 Contractor Recruiter','w5-contractor-recruiter@test.local','active');
insert into public.contractors(id,agency_name,owner_name,main_phone,main_email,city,state,verification_status,account_status) values
('86000000-0000-0000-0001-000000000001','W5 Contractor A','Synthetic Owner A','9876500601','a@test.local','Chennai','Tamil Nadu','verified','active'),
('86000000-0000-0000-0001-000000000002','W5 Contractor B','Synthetic Owner B','9876500602','b@test.local','Pune','Maharashtra','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('86000000-0000-0000-0001-000000000001','86000000-0000-0000-0000-000000000001','owner','active'),
('86000000-0000-0000-0001-000000000002','86000000-0000-0000-0000-000000000002','owner','active'),
('86000000-0000-0000-0001-000000000001','86000000-0000-0000-0000-000000000003','coordinator','active'),
('86000000-0000-0000-0001-000000000001','86000000-0000-0000-0000-000000000004','recruiter','suspended'),
('86000000-0000-0000-0001-000000000001','86000000-0000-0000-0000-000000000008','manager','active'),
('86000000-0000-0000-0001-000000000001','86000000-0000-0000-0000-000000000009','recruiter','active');
insert into public.admin_users(user_id) values('86000000-0000-0000-0000-000000000006');
insert into public.staff_profiles(user_id,display_name,status) values
('86000000-0000-0000-0000-000000000010','W5 Staff Recruiter','active'),
('86000000-0000-0000-0000-000000000011','W5 Staff Operations','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('86000000-0000-0000-0000-000000000010','recruiter','active','86000000-0000-0000-0000-000000000006'),
('86000000-0000-0000-0000-000000000011','operations','active','86000000-0000-0000-0000-000000000006');

do $$ begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('private','public') and p.proname in ('current_contractor_portal_id','can_manage_contractor_vacancies','can_edit_contractor_profile',
    'get_contractor_portal_context','get_contractor_dashboard_metrics','get_contractor_portal_profile','update_contractor_portal_profile',
    'list_contractor_portal_vacancies','get_contractor_portal_vacancy','manage_contractor_portal_vacancy','list_contractor_portal_applications',
    'get_contractor_portal_application','list_contractor_portal_interviews','list_contractor_portal_joinings','list_contractor_vacancy_reviews','review_contractor_vacancy')
    and p.prosecdef and exists(select 1 from unnest(p.proconfig)c where split_part(c,'=',1)='search_path' and btrim(split_part(c,'=',2),'"')=''))<>16 then
    raise exception 'W5 SECURITY DEFINER/search_path posture failed'; end if;
  if has_function_privilege('anon','public.get_contractor_portal_context()','execute')
    or has_function_privilege('authenticated','private.current_contractor_portal_id(boolean)','execute') then raise exception 'W5 execute boundary failed'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000008',true);
do $$ declare ctx record;begin select * into ctx from public.get_contractor_portal_context();if not ctx.can_manage_vacancies or not ctx.can_update_profile then raise exception 'Contractor Manager permissions failed';end if;end $$;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000009',true);
do $$ declare ctx record;begin select * into ctx from public.get_contractor_portal_context();if not ctx.can_manage_vacancies or ctx.can_update_profile then raise exception 'Contractor Recruiter permissions failed';end if;
  begin perform public.update_contractor_portal_profile('Bad',null,null,null,null,null,null,null,null,null,null);raise exception 'Contractor Recruiter updated profile';exception when raise_exception then if sqlerrm='Contractor Recruiter updated profile' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
do $$ declare ctx record; created record; begin
  select * into ctx from public.get_contractor_portal_context();
  if ctx.contractor_name<>'W5 Contractor A' or not ctx.can_manage_vacancies or not ctx.can_update_profile then raise exception 'Contractor A context failed'; end if;
  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Synthetic Client Worksite',p_job_role=>'Fitter',p_job_location=>'Chennai',p_required_headcount=>4,p_qualification=>'ITI');
  if created.submission_status<>'draft' or created.requirement_stage<>'draft' then raise exception 'Contractor draft creation failed'; end if;
  perform set_config('w5.checkpoint_requirement_id',created.id::text,true);
  perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);
  if exists(select 1 from public.employer_requirements r where r.id=created.id) then raise exception 'Contractor bypassed requirement RLS'; end if;
  if exists(select 1 from public.requirement_contractors link where link.requirement_id=created.id) then raise exception 'Contractor bypassed linkage RLS'; end if;
  begin perform public.list_recruitment_candidates();raise exception 'Contractor accessed Candidate Master';exception when raise_exception then if sqlerrm='Contractor accessed Candidate Master' then raise;end if;end;
  begin perform public.get_company_portal_context();raise exception 'Contractor accessed Company Portal';exception when raise_exception then if sqlerrm='Contractor accessed Company Portal' then raise;end if;end;
  begin perform public.review_contractor_vacancy(created.id,'approve',null);raise exception 'Contractor self-approved';exception when raise_exception then if sqlerrm='Contractor self-approved' then raise;end if;end;
end $$;

reset role;
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid;begin
  if (select count(*) from public.employer_requirements r where r.id=rid and r.created_by_user_id='86000000-0000-0000-0000-000000000001' and r.company_id is null and r.requirement_stage='draft' and r.requirement_visibility='private')<>1 then raise exception 'Canonical submitted requirement integrity failed';end if;
  if (select count(*) from public.requirement_contractors link where link.requirement_id=rid and link.contractor_id='86000000-0000-0000-0001-000000000001' and link.origin_type='contractor_submission' and link.submission_status='submitted')<>1 then raise exception 'Canonical submitted linkage integrity failed';end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000002',true);
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid;begin
  if (select count(*) from public.list_contractor_portal_vacancies())<>0 then raise exception 'Contractor B saw Contractor A vacancy';end if;
  if exists(select 1 from public.get_contractor_dashboard_metrics() m where m.draft_vacancies<>0 or m.under_review<>0 or m.approved_active<>0 or m.needs_action<>0 or m.total_openings<>0 or m.applications<>0 or m.interviews<>0 or m.selected<>0 or m.joining_pending<>0 or m.joined<>0) then raise exception 'Zero-data Contractor dashboard failed';end if;
  begin perform public.get_contractor_portal_vacancy(rid);raise exception 'Contractor B read Contractor A vacancy';exception when raise_exception then if sqlerrm='Contractor B read Contractor A vacancy' then raise;end if;end;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'update',p_requirement_id=>rid,p_client_name=>'Spoof',p_job_role=>'Fitter',p_job_location=>'Pune',p_required_headcount=>1);raise exception 'Contractor B mutated Contractor A vacancy';exception when raise_exception then if sqlerrm='Contractor B mutated Contractor A vacancy' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000003',true);
do $$ declare ctx record;begin select * into ctx from public.get_contractor_portal_context();if ctx.can_manage_vacancies or ctx.can_update_profile then raise exception 'Coordinator is not read-only';end if;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Bad',p_job_role=>'Bad',p_job_location=>'Bad',p_required_headcount=>1);raise exception 'Coordinator mutated';exception when raise_exception then if sqlerrm='Coordinator mutated' then raise;end if;end;end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000004',true);
do $$ begin
  begin perform public.get_contractor_dashboard_metrics();raise exception 'Inactive member accessed portal';exception when raise_exception then if sqlerrm='Inactive member accessed portal' then raise;end if;end;
  begin perform public.get_contractor_portal_profile();raise exception 'Inactive member accessed profile';exception when raise_exception then if sqlerrm='Inactive member accessed profile' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000005',true);
do $$ begin begin perform public.get_contractor_portal_context();raise exception 'Company user accessed Contractor Portal';exception when raise_exception then if sqlerrm='Company user accessed Contractor Portal' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000007',true);
do $$ begin begin perform public.get_contractor_portal_context();raise exception 'Non-member accessed Contractor Portal';exception when raise_exception then if sqlerrm='Non-member accessed Contractor Portal' then raise;end if;end;end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000006',true);
do $$ declare rid uuid; reviewed record;begin
  begin perform public.get_contractor_portal_context();raise exception 'Internal staff accessed Contractor Portal';exception when raise_exception then if sqlerrm='Internal staff accessed Contractor Portal' then raise;end if;end;
  rid:=current_setting('w5.checkpoint_requirement_id')::uuid;
  perform public.review_contractor_vacancy(rid,'request_correction','Clarify the shift details');
end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid; updated record; detail jsonb;begin
  detail:=public.get_contractor_portal_vacancy(rid);if detail->>'submission_status'<>'correction_required' or detail->>'review_feedback'<>'Clarify the shift details' then raise exception 'Correction feedback projection failed';end if;
  select * into updated from public.manage_contractor_portal_vacancy(p_action=>'update',p_requirement_id=>rid,p_client_name=>'Synthetic Client Worksite',p_job_role=>'Fitter',p_job_location=>'Chennai',p_required_headcount=>5,p_qualification=>'ITI',p_shift_details=>'General shift');
  if updated.submission_status<>'draft' then raise exception 'Correction edit did not return to Draft';end if;
  perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>rid);
end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000010',true);
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid;begin begin perform public.review_contractor_vacancy(rid,'approve',null);raise exception 'Staff Recruiter approved vacancy';exception when raise_exception then if sqlerrm='Staff Recruiter approved vacancy' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000011',true);
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid;begin begin perform public.review_contractor_vacancy(rid,'approve',null);raise exception 'Staff Operations approved vacancy';exception when raise_exception then if sqlerrm='Staff Operations approved vacancy' then raise;end if;end;end $$;

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000006',true);
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid; reviewed record;begin
  select * into reviewed from public.review_contractor_vacancy(rid,'approve','Approved synthetic vacancy');if reviewed.submission_status<>'approved' or reviewed.requirement_stage<>'open' or reviewed.requirement_visibility<>'assigned' then raise exception 'Internal approval bridge failed';end if;if not exists(select 1 from public.list_recruitment_requirements(null,'open',50,0) r where r.id=rid) then raise exception 'Approved vacancy not visible to W3';end if;end $$;

reset role;
do $$ declare rid uuid:=current_setting('w5.checkpoint_requirement_id')::uuid;begin
  if (select count(*) from public.employer_requirements r where r.id=rid and r.requirement_stage='open' and r.requirement_visibility='assigned')<>1 then raise exception 'Canonical approval did not update the same requirement';end if;
  if (select count(*) from public.requirement_contractors link where link.requirement_id=rid and link.contractor_id='86000000-0000-0000-0001-000000000001' and link.submission_status='approved' and link.reviewed_by='86000000-0000-0000-0000-000000000006' and link.reviewed_at is not null)<>1 then raise exception 'Canonical approval linkage integrity failed';end if;
end $$;
insert into public.candidates(id,full_name,age,gender,mobile,whatsapp_number,current_location,district,state,highest_qualification,specialization,candidate_type,total_experience,interview_available,internal_notes,consent,status)
values('86000000-0000-0000-0002-000000000001','W5 Safe Candidate',27,'Female','9876500611','9876500611','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','3 years','Yes','Never expose this note',true,'new');
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by)
values('86000000-0000-0000-0003-000000000001','86000000-0000-0000-0002-000000000001',current_setting('w5.checkpoint_requirement_id')::uuid,'admin','selected','86000000-0000-0000-0000-000000000006');
insert into public.interviews(id,application_id,interview_round,scheduled_at,mode,location,status,created_by) values('86000000-0000-0000-0004-000000000001','86000000-0000-0000-0003-000000000001',1,now()+interval '2 days','onsite','Chennai','scheduled','86000000-0000-0000-0000-000000000006');
insert into public.candidate_joinings(id,application_id,expected_joining_date,joining_status,created_by) values('86000000-0000-0000-0005-000000000001','86000000-0000-0000-0003-000000000001',current_date+7,'confirmed','86000000-0000-0000-0000-000000000006');

set local role authenticated;select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
do $$ declare app record;detail jsonb;metrics record;begin select * into app from public.list_contractor_portal_applications();if app.candidate_name<>'W5 Safe Candidate' then raise exception 'Safe application projection failed';end if;detail:=public.get_contractor_portal_application(app.application_id);if detail? 'mobile' or detail?'whatsapp_number' or detail?'internal_notes' or detail?'candidate_id' then raise exception 'Contractor candidate privacy failed';end if;if(select count(*) from public.list_contractor_portal_interviews())<>1 or(select count(*) from public.list_contractor_portal_joinings())<>1 then raise exception 'Read-only progress projection failed';end if;select * into metrics from public.get_contractor_dashboard_metrics();if metrics.approved_active<>1 or metrics.applications<>1 or metrics.interviews<>1 or metrics.selected<>1 or metrics.joining_pending<>0 then raise exception 'Contractor dashboard failed';end if;
  begin perform public.schedule_recruitment_interview(app.application_id,now()+interval '3 days','onsite','Chennai',null,null);raise exception 'Contractor scheduled interview';exception when raise_exception then if sqlerrm='Contractor scheduled interview' then raise;end if;end;
  begin perform public.reschedule_recruitment_interview('86000000-0000-0000-0004-000000000001',now()+interval '4 days','onsite','Chennai',null,null);raise exception 'Contractor rescheduled interview';exception when raise_exception then if sqlerrm='Contractor rescheduled interview' then raise;end if;end;
  begin perform public.update_recruitment_interview('86000000-0000-0000-0004-000000000001','completed','selected',null,null);raise exception 'Contractor mutated interview';exception when raise_exception then if sqlerrm='Contractor mutated interview' then raise;end if;end;
  begin perform public.upsert_recruitment_joining('86000000-0000-0000-0003-000000000001',current_date+7,null,'confirmed',null,null,null);raise exception 'Contractor mutated joining';exception when raise_exception then if sqlerrm='Contractor mutated joining' then raise;end if;end;
  begin perform public.manage_contractor_portal_vacancy(p_action=>'update',p_requirement_id=>current_setting('w5.checkpoint_requirement_id')::uuid,p_client_name=>'Synthetic Client Worksite',p_job_role=>'Fitter',p_job_location=>'Chennai',p_required_headcount=>5);raise exception 'Approved vacancy regressed';exception when raise_exception then if sqlerrm='Approved vacancy regressed' then raise;end if;end;
end $$;

reset role;select set_config('request.jwt.claim.sub','',true);
do $$ begin if has_function_privilege('anon','public.list_contractor_portal_vacancies(text,text,integer,integer)','execute') then raise exception 'Anon W5 execution granted';end if;end $$;
rollback;
