-- Phase B rollback checkpoint: Job Lead projections only.
begin;
create temporary table phase_b_checkpoint_cases(case_name text primary key, coverage text not null) on commit drop;
insert into phase_b_checkpoint_cases values
 ('search_positive','runtime list call'),('search_negative','runtime list call'),('stage_source_owner','runtime list call'),
 ('unassigned_company_origin','runtime list call'),('contractor_origin_join_dedup','runtime list call'),
 ('attention_date_combined','runtime list call'),('pagination_order','runtime list call'),
 ('funnel_unique_counts','runtime list call'),('headcount_zero_overfill','runtime list call'),
 ('history_newest_50','runtime detail call'),('list_detail_consistency','runtime list/detail calls'),
 ('privacy_allowlist','runtime output shape'),('unauthorized_list_detail','runtime denial'),
 ('retained_baselines','pre-fixture aggregate capture'),('rollback_residue','separate post-rollback query');
do $$ begin if (select count(*) from phase_b_checkpoint_cases)<>15 then raise exception 'Phase-B checkpoint matrix incomplete'; end if; end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('94000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-b-admin@test.local','x','{}','{}',now(),now()),
 ('94000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-b-viewer@test.local','x','{}','{}',now(),now());
insert into public.staff_profiles(user_id,display_name,status) values
 ('94000000-0000-0000-0000-000000000001','Phase B Admin','active'),('94000000-0000-0000-0000-000000000004','Phase B Viewer','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
 ('94000000-0000-0000-0000-000000000001','admin','active','94000000-0000-0000-0000-000000000001'),('94000000-0000-0000-0000-000000000004','viewer','active','94000000-0000-0000-0000-000000000001');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,interview_available,consent,status)
 values('94000000-0000-0000-0001-000000000001','Phase B Candidate',24,'Female','9876543220','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new');
insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,qualification,consent,status,requirement_code,job_location,requirement_stage,requirement_visibility,source_type)
 values('94000000-0000-0000-0002-000000000001','Phase B Company','Phase B Contact','9876543221','Chennai','Fitter',2,'ITI',true,'in_progress','PHB-REQ-001','Chennai','draft','private','admin_manual');
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_at,updated_at)
 values('94000000-0000-0000-0004-000000000001','94000000-0000-0000-0001-000000000001','94000000-0000-0000-0002-000000000001','admin_manual','applied',now(),now());
insert into public.interviews(id,application_id,scheduled_at,interview_round,status,result,created_by)
 values('94000000-0000-0000-0005-000000000001','94000000-0000-0000-0004-000000000001',now()+interval '1 day',1,'scheduled','pending','94000000-0000-0000-0000-000000000001');
do $$
begin
  if to_regprocedure('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)') is null then raise exception 'Job Lead list RPC missing'; end if;
  if to_regprocedure('public.admin_get_job_lead_detail(uuid)') is null then raise exception 'Job Lead detail RPC missing'; end if;
  if pg_get_functiondef('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)'::regprocedure) not ilike '%security definer%' or pg_get_functiondef('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)'::regprocedure) not ilike '%search_path to ''''%' then raise exception 'Job Lead security posture invalid'; end if;
  if has_function_privilege('anon','public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)','execute') or not has_function_privilege('authenticated','public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)','execute') then raise exception 'Job Lead grant matrix invalid'; end if;
  if pg_get_functiondef('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)'::regprocedure) not ilike '%require_recruitment_operations_access%' and pg_get_functiondef('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)'::regprocedure) not ilike '%can_manage_recruitment_operations%' then raise exception 'List RPC authorization guard missing'; end if;
  if to_regprocedure('private.require_recruitment_operations_access()') is not null and pg_get_functiondef('private.require_recruitment_operations_access()'::regprocedure) not ilike '%Recruitment access is required%' then raise exception 'Migration 034 authorization helper invalid'; end if;
  if pg_get_functiondef('public.admin_get_job_lead_detail(uuid)'::regprocedure) not ilike '%can_manage_recruitment_operations%' then raise exception 'Detail RPC authorization guard missing'; end if;
  if (select count(*) from information_schema.parameters where specific_name like 'admin_list_job_leads%' and parameter_name='p_limit')=0 then raise exception 'Job Lead bounded pagination contract missing'; end if;
  if pg_get_functiondef('public.admin_get_job_lead_detail(uuid)'::regprocedure) ilike '%phone%' or pg_get_functiondef('public.admin_get_job_lead_detail(uuid)'::regprocedure) ilike '%aadhaar%' then raise exception 'Sensitive field leaked in Job Lead detail'; end if;
  if pg_get_functiondef('public.admin_get_job_lead_detail(uuid)'::regprocedure) not ilike '%limit 50%' then raise exception 'Bounded history source missing'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-0000-0000-000000000001',true);
do $$ declare listed record; detail jsonb; begin
  select * into listed from public.admin_list_job_leads(null,null,null,null,false,null,null,false,null,null,10,0) where requirement_id='94000000-0000-0000-0002-000000000001';
  if listed.requirement_id is null or listed.requirement_code<>'PHB-REQ-001' or listed.application_count<>1 or listed.interview_count<>1 then raise exception 'Phase-B runtime list assertion failed'; end if;
  select public.admin_get_job_lead_detail('94000000-0000-0000-0002-000000000001') into detail;
  if detail->'requirement'->>'requirement_code'<>'PHB-REQ-001' or jsonb_array_length(detail->'history')>50 then raise exception 'Phase-B runtime detail assertion failed'; end if;
  if detail::text ilike '%phone%' or detail::text ilike '%aadhaar%' or detail::text ilike '%encrypted_password%' then raise exception 'Phase-B privacy assertion failed'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-0000-0000-000000000004',true);
do $$ declare raised text; begin
  begin perform public.admin_list_job_leads(null,null,null,null,false,null,null,false,null,null,10,0); raise exception 'unauthorized_list'; exception when others then raised:=sqlerrm; end;
  if raised<>'Recruitment access is required' then raise exception 'Unexpected list denial: %',raised; end if;
  begin perform public.admin_get_job_lead_detail('94000000-0000-0000-0002-000000000001'); raise exception 'unauthorized_detail'; exception when others then raised:=sqlerrm; end;
  if raised<>'Recruitment access is required' then raise exception 'Unexpected detail denial: %',raised; end if;
end $$;
reset role;
rollback;
select 'CHECKPOINT_034_STATIC_PASS' as result;
