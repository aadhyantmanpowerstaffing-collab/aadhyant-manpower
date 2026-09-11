-- Batch 2 corrective migration: remove Candidate opportunity projection identifier ambiguity.
-- Migration 044 is installed and immutable. This preserves the Candidate-only
-- signature, approved/open/public/capacity predicate, safe return shape, and
-- candidate-specific application state while using unambiguous local names.
begin;

create or replace function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,company_worksite_name text,department text,job_location text,open_positions integer,
  qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,
  payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,
  employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,
  gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,
  shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,accommodation_status text,
  accommodation_charge_amount numeric,accommodation_charge_basis text,interview_location text,interview_date timestamptz,expected_joining_date date,
  safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_candidate_id uuid := (select private.current_candidate_portal_id()); v_term text := nullif(btrim(p_search),'');
begin
  if v_candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,r.company_name,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,
    r.qualification,r.iti_trade,r.experience_requirement,r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,
    r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,
    r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,r.bonus_provision,
    r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,
    r.accommodation,r.accommodation_status,r.accommodation_charge_amount,r.accommodation_charge_basis,r.interview_location,r.interview_date,
    r.expected_joining_date,r.additional_notes,
    exists(select 1 from public.candidate_applications a where a.candidate_id=v_candidate_id and a.requirement_id=r.id)
  from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null
    and (v_term is null or r.requirement_code ilike '%'||v_term||'%' or r.job_role ilike '%'||v_term||'%' or coalesce(r.job_location,'') ilike '%'||v_term||'%')
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

-- CREATE OR REPLACE retains grants. Reassert the Candidate-only browser boundary.
revoke all on function public.list_candidate_job_opportunities(text,integer,integer) from public,anon;
grant execute on function public.list_candidate_job_opportunities(text,integer,integer) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.oid='public.list_candidate_job_opportunities(text,integer,integer)'::regprocedure
      and (not p.prosecdef or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%'
        or not has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))
  ) then
    raise exception 'Migration 047 Candidate opportunity projection security postcondition failed';
  end if;
end;
$$;

commit;
