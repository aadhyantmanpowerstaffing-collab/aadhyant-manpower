-- Batch D: server-authorized joining lifecycle, fulfillment, and correction hardening.

begin;

do $$
begin
  if to_regclass('public.candidate_applications') is null
     or to_regclass('public.candidate_joinings') is null
     or to_regclass('public.employer_requirements') is null
     or to_regclass('public.audit_logs') is null
     or to_regclass('public.application_stage_history') is null then
    raise exception 'Batch D prerequisite recruitment tables are missing';
  end if;
  if to_regprocedure('private.can_manage_joinings()') is null
     or to_regprocedure('private.is_bootstrap_recruitment_admin()') is null
     or to_regprocedure('private.has_staff_role(text)') is null
     or to_regprocedure('public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)') is null
     or to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') is null
     or to_regprocedure('public.set_company_requirement_stage(uuid,text,text)') is null then
    raise exception 'Batch D prerequisite recruitment functions are missing';
  end if;
  if to_regprocedure('public.create_recruitment_joining(uuid,date,text,text,uuid)') is not null
     or to_regprocedure('public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid)') is not null
     or to_regprocedure('public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid)') is not null
     or to_regprocedure('public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)') is not null
     or to_regprocedure('private.can_correct_joinings()') is not null
     or to_regprocedure('private.joining_application_status(text)') is not null
     or to_regprocedure('private.validate_candidate_joining_dates()') is not null
     or exists(select 1 from pg_constraint where conrelid='public.candidate_joinings'::regclass and conname='candidate_joinings_actual_date_state_check')
     or exists(select 1 from pg_trigger where tgrelid='public.candidate_joinings'::regclass and tgname='candidate_joinings_validate_dates') then
    raise exception 'Batch D migration objects already exist; inspect database state instead of re-running';
  end if;

  if exists(
    select 1
    from public.employer_requirements r
    left join lateral (
      select count(*)::integer joined_count
      from public.candidate_joinings j
      join public.candidate_applications a on a.id=j.application_id
      where a.requirement_id=r.id and j.joining_status='joined'
    ) occupancy on true
    where r.filled_positions<>occupancy.joined_count
  ) then raise exception 'Batch D preflight failed: fulfillment counter mismatch'; end if;

  if exists(select 1 from public.employer_requirements where filled_positions<0 or filled_positions>required_headcount) then
    raise exception 'Batch D preflight failed: requirement is over headcount';
  end if;

  if exists(
    select 1
    from public.candidate_joinings j
    join public.candidate_applications a on a.id=j.application_id
    where a.application_status<>case
      when j.joining_status in ('pending','confirmed','deferred') then 'joining_pending'
      when j.joining_status='joined' then 'joined'
      when j.joining_status in ('no_show','cancelled') then 'cancelled'
      when j.joining_status='left' then 'left'
    end
  ) then raise exception 'Batch D preflight failed: application and joining state mismatch'; end if;

  if exists(select 1 from public.candidate_joinings where joining_status in ('joined','left') and actual_joining_date is null) then
    raise exception 'Batch D preflight failed: Joined or Left record lacks an actual joining date';
  end if;

  if exists(select 1 from public.candidate_joinings where joining_status in ('pending','confirmed','deferred') and expected_joining_date is null) then
    raise exception 'Batch D preflight failed: active joining record lacks an expected joining date';
  end if;

  if exists(select 1 from public.candidate_joinings where actual_joining_date>(clock_timestamp() at time zone 'Asia/Kolkata')::date) then
    raise exception 'Batch D preflight failed: future actual joining date exists';
  end if;

  if exists(
    select 1 from public.employer_requirements
    where (filled_positions=required_headcount and (requirement_stage<>'filled' or requirement_visibility<>'private' or status<>'fulfilled'))
       or (requirement_stage in ('filled','closed','cancelled') and requirement_visibility='public')
  ) then raise exception 'Batch D preflight failed: incompatible full or terminal requirement state'; end if;
end;
$$;

create function private.can_correct_joinings()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select private.is_bootstrap_recruitment_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'));
$$;

create function private.joining_application_status(p_joining_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_joining_status
    when 'pending' then 'joining_pending'
    when 'confirmed' then 'joining_pending'
    when 'deferred' then 'joining_pending'
    when 'joined' then 'joined'
    when 'no_show' then 'cancelled'
    when 'cancelled' then 'cancelled'
    when 'left' then 'left'
  end;
$$;

create function private.validate_candidate_joining_dates()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  if new.joining_status in ('pending','confirmed','deferred') and new.expected_joining_date is null then
    raise exception 'Active joining workflow requires an expected joining date';
  end if;
  if new.joining_status in ('joined','left') and new.actual_joining_date is null then
    raise exception 'Joined or Left status requires an actual joining date';
  end if;
  if new.joining_status not in ('joined','left') and new.actual_joining_date is not null then
    raise exception 'Actual joining date requires Joined or Left status';
  end if;
  if new.actual_joining_date is not null and new.actual_joining_date>india_today then
    raise exception 'Actual joining date cannot be in the future';
  end if;
  return new;
end;
$$;

revoke all on function private.can_correct_joinings() from public, anon, authenticated;
revoke all on function private.joining_application_status(text) from public, anon, authenticated;
revoke all on function private.validate_candidate_joining_dates() from public, anon, authenticated;

alter table public.candidate_joinings
  add constraint candidate_joinings_actual_date_state_check
  check (joining_status not in ('joined','left') or actual_joining_date is not null);

create trigger candidate_joinings_validate_dates
  before insert or update of joining_status, expected_joining_date, actual_joining_date on public.candidate_joinings
  for each row execute function private.validate_candidate_joining_dates();

create function public.create_recruitment_joining(
  p_application_id uuid,
  p_expected_date date,
  p_employee_code text default null,
  p_remarks text default null,
  p_correlation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  app public.candidate_applications%rowtype;
  req public.employer_requirements%rowtype;
  current_joining public.candidate_joinings%rowtype;
  joining_id uuid;
  employee text := nullif(btrim(p_employee_code),'');
  notes text := nullif(btrim(p_remarks),'');
begin
  if actor is null or not (select private.can_manage_joinings()) then raise exception 'Joining management access is required'; end if;
  if p_application_id is null or p_correlation_id is null then raise exception 'Application and operation identifiers are required'; end if;
  if p_expected_date is null then raise exception 'Pending joining requires an expected joining date'; end if;
  if length(coalesce(employee,''))>200 or length(coalesce(notes,''))>4000 then raise exception 'Joining details are too long'; end if;

  select * into app from public.candidate_applications where id=p_application_id for update;
  if app.id is null then raise exception 'Application was not found'; end if;
  select * into req from public.employer_requirements where id=app.requirement_id for update;
  if req.id is null then raise exception 'Requirement was not found'; end if;

  select * into current_joining from public.candidate_joinings where application_id=app.id for update;
  if current_joining.id is not null then
    if current_joining.joining_status='pending'
       and current_joining.expected_joining_date=p_expected_date
       and current_joining.actual_joining_date is null
       and current_joining.employee_code is not distinct from employee
       and current_joining.remarks is not distinct from notes
       and app.application_status='joining_pending'
       and exists(select 1 from public.audit_logs where action='recruitment.joining_created'
         and entity_type='candidate_joining' and entity_id=current_joining.id and correlation_id=p_correlation_id) then
      return current_joining.id;
    end if;
    raise exception 'A joining already exists for this application';
  end if;
  if app.application_status<>'selected' then raise exception 'A new joining requires a selected application'; end if;
  if req.requirement_stage<>'open' then raise exception 'A new joining requires an open requirement'; end if;
  if req.filled_positions>=req.required_headcount then raise exception 'Requirement has no remaining joining capacity'; end if;

  insert into public.candidate_joinings(application_id,expected_joining_date,actual_joining_date,joining_status,employee_code,remarks,created_by)
  values(app.id,p_expected_date,null,'pending',employee,notes,actor)
  returning id into joining_id;

  update public.candidate_applications
  set application_status='joining_pending',correlation_id=p_correlation_id
  where id=app.id;

  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff','recruitment.joining_created','candidate_joining',joining_id,'admin',p_correlation_id,
    jsonb_build_object('operation','create','application_id',app.id,'candidate_id',app.candidate_id,'requirement_id',app.requirement_id,
      'old',null,'new',jsonb_build_object('joining_status','pending','expected_joining_date',p_expected_date,
        'actual_joining_date',null,'employee_code',employee,'remarks',notes)));
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff','recruitment.joining_application_synchronized','candidate_application',app.id,'admin',p_correlation_id,
    jsonb_build_object('joining_id',joining_id,'old_status',app.application_status,'new_status','joining_pending'));
  return joining_id;
end;
$$;

create function public.transition_recruitment_joining(
  p_joining_id uuid,
  p_expected_status text,
  p_expected_updated_at timestamptz,
  p_to_status text,
  p_expected_date date,
  p_actual_date date,
  p_employee_code text default null,
  p_remarks text default null,
  p_correlation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  app_id uuid;
  app public.candidate_applications%rowtype;
  req public.employer_requirements%rowtype;
  req_after public.employer_requirements%rowtype;
  current_joining public.candidate_joinings%rowtype;
  changed_joining public.candidate_joinings%rowtype;
  expected_status text := lower(btrim(coalesce(p_expected_status,'')));
  target_status text := lower(btrim(coalesce(p_to_status,'')));
  employee text := nullif(btrim(p_employee_code),'');
  notes text := nullif(btrim(p_remarks),'');
  new_expected date;
  new_actual date;
  target_application_status text;
  allowed boolean := false;
  counter_delta integer := 0;
  india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  if actor is null or not (select private.can_manage_joinings()) then raise exception 'Joining management access is required'; end if;
  if p_joining_id is null or p_correlation_id is null then raise exception 'Joining and operation identifiers are required'; end if;
  if expected_status not in ('pending','confirmed','deferred','joined','no_show','cancelled','left')
     or target_status not in ('pending','confirmed','deferred','joined','no_show','cancelled','left') then raise exception 'Unsupported joining status'; end if;
  if p_expected_updated_at is null then raise exception 'Expected joining version is required'; end if;
  if length(coalesce(employee,''))>200 or length(coalesce(notes,''))>4000 then raise exception 'Joining details are too long'; end if;

  select application_id into app_id from public.candidate_joinings where id=p_joining_id;
  if app_id is null then raise exception 'Joining was not found'; end if;
  select * into app from public.candidate_applications where id=app_id for update;
  if app.id is null then raise exception 'Application was not found'; end if;
  select * into req from public.employer_requirements where id=app.requirement_id for update;
  if req.id is null then raise exception 'Requirement was not found'; end if;
  select * into current_joining from public.candidate_joinings where id=p_joining_id for update;
  if current_joining.id is null or current_joining.application_id<>app.id then raise exception 'Joining context changed; refresh and try again'; end if;

  new_expected := coalesce(p_expected_date,current_joining.expected_joining_date);
  new_actual := case when target_status='joined' then p_actual_date when target_status='left' then current_joining.actual_joining_date else null end;
  target_application_status := private.joining_application_status(target_status);

  if current_joining.joining_status=target_status
     and current_joining.expected_joining_date is not distinct from new_expected
     and current_joining.actual_joining_date is not distinct from new_actual
     and current_joining.employee_code is not distinct from employee
     and current_joining.remarks is not distinct from notes
     and app.application_status=target_application_status
     and exists(select 1 from public.audit_logs where entity_type='candidate_joining' and entity_id=current_joining.id and correlation_id=p_correlation_id) then
    return current_joining.id;
  end if;

  if current_joining.joining_status<>expected_status or current_joining.updated_at<>p_expected_updated_at then
    raise exception 'Joining state changed; refresh and try again';
  end if;
  if app.application_status<>private.joining_application_status(current_joining.joining_status) then
    raise exception 'Application and joining state are inconsistent';
  end if;

  allowed := (current_joining.joining_status,target_status) in (
    ('pending','confirmed'),('pending','deferred'),('pending','joined'),('pending','no_show'),('pending','cancelled'),
    ('confirmed','deferred'),('confirmed','joined'),('confirmed','no_show'),('confirmed','cancelled'),
    ('deferred','confirmed'),('deferred','joined'),('deferred','no_show'),('deferred','cancelled'),
    ('joined','left')
  );
  if not allowed then raise exception 'Unsupported joining transition'; end if;

  if target_status in ('confirmed','deferred','joined') and req.requirement_stage not in ('open','on_hold') then
    raise exception 'Requirement state does not allow joining progression';
  end if;
  if target_status='joined' and req.filled_positions>=req.required_headcount then
    raise exception 'Requirement has no remaining joining capacity';
  end if;
  if target_status in ('pending','confirmed','deferred') and new_expected is null then raise exception 'Active joining workflow requires an expected joining date'; end if;
  if target_status='joined' and new_actual is null then raise exception 'Joined status requires an actual joining date'; end if;
  if target_status='left' and p_actual_date is not null and p_actual_date is distinct from current_joining.actual_joining_date then
    raise exception 'Left must retain the original actual joining date';
  end if;
  if new_actual is not null and new_actual>india_today then raise exception 'Actual joining date cannot be in the future'; end if;
  if target_status in ('no_show','cancelled','left') and notes is null then raise exception 'This joining outcome requires an operational reason'; end if;

  if target_status='joined' then
    counter_delta := 1;
    update public.employer_requirements
    set filled_positions=filled_positions+1,
        requirement_stage=case when filled_positions+1=required_headcount then 'filled' else requirement_stage end,
        requirement_visibility=case when filled_positions+1=required_headcount then 'private' else requirement_visibility end,
        status=case when filled_positions+1=required_headcount then 'fulfilled' else status end,
        closed_at=case when filled_positions+1=required_headcount then coalesce(closed_at,clock_timestamp()) else closed_at end
    where id=req.id and filled_positions<required_headcount
    returning * into req_after;
    if req_after.id is null then raise exception 'Requirement has no remaining joining capacity'; end if;
  elsif current_joining.joining_status='joined' and target_status='left' then
    counter_delta := -1;
    update public.employer_requirements
    set filled_positions=filled_positions-1
    where id=req.id and filled_positions>0
    returning * into req_after;
    if req_after.id is null then raise exception 'Requirement fulfillment is inconsistent'; end if;
  else
    req_after := req;
  end if;

  update public.candidate_joinings
  set expected_joining_date=new_expected,actual_joining_date=new_actual,joining_status=target_status,
      employee_code=employee,remarks=notes
  where id=current_joining.id and joining_status=current_joining.joining_status and updated_at=current_joining.updated_at
  returning * into changed_joining;
  if changed_joining.id is null then raise exception 'Joining state changed; refresh and try again'; end if;

  update public.candidate_applications
  set application_status=target_application_status,correlation_id=p_correlation_id
  where id=app.id;
  if app.application_status<>target_application_status then
    update public.application_stage_history h
    set reason=case when target_status in ('no_show','cancelled','left') then notes else h.reason end,
        metadata=h.metadata||jsonb_build_object('joining_id',current_joining.id)
    where h.id=(select x.id from public.application_stage_history x where x.application_id=app.id and x.correlation_id=p_correlation_id order by x.created_at desc,x.id desc limit 1);
  end if;

  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff','recruitment.joining_transitioned','candidate_joining',current_joining.id,'admin',p_correlation_id,
    jsonb_build_object('operation','transition','application_id',app.id,'candidate_id',app.candidate_id,'requirement_id',app.requirement_id,
      'reason',case when target_status in ('no_show','cancelled','left') then notes else null end,
      'old',jsonb_build_object('joining_status',current_joining.joining_status,'expected_joining_date',current_joining.expected_joining_date,
        'actual_joining_date',current_joining.actual_joining_date,'employee_code',current_joining.employee_code,'remarks',current_joining.remarks),
      'new',jsonb_build_object('joining_status',changed_joining.joining_status,'expected_joining_date',changed_joining.expected_joining_date,
        'actual_joining_date',changed_joining.actual_joining_date,'employee_code',changed_joining.employee_code,'remarks',changed_joining.remarks)));
  if app.application_status<>target_application_status then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.joining_application_synchronized','candidate_application',app.id,'admin',p_correlation_id,
      jsonb_build_object('joining_id',current_joining.id,'old_status',app.application_status,'new_status',target_application_status));
  end if;
  if counter_delta<>0 then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.joining_fulfillment_changed','employer_requirement',req.id,'admin',p_correlation_id,
      jsonb_build_object('joining_id',current_joining.id,'counter_delta',counter_delta,
        'old_filled_positions',req.filled_positions,'new_filled_positions',req_after.filled_positions,'required_headcount',req.required_headcount,
        'old_requirement_stage',req.requirement_stage,'new_requirement_stage',req_after.requirement_stage,
        'old_visibility',req.requirement_visibility,'new_visibility',req_after.requirement_visibility,
      'old_legacy_status',req.status,'new_legacy_status',req_after.status));
  end if;
  if req.requirement_stage is distinct from req_after.requirement_stage
     or req.requirement_visibility is distinct from req_after.requirement_visibility
     or req.status is distinct from req_after.status then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.requirement_lifecycle_changed','employer_requirement',req.id,'admin',p_correlation_id,
      jsonb_build_object('automatic',true,'joining_id',current_joining.id,'reason','Requirement reached full headcount',
        'old',jsonb_build_object('requirement_stage',req.requirement_stage,'requirement_visibility',req.requirement_visibility,
          'legacy_status',req.status,'filled_positions',req.filled_positions,'required_headcount',req.required_headcount),
        'new',jsonb_build_object('requirement_stage',req_after.requirement_stage,'requirement_visibility',req_after.requirement_visibility,
          'legacy_status',req_after.status,'filled_positions',req_after.filled_positions,'required_headcount',req_after.required_headcount)));
  end if;
  return changed_joining.id;
end;
$$;

create function public.update_recruitment_joining_details(
  p_joining_id uuid,
  p_expected_status text,
  p_expected_updated_at timestamptz,
  p_expected_date date,
  p_employee_code text default null,
  p_remarks text default null,
  p_correlation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  app_id uuid;
  app public.candidate_applications%rowtype;
  req public.employer_requirements%rowtype;
  current_joining public.candidate_joinings%rowtype;
  changed_joining public.candidate_joinings%rowtype;
  expected_status text := lower(btrim(coalesce(p_expected_status,'')));
  employee text := nullif(btrim(p_employee_code),'');
  notes text := nullif(btrim(p_remarks),'');
begin
  if actor is null or not (select private.can_manage_joinings()) then raise exception 'Joining management access is required'; end if;
  if p_joining_id is null or p_correlation_id is null or p_expected_updated_at is null then raise exception 'Joining operation context is required'; end if;
  if expected_status not in ('pending','confirmed','deferred') then raise exception 'Only active joining details can be updated normally'; end if;
  if p_expected_date is null then raise exception 'Active joining workflow requires an expected joining date'; end if;
  if length(coalesce(employee,''))>200 or length(coalesce(notes,''))>4000 then raise exception 'Joining details are too long'; end if;

  select application_id into app_id from public.candidate_joinings where id=p_joining_id;
  if app_id is null then raise exception 'Joining was not found'; end if;
  select * into app from public.candidate_applications where id=app_id for update;
  select * into req from public.employer_requirements where id=app.requirement_id for update;
  select * into current_joining from public.candidate_joinings where id=p_joining_id for update;
  if app.id is null or req.id is null or current_joining.id is null or current_joining.application_id<>app.id then raise exception 'Joining context changed; refresh and try again'; end if;
  if current_joining.joining_status=expected_status
     and current_joining.expected_joining_date is not distinct from p_expected_date
     and current_joining.employee_code is not distinct from employee
     and current_joining.remarks is not distinct from notes
     and app.application_status='joining_pending'
     and exists(select 1 from public.audit_logs where action='recruitment.joining_details_updated'
       and entity_type='candidate_joining' and entity_id=current_joining.id and correlation_id=p_correlation_id) then
    return current_joining.id;
  end if;
  if current_joining.joining_status<>expected_status or current_joining.updated_at<>p_expected_updated_at then raise exception 'Joining state changed; refresh and try again'; end if;
  if req.requirement_stage not in ('open','on_hold') then raise exception 'Requirement state does not allow joining detail changes'; end if;
  if app.application_status<>'joining_pending' then raise exception 'Application and joining state are inconsistent'; end if;
  if current_joining.expected_joining_date is not distinct from p_expected_date
     and current_joining.employee_code is not distinct from employee
     and current_joining.remarks is not distinct from notes then
    raise exception 'Joining detail update does not change any value';
  end if;

  update public.candidate_joinings
  set expected_joining_date=p_expected_date,employee_code=employee,remarks=notes
  where id=current_joining.id and joining_status=current_joining.joining_status and updated_at=current_joining.updated_at
  returning * into changed_joining;
  if changed_joining.id is null then raise exception 'Joining state changed; refresh and try again'; end if;

  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff','recruitment.joining_details_updated','candidate_joining',current_joining.id,'admin',p_correlation_id,
    jsonb_build_object('operation','details_update','application_id',app.id,'candidate_id',app.candidate_id,'requirement_id',app.requirement_id,
      'old',jsonb_build_object('joining_status',current_joining.joining_status,'expected_joining_date',current_joining.expected_joining_date,
        'actual_joining_date',current_joining.actual_joining_date,'employee_code',current_joining.employee_code,'remarks',current_joining.remarks),
      'new',jsonb_build_object('joining_status',changed_joining.joining_status,'expected_joining_date',changed_joining.expected_joining_date,
        'actual_joining_date',changed_joining.actual_joining_date,'employee_code',changed_joining.employee_code,'remarks',changed_joining.remarks)));
  return changed_joining.id;
end;
$$;

create function public.correct_recruitment_joining(
  p_joining_id uuid,
  p_expected_updated_at timestamptz,
  p_joining_status text,
  p_expected_date date,
  p_actual_date date,
  p_employee_code text,
  p_remarks text,
  p_reason text,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  app_id uuid;
  app public.candidate_applications%rowtype;
  req public.employer_requirements%rowtype;
  req_after public.employer_requirements%rowtype;
  current_joining public.candidate_joinings%rowtype;
  changed_joining public.candidate_joinings%rowtype;
  target_status text := lower(btrim(coalesce(p_joining_status,'')));
  employee text := nullif(btrim(p_employee_code),'');
  notes text := nullif(btrim(p_remarks),'');
  correction_reason text := nullif(btrim(p_reason),'');
  target_application_status text;
  counter_delta integer;
  india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  if actor is null or not (select private.can_correct_joinings()) then raise exception 'Joining correction access is required'; end if;
  if p_joining_id is null or p_expected_updated_at is null or p_correlation_id is null then raise exception 'Joining correction context is required'; end if;
  if correction_reason is null then raise exception 'Joining correction reason is required'; end if;
  if length(correction_reason)>2000 then raise exception 'Joining correction reason is too long'; end if;
  if target_status not in ('pending','confirmed','deferred','joined','no_show','cancelled','left') then raise exception 'Unsupported joining status'; end if;
  if length(coalesce(employee,''))>200 or length(coalesce(notes,''))>4000 then raise exception 'Joining details are too long'; end if;
  if target_status in ('pending','confirmed','deferred') and p_expected_date is null then raise exception 'Active joining workflow requires an expected joining date'; end if;
  if target_status in ('joined','left') and p_actual_date is null then raise exception 'Joined or Left status requires an actual joining date'; end if;
  if target_status not in ('joined','left') and p_actual_date is not null then raise exception 'Actual joining date requires Joined or Left status'; end if;
  if p_actual_date is not null and p_actual_date>india_today then raise exception 'Actual joining date cannot be in the future'; end if;

  select application_id into app_id from public.candidate_joinings where id=p_joining_id;
  if app_id is null then raise exception 'Joining was not found'; end if;
  select * into app from public.candidate_applications where id=app_id for update;
  select * into req from public.employer_requirements where id=app.requirement_id for update;
  select * into current_joining from public.candidate_joinings where id=p_joining_id for update;
  if app.id is null or req.id is null or current_joining.id is null or current_joining.application_id<>app.id then raise exception 'Joining context changed; refresh and try again'; end if;

  target_application_status := private.joining_application_status(target_status);
  if current_joining.joining_status=target_status
     and current_joining.expected_joining_date is not distinct from p_expected_date
     and current_joining.actual_joining_date is not distinct from p_actual_date
     and current_joining.employee_code is not distinct from employee
     and current_joining.remarks is not distinct from notes
     and app.application_status=target_application_status
     and exists(select 1 from public.audit_logs where action='recruitment.joining_corrected'
       and entity_type='candidate_joining' and entity_id=current_joining.id and correlation_id=p_correlation_id
       and metadata->>'reason'=correction_reason) then
    return current_joining.id;
  end if;
  if current_joining.updated_at<>p_expected_updated_at then raise exception 'Joining state changed; refresh and try again'; end if;
  counter_delta := (case when target_status='joined' then 1 else 0 end)
    - (case when current_joining.joining_status='joined' then 1 else 0 end);
  if current_joining.joining_status=target_status
     and current_joining.expected_joining_date is not distinct from p_expected_date
     and current_joining.actual_joining_date is not distinct from p_actual_date
     and current_joining.employee_code is not distinct from employee
     and current_joining.remarks is not distinct from notes
     and app.application_status=target_application_status then raise exception 'Correction does not change any joining value'; end if;

  if counter_delta=1 then
    if req.requirement_stage in ('draft','closed','cancelled') then raise exception 'Requirement state does not allow a Joined correction'; end if;
    update public.employer_requirements
    set filled_positions=filled_positions+1,
        requirement_stage=case when filled_positions+1=required_headcount then 'filled' else requirement_stage end,
        requirement_visibility=case when filled_positions+1=required_headcount then 'private' else requirement_visibility end,
        status=case when filled_positions+1=required_headcount then 'fulfilled' else status end,
        closed_at=case when filled_positions+1=required_headcount then coalesce(closed_at,clock_timestamp()) else closed_at end
    where id=req.id and filled_positions<required_headcount
    returning * into req_after;
    if req_after.id is null then raise exception 'Requirement has no remaining joining capacity'; end if;
  elsif counter_delta=-1 then
    update public.employer_requirements set filled_positions=filled_positions-1
    where id=req.id and filled_positions>0 returning * into req_after;
    if req_after.id is null then raise exception 'Requirement fulfillment is inconsistent'; end if;
  else
    req_after := req;
  end if;

  update public.candidate_joinings
  set expected_joining_date=p_expected_date,actual_joining_date=p_actual_date,joining_status=target_status,
      employee_code=employee,remarks=notes
  where id=current_joining.id and updated_at=current_joining.updated_at
  returning * into changed_joining;
  if changed_joining.id is null then raise exception 'Joining state changed; refresh and try again'; end if;

  update public.candidate_applications set application_status=target_application_status,correlation_id=p_correlation_id where id=app.id;
  if app.application_status<>target_application_status then
    update public.application_stage_history h
    set reason=correction_reason,metadata=h.metadata||jsonb_build_object('joining_id',current_joining.id,'correction',true)
    where h.id=(select x.id from public.application_stage_history x where x.application_id=app.id and x.correlation_id=p_correlation_id order by x.created_at desc,x.id desc limit 1);
  end if;

  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff','recruitment.joining_corrected','candidate_joining',current_joining.id,'admin',p_correlation_id,
    jsonb_build_object('operation','correction','application_id',app.id,'candidate_id',app.candidate_id,'requirement_id',app.requirement_id,'reason',correction_reason,
      'old',jsonb_build_object('joining_status',current_joining.joining_status,'expected_joining_date',current_joining.expected_joining_date,
        'actual_joining_date',current_joining.actual_joining_date,'employee_code',current_joining.employee_code,'remarks',current_joining.remarks),
      'new',jsonb_build_object('joining_status',changed_joining.joining_status,'expected_joining_date',changed_joining.expected_joining_date,
        'actual_joining_date',changed_joining.actual_joining_date,'employee_code',changed_joining.employee_code,'remarks',changed_joining.remarks)));
  if app.application_status<>target_application_status then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.joining_application_synchronized','candidate_application',app.id,'admin',p_correlation_id,
      jsonb_build_object('joining_id',current_joining.id,'old_status',app.application_status,'new_status',target_application_status,'correction',true,'reason',correction_reason));
  end if;
  if counter_delta<>0 then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.joining_fulfillment_changed','employer_requirement',req.id,'admin',p_correlation_id,
      jsonb_build_object('joining_id',current_joining.id,'counter_delta',counter_delta,'correction',true,'reason',correction_reason,
        'old_filled_positions',req.filled_positions,'new_filled_positions',req_after.filled_positions,'required_headcount',req.required_headcount,
        'old_requirement_stage',req.requirement_stage,'new_requirement_stage',req_after.requirement_stage,
        'old_visibility',req.requirement_visibility,'new_visibility',req_after.requirement_visibility,
        'old_legacy_status',req.status,'new_legacy_status',req_after.status));
  end if;
  if req.requirement_stage is distinct from req_after.requirement_stage
     or req.requirement_visibility is distinct from req_after.requirement_visibility
     or req.status is distinct from req_after.status then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.requirement_lifecycle_changed','employer_requirement',req.id,'admin',p_correlation_id,
      jsonb_build_object('automatic',true,'correction',true,'joining_id',current_joining.id,'reason',correction_reason,
        'old',jsonb_build_object('requirement_stage',req.requirement_stage,'requirement_visibility',req.requirement_visibility,
          'legacy_status',req.status,'filled_positions',req.filled_positions,'required_headcount',req.required_headcount),
        'new',jsonb_build_object('requirement_stage',req_after.requirement_stage,'requirement_visibility',req_after.requirement_visibility,
          'legacy_status',req_after.status,'filled_positions',req_after.filled_positions,'required_headcount',req_after.required_headcount)));
  end if;
  return changed_joining.id;
end;
$$;

create or replace function public.upsert_recruitment_joining(p_application_id uuid,p_expected_date date,p_actual_date date,
  p_joining_status text,p_employee_code text default null,p_remarks text default null,p_correlation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  current_joining public.candidate_joinings%rowtype;
  target_status text := lower(btrim(coalesce(p_joining_status,'')));
  operation_id uuid := coalesce(p_correlation_id,gen_random_uuid());
begin
  if (select auth.uid()) is null or not (select private.can_manage_joinings()) then raise exception 'Joining management access is required'; end if;
  select * into current_joining from public.candidate_joinings where application_id=p_application_id;
  if current_joining.id is null then
    if target_status<>'pending' then raise exception 'A new joining must start as Pending'; end if;
    return public.create_recruitment_joining(p_application_id,p_expected_date,p_employee_code,p_remarks,operation_id);
  end if;
  if target_status=current_joining.joining_status and target_status in ('pending','confirmed','deferred') then
    return public.update_recruitment_joining_details(current_joining.id,current_joining.joining_status,current_joining.updated_at,
      p_expected_date,p_employee_code,p_remarks,operation_id);
  end if;
  if target_status=current_joining.joining_status
     and current_joining.expected_joining_date is not distinct from coalesce(p_expected_date,current_joining.expected_joining_date)
     and current_joining.actual_joining_date is not distinct from (case when target_status in ('joined','left') then coalesce(p_actual_date,current_joining.actual_joining_date) else null end)
     and current_joining.employee_code is not distinct from nullif(btrim(p_employee_code),'')
     and current_joining.remarks is not distinct from nullif(btrim(p_remarks),'') then return current_joining.id; end if;
  return public.transition_recruitment_joining(current_joining.id,current_joining.joining_status,current_joining.updated_at,
    target_status,p_expected_date,p_actual_date,p_employee_code,p_remarks,operation_id);
end;
$$;

create or replace function public.admin_update_candidate_application(
  p_application_id uuid,p_application_status text,p_admin_notes text default null
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  current_application public.candidate_applications%rowtype;
  target_status text := lower(btrim(coalesce(p_application_status,'')));
  notes text := nullif(btrim(p_admin_notes),'');
  operation_id uuid := gen_random_uuid();
  allowed boolean := false;
begin
  if actor is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_application_id is null then raise exception 'Candidate application identifier is required'; end if;
  if target_status not in ('interested','applied','screening','shortlisted','interview','selected','rejected','joining_pending','joined','left','cancelled') then
    raise exception 'Unsupported Candidate application status';
  end if;
  if length(coalesce(notes,''))>4000 then raise exception 'Internal Admin note must be 4000 characters or fewer'; end if;
  select * into current_application from public.candidate_applications where id=p_application_id for update;
  if current_application.id is null then raise exception 'Candidate application was not found'; end if;

  if current_application.application_status in ('joining_pending','joined','left','cancelled') then
    if target_status<>current_application.application_status then raise exception 'Joining-owned application stage must be changed through the joining workflow'; end if;
  elsif target_status in ('joining_pending','joined','left','cancelled') then
    raise exception 'Joining-owned application stage must be changed through the joining workflow';
  elsif target_status<>current_application.application_status then
    allowed := (current_application.application_status,target_status) in (
      ('interested','applied'),('applied','screening'),('screening','shortlisted'),
      ('shortlisted','interview'),('interview','selected'),('interview','rejected'),('selected','rejected')
    );
    if not allowed then raise exception 'Unsupported application stage transition'; end if;
  end if;

  update public.candidate_applications
  set application_status=target_status,admin_notes=notes,
      correlation_id=case when target_status<>current_application.application_status then operation_id else correlation_id end
  where id=current_application.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values(actor,'staff',case when target_status=current_application.application_status then 'recruitment.application_notes_updated' else 'recruitment.application_transitioned' end,
    'candidate_application',current_application.id,'admin',operation_id,
    jsonb_build_object('old',jsonb_build_object('application_status',current_application.application_status,'admin_notes',current_application.admin_notes),
      'new',jsonb_build_object('application_status',target_status,'admin_notes',notes)));
  return true;
end;
$$;

create or replace function public.set_company_requirement_stage(
  p_requirement_id uuid,p_requirement_stage text,p_requirement_visibility text
)
returns public.employer_requirements language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  current_requirement public.employer_requirements%rowtype;
  updated_requirement public.employer_requirements%rowtype;
  operation_id uuid := gen_random_uuid();
begin
  if actor is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_requirement_stage not in ('draft','open','on_hold','filled','closed','cancelled')
     or p_requirement_visibility not in ('private','assigned','public') then raise exception 'Invalid lifecycle value'; end if;
  select * into current_requirement from public.employer_requirements where id=p_requirement_id and company_id is not null for update;
  if current_requirement.id is null then raise exception 'Company requirement was not found'; end if;
  if p_requirement_stage='open' and current_requirement.filled_positions>=current_requirement.required_headcount then
    raise exception 'Requirement has no remaining capacity and cannot be opened';
  end if;
  if p_requirement_stage='filled' and current_requirement.filled_positions<>current_requirement.required_headcount then
    raise exception 'Requirement can be Filled only at full headcount';
  end if;
  if p_requirement_stage='filled' and p_requirement_visibility<>'private' then raise exception 'Filled requirement must be private'; end if;
  if p_requirement_stage in ('closed','cancelled') and p_requirement_visibility='public' then raise exception 'Closed or Cancelled requirement cannot be public'; end if;

  update public.employer_requirements
  set requirement_stage=p_requirement_stage,requirement_visibility=p_requirement_visibility,
      published_at=case when p_requirement_stage='open' then coalesce(published_at,clock_timestamp()) else published_at end,
      closed_at=case when p_requirement_stage in ('filled','closed','cancelled') then coalesce(closed_at,clock_timestamp()) else null end,
      status=case when p_requirement_stage='filled' then 'fulfilled' when p_requirement_stage in ('closed','cancelled') then 'closed'
        when p_requirement_stage='open' then 'in_progress' else status end
  where id=current_requirement.id returning * into updated_requirement;

  if current_requirement.requirement_stage is distinct from updated_requirement.requirement_stage
     or current_requirement.requirement_visibility is distinct from updated_requirement.requirement_visibility
     or current_requirement.status is distinct from updated_requirement.status then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    values(actor,'staff','recruitment.requirement_lifecycle_changed','employer_requirement',updated_requirement.id,'admin',operation_id,
      jsonb_build_object('old',jsonb_build_object('requirement_stage',current_requirement.requirement_stage,
        'requirement_visibility',current_requirement.requirement_visibility,'legacy_status',current_requirement.status,
        'filled_positions',current_requirement.filled_positions,'required_headcount',current_requirement.required_headcount),
        'new',jsonb_build_object('requirement_stage',updated_requirement.requirement_stage,
        'requirement_visibility',updated_requirement.requirement_visibility,'legacy_status',updated_requirement.status,
        'filled_positions',updated_requirement.filled_positions,'required_headcount',updated_requirement.required_headcount)));
  end if;
  return updated_requirement;
end;
$$;

revoke all on function public.create_recruitment_joining(uuid,date,text,text,uuid) from public, anon, authenticated;
revoke all on function public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid) from public, anon, authenticated;
revoke all on function public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid) from public, anon, authenticated;
revoke all on function public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.create_recruitment_joining(uuid,date,text,text,uuid) to authenticated;
grant execute on function public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid) to authenticated;
grant execute on function public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid) to authenticated;
grant execute on function public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid) to authenticated;

-- Migration 038 will separately revoke legacy direct table writes and retire the compatibility wrapper.

commit;
