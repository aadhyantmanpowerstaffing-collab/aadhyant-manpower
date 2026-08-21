\set ON_ERROR_STOP on
begin;

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
('85000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-coverage-recruiter-a@test.local', 'x', '{}', '{}', now(), now()),
('85000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-coverage-owner-b@test.local', 'x', '{}', '{}', now(), now()),
('85000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-coverage-viewer-a@test.local', 'x', '{}', '{}', now(), now()),
('85000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'w4-coverage-zero-owner@test.local', 'x', '{}', '{}', now(), now());

insert into public.platform_users(user_id, account_type, display_name, email, account_status) values
('85000000-0000-0000-0000-000000000001', 'company', 'W4 Coverage Recruiter A', 'w4-coverage-recruiter-a@test.local', 'active'),
('85000000-0000-0000-0000-000000000002', 'company', 'W4 Coverage Owner B', 'w4-coverage-owner-b@test.local', 'active'),
('85000000-0000-0000-0000-000000000003', 'company', 'W4 Coverage Viewer A', 'w4-coverage-viewer-a@test.local', 'active'),
('85000000-0000-0000-0000-000000000004', 'company', 'W4 Coverage Zero Owner', 'w4-coverage-zero-owner@test.local', 'active');

insert into public.companies(id, legal_name, main_email, verification_status, account_status) values
('85000000-0000-0000-0001-000000000001', 'W4 Coverage Company A', 'coverage-a@test.local', 'verified', 'active'),
('85000000-0000-0000-0001-000000000002', 'W4 Coverage Company B', 'coverage-b@test.local', 'verified', 'active'),
('85000000-0000-0000-0001-000000000003', 'W4 Coverage Zero Company', 'coverage-zero@test.local', 'verified', 'active');

insert into public.company_users(company_id, user_id, role, status) values
('85000000-0000-0000-0001-000000000001', '85000000-0000-0000-0000-000000000001', 'recruiter', 'active'),
('85000000-0000-0000-0001-000000000002', '85000000-0000-0000-0000-000000000002', 'owner', 'active'),
('85000000-0000-0000-0001-000000000001', '85000000-0000-0000-0000-000000000003', 'viewer', 'active'),
('85000000-0000-0000-0001-000000000003', '85000000-0000-0000-0000-000000000004', 'owner', 'active');

insert into public.employer_requirements(
  id, company_name, contact_person, mobile, company_location, job_role, required_headcount,
  qualification, consent, status, requirement_code, company_id, created_by_user_id,
  department, job_location, filled_positions, requirement_visibility, requirement_stage
) values
('85000000-0000-0000-0002-000000000001', 'W4 Coverage Company A', 'Synthetic HR', '9876500301', 'Chennai', 'Fitter', 2,
 'ITI', true, 'new', 'W4-COV-A-DRAFT', '85000000-0000-0000-0001-000000000001', '85000000-0000-0000-0000-000000000001',
 'Production', 'Chennai', 0, 'private', 'draft'),
('85000000-0000-0000-0002-000000000002', 'W4 Coverage Company A', 'Synthetic HR', '9876500301', 'Chennai', 'Technician', 2,
 'Diploma', true, 'in_progress', 'W4-COV-A-OPEN', '85000000-0000-0000-0001-000000000001', '85000000-0000-0000-0000-000000000001',
 'Maintenance', 'Chennai', 0, 'private', 'open'),
('85000000-0000-0000-0002-000000000003', 'W4 Coverage Company B', 'Synthetic HR', '9876500302', 'Pune', 'Operator', 1,
 '12th', true, 'new', 'W4-COV-B-DRAFT', '85000000-0000-0000-0001-000000000002', '85000000-0000-0000-0000-000000000002',
 'Operations', 'Pune', 0, 'private', 'draft');

insert into public.candidates(
  id, full_name, age, gender, mobile, whatsapp_number, current_location, district, state,
  highest_qualification, specialization, candidate_type, total_experience,
  interview_available, internal_notes, consent, status
) values
('85000000-0000-0000-0003-000000000001', 'W4 Coverage Candidate Interview', 28, 'Female', '9876500401', '9876500401', 'Chennai', 'Chennai', 'Tamil Nadu',
 'Diploma', 'Technician', 'Experienced', '3 years', 'Yes', 'Private recruiter note A', true, 'new'),
('85000000-0000-0000-0003-000000000002', 'W4 Coverage Candidate Joining', 30, 'Male', '9876500402', '9876500402', 'Chennai', 'Chennai', 'Tamil Nadu',
 'ITI', 'Fitter', 'Experienced', '4 years', 'Yes', 'Private recruiter note B', true, 'new');

insert into public.candidate_applications(id, candidate_id, requirement_id, source_type, application_status, created_by) values
('85000000-0000-0000-0004-000000000001', '85000000-0000-0000-0003-000000000001', '85000000-0000-0000-0002-000000000002', 'admin', 'interview', '85000000-0000-0000-0000-000000000001'),
('85000000-0000-0000-0004-000000000002', '85000000-0000-0000-0003-000000000002', '85000000-0000-0000-0002-000000000002', 'admin', 'selected', '85000000-0000-0000-0000-000000000001');

insert into public.interviews(id, application_id, interview_round, scheduled_at, mode, location, status, created_by) values
('85000000-0000-0000-0005-000000000001', '85000000-0000-0000-0004-000000000001', 1, now() + interval '2 days', 'onsite', 'Chennai', 'scheduled', '85000000-0000-0000-0000-000000000001');

insert into public.candidate_joinings(id, application_id, expected_joining_date, joining_status, created_by) values
('85000000-0000-0000-0006-000000000001', '85000000-0000-0000-0004-000000000002', current_date + 7, 'confirmed', '85000000-0000-0000-0000-000000000001');

set local role authenticated;

-- Active Company A recruiter: portal access and requirement management, but no profile or W3 authority.
select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000001', true);
do $$
declare
  ctx record;
  changed record;
  projected record;
  detail jsonb;
begin
  select * into ctx from public.get_company_portal_context();
  if ctx.member_role <> 'recruiter' or not ctx.can_manage_requirements or ctx.can_update_profile then
    raise exception 'Active Company Recruiter context failed';
  end if;
  if (select count(*) from public.list_company_portal_requirements()) <> 2 then
    raise exception 'Active Company Recruiter own-requirement visibility failed';
  end if;

  begin
    perform public.update_company_profile('Trade', 'Industry', null, '9876500301', 'Address', 'Chennai', 'Chennai', 'Tamil Nadu', '600001', 'Synthetic HR', '11-50');
    raise exception 'Company Recruiter administered protected profile';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter administered protected profile' then raise; end if;
    if sqlerrm <> 'Company profile management access is required' then raise exception 'Unexpected Company Recruiter profile denial: %', sqlerrm; end if;
  end;

  begin
    perform public.get_company_portal_requirement('85000000-0000-0000-0002-000000000003');
    raise exception 'Company Recruiter read another company requirement';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter read another company requirement' then raise; end if;
  end;
  begin
    perform public.list_recruitment_candidates();
    raise exception 'Company Recruiter accessed internal Candidate Master';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter accessed internal Candidate Master' then raise; end if;
    if sqlerrm <> 'Recruitment access is required' then raise exception 'Unexpected Candidate Master denial: %', sqlerrm; end if;
  end;

  select * into changed from public.manage_company_portal_requirement(
    'update', '85000000-0000-0000-0002-000000000001', 'Production', 'Senior Fitter', 'Chennai', 3,
    'ITI', 'Experienced', 'Any', 20, 50, 18000, 26000, 'Day', '8 hours', null,
    'Yes', 'Yes', 'No', null, null, 'Updated by synthetic recruiter'
  );
  if changed.requirement_stage <> 'draft' then raise exception 'Authorized draft edit changed lifecycle unexpectedly'; end if;
  if (public.get_company_portal_requirement('85000000-0000-0000-0002-000000000001')->>'job_role') <> 'Senior Fitter' then
    raise exception 'Authorized draft edit did not persist inside transaction';
  end if;

  select * into changed from public.manage_company_portal_requirement('close', '85000000-0000-0000-0002-000000000001');
  if changed.requirement_stage <> 'cancelled' or changed.requirement_visibility <> 'private' then
    raise exception 'Authorized draft close did not produce terminal cancellation';
  end if;
  begin
    perform public.manage_company_portal_requirement(
      'update', '85000000-0000-0000-0002-000000000001', 'Production', 'Reopened Fitter', 'Chennai', 3,
      'ITI', 'Experienced', 'Any', 20, 50, 18000, 26000
    );
    raise exception 'Terminal requirement was edited or reopened';
  exception when raise_exception then
    if sqlerrm = 'Terminal requirement was edited or reopened' then raise; end if;
  end;
  begin
    perform public.manage_company_portal_requirement('close', '85000000-0000-0000-0002-000000000001');
    raise exception 'Terminal requirement was closed twice';
  exception when raise_exception then
    if sqlerrm = 'Terminal requirement was closed twice' then raise; end if;
  end;
  begin
    perform public.manage_company_portal_requirement('update', '85000000-0000-0000-0002-000000000003', 'Operations', 'Operator', 'Pune', 1);
    raise exception 'Company Recruiter mutated another company requirement';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter mutated another company requirement' then raise; end if;
  end;
  begin
    perform public.set_company_requirement_stage('85000000-0000-0000-0002-000000000002', 'open', 'public');
    raise exception 'Company Recruiter activated an internal requirement state';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter activated an internal requirement state' then raise; end if;
    if sqlerrm <> 'Approved administrator access is required' then raise exception 'Unexpected activation denial: %', sqlerrm; end if;
  end;

  select * into projected from public.list_company_portal_applications(null, 'interview');
  detail := public.get_company_portal_application('85000000-0000-0000-0004-000000000001');
  if to_jsonb(projected) ?| array['mobile', 'whatsapp_number', 'auth_user_id', 'candidate_id', 'internal_notes']
     or to_jsonb(projected)::text like '%9876500401%'
     or detail ?| array['mobile', 'whatsapp_number', 'auth_user_id', 'candidate_id', 'internal_notes']
     or detail::text like '%Private recruiter note%' then
    raise exception 'Focused Company candidate privacy projection failed';
  end if;

  begin
    perform public.schedule_recruitment_interview('85000000-0000-0000-0004-000000000001', now() + interval '4 days', 'onsite', 'Chennai');
    raise exception 'Company Recruiter scheduled an internal interview';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter scheduled an internal interview' then raise; end if;
    if sqlerrm <> 'Interview management access is required' then raise exception 'Unexpected schedule denial: %', sqlerrm; end if;
  end;
  begin
    perform public.reschedule_recruitment_interview('85000000-0000-0000-0005-000000000001', now() + interval '5 days', 'video');
    raise exception 'Company Recruiter rescheduled an internal interview';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter rescheduled an internal interview' then raise; end if;
    if sqlerrm <> 'Interview management access is required' then raise exception 'Unexpected reschedule denial: %', sqlerrm; end if;
  end;
  begin
    perform public.update_recruitment_interview('85000000-0000-0000-0005-000000000001', 'completed', 'selected');
    raise exception 'Company Recruiter finalized an internal interview';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter finalized an internal interview' then raise; end if;
    if sqlerrm <> 'Interview management access is required' then raise exception 'Unexpected finalization denial: %', sqlerrm; end if;
  end;
  begin
    perform public.upsert_recruitment_joining('85000000-0000-0000-0004-000000000001', current_date + 10, null, 'pending');
    raise exception 'Company Recruiter created an internal joining';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter created an internal joining' then raise; end if;
    if sqlerrm <> 'Joining management access is required' then raise exception 'Unexpected joining-create denial: %', sqlerrm; end if;
  end;
  begin
    perform public.upsert_recruitment_joining('85000000-0000-0000-0004-000000000002', current_date + 10, null, 'pending');
    raise exception 'Company Recruiter updated an internal joining';
  exception when raise_exception then
    if sqlerrm = 'Company Recruiter updated an internal joining' then raise; end if;
    if sqlerrm <> 'Joining management access is required' then raise exception 'Unexpected joining-update denial: %', sqlerrm; end if;
  end;
end;
$$;

-- Company A viewer remains unable to mutate a still-editable requirement.
select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000003', true);
do $$
begin
  begin
    perform public.manage_company_portal_requirement('update', '85000000-0000-0000-0002-000000000002', 'Maintenance', 'Technician', 'Chennai', 2);
    raise exception 'Company Viewer edited a requirement';
  exception when raise_exception then
    if sqlerrm = 'Company Viewer edited a requirement' then raise; end if;
    if sqlerrm <> 'Company requirement management access is required' then raise exception 'Unexpected Viewer denial: %', sqlerrm; end if;
  end;
end;
$$;

-- Company B resolves only its own profile and cannot see Company A interview/joining/application context.
select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000002', true);
do $$
declare
  profile record;
begin
  select * into profile from public.get_company_profile();
  if profile.legal_name <> 'W4 Coverage Company B' then raise exception 'Company B profile isolation failed'; end if;
  if (select count(*) from public.list_company_portal_interviews()) <> 0 then raise exception 'Company B saw Company A interviews'; end if;
  if (select count(*) from public.list_company_portal_joinings()) <> 0 then raise exception 'Company B saw Company A joinings'; end if;
  if (select count(*) from public.list_company_portal_applications()) <> 0 then raise exception 'Company B saw Company A applications'; end if;
  begin
    perform public.get_company_portal_application('85000000-0000-0000-0004-000000000001');
    raise exception 'Company B accessed Company A candidate history';
  exception when raise_exception then
    if sqlerrm = 'Company B accessed Company A candidate history' then raise; end if;
  end;
end;
$$;

-- Active Company C owner with no recruitment data receives a complete numeric-zero dashboard.
select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000004', true);
do $$
declare
  metrics record;
begin
  select * into metrics from public.get_company_dashboard_metrics();
  if metrics.active_requirements <> 0 or metrics.total_openings <> 0 or metrics.applications <> 0
     or metrics.screening <> 0 or metrics.shortlisted <> 0 or metrics.interviews <> 0
     or metrics.selected <> 0 or metrics.joining_pending <> 0 or metrics.joined <> 0 then
    raise exception 'Zero-data Company dashboard did not return all numeric zeros';
  end if;
end;
$$;

rollback;
