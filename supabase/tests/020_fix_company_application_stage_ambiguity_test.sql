\set ON_ERROR_STOP on
begin;

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
('84000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-fix-company-a@test.local', 'x', '{}', '{}', now(), now()),
('84000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-fix-company-b@test.local', 'x', '{}', '{}', now(), now()),
('84000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-fix-nonmember@test.local', 'x', '{}', '{}', now(), now());

insert into public.platform_users(user_id, account_type, display_name, email, account_status) values
('84000000-0000-0000-0000-000000000001', 'company', 'W4 Fix Company A', 'w4-fix-company-a@test.local', 'active'),
('84000000-0000-0000-0000-000000000002', 'company', 'W4 Fix Company B', 'w4-fix-company-b@test.local', 'active');

insert into public.companies(id, legal_name, verification_status, account_status) values
('84000000-0000-0000-0001-000000000001', 'W4 Fix Company A', 'verified', 'active'),
('84000000-0000-0000-0001-000000000002', 'W4 Fix Company B', 'verified', 'active');

insert into public.company_users(company_id, user_id, role, status) values
('84000000-0000-0000-0001-000000000001', '84000000-0000-0000-0000-000000000001', 'hr_admin', 'active'),
('84000000-0000-0000-0001-000000000002', '84000000-0000-0000-0000-000000000002', 'owner', 'active');

insert into public.employer_requirements(
  id, company_name, contact_person, mobile, company_location, job_role, required_headcount,
  qualification, consent, status, requirement_code, company_id, created_by_user_id,
  job_location, filled_positions, requirement_visibility, requirement_stage
) values
('84000000-0000-0000-0002-000000000001', 'W4 Fix Company A', 'Synthetic HR', '9876500101', 'Chennai', 'Fitter', 2,
 'ITI', true, 'in_progress', 'W4-FIX-A-001', '84000000-0000-0000-0001-000000000001', '84000000-0000-0000-0000-000000000001',
 'Chennai', 0, 'private', 'open'),
('84000000-0000-0000-0002-000000000002', 'W4 Fix Company B', 'Synthetic HR', '9876500102', 'Pune', 'Operator', 1,
 '12th', true, 'in_progress', 'W4-FIX-B-001', '84000000-0000-0000-0001-000000000002', '84000000-0000-0000-0000-000000000002',
 'Pune', 0, 'private', 'open');

insert into public.candidates(
  id, full_name, age, gender, mobile, whatsapp_number, current_location, district, state,
  highest_qualification, specialization, candidate_type, total_experience,
  interview_available, internal_notes, consent, status
) values
('84000000-0000-0000-0003-000000000001', 'W4 Fix Candidate A', 27, 'Female', '9876500201', '9876500201', 'Chennai', 'Chennai', 'Tamil Nadu',
 'ITI', 'Fitter', 'Experienced', '2 years', 'Yes', 'Must remain private', true, 'new'),
('84000000-0000-0000-0003-000000000002', 'W4 Fix Candidate B', 29, 'Male', '9876500202', '9876500202', 'Pune', 'Pune', 'Maharashtra',
 '12th', 'Operator', 'Fresher', null, 'Yes', 'Must remain private', true, 'new');

insert into public.candidate_applications(id, candidate_id, requirement_id, source_type, application_status, created_by) values
('84000000-0000-0000-0004-000000000001', '84000000-0000-0000-0003-000000000001', '84000000-0000-0000-0002-000000000001', 'admin', 'screening', '84000000-0000-0000-0000-000000000001'),
('84000000-0000-0000-0004-000000000002', '84000000-0000-0000-0003-000000000002', '84000000-0000-0000-0002-000000000002', 'admin', 'applied', '84000000-0000-0000-0000-000000000002');

set local role authenticated;

select set_config('request.jwt.claim.sub', '84000000-0000-0000-0000-000000000001', true);
do $$
declare
  item record;
begin
  if (select count(*) from public.list_company_portal_applications()) <> 1 then
    raise exception 'Unfiltered Company A application listing failed';
  end if;
  if (select count(*) from public.list_company_portal_applications(null, 'screening')) <> 1 then
    raise exception 'Canonical stage filtering failed';
  end if;
  if (select count(*) from public.list_company_portal_applications(null, 'applied')) <> 0 then
    raise exception 'Stage filtering crossed application scope';
  end if;
  select * into item from public.list_company_portal_applications();
  if item.candidate_name <> 'W4 Fix Candidate A'
     or item.application_stage <> 'screening'
     or item.requirement_code <> 'W4-FIX-A-001' then
    raise exception 'Company-safe application projection changed';
  end if;
  if to_jsonb(item) ?| array['mobile', 'whatsapp_number', 'auth_user_id', 'internal_notes', 'candidate_id']
     or to_jsonb(item)::text like '%Must remain private%'
     or to_jsonb(item)::text like '%9876500201%' then
    raise exception 'Company application projection exposes a restricted column';
  end if;
  begin
    perform public.list_company_portal_applications('84000000-0000-0000-0002-000000000002');
    raise exception 'Company A accessed Company B applications';
  exception
    when raise_exception then
      if sqlerrm = 'Company A accessed Company B applications' then raise; end if;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '84000000-0000-0000-0000-000000000002', true);
do $$
begin
  if (select count(*) from public.list_company_portal_applications()) <> 1 then
    raise exception 'Company B own application listing failed';
  end if;
  if exists (
    select 1 from public.list_company_portal_applications()
    where requirement_code = 'W4-FIX-A-001'
  ) then
    raise exception 'Company B saw Company A application data';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '84000000-0000-0000-0000-000000000003', true);
do $$
begin
  begin
    perform public.list_company_portal_applications();
    raise exception 'Non-member accessed Company Portal applications';
  exception
    when raise_exception then
      if sqlerrm = 'Non-member accessed Company Portal applications' then raise; end if;
  end;
end;
$$;

rollback;
