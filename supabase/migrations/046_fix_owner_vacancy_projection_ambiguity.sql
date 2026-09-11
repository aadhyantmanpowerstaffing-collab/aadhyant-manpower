-- Batch 2 corrective migration: remove PL/pgSQL owner-projection identifier ambiguity.
-- Migration 044 is installed and immutable. This migration preserves the four
-- callable owner list/detail signatures, result shapes, tenant boundaries, and
-- compensation/accommodation projections while using unambiguous local names.
begin;

create or replace function public.list_company_portal_requirements(p_search text default null,p_stage text default null,
  p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,department text,job_role text,job_location text,required_headcount integer,
  filled_positions integer,qualification text,experience_requirement text,gender_preference text,age_min integer,age_max integer,
  salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,
  leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,
  other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,
  other_ctc_component numeric,approx_in_hand numeric,ctc numeric,accommodation_status text,accommodation_charge_amount numeric,
  accommodation_charge_basis text,shift_details text,working_hours text,overtime_details text,canteen text,transport text,
  accommodation text,interview_location text,interview_date timestamptz,additional_notes text,requirement_stage text,
  requirement_visibility text,application_count bigint,interview_count bigint,selected_count bigint,joined_count bigint,
  created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid := (select private.current_company_portal_id(true)); v_needle text := nullif(btrim(p_search),''); v_stage text := nullif(lower(btrim(p_stage)), '');
begin
  if v_company_id is null then raise exception 'Active Company access is required'; end if;
  if v_stage is not null and v_stage not in ('draft','open','on_hold','filled','closed','cancelled') then raise exception 'Unsupported requirement stage'; end if;
  return query select r.id,r.requirement_code,r.department,r.job_role,r.job_location,r.required_headcount,r.filled_positions,
    r.qualification,r.experience_requirement,r.gender_preference,r.age_min,r.age_max,r.salary_min,r.salary_max,
    r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,
    r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,
    r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.accommodation_status,
    r.accommodation_charge_amount,r.accommodation_charge_basis,r.shift_details,r.working_hours,r.overtime_details,
    r.canteen,r.transport,r.accommodation,r.interview_location,r.interview_date,r.additional_notes,r.requirement_stage,
    r.requirement_visibility,count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),
    count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id
    left join public.interviews i on i.application_id=a.id
  where r.company_id=v_company_id and (v_stage is null or r.requirement_stage=v_stage)
    and (v_needle is null or r.requirement_code ilike '%'||v_needle||'%' or r.job_role ilike '%'||v_needle||'%' or r.job_location ilike '%'||v_needle||'%')
  group by r.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create or replace function public.list_contractor_portal_vacancies(p_search text default null,p_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,client_name text,job_role text,job_location text,required_headcount integer,
  salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,
  leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,
  other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,
  other_ctc_component numeric,approx_in_hand numeric,ctc numeric,accommodation_status text,accommodation_charge_amount numeric,
  accommodation_charge_basis text,submission_status text,requirement_stage text,review_feedback text,application_count bigint,interview_count bigint,
  selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_contractor_id uuid := (select private.current_contractor_portal_id(true)); v_needle text := nullif(btrim(p_search),''); v_filter_status text := nullif(lower(btrim(p_status)), '');
begin
  if v_contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  if v_filter_status is not null and v_filter_status not in ('draft','submitted','under_review','correction_required','approved','rejected','closed','cancelled') then raise exception 'Unsupported submission status'; end if;
  return query select r.id,r.requirement_code,r.company_name,r.job_role,r.job_location,r.required_headcount,r.salary_min,r.salary_max,
    r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,
    r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,
    r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.accommodation_status,
    r.accommodation_charge_amount,r.accommodation_charge_basis,rc.submission_status,r.requirement_stage,rc.review_feedback,
    count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),
    count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' and (v_filter_status is null or rc.submission_status=v_filter_status)
    and (v_needle is null or r.requirement_code ilike '%'||v_needle||'%' or r.job_role ilike '%'||v_needle||'%' or r.job_location ilike '%'||v_needle||'%')
  group by r.id,rc.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create or replace function public.get_company_portal_requirement(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid := (select private.current_company_portal_id(true)); v_result jsonb;
begin
  if v_company_id is null then raise exception 'Active Company access is required'; end if;
  select jsonb_build_object(
    'requirement_code',r.requirement_code,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,
    'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,
    'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,
    'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,
    'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),
    'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,
    'review_status',r.review_status,'review_feedback',r.review_feedback,'submitted_at',r.submitted_at,'reviewed_at',r.reviewed_at,
    'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'created_at',r.created_at,'updated_at',r.updated_at,
    'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),
      'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct i.id),
      'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct j.id) filter(where j.joining_status='joined'))
  ) into v_result from public.employer_requirements r
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
    left join public.candidate_joinings j on j.application_id=a.id
  where r.id=p_requirement_id and r.company_id=v_company_id group by r.id;
  if v_result is null then raise exception 'Company requirement was not found'; end if;
  return v_result;
end;
$$;

create or replace function public.get_contractor_portal_vacancy(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_contractor_id uuid := (select private.current_contractor_portal_id(true)); v_result jsonb;
begin
  if v_contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  select jsonb_build_object(
    'requirement_code',r.requirement_code,'client_name',r.company_name,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,
    'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,
    'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,
    'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,
    'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),
    'interview_location',r.interview_location,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,
    'submission_status',rc.submission_status,'normalized_review_status',private.normalized_vacancy_review_status(r.id),
    'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'review_feedback',rc.review_feedback,
    'submitted_at',rc.submitted_at,'reviewed_at',rc.reviewed_at,'created_at',r.created_at,'updated_at',r.updated_at,
    'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),
      'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct i.id),
      'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct j.id) filter(where j.joining_status='joined'))
  ) into v_result from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
    left join public.candidate_joinings j on j.application_id=a.id
  where r.id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' group by r.id,rc.id;
  if v_result is null then raise exception 'Contractor vacancy was not found'; end if;
  return v_result;
end;
$$;

-- CREATE OR REPLACE retains grants. Reassert the M044 browser boundary and fail
-- closed if ownership projections no longer have their approved security posture.
revoke all on function public.list_company_portal_requirements(text,text,integer,integer),public.list_contractor_portal_vacancies(text,text,integer,integer),
  public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid) from public,anon;
grant execute on function public.list_company_portal_requirements(text,text,integer,integer),public.list_contractor_portal_vacancies(text,text,integer,integer),
  public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.oid = any(array[
      'public.list_company_portal_requirements(text,text,integer,integer)'::regprocedure,
      'public.list_contractor_portal_vacancies(text,text,integer,integer)'::regprocedure,
      'public.get_company_portal_requirement(uuid)'::regprocedure,
      'public.get_contractor_portal_vacancy(uuid)'::regprocedure
    ]) and (not p.prosecdef or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%'
      or not has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))
  ) then
    raise exception 'Migration 046 owner vacancy projection security postcondition failed';
  end if;
end;
$$;

commit;
