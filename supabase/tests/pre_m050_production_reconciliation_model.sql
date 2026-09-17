-- Disposable-only model of the audited Production pre-M050 state.
-- It contains synthetic data only and must never be run against a hosted DB.
create extension if not exists pgcrypto;
create schema auth;
create schema private;
do $$ begin
  create role anon nologin;
exception when duplicate_object then null;
end $$;
do $$ begin
  create role authenticated nologin;
exception when duplicate_object then null;
end $$;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('test.auth_uid', true), '')::uuid
$$;

create table public.platform_users (user_id uuid primary key, account_type text not null, account_status text not null default 'active', display_name text);
create table public.companies (id uuid primary key, legal_name text not null, account_status text not null default 'active');
create table public.company_users (company_id uuid not null references public.companies(id), user_id uuid not null references public.platform_users(user_id), status text not null default 'active', role text not null);
create table public.contractors (id uuid primary key, agency_name text, owner_name text);
create table public.candidates (id uuid primary key);
create table public.employer_requirements (
  id uuid primary key default gen_random_uuid(), requirement_code text not null unique, company_id uuid references public.companies(id), company_name text,
  department text, job_role text, job_location text, company_location text, required_headcount integer not null, filled_positions integer not null default 0,
  qualification text, iti_trade text, experience_requirement text, gender_preference text, age_min integer, age_max integer, salary_min numeric, salary_max numeric,
  salary_wage text, shift_details text, working_hours text, overtime_details text, canteen text, transport text, accommodation text, interview_location text,
  interview_date timestamptz, expected_joining_date date, additional_notes text, source_type text not null, status text not null, requirement_stage text not null,
  requirement_visibility text not null, published_at timestamptz, closed_at timestamptz, created_at timestamptz not null default clock_timestamp(), updated_at timestamptz not null default clock_timestamp(), created_by_user_id uuid
);
create table public.requirement_contractors (id uuid primary key default gen_random_uuid(), requirement_id uuid not null references public.employer_requirements(id), contractor_id uuid references public.contractors(id), assigned_headcount integer, assignment_status text, origin_type text, submission_status text, submitted_at timestamptz, reviewed_at timestamptz, reviewed_by uuid, review_feedback text, closed_at timestamptz, created_at timestamptz not null default clock_timestamp());
create table public.candidate_applications (id uuid primary key default gen_random_uuid(), requirement_id uuid not null references public.employer_requirements(id), candidate_id uuid not null references public.candidates(id), application_status text not null default 'applied');
create table public.candidate_joinings (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.candidate_applications(id), expected_joining_date date, actual_joining_date date, joining_status text not null);
create table public.interviews (id uuid primary key default gen_random_uuid(), application_id uuid not null references public.candidate_applications(id));
create table public.audit_logs (id uuid primary key default gen_random_uuid(), actor_user_id uuid, actor_type text, action text not null, entity_type text not null, entity_id uuid not null, source text, correlation_id uuid, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default clock_timestamp());

alter table public.candidate_applications enable row level security;
alter table public.candidate_joinings enable row level security;
grant select, insert, update on public.candidate_applications, public.candidate_joinings to authenticated;
create policy "M7 admins create applications" on public.candidate_applications for insert to authenticated with check (true);
create policy "M7 admins read applications" on public.candidate_applications for select to authenticated using (true);
create policy "M7 admins update applications" on public.candidate_applications for update to authenticated using (true) with check (true);
create policy "M7 admins create joinings" on public.candidate_joinings for insert to authenticated with check (true);
create policy "M7 admins read joinings" on public.candidate_joinings for select to authenticated using (true);
create policy "M7 admins update joinings" on public.candidate_joinings for update to authenticated using (true) with check (true);

create function private.current_contractor_portal_id(p_require_active boolean default true) returns uuid language sql stable security definer set search_path='' as $$ select null::uuid $$;
create function private.can_manage_contractor_vacancies() returns boolean language sql stable security definer set search_path='' as $$ select false $$;
create function private.current_candidate_portal_id() returns uuid language sql stable security definer set search_path='' as $$ select null::uuid $$;
create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select true $$;
create function private.has_staff_role(p_role text) returns boolean language sql stable security definer set search_path='' as $$ select false $$;

create function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid,p_client_name text,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,p_accommodation text,p_interview_location text,p_expected_joining_date date,p_additional_notes text)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz) language sql security definer set search_path='' as $$ select null::uuid,null::text,null::text,null::text,null::timestamptz where false $$;
revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) from public, anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) to authenticated;
create function public.list_contractor_portal_vacancies(p_search text default null,p_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,client_name text,job_role text,job_location text,required_headcount integer,salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,accommodation_status text,accommodation_charge_amount numeric,accommodation_charge_basis text,submission_status text,requirement_stage text,review_feedback text,application_count bigint,interview_count bigint,selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_contractor_id uuid := private.current_contractor_portal_id(true); v_needle text := nullif(btrim(p_search),''); v_filter_status text := nullif(lower(btrim(p_status)), '');
begin
  if v_contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  if v_filter_status is not null and v_filter_status not in ('draft','submitted','under_review','correction_required','approved','rejected','closed','cancelled') then raise exception 'Unsupported submission status'; end if;
  return query select r.id,r.requirement_code,r.company_name,r.job_role,r.job_location,r.required_headcount,r.salary_min,r.salary_max,r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.accommodation_status,r.accommodation_charge_amount,r.accommodation_charge_basis,rc.submission_status,r.requirement_stage,rc.review_feedback,count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' and (v_filter_status is null or rc.submission_status=v_filter_status) and (v_needle is null or r.requirement_code ilike '%'||v_needle||'%' or r.job_role ilike '%'||v_needle||'%' or r.job_location ilike '%'||v_needle||'%')
  group by r.id,rc.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;
revoke all on function public.list_contractor_portal_vacancies(text,text,integer,integer) from public, anon;
grant execute on function public.list_contractor_portal_vacancies(text,text,integer,integer) to authenticated;
create function public.register_candidate_requirement_interest(p_requirement_code text,p_candidate jsonb) returns boolean language sql security definer set search_path='' as $$ select true $$;
revoke all on function public.register_candidate_requirement_interest(text,jsonb) from public, authenticated;
grant execute on function public.register_candidate_requirement_interest(text,jsonb) to anon;
create function public.upsert_recruitment_joining(p_application_id uuid,p_expected_date date,p_actual_date date,p_joining_status text,p_employee_code text,p_remarks text,p_correlation_id uuid) returns boolean language sql security definer set search_path='' as $$ select true $$;
revoke all on function public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid) from public, anon;
grant execute on function public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid) to authenticated;

insert into public.employer_requirements(requirement_code,company_name,job_role,job_location,required_headcount,source_type,status,requirement_stage,requirement_visibility,published_at)
values ('HIST-OPEN','Synthetic Worksite','Synthetic Operator','Synthetic Location',2,'admin_manual','in_progress','open','public',clock_timestamp()),
       ('HIST-DRAFT','Synthetic Worksite','Synthetic Draft Role','Synthetic Location',2,'admin_manual','new','draft','private',null);
