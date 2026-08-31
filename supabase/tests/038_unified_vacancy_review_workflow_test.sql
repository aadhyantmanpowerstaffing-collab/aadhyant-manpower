-- Batch 2 checkpoint: unified Company/Contractor vacancy review and publication.
-- Fixtures are entirely transaction-local; this file must end in ROLLBACK.
\set ON_ERROR_STOP on
begin;

do $$
declare signature text;
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='employer_requirements'
    and column_name in ('review_status','review_feedback','submitted_at','reviewed_at','reviewed_by') group by table_name having count(*)=5)
     or not exists(select 1 from pg_constraint where conname='employer_requirements_review_status_check') then
    raise exception 'Checkpoint 038 Company review columns or constraint are missing';
  end if;
  foreach signature in array array[
    'public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)',
    'public.admin_list_vacancy_reviews(text,text,integer,integer)',
    'public.admin_get_vacancy_review_detail(uuid)',
    'public.admin_approve_and_publish_vacancy(uuid,timestamp with time zone)',
    'public.admin_request_vacancy_correction(uuid,text,timestamp with time zone)',
    'public.admin_reject_vacancy(uuid,text,timestamp with time zone)'
  ] loop
    if to_regprocedure(signature) is null or not has_function_privilege('authenticated',signature,'execute')
       or has_function_privilege('anon',signature,'execute') then
      raise exception 'Checkpoint 038 canonical RPC grant is invalid for %',signature;
    end if;
    if pg_get_functiondef(to_regprocedure(signature)) not ilike '%security definer%'
       or pg_get_functiondef(to_regprocedure(signature)) not ilike '%set search_path to ''''%' then
      raise exception 'Checkpoint 038 SECURITY DEFINER posture is invalid for %',signature;
    end if;
  end loop;
  foreach signature in array array[
    'private.normalized_vacancy_review_status(uuid)',
    'private.vacancy_is_application_eligible(uuid)',
    'private.can_review_vacancies()'
  ] loop
    if has_function_privilege('authenticated',signature,'execute') or has_function_privilege('anon',signature,'execute') then
      raise exception 'Checkpoint 038 private helper is browser-accessible: %',signature;
    end if;
  end loop;
  if not exists(select 1 from pg_trigger where tgname='candidate_applications_require_approved_public_vacancy' and not tgisinternal)
     or not exists(select 1 from pg_trigger where tgname='whatsapp_campaigns_require_approved_public_vacancy' and not tgisinternal) then
    raise exception 'Checkpoint 038 application or matching gate trigger is missing';
  end if;
end;
$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('98000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b39-admin@test.invalid','x','{}','{}',now(),now()),
('98000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b39-company@test.invalid','x','{}','{}',now(),now()),
('98000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b39-contractor@test.invalid','x','{}','{}',now(),now()),
('98000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b39-other-company@test.invalid','x','{}','{}',now(),now());
insert into public.admin_users(user_id) values('98000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('98000000-0000-0000-0000-000000000002','company','Batch 039 Company','9876509802','b39-company@test.invalid','active'),
('98000000-0000-0000-0000-000000000003','contractor','Batch 039 Contractor','9876509803','b39-contractor@test.invalid','active'),
('98000000-0000-0000-0000-000000000004','company','Batch 039 Other Company','9876509804','b39-other-company@test.invalid','active');
insert into public.companies(id,legal_name,trade_name,main_phone,main_email,city,state,verification_status,account_status) values
('98000000-0000-0000-0001-000000000001','Batch 039 Company Private Limited','Batch 039 Company','9876509802','b39-company@test.invalid','Ahmedabad','Gujarat','verified','active'),
('98000000-0000-0000-0001-000000000002','Batch 039 Other Company Private Limited','Batch 039 Other','9876509804','b39-other-company@test.invalid','Surat','Gujarat','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
('98000000-0000-0000-0001-000000000001','98000000-0000-0000-0000-000000000002','owner','active'),
('98000000-0000-0000-0001-000000000002','98000000-0000-0000-0000-000000000004','owner','active');
insert into public.contractors(id,agency_name,owner_name,main_phone,main_email,verification_status,account_status) values
('98000000-0000-0000-0001-000000000003','Batch 039 Staffing','Staffing Owner','9876509803','b39-contractor@test.invalid','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('98000000-0000-0000-0001-000000000003','98000000-0000-0000-0000-000000000003','owner','active');

do $$
declare company_requirement uuid; contractor_requirement uuid; detail jsonb; result record;
begin
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000002',true);
  select * into result from public.manage_company_portal_vacancy('create',null,'Production','Batch 039 Fitter','Ahmedabad',2,'ITI','Fitter','Both','Any',18,55,180000,240000,'Day','8 hours','As applicable','Yes','No','No','Ahmedabad',null,current_date+10,'Fixture') limit 1;
  company_requirement:=result.id;
  if result.review_status<>'draft' or result.requirement_stage<>'draft' or result.requirement_visibility<>'private' then raise exception 'Company draft contract failed'; end if;
  select * into result from public.manage_company_portal_vacancy('submit',company_requirement) limit 1;
  if result.review_status<>'pending_review' or result.requirement_stage<>'draft' or result.requirement_visibility<>'private' then raise exception 'Company submit contract failed'; end if;
  if (select count(*) from public.list_company_portal_vacancy_reviews(null,'pending_review',25,0) where requirement_id=company_requirement)=1 then
    null;
  else raise exception 'Company review-list projection failed'; end if;
  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000004',true);
  begin
    perform public.manage_company_portal_vacancy('update',company_requirement,'X','X','X',1,'ITI','Fitter','Both','Any',null,null,null,null,null,null,null,'No','No','No',null,null,null,null);
    raise exception 'Cross-tenant Company edit succeeded';
  exception when others then if sqlerrm like 'Cross-tenant%' then raise; end if; end;
  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000001',true);
  detail:=public.admin_request_vacancy_correction(company_requirement,'Add shift confirmation',null);
  if detail#>>'{review,normalized_status}'<>'correction_required' or detail#>>'{lifecycle,requirement_visibility}'<>'private' then raise exception 'Correction contract failed'; end if;
  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000002',true);
  select * into result from public.manage_company_portal_vacancy('resubmit',company_requirement) limit 1;
  if result.review_status<>'pending_review' then raise exception 'Company resubmit contract failed'; end if;
  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000001',true);
  detail:=public.admin_approve_and_publish_vacancy(company_requirement,null);
  if detail#>>'{review,normalized_status}'<>'approved' or detail#>>'{lifecycle,requirement_stage}'<>'open' or detail#>>'{lifecycle,requirement_visibility}'<>'public'
     or detail#>>'{vacancy,job_role}'<>'Batch 039 Fitter' then raise exception 'Approve and full-detail contract failed'; end if;

  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000003',true);
  select * into result from public.manage_contractor_portal_vacancy('create_and_submit',null,'Batch 039 Client','Fabrication','Batch 039 Welder','Vadodara',3,'ITI','Welder','Experienced','Any',20,50,200000,280000,'Night','8 hours','As applicable','Yes','Yes','No','Vadodara',current_date+15,'Fixture') limit 1;
  contractor_requirement:=result.id;
  if result.submission_status<>'submitted' or result.requirement_stage<>'draft' then raise exception 'Contractor submit contract failed'; end if;
  perform set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000001',true);
  detail:=public.admin_reject_vacancy(contractor_requirement,'Insufficient worksite details',null);
  if detail#>>'{review,normalized_status}'<>'rejected' or detail#>>'{lifecycle,requirement_visibility}'<>'private' then raise exception 'Reject contract failed'; end if;
  begin
    perform public.admin_approve_and_publish_vacancy(contractor_requirement,null);
    raise exception 'Rejected vacancy was republished';
  exception when others then if sqlerrm like 'Rejected vacancy%' then raise; end if; end;
  if (select count(*) from public.admin_list_vacancy_reviews('pending_review',null,50,0) where requirement_id in (company_requirement,contractor_requirement))<>0 then
    raise exception 'Review queue contains finalized fixture vacancy'; end if;
end;
$$;

do $$
begin
  if (select count(*) from public.employer_requirements
      where job_role in ('Batch 039 Fitter','Batch 039 Welder'))<>2
     or (select count(*) from public.audit_logs l
         join public.employer_requirements r on r.id=l.entity_id
         where l.entity_type='employer_requirement'
           and r.job_role in ('Batch 039 Fitter','Batch 039 Welder'))<5 then
    raise exception 'Checkpoint 038 fixture/audit assertions failed';
  end if;
  raise notice 'CHECKPOINT_038_UNIFIED_VACANCY_REVIEW_PASS';
end;
$$;

rollback;
