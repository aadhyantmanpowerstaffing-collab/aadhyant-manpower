-- Manual, production-specific reconciliation for the audited pre-M050 drift.
--
-- This is deliberately NOT a numbered migration.  Run it once, only through
-- the controlled production procedure in PRODUCTION_PRE_M050_RECONCILIATION_RUNBOOK.md.
-- It contains no project reference, credential, record identifier, or PII.
-- It does not install M049 or M050.

begin;

-- The runner must opt in inside the same transaction after its independent
-- target/TLS guard has succeeded.  This prevents accidental copy/paste.
do $$
begin
  if coalesce(current_setting('app.pre_m050_reconciliation_approved', true), '') <> 'yes' then
    raise exception 'Set app.pre_m050_reconciliation_approved=yes only in the approved controlled session';
  end if;
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.candidate_joinings') is null
     or to_regclass('public.requirement_contractors') is null
     or to_regclass('public.candidates') is null
     or to_regclass('public.companies') is null
     or to_regclass('public.company_users') is null
     or to_regclass('public.contractors') is null
     or to_regclass('public.platform_users') is null then
    raise exception 'The canonical recruitment/portal foundation is not present';
  end if;
  if to_regclass('private.contractor_vacancy_submission_requests') is not null
     or to_regclass('private.vacancy_candidate_benefits') is not null then
    raise exception 'M049 or M050 evidence is already present; do not reconcile over it';
  end if;
  if exists (select 1 from pg_trigger where tgrelid='public.employer_requirements'::regclass
             and tgname in ('contractor_expected_joining_date_guard','vacancy_candidate_terms_material_change_guard')) then
    raise exception 'Later migration trigger evidence is present; stop for reconciliation review';
  end if;
  if (select count(*) from public.employer_requirements) <> 2
     or (select count(*) from public.employer_requirements
         where status='in_progress' and requirement_stage='open'
           and requirement_visibility='public' and published_at is not null) <> 1
     or (select count(*) from public.employer_requirements
         where status='new' and requirement_stage='draft'
           and requirement_visibility='private' and published_at is null) <> 1 then
    raise exception 'The approved two-row lifecycle mapping no longer matches the audited production state';
  end if;
  if exists (select 1 from public.candidate_joinings) then
    raise exception 'Historical joining rows require a separately reviewed normalization decision';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='manage_company_portal_requirement') then
    raise exception 'Company management collision: expected contract is not absent';
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='employer_requirements'
             and column_name in ('review_status','review_feedback','submitted_at','reviewed_at','reviewed_by',
               'payable_days','basic_da','attendance_bonus','monthly_bonus','leave_amount','other_fixed_earning','gross_wages',
               'employee_pf','employee_esic','canteen_deduction','other_deduction','employer_pf','employer_esic','gratuity_provision',
               'bonus_provision','leave_provision','other_ctc_component','approx_in_hand','ctc','accommodation_status',
               'accommodation_charge_amount','accommodation_charge_basis'))
     or exists (select 1 from pg_constraint where conrelid='public.employer_requirements'::regclass
                and conname in ('employer_requirements_review_status_check','employer_requirements_review_feedback_check',
                  'employer_requirements_review_reason_check','employer_requirements_payable_days_check',
                  'employer_requirements_wage_amounts_nonnegative_check','employer_requirements_wage_totals_check',
                  'employer_requirements_accommodation_status_check','employer_requirements_accommodation_basis_check',
                  'employer_requirements_accommodation_charge_check')) then
    raise exception 'M039 or M044 collision: expected schema additions are not wholly absent';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname in ('private','public') and p.proname in (
               'normalized_vacancy_review_status','vacancy_is_application_eligible','can_review_vacancies',
               'enforce_candidate_application_vacancy_gate','lock_vacancy_review','admin_approve_and_publish_vacancy',
               'admin_request_vacancy_correction','admin_reject_vacancy','vacancy_compensation_projection',
               'vacancy_accommodation_projection','vacancy_has_recruitment_dependencies','list_company_portal_requirements',
               'admin_list_vacancy_reviews','admin_get_vacancy_review_detail','list_company_portal_vacancy_reviews',
               'get_company_portal_requirement','get_contractor_portal_vacancy','review_contractor_vacancy',
               'list_candidate_job_opportunities','delete_company_portal_draft_vacancy','withdraw_company_portal_vacancy',
               'close_company_portal_open_vacancy','delete_contractor_portal_draft_vacancy','withdraw_contractor_portal_vacancy',
               'close_contractor_portal_open_vacancy')
             ) then
    raise exception 'M039 through M047 function collision or partial state';
  end if;
  if exists (select 1 from pg_trigger where tgrelid='public.candidate_applications'::regclass
             and tgname='candidate_applications_require_approved_public_vacancy') then
    raise exception 'M039 application-gate trigger collision';
  end if;
  if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)') is null
     or to_regprocedure('private.current_contractor_portal_id(boolean)') is null
     or to_regprocedure('private.can_manage_contractor_vacancies()') is null then
    raise exception 'The preserved Contractor base contract is unavailable';
  end if;
  if to_regprocedure('private.current_candidate_portal_id()') is null then
    raise exception 'The canonical Candidate portal identity contract is unavailable';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.proname='manage_contractor_portal_vacancy'
               and (not p.prosecdef or coalesce(array_to_string(p.proconfig, ','),'') not like '%search_path=%'
                 or has_function_privilege('anon',p.oid,'execute')
                 or not has_function_privilege('authenticated',p.oid,'execute'))) then
    raise exception 'Preserved Contractor management contract has incompatible security';
  end if;
  if not exists (
    select 1
    from pg_proc p
    where p.oid='public.list_contractor_portal_vacancies(text,text,integer,integer)'::regprocedure
      and p.prosecdef
      and coalesce(array_to_string(p.proconfig, ','),'') like '%search_path=%'
      and not has_function_privilege('anon',p.oid,'execute')
      and has_function_privilege('authenticated',p.oid,'execute')
      -- The audited list is preserved only when its M046 tenant, lifecycle,
      -- and structured-compensation semantics are still present. This never
      -- prints function source and is deliberately stricter than signature.
      and pg_get_functiondef(p.oid) ~ 'rc\.contractor_id\s*=\s*v_contractor_id'
      and pg_get_functiondef(p.oid) ~ 'rc\.origin_type\s*=\s*''contractor_submission'''
      and pg_get_functiondef(p.oid) ~ 'rc\.submission_status\s*=\s*v_filter_status'
      and pg_get_functiondef(p.oid) ~ 'r\.payable_days'
      and pg_get_functiondef(p.oid) ~ 'r\.accommodation_charge_basis'
      and (select string_agg(coalesce(a.argname,'') || ':' || format_type(a.argtype,null), '|' order by a.ord)
           from unnest(p.proallargtypes,p.proargmodes,p.proargnames) with ordinality a(argtype,argmode,argname,ord)
           where a.argmode in ('o','t')) =
          'id:uuid|requirement_code:text|client_name:text|job_role:text|job_location:text|required_headcount:integer|salary_min:numeric|salary_max:numeric|payable_days:integer|basic_da:numeric|attendance_bonus:numeric|monthly_bonus:numeric|leave_amount:numeric|other_fixed_earning:numeric|gross_wages:numeric|employee_pf:numeric|employee_esic:numeric|canteen_deduction:numeric|other_deduction:numeric|employer_pf:numeric|employer_esic:numeric|gratuity_provision:numeric|bonus_provision:numeric|leave_provision:numeric|other_ctc_component:numeric|approx_in_hand:numeric|ctc:numeric|accommodation_status:text|accommodation_charge_amount:numeric|accommodation_charge_basis:text|submission_status:text|requirement_stage:text|review_feedback:text|application_count:bigint|interview_count:bigint|selected_count:bigint|joined_count:bigint|created_at:timestamp with time zone|updated_at:timestamp with time zone'
  ) then
    raise exception 'Preserved Contractor list projection is not the exact M046 contract';
  end if;
  if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)') is not null then
    raise exception 'M048 Contractor shape collision: expected extended overload is absent';
  end if;
end;
$$;

-- M037: no historical joining rows exist, so add the final validator without
-- data rewriting.  Any same-name collision is an explicit stop condition.
do $$
begin
  if to_regprocedure('private.validate_candidate_joining_dates()') is not null
     or exists (select 1 from pg_constraint where conrelid='public.candidate_joinings'::regclass
                and conname='candidate_joinings_actual_date_state_check')
     or exists (select 1 from pg_trigger where tgrelid='public.candidate_joinings'::regclass
                and tgname='candidate_joinings_validate_dates') then
    raise exception 'M037 collision or partial state';
  end if;
end;
$$;

create function private.validate_candidate_joining_dates()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.joining_status in ('joined','left') and new.actual_joining_date is null then
    raise exception 'Actual joining date is required when a joining is joined or left';
  end if;
  if new.joining_status not in ('joined','left') and new.actual_joining_date is not null then
    raise exception 'Actual joining date requires Joined or Left status';
  end if;
  if new.joining_status in ('pending','confirmed','deferred') and new.expected_joining_date is null then
    raise exception 'Expected joining date is required for an active joining';
  end if;
  if new.actual_joining_date is not null
     and new.actual_joining_date > (clock_timestamp() at time zone 'Asia/Kolkata')::date then
    raise exception 'Actual joining date cannot be in the future';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_candidate_joining_dates() from public, anon, authenticated;
alter table public.candidate_joinings add constraint candidate_joinings_actual_date_state_check
  check ((joining_status not in ('joined','left')) or actual_joining_date is not null);
create trigger candidate_joinings_validate_dates before insert or update of joining_status, expected_joining_date, actual_joining_date
  on public.candidate_joinings for each row execute function private.validate_candidate_joining_dates();

-- M038: preserve the audited authenticated read grants and the three admin
-- read policies; remove only direct browser writes and the corresponding M7
-- create/update policies after checking their exact command/role posture.
do $$
begin
  if not (select relrowsecurity from pg_class where oid='public.candidate_applications'::regclass)
     or not (select relrowsecurity from pg_class where oid='public.candidate_joinings'::regclass) then
    raise exception 'Recruitment RLS must already be enabled';
  end if;
  if (select count(*) from pg_policy where polrelid in ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass)
      and polname in ('M7 admins create applications','M7 admins update applications','M7 admins create joinings','M7 admins update joinings')
      and polcmd in ('a','w') and polroles = array['authenticated'::regrole::oid]) <> 4 then
    raise exception 'M038 policy collision: audited direct-write policies do not match';
  end if;
end;
$$;
revoke insert, update on public.candidate_applications from authenticated;
revoke insert, update on public.candidate_joinings from authenticated;
drop policy "M7 admins create applications" on public.candidate_applications;
drop policy "M7 admins update applications" on public.candidate_applications;
drop policy "M7 admins create joinings" on public.candidate_joinings;
drop policy "M7 admins update joinings" on public.candidate_joinings;

-- M039 foundation and the approved, generic two-row mapping.  No reviewer or
-- review timestamp is fabricated for either historical requirement.
alter table public.employer_requirements
  add column review_status text,
  add column review_feedback text,
  add column submitted_at timestamptz,
  add column reviewed_at timestamptz,
  add column reviewed_by uuid references auth.users(id) on delete set null;
alter table public.employer_requirements
  add constraint employer_requirements_review_status_check check (review_status is null or review_status in ('draft','pending_review','correction_required','approved','rejected','closed')),
  add constraint employer_requirements_review_feedback_check check (review_feedback is null or length(btrim(review_feedback)) between 1 and 2000),
  add constraint employer_requirements_review_reason_check check (review_status not in ('correction_required','rejected') or review_feedback is not null);
create index employer_requirements_review_queue_idx on public.employer_requirements(review_status, submitted_at desc, id)
  where review_status in ('pending_review','correction_required');

update public.employer_requirements
set review_status='approved', review_feedback=null
where status='in_progress' and requirement_stage='open'
  and requirement_visibility='public' and published_at is not null;
update public.employer_requirements
set review_status='draft', review_feedback=null
where status='new' and requirement_stage='draft'
  and requirement_visibility='private' and published_at is null;

create function private.normalized_vacancy_review_status(p_requirement_id uuid)
returns text language sql stable security definer set search_path='' as $$
  select case when count(rc.id) filter(where rc.origin_type='contractor_submission') > 1 then null
    when count(rc.id) filter(where rc.origin_type='contractor_submission') = 1 then max(case rc.submission_status
      when 'draft' then 'draft' when 'submitted' then 'pending_review' when 'under_review' then 'pending_review'
      when 'correction_required' then 'correction_required' when 'approved' then 'approved'
      when 'rejected' then 'rejected' when 'closed' then 'closed' when 'cancelled' then 'closed' end)
    else max(r.review_status) end
  from public.employer_requirements r left join public.requirement_contractors rc
    on rc.requirement_id=r.id and rc.origin_type='contractor_submission'
  where r.id=p_requirement_id group by r.id;
$$;
create function private.vacancy_is_application_eligible(p_requirement_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.employer_requirements r where r.id=p_requirement_id
    and private.normalized_vacancy_review_status(r.id)='approved'
    and r.requirement_stage='open' and r.requirement_visibility='public'
    and r.filled_positions<r.required_headcount);
$$;
create function private.can_review_vacancies()
returns boolean language sql stable security definer set search_path='' as $$
  select (select private.is_admin()) or (select private.has_staff_role('super_admin')) or (select private.has_staff_role('admin'));
$$;
revoke all on function private.normalized_vacancy_review_status(uuid), private.vacancy_is_application_eligible(uuid), private.can_review_vacancies() from public, anon, authenticated;

create function private.enforce_candidate_application_vacancy_gate()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if current_setting('request.jwt.claim.role',true) is not null
     and not private.vacancy_is_application_eligible(new.requirement_id) then
    raise exception using errcode='42501', message='Applications are allowed only for approved public vacancies with capacity';
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_candidate_application_vacancy_gate() from public, anon, authenticated;
create trigger candidate_applications_require_approved_public_vacancy before insert on public.candidate_applications
  for each row execute function private.enforce_candidate_application_vacancy_gate();

-- Generic M039 administrative transitions.  They are deliberately record-
-- neutral: no retained fixture, reviewer, or historic review time is inferred.
create function private.lock_vacancy_review(p_requirement_id uuid)
returns public.employer_requirements language plpgsql security definer set search_path='' as $$
declare v_row public.employer_requirements%rowtype;
begin
  select * into v_row from public.employer_requirements where id=p_requirement_id for update;
  if v_row.id is null then raise exception 'Vacancy was not found'; end if;
  return v_row;
end;
$$;
revoke all on function private.lock_vacancy_review(uuid) from public, anon, authenticated;

create function public.admin_approve_and_publish_vacancy(p_requirement_id uuid,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_row public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype; v_now timestamptz:=clock_timestamp();
begin
  if v_actor is null or not private.can_review_vacancies() then raise exception 'Approved administrator access is required'; end if;
  v_row:=private.lock_vacancy_review(p_requirement_id);
  if p_expected_updated_at is not null and v_row.updated_at is distinct from p_expected_updated_at then raise exception 'Vacancy changed; refresh before reviewing'; end if;
  if not (v_row.required_headcount>v_row.filled_positions) then raise exception 'A full vacancy cannot be published'; end if;
  if v_row.source_type='contractor_portal' then
    select * into v_link from public.requirement_contractors where requirement_id=v_row.id and origin_type='contractor_submission' for update;
    if v_link.id is null or v_link.submission_status not in ('submitted','under_review') then raise exception 'Only a pending Contractor vacancy can be approved'; end if;
    update public.requirement_contractors set submission_status='approved',assignment_status='active',reviewed_at=v_now,reviewed_by=v_actor where id=v_link.id;
  elsif v_row.source_type='employer_portal' then
    if v_row.review_status<>'pending_review' then raise exception 'Only a pending Company vacancy can be approved'; end if;
    update public.employer_requirements set review_status='approved',reviewed_at=v_now,reviewed_by=v_actor,review_feedback=null where id=v_row.id;
  else raise exception 'Only portal-submitted vacancies can be approved'; end if;
  update public.employer_requirements set requirement_stage='open',requirement_visibility='public',status='in_progress',published_at=coalesce(published_at,v_now),closed_at=null where id=v_row.id returning * into v_row;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(v_actor,'staff','vacancy_review_approved_published','employer_requirement',v_row.id,'admin',jsonb_build_object('source_type',v_row.source_type));
  return public.admin_get_vacancy_review_detail(v_row.id);
end;
$$;
create function public.admin_request_vacancy_correction(p_requirement_id uuid,p_reason text,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_row public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype; v_reason text:=nullif(btrim(p_reason),''); v_now timestamptz:=clock_timestamp();
begin
  if v_actor is null or not private.can_review_vacancies() then raise exception 'Approved administrator access is required'; end if;
  if v_reason is null or length(v_reason)>2000 then raise exception 'A correction reason of at most 2000 characters is required'; end if;
  v_row:=private.lock_vacancy_review(p_requirement_id);
  if p_expected_updated_at is not null and v_row.updated_at is distinct from p_expected_updated_at then raise exception 'Vacancy changed; refresh before reviewing'; end if;
  if v_row.source_type='contractor_portal' then select * into v_link from public.requirement_contractors where requirement_id=v_row.id and origin_type='contractor_submission' for update;
    if v_link.id is null or v_link.submission_status not in ('submitted','under_review') then raise exception 'Only a pending Contractor vacancy can require correction'; end if;
    update public.requirement_contractors set submission_status='correction_required',review_feedback=v_reason,reviewed_at=v_now,reviewed_by=v_actor where id=v_link.id;
  elsif v_row.source_type='employer_portal' then
    if v_row.review_status<>'pending_review' then raise exception 'Only a pending Company vacancy can require correction'; end if;
    update public.employer_requirements set review_status='correction_required',review_feedback=v_reason,reviewed_at=v_now,reviewed_by=v_actor where id=v_row.id;
  else raise exception 'Only portal-submitted vacancies can require correction'; end if;
  update public.employer_requirements set requirement_stage='draft',requirement_visibility='private',published_at=null,closed_at=null where id=v_row.id returning * into v_row;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(v_actor,'staff','vacancy_review_correction_requested','employer_requirement',v_row.id,'admin',jsonb_build_object('source_type',v_row.source_type,'reason',v_reason));
  return public.admin_get_vacancy_review_detail(v_row.id);
end;
$$;
create function public.admin_reject_vacancy(p_requirement_id uuid,p_reason text,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_row public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype; v_reason text:=nullif(btrim(p_reason),''); v_now timestamptz:=clock_timestamp();
begin
  if v_actor is null or not private.can_review_vacancies() then raise exception 'Approved administrator access is required'; end if;
  if v_reason is null or length(v_reason)>2000 then raise exception 'A rejection reason of at most 2000 characters is required'; end if;
  v_row:=private.lock_vacancy_review(p_requirement_id);
  if p_expected_updated_at is not null and v_row.updated_at is distinct from p_expected_updated_at then raise exception 'Vacancy changed; refresh before reviewing'; end if;
  if v_row.source_type='contractor_portal' then select * into v_link from public.requirement_contractors where requirement_id=v_row.id and origin_type='contractor_submission' for update;
    if v_link.id is null or v_link.submission_status not in ('submitted','under_review') then raise exception 'Only a pending Contractor vacancy can be rejected'; end if;
    update public.requirement_contractors set submission_status='rejected',assignment_status='cancelled',review_feedback=v_reason,reviewed_at=v_now,reviewed_by=v_actor,closed_at=v_now where id=v_link.id;
  elsif v_row.source_type='employer_portal' then
    if v_row.review_status<>'pending_review' then raise exception 'Only a pending Company vacancy can be rejected'; end if;
    update public.employer_requirements set review_status='rejected',review_feedback=v_reason,reviewed_at=v_now,reviewed_by=v_actor where id=v_row.id;
  else raise exception 'Only portal-submitted vacancies can be rejected'; end if;
  update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=v_now where id=v_row.id returning * into v_row;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(v_actor,'staff','vacancy_review_rejected','employer_requirement',v_row.id,'admin',jsonb_build_object('source_type',v_row.source_type,'reason',v_reason));
  return public.admin_get_vacancy_review_detail(v_row.id);
end;
$$;
revoke all on function public.admin_approve_and_publish_vacancy(uuid,timestamptz), public.admin_request_vacancy_correction(uuid,text,timestamptz), public.admin_reject_vacancy(uuid,text,timestamptz) from public, anon;
grant execute on function public.admin_approve_and_publish_vacancy(uuid,timestamptz), public.admin_request_vacancy_correction(uuid,text,timestamptz), public.admin_reject_vacancy(uuid,text,timestamptz) to authenticated;

-- Final M039 reviewer surfaces.  These are the reviewed signatures; later
-- M044/M046 projections replace only the owner detail/list shapes below.
create function public.admin_list_vacancy_reviews(p_review_status text default 'pending_review',p_source_type text default null,p_limit integer default 50,p_offset integer default 0)
returns table(requirement_id uuid,requirement_code text,source_type text,normalized_review_status text,contractor_submission_status text,submitted_at timestamptz,company_name text,contractor_name text,job_role text,department text,job_location text,required_headcount integer,filled_positions integer,remaining_positions integer,review_feedback text,requirement_stage text,requirement_visibility text)
language sql stable security definer set search_path='' as $$
  with authz as (select private.can_review_vacancies() allowed), rows as (
    select r.id,r.requirement_code,r.source_type,private.normalized_vacancy_review_status(r.id) normalized_review_status,
      rc.submission_status,coalesce(rc.submitted_at,r.submitted_at) submitted_at,r.company_name,coalesce(c.agency_name,c.owner_name) contractor_name,
      r.job_role,r.department,coalesce(r.job_location,r.company_location) job_location,r.required_headcount,r.filled_positions,
      r.required_headcount-r.filled_positions remaining_positions,coalesce(rc.review_feedback,r.review_feedback) review_feedback,
      r.requirement_stage,r.requirement_visibility
    from public.employer_requirements r
    left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
    left join public.contractors c on c.id=rc.contractor_id)
  select rows.id,rows.requirement_code,rows.source_type,rows.normalized_review_status,rows.submission_status,rows.submitted_at,rows.company_name,rows.contractor_name,rows.job_role,rows.department,rows.job_location,rows.required_headcount,rows.filled_positions,rows.remaining_positions,rows.review_feedback,rows.requirement_stage,rows.requirement_visibility
  from rows cross join authz where authz.allowed and (p_review_status is null or rows.normalized_review_status=lower(btrim(p_review_status))) and (p_source_type is null or rows.source_type=lower(btrim(p_source_type)))
  order by rows.submitted_at nulls last,rows.requirement_code limit greatest(1,least(coalesce(p_limit,50),200)) offset greatest(0,coalesce(p_offset,0));
$$;

create function public.admin_get_vacancy_review_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not private.can_review_vacancies() then raise exception 'Approved administrator access is required'; end if;
  select jsonb_build_object(
    'source',jsonb_strip_nulls(jsonb_build_object('source_type',r.source_type,'submitted_by',u.display_name,'company',r.company_name,'contractor',coalesce(c.agency_name,c.owner_name))),
    'vacancy',jsonb_strip_nulls(jsonb_build_object('requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,'department',r.department,'location',coalesce(r.job_location,r.company_location),'openings',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes)),
    'review',jsonb_strip_nulls(jsonb_build_object('normalized_status',private.normalized_vacancy_review_status(r.id),'contractor_submission_status',rc.submission_status,'feedback',coalesce(rc.review_feedback,r.review_feedback),'submitted_at',coalesce(rc.submitted_at,r.submitted_at),'reviewed_at',coalesce(rc.reviewed_at,r.reviewed_at),'reviewer',reviewer.display_name)),
    'lifecycle',jsonb_build_object('requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'published_at',r.published_at,'closed_at',r.closed_at,'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,'remaining_positions',r.required_headcount-r.filled_positions),
    'progress',jsonb_build_object('applications',(select count(*) from public.candidate_applications a where a.requirement_id=r.id),'interviews',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id),'selected',(select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status='selected'),'joined',(select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=r.id and j.joining_status='joined')))
  into result from public.employer_requirements r
    left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
    left join public.contractors c on c.id=rc.contractor_id left join public.platform_users u on u.user_id=r.created_by_user_id left join public.platform_users reviewer on reviewer.user_id=coalesce(rc.reviewed_by,r.reviewed_by)
  where r.id=p_requirement_id;
  if result is null then raise exception 'Vacancy was not found'; end if;
  return result;
end;
$$;

create function public.list_company_portal_vacancy_reviews(p_search text default null,p_review_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_id uuid,requirement_code text,job_role text,department text,job_location text,required_headcount integer,filled_positions integer,remaining_positions integer,review_status text,review_feedback text,requirement_stage text,requirement_visibility text,application_count bigint,interview_count bigint,selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid:=private.current_company_portal_id(true); v_term text:=nullif(btrim(p_search),''); v_status text:=nullif(lower(btrim(p_review_status)), '');
begin
  if v_company_id is null then raise exception 'Active Company access is required'; end if;
  if v_status is not null and v_status not in ('draft','pending_review','correction_required','approved','rejected','closed') then raise exception 'Unsupported review status'; end if;
  return query select r.id,r.requirement_code,r.job_role,r.department,r.job_location,r.required_headcount,r.filled_positions,r.required_headcount-r.filled_positions,r.review_status,r.review_feedback,r.requirement_stage,r.requirement_visibility,count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where r.company_id=v_company_id and r.source_type='employer_portal' and (v_status is null or r.review_status=v_status) and (v_term is null or r.requirement_code ilike '%'||v_term||'%' or r.job_role ilike '%'||v_term||'%' or r.job_location ilike '%'||v_term||'%')
  group by r.id order by r.updated_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.admin_list_vacancy_reviews(text,text,integer,integer),public.admin_get_vacancy_review_detail(uuid),public.list_company_portal_vacancy_reviews(text,text,integer,integer) from public,anon;
grant execute on function public.admin_list_vacancy_reviews(text,text,integer,integer),public.admin_get_vacancy_review_detail(uuid),public.list_company_portal_vacancy_reviews(text,text,integer,integer) to authenticated;

create function public.review_contractor_vacancy(p_requirement_id uuid,p_action text,p_feedback text default null)
returns table(requirement_id uuid,requirement_code text,submission_status text,requirement_stage text,requirement_visibility text)
language plpgsql security definer set search_path='' as $$
declare v_row public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype; v_action text:=lower(btrim(coalesce(p_action,'')));
begin
  if not private.can_review_vacancies() then raise exception 'Contractor vacancy review access is required'; end if;
  if length(coalesce(p_feedback,''))>2000 then raise exception 'Review feedback is too long'; end if;
  v_row:=private.lock_vacancy_review(p_requirement_id);
  if v_row.source_type<>'contractor_portal' then raise exception 'Contractor vacancy was not found'; end if;
  select * into v_link from public.requirement_contractors where requirement_id=v_row.id and origin_type='contractor_submission' for update;
  if v_link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if v_action='start_review' then
    if v_link.submission_status<>'submitted' then raise exception 'Only a submitted vacancy can be opened for review'; end if;
    update public.requirement_contractors set submission_status='under_review',reviewed_at=clock_timestamp(),reviewed_by=auth.uid() where id=v_link.id returning * into v_link;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(auth.uid(),'staff','contractor_vacancy_review_opened','employer_requirement',v_row.id,'admin','{}');
  elsif v_action='approve' then
    perform public.admin_approve_and_publish_vacancy(v_row.id,null);
    select * into v_link from public.requirement_contractors where id=v_link.id; select * into v_row from public.employer_requirements where id=v_row.id;
  elsif v_action='request_correction' then
    perform public.admin_request_vacancy_correction(v_row.id,p_feedback,null);
    select * into v_link from public.requirement_contractors where id=v_link.id; select * into v_row from public.employer_requirements where id=v_row.id;
  elsif v_action='reject' then
    perform public.admin_reject_vacancy(v_row.id,p_feedback,null);
    select * into v_link from public.requirement_contractors where id=v_link.id; select * into v_row from public.employer_requirements where id=v_row.id;
  elsif v_action='close' then
    if v_link.submission_status<>'approved' then raise exception 'Only an approved vacancy can be closed'; end if;
    update public.requirement_contractors set submission_status='closed',assignment_status='completed',reviewed_at=clock_timestamp(),reviewed_by=auth.uid(),closed_at=clock_timestamp() where id=v_link.id returning * into v_link;
    update public.employer_requirements set requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=v_row.id returning * into v_row;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(auth.uid(),'staff','contractor_vacancy_review_closed','employer_requirement',v_row.id,'admin','{}');
  else raise exception 'Invalid Contractor vacancy review action'; end if;
  return query select v_row.id,v_row.requirement_code,v_link.submission_status,v_row.requirement_stage,v_row.requirement_visibility;
end;
$$;
revoke all on function public.review_contractor_vacancy(uuid,text,text) from public,anon;
grant execute on function public.review_contractor_vacancy(uuid,text,text) to authenticated;

-- M043 Company contract.  This is a narrow owner boundary, not a direct table
-- grant.  It deliberately keeps the historical Company portal arguments and
-- routes all create/update/submit operations through one SECURITY DEFINER RPC.
create function private.current_company_portal_id(p_require_active boolean default true)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid; v_count integer;
begin
  if auth.uid() is null then return null; end if;
  select min(cu.company_id::text)::uuid, count(*)::integer into v_company_id, v_count
  from public.company_users cu join public.platform_users pu on pu.user_id=cu.user_id
    join public.companies c on c.id=cu.company_id
  where cu.user_id=auth.uid() and pu.account_type='company'
    and (not p_require_active or (pu.account_status='active' and cu.status='active' and c.account_status='active'));
  if v_count=0 then return null; end if;
  if v_count<>1 then raise exception 'Exactly one company membership is required'; end if;
  return v_company_id;
end;
$$;
create function private.can_manage_company_portal()
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.company_users cu where cu.user_id=auth.uid()
    and cu.company_id=private.current_company_portal_id(true) and cu.status='active'
    and cu.role in ('owner','hr_admin','recruiter'));
$$;
revoke all on function private.current_company_portal_id(boolean), private.can_manage_company_portal() from public, anon, authenticated;

create function public.manage_company_portal_requirement(
  p_action text,p_requirement_id uuid,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,
  p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,
  p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,
  p_accommodation text,p_interview_location text,p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare v_company_id uuid:=private.current_company_portal_id(true); v_action text:=lower(btrim(coalesce(p_action,''))); v_row public.employer_requirements%rowtype;
begin
  if auth.uid() is null or not private.can_manage_company_portal() or v_company_id is null then raise exception 'Company requirement management access is required'; end if;
  if v_action in ('create','create_draft','create_and_submit') then
    if length(btrim(coalesce(p_department,''))) not between 1 and 160 or length(btrim(coalesce(p_job_role,''))) not between 1 and 200
       or length(btrim(coalesce(p_job_location,''))) not between 1 and 240 or p_required_headcount not between 1 and 100000 then
      raise exception 'Department, role, location, and valid openings are required';
    end if;
    insert into public.employer_requirements(company_id,company_name,department,job_role,job_location,company_location,required_headcount,qualification,iti_trade,
      experience_requirement,gender_preference,age_min,age_max,salary_min,salary_max,salary_wage,shift_details,working_hours,overtime_details,canteen,transport,
      accommodation,interview_location,interview_date,expected_joining_date,additional_notes,source_type,status,requirement_stage,requirement_visibility,review_status,created_by_user_id)
    select v_company_id,c.legal_name,nullif(btrim(p_department),''),btrim(p_job_role),btrim(p_job_location),btrim(p_job_location),p_required_headcount,
      nullif(btrim(p_qualification),''),nullif(btrim(p_iti_trade),''),coalesce(nullif(btrim(p_experience_requirement),''),'Both'),coalesce(nullif(btrim(p_gender_preference),''),'Any'),
      p_age_min,p_age_max,p_salary_min,p_salary_max,case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
      nullif(btrim(p_shift_details),''),nullif(btrim(p_working_hours),''),nullif(btrim(p_overtime_details),''),coalesce(p_canteen,'Not Applicable'),coalesce(p_transport,'Not Applicable'),coalesce(p_accommodation,'Not Applicable'),
      nullif(btrim(p_interview_location),''),p_interview_date,p_expected_joining_date,nullif(btrim(p_additional_notes),''),'employer_portal','new','draft','private',
      case when v_action='create_and_submit' then 'pending_review' else 'draft' end,auth.uid()
    from public.companies c where c.id=v_company_id returning * into v_row;
    if v_action='create_and_submit' then update public.employer_requirements set submitted_at=clock_timestamp() where id=v_row.id returning * into v_row; end if;
  elsif v_action in ('update','update_draft','submit','resubmit') then
    select * into v_row from public.employer_requirements where id=p_requirement_id and company_id=v_company_id and source_type='employer_portal' for update;
    if v_row.id is null then raise exception 'Company vacancy was not found'; end if;
    if v_action in ('update','update_draft') then
      if v_row.review_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be edited'; end if;
      update public.employer_requirements set department=nullif(btrim(p_department),''),job_role=btrim(p_job_role),job_location=btrim(p_job_location),company_location=btrim(p_job_location),required_headcount=p_required_headcount,
        qualification=nullif(btrim(p_qualification),''),iti_trade=nullif(btrim(p_iti_trade),''),experience_requirement=coalesce(nullif(btrim(p_experience_requirement),''),'Both'),gender_preference=coalesce(nullif(btrim(p_gender_preference),''),'Any'),age_min=p_age_min,age_max=p_age_max,salary_min=p_salary_min,salary_max=p_salary_max,shift_details=nullif(btrim(p_shift_details),''),working_hours=nullif(btrim(p_working_hours),''),overtime_details=nullif(btrim(p_overtime_details),''),canteen=coalesce(p_canteen,'Not Applicable'),transport=coalesce(p_transport,'Not Applicable'),accommodation=coalesce(p_accommodation,'Not Applicable'),interview_location=nullif(btrim(p_interview_location),''),interview_date=p_interview_date,expected_joining_date=p_expected_joining_date,additional_notes=nullif(btrim(p_additional_notes),''),requirement_stage='draft',requirement_visibility='private',review_status='draft',review_feedback=null,reviewed_at=null,reviewed_by=null where id=v_row.id returning * into v_row;
    else
      if v_row.review_status not in ('draft','correction_required') then raise exception 'Only a draft or correction-required vacancy can be submitted'; end if;
      update public.employer_requirements set review_status='pending_review',review_feedback=null,submitted_at=clock_timestamp(),reviewed_at=null,reviewed_by=null,requirement_stage='draft',requirement_visibility='private' where id=v_row.id returning * into v_row;
    end if;
  else raise exception 'Unsupported Company vacancy action'; end if;
  return query select v_row.id,v_row.requirement_code,v_row.requirement_stage,v_row.requirement_visibility,v_row.updated_at;
end;
$$;
revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text) from public, anon;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text) to authenticated;

-- M044 structured compensation/accommodation, including the private-only
-- projection helpers used by later owner and Candidate-safe projections.
alter table public.employer_requirements
  add column payable_days integer, add column basic_da numeric, add column attendance_bonus numeric, add column monthly_bonus numeric,
  add column leave_amount numeric, add column other_fixed_earning numeric, add column gross_wages numeric, add column employee_pf numeric,
  add column employee_esic numeric, add column canteen_deduction numeric, add column other_deduction numeric, add column employer_pf numeric,
  add column employer_esic numeric, add column gratuity_provision numeric, add column bonus_provision numeric, add column leave_provision numeric,
  add column other_ctc_component numeric, add column approx_in_hand numeric, add column ctc numeric, add column accommodation_status text,
  add column accommodation_charge_amount numeric, add column accommodation_charge_basis text;
alter table public.employer_requirements
  add constraint employer_requirements_payable_days_check check (payable_days is null or payable_days between 1 and 31),
  add constraint employer_requirements_wage_amounts_nonnegative_check check (coalesce(basic_da,0)>=0 and coalesce(attendance_bonus,0)>=0 and coalesce(monthly_bonus,0)>=0 and coalesce(leave_amount,0)>=0 and coalesce(other_fixed_earning,0)>=0 and coalesce(gross_wages,0)>=0 and coalesce(employee_pf,0)>=0 and coalesce(employee_esic,0)>=0 and coalesce(canteen_deduction,0)>=0 and coalesce(other_deduction,0)>=0 and coalesce(employer_pf,0)>=0 and coalesce(employer_esic,0)>=0 and coalesce(gratuity_provision,0)>=0 and coalesce(bonus_provision,0)>=0 and coalesce(leave_provision,0)>=0 and coalesce(other_ctc_component,0)>=0 and coalesce(approx_in_hand,0)>=0 and coalesce(ctc,0)>=0),
  add constraint employer_requirements_wage_totals_check check ((basic_da is null and attendance_bonus is null and monthly_bonus is null and leave_amount is null and other_fixed_earning is null and gross_wages is null and employee_pf is null and employee_esic is null and canteen_deduction is null and other_deduction is null and employer_pf is null and employer_esic is null and gratuity_provision is null and bonus_provision is null and leave_provision is null and other_ctc_component is null and approx_in_hand is null and ctc is null) or (gross_wages is not null and approx_in_hand is not null and ctc is not null and gross_wages=coalesce(basic_da,0)+coalesce(attendance_bonus,0)+coalesce(monthly_bonus,0)+coalesce(leave_amount,0)+coalesce(other_fixed_earning,0) and approx_in_hand=gross_wages-coalesce(employee_pf,0)-coalesce(employee_esic,0)-coalesce(canteen_deduction,0)-coalesce(other_deduction,0) and ctc=gross_wages+coalesce(employer_pf,0)+coalesce(employer_esic,0)+coalesce(gratuity_provision,0)+coalesce(bonus_provision,0)+coalesce(leave_provision,0)+coalesce(other_ctc_component,0))),
  add constraint employer_requirements_accommodation_status_check check (accommodation_status is null or accommodation_status in ('not_available','free','chargeable')),
  add constraint employer_requirements_accommodation_basis_check check (accommodation_charge_basis is null or accommodation_charge_basis in ('per_day','per_month')),
  add constraint employer_requirements_accommodation_charge_check check ((accommodation_status is null and accommodation_charge_amount is null and accommodation_charge_basis is null) or (accommodation_status='chargeable' and accommodation_charge_amount is not null and accommodation_charge_amount>0 and accommodation_charge_basis is not null) or (accommodation_status in ('not_available','free') and accommodation_charge_amount is null and accommodation_charge_basis is null));
create function private.vacancy_compensation_projection(p_requirement public.employer_requirements) returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_strip_nulls(jsonb_build_object('payable_days',p_requirement.payable_days,'basic_da',p_requirement.basic_da,'attendance_bonus',p_requirement.attendance_bonus,'monthly_bonus',p_requirement.monthly_bonus,'leave_amount',p_requirement.leave_amount,'other_fixed_earning',p_requirement.other_fixed_earning,'gross_wages',p_requirement.gross_wages,'employee_pf',p_requirement.employee_pf,'employee_esic',p_requirement.employee_esic,'canteen_deduction',p_requirement.canteen_deduction,'other_deduction',p_requirement.other_deduction,'employer_pf',p_requirement.employer_pf,'employer_esic',p_requirement.employer_esic,'gratuity_provision',p_requirement.gratuity_provision,'bonus_provision',p_requirement.bonus_provision,'leave_provision',p_requirement.leave_provision,'other_ctc_component',p_requirement.other_ctc_component,'approx_in_hand',p_requirement.approx_in_hand,'ctc',p_requirement.ctc)); $$;
create function private.vacancy_accommodation_projection(p_requirement public.employer_requirements) returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_strip_nulls(jsonb_build_object('status',p_requirement.accommodation_status,'charge_amount',p_requirement.accommodation_charge_amount,'charge_basis',p_requirement.accommodation_charge_basis)); $$;
create function private.vacancy_has_recruitment_dependencies(p_requirement_id uuid,p_ignored_contractor_link_id uuid default null) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.candidate_applications a where a.requirement_id=p_requirement_id) or exists(select 1 from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=p_requirement_id) or exists(select 1 from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=p_requirement_id) or exists(select 1 from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.id is distinct from p_ignored_contractor_link_id); $$;
revoke all on function private.vacancy_compensation_projection(public.employer_requirements), private.vacancy_accommodation_projection(public.employer_requirements), private.vacancy_has_recruitment_dependencies(uuid,uuid) from public, anon, authenticated;

-- M044's extended Company shape is a separate overload.  It preserves the
-- M043 owner boundary and cannot be selected accidentally by legacy callers.
create function public.manage_company_portal_requirement(p_action text,p_requirement_id uuid,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,p_accommodation text,p_interview_location text,p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text,p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz) language plpgsql security definer set search_path='' as $$
declare v_result record; v_action text:=lower(btrim(coalesce(p_action,''))); v_updated public.employer_requirements%rowtype;
begin
 select * into v_result from public.manage_company_portal_requirement(p_action,p_requirement_id,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_interview_date,p_expected_joining_date,p_additional_notes);
 if v_action in ('create','create_draft','create_and_submit','update','update_draft') then update public.employer_requirements set payable_days=p_payable_days,basic_da=p_basic_da,attendance_bonus=p_attendance_bonus,monthly_bonus=p_monthly_bonus,leave_amount=p_leave_amount,other_fixed_earning=p_other_fixed_earning,gross_wages=p_gross_wages,employee_pf=p_employee_pf,employee_esic=p_employee_esic,canteen_deduction=p_canteen_deduction,other_deduction=p_other_deduction,employer_pf=p_employer_pf,employer_esic=p_employer_esic,gratuity_provision=p_gratuity_provision,bonus_provision=p_bonus_provision,leave_provision=p_leave_provision,other_ctc_component=p_other_ctc_component,approx_in_hand=p_approx_in_hand,ctc=p_ctc,accommodation_status=p_accommodation_status,accommodation_charge_amount=p_accommodation_charge_amount,accommodation_charge_basis=p_accommodation_charge_basis where id=v_result.id returning * into v_updated; end if;
 return query select v_result.id,v_result.requirement_code,v_result.requirement_stage,v_result.requirement_visibility,coalesce(v_updated.updated_at,v_result.updated_at);
end;
$$;
revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) from public, anon;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) to authenticated;

-- M045 lifecycle endpoints share the same owner predicate.  They never
-- bypass recruitment-dependency checks and expose no direct table privilege.
create function public.delete_company_portal_draft_vacancy(p_requirement_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_row public.employer_requirements%rowtype; begin
 if auth.uid() is null or not private.can_manage_company_portal() then raise exception 'Company requirement management access is required'; end if;
 select * into v_row from public.employer_requirements where id=p_requirement_id and company_id=private.current_company_portal_id(true) and source_type='employer_portal' for update;
 if v_row.id is null or v_row.review_status<>'draft' or v_row.requirement_stage<>'draft' then raise exception 'Only an owned draft vacancy can be deleted'; end if;
 if private.vacancy_has_recruitment_dependencies(v_row.id,null) then raise exception 'Vacancies with recruitment dependencies cannot be deleted'; end if;
 delete from public.employer_requirements where id=v_row.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'company','company_vacancy_draft_deleted','employer_requirement',v_row.id,'company',jsonb_build_object('requirement_code',v_row.requirement_code));
 return true; end;
$$;
create function public.withdraw_company_portal_vacancy(p_requirement_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_row public.employer_requirements%rowtype; begin
 if auth.uid() is null or not private.can_manage_company_portal() then raise exception 'Company requirement management access is required'; end if;
 select * into v_row from public.employer_requirements where id=p_requirement_id and company_id=private.current_company_portal_id(true) and source_type='employer_portal' for update;
 if v_row.id is null or v_row.review_status<>'pending_review' then raise exception 'Only an owned pending-review vacancy can be withdrawn'; end if;
 update public.employer_requirements set review_status='closed',requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=v_row.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'company','company_vacancy_withdrawn','employer_requirement',v_row.id,'company',jsonb_build_object('prior_review_status','pending_review'));
 return true; end;
$$;
create function public.close_company_portal_open_vacancy(p_requirement_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_row public.employer_requirements%rowtype; begin
 if auth.uid() is null or not private.can_manage_company_portal() then raise exception 'Company requirement management access is required'; end if;
 select * into v_row from public.employer_requirements where id=p_requirement_id and company_id=private.current_company_portal_id(true) and source_type='employer_portal' for update;
 if v_row.id is null or v_row.review_status<>'approved' or v_row.requirement_stage<>'open' or v_row.requirement_visibility<>'public' then raise exception 'Only an owned published vacancy can be closed'; end if;
 update public.employer_requirements set review_status='closed',requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=v_row.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'company','company_vacancy_closed','employer_requirement',v_row.id,'company',jsonb_build_object('prior_stage','open'));
 return true; end;
$$;
create function public.delete_contractor_portal_draft_vacancy(p_requirement_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_link public.requirement_contractors%rowtype; v_row public.employer_requirements%rowtype; begin
 if auth.uid() is null or not private.can_manage_contractor_vacancies() then raise exception 'Contractor vacancy management access is required'; end if;
 select rc.* into v_link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=private.current_contractor_portal_id(true) and rc.origin_type='contractor_submission' for update;
 select * into v_row from public.employer_requirements where id=p_requirement_id and source_type='contractor_portal' for update;
 if v_link.id is null or v_row.id is null or v_link.submission_status<>'draft' or v_row.requirement_stage<>'draft' then raise exception 'Only an owned draft vacancy can be deleted'; end if;
 if private.vacancy_has_recruitment_dependencies(v_row.id,v_link.id) then raise exception 'Vacancies with recruitment dependencies cannot be deleted'; end if;
 delete from public.requirement_contractors where id=v_link.id; delete from public.employer_requirements where id=v_row.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'contractor','contractor_vacancy_draft_deleted','employer_requirement',v_row.id,'contractor',jsonb_build_object('requirement_code',v_row.requirement_code));
 return true; end;
$$;
create function public.withdraw_contractor_portal_vacancy(p_requirement_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_link public.requirement_contractors%rowtype; begin
 if auth.uid() is null or not private.can_manage_contractor_vacancies() then raise exception 'Contractor vacancy management access is required'; end if;
 select rc.* into v_link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=private.current_contractor_portal_id(true) and rc.origin_type='contractor_submission' for update;
 if v_link.id is null or v_link.submission_status not in ('submitted','under_review') then raise exception 'Only an owned pending-review vacancy can be withdrawn'; end if;
 update public.requirement_contractors set submission_status='cancelled',closed_at=clock_timestamp() where id=v_link.id;
 update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=p_requirement_id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'contractor','contractor_vacancy_withdrawn','employer_requirement',p_requirement_id,'contractor',jsonb_build_object('prior_submission_status',v_link.submission_status));
 return true; end;
$$;
create function public.close_contractor_portal_open_vacancy(p_requirement_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_link public.requirement_contractors%rowtype; begin
 if auth.uid() is null or not private.can_manage_contractor_vacancies() then raise exception 'Contractor vacancy management access is required'; end if;
 select rc.* into v_link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=private.current_contractor_portal_id(true) and rc.origin_type='contractor_submission' for update;
 if v_link.id is null or v_link.submission_status<>'approved' then raise exception 'Only an owned published vacancy can be closed'; end if;
 update public.requirement_contractors set submission_status='closed',assignment_status='completed',closed_at=clock_timestamp() where id=v_link.id;
 update public.employer_requirements set review_status='closed',requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=p_requirement_id and requirement_stage='open' and requirement_visibility='public';
 if not found then raise exception 'Only an owned published vacancy can be closed'; end if;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'contractor','contractor_vacancy_closed','employer_requirement',p_requirement_id,'contractor',jsonb_build_object('prior_stage','open'));
 return true; end;
$$;
revoke all on function public.delete_company_portal_draft_vacancy(uuid), public.withdraw_company_portal_vacancy(uuid), public.close_company_portal_open_vacancy(uuid), public.delete_contractor_portal_draft_vacancy(uuid), public.withdraw_contractor_portal_vacancy(uuid), public.close_contractor_portal_open_vacancy(uuid) from public, anon;
grant execute on function public.delete_company_portal_draft_vacancy(uuid), public.withdraw_company_portal_vacancy(uuid), public.close_company_portal_open_vacancy(uuid), public.delete_contractor_portal_draft_vacancy(uuid), public.withdraw_contractor_portal_vacancy(uuid), public.close_contractor_portal_open_vacancy(uuid) to authenticated;

-- M046/M047 final safe projections.  The existing Contractor projection is
-- deliberately preserved; the preflight above refuses a security mismatch.
create function public.list_company_portal_requirements(p_search text default null,p_stage text default null,p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,department text,job_role text,job_location text,required_headcount integer,filled_positions integer,qualification text,experience_requirement text,gender_preference text,age_min integer,age_max integer,salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,accommodation_status text,accommodation_charge_amount numeric,accommodation_charge_basis text,shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,interview_location text,interview_date timestamptz,additional_notes text,requirement_stage text,requirement_visibility text,application_count bigint,interview_count bigint,selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid:=private.current_company_portal_id(true); v_term text:=nullif(btrim(p_search),''); v_stage text:=nullif(lower(btrim(p_stage)), '');
begin
 if v_company_id is null then raise exception 'Active Company access is required'; end if;
 if v_stage is not null and v_stage not in ('draft','open','on_hold','filled','closed','cancelled') then raise exception 'Unsupported requirement stage'; end if;
 return query select r.id,r.requirement_code,r.department,r.job_role,r.job_location,r.required_headcount,r.filled_positions,r.qualification,r.experience_requirement,r.gender_preference,r.age_min,r.age_max,r.salary_min,r.salary_max,r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.accommodation_status,r.accommodation_charge_amount,r.accommodation_charge_basis,r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,r.accommodation,r.interview_location,r.interview_date,r.additional_notes,r.requirement_stage,r.requirement_visibility,count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id where r.company_id=v_company_id and (v_stage is null or r.requirement_stage=v_stage) and (v_term is null or r.requirement_code ilike '%'||v_term||'%' or r.job_role ilike '%'||v_term||'%' or r.job_location ilike '%'||v_term||'%') group by r.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;
revoke all on function public.list_company_portal_requirements(text,text,integer,integer) from public, anon;
grant execute on function public.list_company_portal_requirements(text,text,integer,integer) to authenticated;

create function public.get_company_portal_requirement(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid := private.current_company_portal_id(true); v_result jsonb;
begin
  if v_company_id is null then raise exception 'Active Company access is required'; end if;
  select jsonb_build_object(
    'requirement_code',r.requirement_code,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,'review_status',r.review_status,'review_feedback',r.review_feedback,'submitted_at',r.submitted_at,'reviewed_at',r.reviewed_at,'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'created_at',r.created_at,'updated_at',r.updated_at,
    'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct i.id),'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct j.id) filter(where j.joining_status='joined')))
  into v_result from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id left join public.candidate_joinings j on j.application_id=a.id
  where r.id=p_requirement_id and r.company_id=v_company_id group by r.id;
  if v_result is null then raise exception 'Company requirement was not found'; end if;
  return v_result;
end;
$$;

create function public.get_contractor_portal_vacancy(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_contractor_id uuid := private.current_contractor_portal_id(true); v_result jsonb;
begin
  if v_contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  select jsonb_build_object(
    'requirement_code',r.requirement_code,'client_name',r.company_name,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),'interview_location',r.interview_location,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,'submission_status',rc.submission_status,'normalized_review_status',private.normalized_vacancy_review_status(r.id),'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'review_feedback',rc.review_feedback,'submitted_at',rc.submitted_at,'reviewed_at',rc.reviewed_at,'created_at',r.created_at,'updated_at',r.updated_at,
    'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct i.id),'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct j.id) filter(where j.joining_status='joined')))
  into v_result from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id left join public.candidate_joinings j on j.application_id=a.id
  where r.id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' group by r.id,rc.id;
  if v_result is null then raise exception 'Contractor vacancy was not found'; end if;
  return v_result;
end;
$$;

revoke all on function public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid) from public,anon;
grant execute on function public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid) to authenticated;

create function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,company_worksite_name text,department text,job_location text,open_positions integer,qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,accommodation_status text,accommodation_charge_amount numeric,accommodation_charge_basis text,interview_location text,interview_date timestamptz,expected_joining_date date,safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_candidate_id uuid:=private.current_candidate_portal_id(); v_term text:=nullif(btrim(p_search),'');
begin
 if v_candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
 return query select r.requirement_code,r.job_role,r.company_name,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,r.qualification,r.iti_trade,r.experience_requirement,r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,r.accommodation,r.accommodation_status,r.accommodation_charge_amount,r.accommodation_charge_basis,r.interview_location,r.interview_date,r.expected_joining_date,r.additional_notes,exists(select 1 from public.candidate_applications a where a.candidate_id=v_candidate_id and a.requirement_id=r.id) from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null and (v_term is null or r.requirement_code ilike '%'||v_term||'%' or r.job_role ilike '%'||v_term||'%' or coalesce(r.job_location,'') ilike '%'||v_term||'%') order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;
revoke all on function public.list_candidate_job_opportunities(text,integer,integer) from public, anon;
grant execute on function public.list_candidate_job_opportunities(text,integer,integer) to authenticated;

-- M048 prerequisite: create the reviewed extended Contractor shape from the
-- preserved historical base RPC.  It intentionally does not replace it.
create function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid,p_client_name text,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,p_accommodation text,p_interview_location text,p_expected_joining_date date,p_additional_notes text,p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz) language plpgsql security definer set search_path='' as $$
declare v_result record; v_action text:=lower(btrim(coalesce(p_action,''))); v_updated public.employer_requirements%rowtype;
begin
 select * into v_result from public.manage_contractor_portal_vacancy(p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes);
 if v_action in ('create','create_draft','create_and_submit','update','update_draft') then update public.employer_requirements set payable_days=p_payable_days,basic_da=p_basic_da,attendance_bonus=p_attendance_bonus,monthly_bonus=p_monthly_bonus,leave_amount=p_leave_amount,other_fixed_earning=p_other_fixed_earning,gross_wages=p_gross_wages,employee_pf=p_employee_pf,employee_esic=p_employee_esic,canteen_deduction=p_canteen_deduction,other_deduction=p_other_deduction,employer_pf=p_employer_pf,employer_esic=p_employer_esic,gratuity_provision=p_gratuity_provision,bonus_provision=p_bonus_provision,leave_provision=p_leave_provision,other_ctc_component=p_other_ctc_component,approx_in_hand=p_approx_in_hand,ctc=p_ctc,accommodation_status=p_accommodation_status,accommodation_charge_amount=p_accommodation_charge_amount,accommodation_charge_basis=p_accommodation_charge_basis where id=v_result.id returning * into v_updated; end if;
 return query select v_result.id,v_result.requirement_code,v_result.submission_status,v_result.requirement_stage,coalesce(v_updated.updated_at,v_result.updated_at);
end;
$$;
revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) from public, anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) to authenticated;

-- Exact M049 prerequisite postflight.  Do not create its ledger, idempotent
-- overload, or Candidate terms objects here: those remain separate migrations.
do $$
begin
 if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)') is null
    or to_regprocedure('private.vacancy_compensation_projection(public.employer_requirements)') is null
    or to_regprocedure('private.vacancy_accommodation_projection(public.employer_requirements)') is null
    or to_regprocedure('private.vacancy_is_application_eligible(uuid)') is null
    or exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('assert_contractor_expected_joining_date','enforce_contractor_expected_joining_date'))
    or to_regclass('private.contractor_vacancy_submission_requests') is not null
    or to_regclass('private.vacancy_candidate_benefits') is not null then
   raise exception 'Pre-M050 reconciliation postflight failed; M049/M050 must remain absent';
 end if;
 if has_table_privilege('authenticated','public.candidate_applications','insert,update')
    or has_table_privilege('authenticated','public.candidate_joinings','insert,update')
    or has_function_privilege('anon','private.vacancy_compensation_projection(public.employer_requirements)','execute')
    or has_function_privilege('authenticated','private.vacancy_compensation_projection(public.employer_requirements)','execute') then
   raise exception 'Direct-write or private-helper browser privilege regression';
 end if;
end;
$$;

commit;
