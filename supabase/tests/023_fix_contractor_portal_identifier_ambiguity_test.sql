\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('87000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-fix-owner-a@test.local','x','{}','{}',now(),now()),
('87000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-fix-owner-b@test.local','x','{}','{}',now(),now()),
('87000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w5-fix-denied@test.local','x','{}','{}',now(),now());
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('87000000-0000-0000-0000-000000000001','contractor','W5 Fix Owner A','w5-fix-owner-a@test.local','active'),
('87000000-0000-0000-0000-000000000002','contractor','W5 Fix Owner B','w5-fix-owner-b@test.local','active');
insert into public.contractors(id,agency_name,owner_name,main_phone,main_email,city,state,verification_status,account_status) values
('87000000-0000-0000-0001-000000000001','W5 Fix Contractor A','Synthetic Owner A','9876500701','a@test.local','Chennai','Tamil Nadu','verified','active'),
('87000000-0000-0000-0001-000000000002','W5 Fix Contractor B','Synthetic Owner B','9876500702','b@test.local','Pune','Maharashtra','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('87000000-0000-0000-0001-000000000001','87000000-0000-0000-0000-000000000001','owner','active'),
('87000000-0000-0000-0001-000000000002','87000000-0000-0000-0000-000000000002','owner','active');

set local role authenticated;
select set_config('request.jwt.claim.sub','87000000-0000-0000-0000-000000000001',true);
do $$ declare created record;begin
  select * into created from public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Synthetic Client',p_job_role=>'Fitter',p_job_location=>'Chennai',p_required_headcount=>3,p_qualification=>'ITI');
  if created.submission_status<>'draft' or created.requirement_stage<>'draft' then raise exception 'Corrected vacancy creation failed';end if;
  if (select count(*) from public.employer_requirements r where r.id=created.id and r.created_by_user_id=(select auth.uid()) and r.company_id is null and r.requirement_visibility='private')<>1 then raise exception 'Canonical requirement ownership failed';end if;
  if (select count(*) from public.requirement_contractors link where link.requirement_id=created.id and link.contractor_id='87000000-0000-0000-0001-000000000001' and link.origin_type='contractor_submission' and link.submission_status='draft')<>1 then raise exception 'Contractor linkage failed';end if;
  perform public.manage_contractor_portal_vacancy(p_action=>'submit',p_requirement_id=>created.id);
  begin perform public.review_contractor_vacancy(created.id,'approve',null);raise exception 'Contractor self-approved';exception when raise_exception then if sqlerrm='Contractor self-approved' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','87000000-0000-0000-0000-000000000002',true);
do $$ declare target uuid;begin
  select r.id into target from public.employer_requirements r where r.created_by_user_id='87000000-0000-0000-0000-000000000001';
  begin perform public.manage_contractor_portal_vacancy(p_action=>'update',p_requirement_id=>target,p_client_name=>'Spoof',p_job_role=>'Fitter',p_job_location=>'Pune',p_required_headcount=>1);raise exception 'Contractor B mutated Contractor A';exception when raise_exception then if sqlerrm='Contractor B mutated Contractor A' then raise;end if;end;
end $$;

select set_config('request.jwt.claim.sub','87000000-0000-0000-0000-000000000003',true);
do $$ begin
  begin perform public.manage_contractor_portal_vacancy(p_action=>'create',p_client_name=>'Denied',p_job_role=>'Fitter',p_job_location=>'Pune',p_required_headcount=>1);raise exception 'Non-member created vacancy';exception when raise_exception then if sqlerrm='Non-member created vacancy' then raise;end if;end;
end $$;

rollback;
