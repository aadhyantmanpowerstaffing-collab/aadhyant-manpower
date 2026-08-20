-- Run only against isolated disposable Supabase with migrations through 018.
-- All W3 identities and recruitment fixtures roll back.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('82000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-bootstrap@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-super@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-admin@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-recruiter@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-operations@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-viewer@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-inactive@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-nonmember@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-company@test.local','x','{}','{}',now(),now()),
('82000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w3-contractor@test.local','x','{}','{}',now(),now());

insert into public.admin_users(user_id) values('82000000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values
('82000000-0000-0000-0000-000000000002','W3 Super','active'),
('82000000-0000-0000-0000-000000000003','W3 Admin','active'),
('82000000-0000-0000-0000-000000000004','W3 Recruiter','active'),
('82000000-0000-0000-0000-000000000005','W3 Operations','active'),
('82000000-0000-0000-0000-000000000006','W3 Viewer','active'),
('82000000-0000-0000-0000-000000000007','W3 Inactive','suspended');
insert into public.staff_roles(user_id,role,status,granted_by) values
('82000000-0000-0000-0000-000000000002','super_admin','active','82000000-0000-0000-0000-000000000001'),
('82000000-0000-0000-0000-000000000003','admin','active','82000000-0000-0000-0000-000000000001'),
('82000000-0000-0000-0000-000000000004','recruiter','active','82000000-0000-0000-0000-000000000001'),
('82000000-0000-0000-0000-000000000005','operations','active','82000000-0000-0000-0000-000000000001'),
('82000000-0000-0000-0000-000000000006','viewer','active','82000000-0000-0000-0000-000000000001'),
('82000000-0000-0000-0000-000000000007','viewer','active','82000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('82000000-0000-0000-0000-000000000009','company','W3 Company','w3-company@test.local','active'),
('82000000-0000-0000-0000-000000000010','contractor','W3 Contractor','w3-contractor@test.local','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,
  specialization,candidate_type,interview_available,consent,status)
values('82000000-0000-0000-0001-000000000001','W3 Candidate',24,'Female','9876543210','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new');
insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,consent,status,requirement_code,job_location,requirement_stage,requirement_visibility)
values('82000000-0000-0000-0002-000000000001','W3 Company A','W3 Contact','9876543211','Chennai','Fitter',5,
  'ITI',true,'in_progress','W3-REQ-001','Chennai','open','private');

do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname like 'can_%recruitment%' and p.prosecdef
        and exists(select 1 from unnest(p.proconfig) c where c='search_path=')) <> 1 then
    -- The remaining helpers use domain-specific names; validate all six explicitly below.
    null;
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname in ('is_bootstrap_recruitment_admin','can_view_recruitment',
        'can_manage_candidates','can_manage_applications','can_manage_interviews','can_manage_joinings')
        and p.prosecdef and exists(select 1 from unnest(p.proconfig) c where c='search_path=')) <> 6 then
    raise exception 'W3 private helper security configuration is invalid';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('get_recruitment_permissions','get_recruitment_dashboard',
        'list_recruitment_candidates','get_recruitment_candidate','update_recruitment_candidate',
        'list_recruitment_requirements','create_recruitment_application','list_recruitment_applications',
        'get_recruitment_application','transition_recruitment_application','list_recruitment_interviews',
        'schedule_recruitment_interview','update_recruitment_interview','reschedule_recruitment_interview',
        'list_recruitment_joinings','upsert_recruitment_joining')
        and p.prosecdef and exists(select 1 from unnest(p.proconfig) c where c='search_path=')) <> 16 then
    raise exception 'W3 RPC security configuration is invalid';
  end if;
  if has_function_privilege('anon','public.get_recruitment_dashboard()','EXECUTE')
     or has_function_privilege('anon','public.list_recruitment_candidates(text,text,text,text,text,text,integer,integer)','EXECUTE')
     or has_function_privilege('authenticated','private.can_view_recruitment()','EXECUTE') then
    raise exception 'W3 grant boundary is invalid';
  end if;
  if has_table_privilege('authenticated','public.audit_logs','INSERT') then raise exception 'Browser can forge W3 audit rows'; end if;
end;
$$;

-- Recruiter: projected read, candidate mutation, matching, stage, and interview.
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000004',true);
do $$ declare p record; app uuid; interview uuid; begin
  select * into p from public.get_recruitment_permissions();
  if not p.view_access or not p.candidate_mutation or not p.application_mutation or not p.interview_mutation or p.joining_mutation then
    raise exception 'Recruiter permission matrix failed'; end if;
  if (select count(*) from public.list_recruitment_candidates())<>1 then raise exception 'Recruiter candidate read failed'; end if;
  perform public.update_recruitment_candidate('82000000-0000-0000-0001-000000000001','contacted','Yes','Safe note',null);
  app:=public.create_recruitment_application('82000000-0000-0000-0001-000000000001','82000000-0000-0000-0002-000000000001','manual',null);
  begin perform public.create_recruitment_application('82000000-0000-0000-0001-000000000001','82000000-0000-0000-0002-000000000001',null,null); raise exception 'Duplicate application succeeded';
  exception when raise_exception then if sqlerrm='Duplicate application succeeded' then raise; end if; end;
  perform public.transition_recruitment_application(app,'screening','Reviewed',null,null);
  perform public.transition_recruitment_application(app,'shortlisted','Qualified',null,null);
  interview:=public.schedule_recruitment_interview(app,now()+interval '2 days','onsite','Chennai','Bring resume',null);
  if interview is null then raise exception 'Recruiter interview scheduling failed'; end if;
  interview:=public.reschedule_recruitment_interview(interview,now()+interval '3 days','video',null,'Updated round',null);
  perform public.update_recruitment_interview(interview,'completed','selected','Passed',null);
  begin perform public.transition_recruitment_application(app,'joining_pending',null,null,null); raise exception 'Recruiter bypassed joining workflow';
  exception when raise_exception then if sqlerrm='Recruiter bypassed joining workflow' then raise; end if; end;
  begin perform public.upsert_recruitment_joining(app,current_date+7,null,'pending',null,null,null); raise exception 'Recruiter managed joining';
  exception when raise_exception then if sqlerrm='Recruiter managed joining' then raise; end if; end;
end $$;
reset role;

do $$ begin
  if not exists(select 1 from public.application_stage_history where application_id in
    (select id from public.candidate_applications where candidate_id='82000000-0000-0000-0001-000000000001') and to_stage='selected') then
    raise exception 'Automatic stage history was not recorded'; end if;
end $$;

-- Operations: selected context and joining mutation only.
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000005',true);
do $$ declare p record; app uuid; joining uuid; begin
  select * into p from public.get_recruitment_permissions();
  if not p.view_access or p.candidate_mutation or p.application_mutation or p.interview_mutation or not p.joining_mutation then
    raise exception 'Operations permission matrix failed'; end if;
  select id into app from public.candidate_applications where candidate_id='82000000-0000-0000-0001-000000000001';
  if (select count(*) from public.list_recruitment_candidates())<>1 then raise exception 'Operations selected scope failed'; end if;
  joining:=public.upsert_recruitment_joining(app,current_date+7,null,'confirmed',null,'Confirmed',null);
  if joining is null then raise exception 'Operations joining create failed'; end if;
  perform public.upsert_recruitment_joining(app,current_date+7,current_date+7,'joined','W3-EMP-1','Joined',null);
  begin perform public.upsert_recruitment_joining(app,current_date+7,null,'pending',null,null,null); raise exception 'Joined placement regressed to pending';
  exception when raise_exception then if sqlerrm='Joined placement regressed to pending' then raise; end if; end;
  begin perform public.update_recruitment_candidate('82000000-0000-0000-0001-000000000001','selected','Yes',null,null); raise exception 'Operations mutated candidate';
  exception when raise_exception then if sqlerrm='Operations mutated candidate' then raise; end if; end;
end $$;
reset role;

do $$ declare interview uuid; begin
  select id into interview from public.interviews where status='completed' limit 1;
  if interview is null then raise exception 'Completed interview fixture missing'; end if;
  perform set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000004',true);
  begin perform public.update_recruitment_interview(interview,'cancelled','selected',null,null); raise exception 'Final interview accepted contradictory result';
  exception when raise_exception then if sqlerrm='Final interview accepted contradictory result' then raise; end if; end;
end $$;

-- Viewer: projected reads, no mutation and no candidate PII.
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-0000-0000-000000000006',true);
do $$ declare p record; detail jsonb; begin
  select * into p from public.get_recruitment_permissions();
  if not p.view_access or p.candidate_mutation or p.application_mutation or p.interview_mutation or p.joining_mutation or p.pii_detail_access then
    raise exception 'Viewer permission matrix failed'; end if;
  detail:=public.get_recruitment_candidate('82000000-0000-0000-0001-000000000001');
  if detail->'mobile' <> 'null'::jsonb or detail->'whatsapp_number' <> 'null'::jsonb then raise exception 'Viewer received candidate contact PII'; end if;
  begin perform public.transition_recruitment_application((select id from public.candidate_applications limit 1),'joining_pending',null,null,null); raise exception 'Viewer transitioned application';
  exception when raise_exception then if sqlerrm='Viewer transitioned application' then raise; end if; end;
end $$;
reset role;

-- Bootstrap, super-admin, and admin retain full operations authority.
do $$ declare actor uuid; p record; begin
  foreach actor in array array['82000000-0000-0000-0000-000000000001'::uuid,'82000000-0000-0000-0000-000000000002'::uuid,'82000000-0000-0000-0000-000000000003'::uuid] loop
    perform set_config('request.jwt.claim.sub',actor::text,true); select * into p from public.get_recruitment_permissions();
    if not (p.view_access and p.candidate_mutation and p.application_mutation and p.interview_mutation and p.joining_mutation and p.pii_detail_access) then
      raise exception 'Full operations authority failed for %',actor; end if;
  end loop;
end $$;

-- Inactive, non-member, company, contractor, and anonymous are denied.
do $$ declare actor text; begin
  foreach actor in array array['82000000-0000-0000-0000-000000000007','82000000-0000-0000-0000-000000000008',
    '82000000-0000-0000-0000-000000000009','82000000-0000-0000-0000-000000000010',''] loop
    perform set_config('request.jwt.claim.sub',actor,true);
    begin perform public.get_recruitment_dashboard(); raise exception 'Unauthorized W3 access succeeded for %',actor;
    exception when raise_exception then if sqlerrm like 'Unauthorized W3 access succeeded%' then raise; end if; end;
  end loop;
end $$;

-- W2 staff-management and migration 015 tenant contracts remain installed.
do $$ begin
  if to_regprocedure('public.list_internal_staff()') is null
     or to_regprocedure('public.get_company_requirements()') is null
     or to_regprocedure('public.get_staffing_partner_assignments()') is null then
    raise exception 'W2 or tenant regression contract disappeared'; end if;
end $$;

rollback;
