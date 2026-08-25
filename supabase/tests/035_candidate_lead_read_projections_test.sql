-- Phase C rollback checkpoint: Candidate Lead read projections.
begin;
do $$
begin
  if to_regprocedure('public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)') is null then raise exception 'Candidate Lead list RPC missing'; end if;
  if to_regprocedure('public.admin_get_candidate_lead_detail(uuid)') is null then raise exception 'Candidate Lead detail RPC missing'; end if;
  if pg_get_functiondef('public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)'::regprocedure) not ilike '%security definer%' or pg_get_functiondef('public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)'::regprocedure) not ilike '%search_path to ''''%' then raise exception 'Candidate list security posture invalid'; end if;
  if has_function_privilege('anon','public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)','execute') or not has_function_privilege('authenticated','public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)','execute') then raise exception 'Candidate list grant matrix invalid'; end if;
  if pg_get_functiondef('public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)'::regprocedure) not ilike '%Recruitment access is required%' then raise exception 'Candidate list authorization missing'; end if;
  if pg_get_functiondef('public.admin_get_candidate_lead_detail(uuid)'::regprocedure) ilike '%mobile%' or pg_get_functiondef('public.admin_get_candidate_lead_detail(uuid)'::regprocedure) ilike '%aadhaar%' or pg_get_functiondef('public.admin_get_candidate_lead_detail(uuid)'::regprocedure) ilike '%internal_notes%' then raise exception 'Candidate detail privacy contract invalid'; end if;
  if pg_get_functiondef('public.admin_get_candidate_lead_detail(uuid)'::regprocedure) not ilike '%limit 50%' then raise exception 'Candidate history bound missing'; end if;
end $$;
create temporary table phase_c_retained_baselines as
select (select count(*) from public.candidates) candidates,(select count(*) from public.candidate_applications) applications,
       (select count(*) from public.interviews) interviews,(select count(*) from public.candidate_joinings) joinings;
do $$ begin if (select candidates from phase_c_retained_baselines) is null then raise exception 'Baseline capture failed'; end if; end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('95000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-c-admin@test.invalid','x','{}','{}',now(),now()),
       ('95000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','phase-c-viewer@test.invalid','x','{}','{}',now(),now());
insert into public.staff_profiles(user_id,display_name,status) values
 ('95000000-0000-0000-0000-000000000001','Phase C Admin','active'),('95000000-0000-0000-0000-000000000004','Phase C Viewer','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
 ('95000000-0000-0000-0000-000000000001','admin','active','95000000-0000-0000-0000-000000000001'),('95000000-0000-0000-0000-000000000004','viewer','active','95000000-0000-0000-0000-000000000001');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,interview_available,consent,status,profile_completion_status,availability_status,acquisition_source_type)
values ('95000000-0000-0000-0001-000000000001','Phase C Candidate',25,'Female','9876543290','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','complete','available','whatsapp_campaign');
insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,qualification,consent,status,requirement_code,job_location,requirement_stage,requirement_visibility,source_type)
values ('95000000-0000-0000-0002-000000000001','Phase C Company','Phase C Contact','9876543291','Chennai','Fitter',1,'ITI',true,'in_progress','PHC-REQ-001','Chennai','open','private','admin_manual');
insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_at,updated_at)
values ('95000000-0000-0000-0004-000000000001','95000000-0000-0000-0001-000000000001','95000000-0000-0000-0002-000000000001','whatsapp_campaign','applied',now(),now());
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000001',true);
do $$ declare row_data record; detail jsonb; begin
  select * into row_data from public.admin_list_candidate_leads(null,null,null,false,null,null,null,false,null,null,10,0) where candidate_id='95000000-0000-0000-0001-000000000001';
  if row_data.candidate_id is null or row_data.application_count<>1 or row_data.operational_state<>'applied' then raise exception 'Candidate Lead list runtime assertion failed'; end if;
  if not exists(select 1 from public.admin_list_candidate_leads('Phase C Candidate',null,null,false,null,null,null,false,null,null,10,0) where candidate_id=row_data.candidate_id) then raise exception 'Candidate search positive failed'; end if;
  if exists(select 1 from public.admin_list_candidate_leads('No Such Candidate',null,null,false,null,null,null,false,null,null,10,0)) then raise exception 'Candidate search negative failed'; end if;
  if not exists(select 1 from public.admin_list_candidate_leads(null,'whatsapp_campaign',null,false,'complete','applied','applied',false,current_date,current_date,1,0) where candidate_id=row_data.candidate_id) then raise exception 'Candidate filter matrix failed'; end if;
  if exists(select 1 from public.admin_list_candidate_leads(null,'admin_manual',null,false,null,null,null,false,null,null,10,0) where candidate_id=row_data.candidate_id) then raise exception 'Candidate source negative failed'; end if;
  if not exists(select 1 from public.admin_list_candidate_leads(null,null,null,true,null,null,null,false,null,null,10,0) where candidate_id=row_data.candidate_id) then raise exception 'Candidate unassigned filter failed'; end if;
  if exists(select 1 from public.admin_list_candidate_leads(null,null,null,false,null,null,'selected',false,null,null,10,0) where candidate_id=row_data.candidate_id) then raise exception 'Candidate stage negative failed'; end if;
  if (select count(*) from public.admin_list_candidate_leads(null,null,null,false,null,null,null,false,null,null,1,1))<>0 then raise exception 'Candidate pagination offset failed'; end if;
  select public.admin_get_candidate_lead_detail('95000000-0000-0000-0001-000000000001') into detail;
  if detail->'candidate'->>'full_name'<>'Phase C Candidate' or detail->'applications'->0->>'application_source'<>'whatsapp_campaign' or detail::text ilike '%mobile%' then raise exception 'Candidate Lead detail/privacy assertion failed'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000004',true);
do $$ declare message text; begin begin perform public.admin_list_candidate_leads(null,null,null,false,null,null,null,false,null,null,10,0); raise exception 'unauthorized_candidate_list'; exception when others then message:=sqlerrm; end; if message<>'Recruitment access is required' then raise exception 'Unexpected Candidate list denial: %',message; end if; begin perform public.admin_get_candidate_lead_detail('95000000-0000-0000-0000-000000000001'); raise exception 'unauthorized_candidate_detail'; exception when others then message:=sqlerrm; end; if message<>'Recruitment access is required' then raise exception 'Unexpected Candidate detail denial: %',message; end if; end $$;
reset role;
rollback;
select 'CHECKPOINT_035_STATIC_PASS' as result;
