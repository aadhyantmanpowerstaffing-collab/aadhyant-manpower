-- Run only against an isolated disposable Supabase database with migrations through 011.
-- The transaction rolls back every fixture and test-only grant change.

begin;

do $$
begin
  if to_regprocedure('public.get_public_job_requirements(integer,integer)') is null then
    raise exception 'R10 function is missing';
  end if;
end;
$$;

insert into public.employer_requirements (
  company_name, contact_person, mobile, email, company_location,
  job_role, required_headcount, qualification, experience_requirement,
  salary_wage, shift_details, consent, status, department, job_location,
  filled_positions, salary_min, salary_max, requirement_visibility,
  requirement_stage, published_at, internal_notes
) values
  ('R10 Private Company', 'Private Contact', '9876500001', 'private-r10@example.invalid', 'Private Location',
   'Private Role', 10, 'ITI', 'Experienced', 'Private salary', 'Day', true, 'new', 'Private Department', 'Private Job Location',
   0, 10000, 12000, 'private', 'open', now(), 'R10 private internal note'),
  ('R10 Draft Company', 'Draft Contact', '9876500002', 'draft-r10@example.invalid', 'Draft Location',
   'Draft Role', 10, 'ITI', 'Fresher', 'Draft salary', 'Day', true, 'new', 'Draft Department', 'Draft Job Location',
   0, 10000, 12000, 'public', 'draft', now(), 'R10 draft internal note'),
  ('R10 Closed Company', 'Closed Contact', '9876500003', 'closed-r10@example.invalid', 'Closed Location',
   'Closed Role', 10, 'ITI', 'Both', 'Closed salary', 'Night', true, 'closed', 'Closed Department', 'Closed Job Location',
   0, 10000, 12000, 'public', 'closed', now(), 'R10 closed internal note'),
  ('R10 Public Company', 'Public Contact', '9876500004', 'public-r10@example.invalid', 'Public Company Location',
   'R10 Public Fitter', 10, 'ITI', 'Experienced', '10000 - 12000', 'Day', true, 'in_progress', 'Production', 'R10 Public Job Location',
   3, 10000, 12000, 'public', 'open', now(), 'R10 secret internal note');

set local role anon;

do $$
declare
  public_count integer;
  projected record;
  base_read_denied boolean := false;
  candidates_read_denied boolean := false;
  assignments_read_denied boolean := false;
begin
  begin
    perform 1 from public.employer_requirements limit 1;
  exception when insufficient_privilege then
    base_read_denied := true;
  end;
  if not base_read_denied then
    raise exception 'anon unexpectedly read employer_requirements directly';
  end if;

  begin
    perform 1 from public.candidates limit 1;
  exception when insufficient_privilege then
    candidates_read_denied := true;
  end;
  if not candidates_read_denied then
    raise exception 'anon unexpectedly read candidates directly';
  end if;

  begin
    perform 1 from public.requirement_contractors limit 1;
  exception when insufficient_privilege then
    assignments_read_denied := true;
  end;
  if not assignments_read_denied then
    raise exception 'anon unexpectedly read requirement assignments directly';
  end if;

  select count(*) into public_count
  from public.get_public_job_requirements(50, 0)
  where job_role = 'R10 Public Fitter';
  if public_count <> 1 then
    raise exception 'projection expected one R10 public/open row, received %', public_count;
  end if;

  if exists (
    select 1 from public.get_public_job_requirements(50, 0)
    where job_role in ('Private Role', 'Draft Role', 'Closed Role')
  ) then
    raise exception 'private, draft, or closed fixture leaked through the projection';
  end if;

  select * into projected
  from public.get_public_job_requirements(50, 0)
  where job_role = 'R10 Public Fitter';
  if projected.open_positions <> 7
     or projected.job_location <> 'R10 Public Job Location'
     or projected.requirement_code is null then
    raise exception 'public projection values are incorrect';
  end if;

  if (select count(*) from public.get_public_job_requirements(100000, 0)) > 50 then
    raise exception 'public page-size maximum was not enforced';
  end if;

  if exists (
    select 1 from information_schema.parameters
    where specific_schema = 'public'
      and specific_name like 'get_public_job_requirements_%'
      and parameter_mode = 'OUT'
      and parameter_name = any(array[
        'id', 'company_id', 'created_by_user_id', 'company_name', 'contact_person',
        'mobile', 'email', 'internal_notes', 'additional_notes'
      ])
  ) then
    raise exception 'sensitive field appears in the public function signature';
  end if;
end;
$$;

reset role;

do $$
begin
  if not has_function_privilege('anon', 'public.get_public_job_requirements(integer,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_public_job_requirements(integer,integer)', 'EXECUTE') then
    raise exception 'expected execute grants are missing';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'employer_requirements'
      and 'anon' = any(roles) and cmd = 'SELECT'
  ) then
    raise exception 'anonymous base-table SELECT policy must remain absent';
  end if;
  if exists (select 1 from pg_policies where schemaname='public' and tablename='employer_requirements'
       and policyname in ('M8B active company reads own requirements','M8C active contractor reads assigned requirements'))
     or exists (select 1 from pg_policies where schemaname='public' and tablename='requirement_contractors'
       and policyname='M8C active contractor reads own assignments') then
    raise exception 'migration 015 tenant base-read policy was reintroduced';
  end if;
  if to_regprocedure('public.get_company_requirements()') is null
     or to_regprocedure('public.get_staffing_partner_assignments()') is null then
    raise exception 'migration 015 tenant projection RPC is missing';
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='employer_requirements'
       and policyname='Admins can read employer requirements') then
    raise exception 'compatible Admin requirement-read policy is missing';
  end if;
end;
$$;

rollback;
