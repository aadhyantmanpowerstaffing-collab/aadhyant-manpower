-- Run only against isolated disposable Supabase with migrations through 015.
-- All fixtures and workflow changes roll back.

\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('71000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-admin@test.local','x','{}','{}',now(),now()),
('71000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-company-a@test.local','x','{}','{}',now(),now()),
('71000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-company-b@test.local','x','{}','{}',now(),now()),
('71000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-partner-a@test.local','x','{}','{}',now(),now()),
('71000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-partner-b@test.local','x','{}','{}',now(),now()),
('71000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-nonmember@test.local','x','{}','{}',now(),now());

insert into public.admin_users(user_id) values('71000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('71000000-0000-0000-0000-000000000002','company','C1 Company A','c1-company-a@test.local','active'),
('71000000-0000-0000-0000-000000000003','company','C1 Company B','c1-company-b@test.local','active'),
('71000000-0000-0000-0000-000000000004','contractor','C1 Partner A','c1-partner-a@test.local','active'),
('71000000-0000-0000-0000-000000000005','contractor','C1 Partner B','c1-partner-b@test.local','active'),
('71000000-0000-0000-0000-000000000006','candidate','C1 Nonmember','c1-nonmember@test.local','active');

insert into public.companies(id,legal_name,main_phone,main_email,city,state,verification_status,account_status) values
('72000000-0000-0000-0000-000000000001','C1 Company A','9876540101','c1-company-a@test.local','Ahmedabad','Gujarat','verified','active'),
('72000000-0000-0000-0000-000000000002','C1 Company B','9876540102','c1-company-b@test.local','Surat','Gujarat','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
('72000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000002','owner','active'),
('72000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000003','owner','active');

insert into public.contractors(id,agency_name,main_phone,main_email,city,state,verification_status,account_status) values
('73000000-0000-0000-0000-000000000001','C1 Partner A','9876540201','c1-partner-a@test.local','Ahmedabad','Gujarat','verified','active'),
('73000000-0000-0000-0000-000000000002','C1 Partner B','9876540202','c1-partner-b@test.local','Surat','Gujarat','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('73000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000004','owner','active'),
('73000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000005','owner','active');

insert into public.employer_requirements(
  id,company_name,contact_person,mobile,email,company_location,job_role,
  required_headcount,filled_positions,consent,status,company_id,created_by_user_id,
  department,job_location,requirement_stage,requirement_visibility,internal_notes
) values
('74000000-0000-0000-0000-000000000001','C1 Company A','Private Contact A','9876540301','private-a@test.local','Ahmedabad','C1 Fitter',20,0,true,'in_progress','72000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000002','Production','Ahmedabad','open','assigned','ADMIN REQUIREMENT NOTE A'),
('74000000-0000-0000-0000-000000000002','C1 Company B','Private Contact B','9876540302','private-b@test.local','Surat','C1 Welder',10,0,true,'in_progress','72000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000003','Assembly','Surat','open','assigned','ADMIN REQUIREMENT NOTE B');

insert into public.requirement_contractors(
  id,requirement_id,contractor_id,assigned_headcount,assignment_status,assigned_by,internal_notes
) values
('75000000-0000-0000-0000-000000000001','74000000-0000-0000-0000-000000000001','73000000-0000-0000-0000-000000000001',10,'assigned','71000000-0000-0000-0000-000000000001','ADMIN ASSIGNMENT NOTE A'),
('75000000-0000-0000-0000-000000000002','74000000-0000-0000-0000-000000000002','73000000-0000-0000-0000-000000000002',5,'assigned','71000000-0000-0000-0000-000000000001','ADMIN ASSIGNMENT NOTE B');

do $$
declare
  company_result text := pg_get_function_result(to_regprocedure('public.get_company_requirements()'));
  partner_result text := pg_get_function_result(to_regprocedure('public.get_staffing_partner_assignments()'));
  company_mutation_result text := pg_get_function_result(to_regprocedure('public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)'));
begin
  if company_result ilike '%internal_notes%'
     or company_result ilike '%contact_person%'
     or company_result ilike '%created_by_user_id%' then
    raise exception 'Company projection signature exposes a private column: %', company_result;
  end if;
  if partner_result ilike '%internal_notes%'
     or partner_result ilike '%contact_person%'
     or partner_result ilike '%mobile%'
     or partner_result ilike '%email%'
     or partner_result ilike '%candidate_id%'
     or partner_result ilike '%application_id%' then
    raise exception 'Partner projection signature exposes a private column: %', partner_result;
  end if;
  if company_mutation_result ilike '%internal_notes%'
     or company_mutation_result ilike '%contact_person%'
     or company_mutation_result ilike '%company_id%' then
    raise exception 'Company mutation signature exposes a private column: %', company_mutation_result;
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000002',true);
do $$
begin
  if (select count(*) from public.get_company_requirements()) <> 1
     or not exists(select 1 from public.get_company_requirements() where id='74000000-0000-0000-0000-000000000001') then
    raise exception 'Company A safe projection failed';
  end if;
  if exists(select 1 from public.get_company_requirements() where id='74000000-0000-0000-0000-000000000002') then
    raise exception 'Company A projection returned Company B requirement';
  end if;
  if exists(select 1 from public.employer_requirements) then
    raise exception 'Company can bypass projection with a base-table read';
  end if;
  if exists(select internal_notes from public.employer_requirements where internal_notes is not null) then
    raise exception 'Company can retrieve requirement internal notes';
  end if;
  if exists(select internal_notes from public.requirement_contractors where internal_notes is not null) then
    raise exception 'Company can retrieve assignment internal notes';
  end if;
end;
$$;

select public.manage_company_requirement(
  'create',null,'C1 Department','C1 New Role','Ahmedabad',3,null,'Both','Any',null,null,
  null,null,null,null,null,'Not Applicable','Not Applicable','Not Applicable',null,null,null
);
do $$ begin
  if (select count(*) from public.get_company_requirements()) <> 2 then
    raise exception 'Company requirement creation is not visible through safe projection';
  end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000003',true);
do $$ begin
  if (select count(*) from public.get_company_requirements()) <> 1
     or not exists(select 1 from public.get_company_requirements() where id='74000000-0000-0000-0000-000000000002') then
    raise exception 'Company B isolation failed';
  end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000004',true);
do $$
begin
  if (select count(*) from public.get_staffing_partner_assignments()) <> 1
     or not exists(select 1 from public.get_staffing_partner_assignments() where id='75000000-0000-0000-0000-000000000001') then
    raise exception 'Partner A safe projection failed';
  end if;
  if exists(select 1 from public.get_staffing_partner_assignments() where id='75000000-0000-0000-0000-000000000002') then
    raise exception 'Partner A projection returned Partner B assignment';
  end if;
  if exists(select 1 from public.employer_requirements)
     or exists(select 1 from public.requirement_contractors) then
    raise exception 'Partner can bypass projection with a base-table read';
  end if;
  if exists(select internal_notes from public.employer_requirements where internal_notes is not null)
     or exists(select internal_notes from public.requirement_contractors where internal_notes is not null) then
    raise exception 'Partner can retrieve an internal note column';
  end if;
end;
$$;
select public.staffing_partner_respond_requirement_assignment('75000000-0000-0000-0000-000000000001','accepted',null);
do $$ begin
  if not exists(
    select 1 from public.get_staffing_partner_assignments()
    where id='75000000-0000-0000-0000-000000000001' and assignment_status='accepted'
  ) then raise exception 'Partner response regression'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000006',true);
do $$
begin
  begin perform 1 from public.get_company_requirements(); raise exception 'Nonmember used Company projection';
  exception when raise_exception then
    if sqlerrm = 'Nonmember used Company projection' then raise; end if;
  end;
  begin perform 1 from public.get_staffing_partner_assignments(); raise exception 'Nonmember used Partner projection';
  exception when raise_exception then
    if sqlerrm = 'Nonmember used Partner projection' then raise; end if;
  end;
  if exists(select 1 from public.employer_requirements)
     or exists(select 1 from public.requirement_contractors) then
    raise exception 'Nonmember can read tenant base data';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
do $$
begin
  if not exists(
       select 1 from public.employer_requirements
       where id='74000000-0000-0000-0000-000000000001'
         and internal_notes='ADMIN REQUIREMENT NOTE A'
     ) then raise exception 'Admin requirement-note read regressed'; end if;
  if not exists(
       select 1 from public.requirement_contractors
       where id='75000000-0000-0000-0000-000000000001'
         and internal_notes='ADMIN ASSIGNMENT NOTE A'
     ) then raise exception 'Admin assignment-note read regressed'; end if;
end;
$$;
select public.set_requirement_assignment_status('75000000-0000-0000-0000-000000000001','active');
reset role;

set local role anon;
do $$
declare denied boolean;
begin
  if has_function_privilege('anon','public.get_company_requirements()','EXECUTE')
     or has_function_privilege('anon','public.get_staffing_partner_assignments()','EXECUTE')
     or has_function_privilege('anon','public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)','EXECUTE')
     or has_function_privilege('anon','public.staffing_partner_respond_requirement_assignment(uuid,text,text)','EXECUTE') then
    raise exception 'Anonymous has tenant RPC execute privilege';
  end if;
  denied := false;
  begin perform 1 from public.employer_requirements; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous read employer requirements'; end if;
  denied := false;
  begin perform 1 from public.requirement_contractors; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous read assignments'; end if;
  if to_regprocedure('public.get_public_job_requirements(integer,integer)') is null then
    raise exception 'R10 public Jobs RPC is missing';
  end if;
end;
$$;
select count(*) from public.get_public_job_requirements(20,0);
reset role;

do $$
begin
  if has_function_privilege('authenticated','public.create_company_requirement(text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)','EXECUTE')
     or has_function_privilege('authenticated','public.update_company_requirement(uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)','EXECUTE')
     or has_function_privilege('authenticated','public.close_company_requirement(uuid)','EXECUTE')
     or has_function_privilege('authenticated','public.respond_requirement_assignment(uuid,text,text)','EXECUTE') then
    raise exception 'Authenticated can still execute a legacy full-row tenant mutation RPC';
  end if;
  if not has_function_privilege('authenticated','public.get_company_requirements()','EXECUTE')
     or not has_function_privilege('authenticated','public.get_staffing_partner_assignments()','EXECUTE')
     or not has_function_privilege('authenticated','public.manage_company_requirement(text,uuid,text,text,text,integer,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.staffing_partner_respond_requirement_assignment(uuid,text,text)','EXECUTE') then
    raise exception 'Authenticated is missing a C1 safe tenant RPC grant';
  end if;
  if to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null
     or to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') is null
     or to_regprocedure('public.admin_schedule_candidate_interview(uuid,timestamp with time zone,text,text,text,text,text,text)') is null
     or to_regprocedure('public.admin_reschedule_candidate_interview(uuid,timestamp with time zone,text,text,text,text,text,text)') is null
     or to_regprocedure('public.admin_update_candidate_interview(uuid,text,text,text)') is null then
    raise exception 'R11/R12/R13 function regression';
  end if;
  if exists(
    select 1 from pg_policies
    where schemaname='public' and policyname in (
      'M8B active company reads own requirements',
      'M8C active contractor reads assigned requirements',
      'M8C active contractor reads own assignments'
    )
  ) then raise exception 'A removed tenant base-read policy still exists'; end if;
end;
$$;

rollback;
\echo 'PRE-R14 C1 TENANT SECURITY TESTS PASSED'
