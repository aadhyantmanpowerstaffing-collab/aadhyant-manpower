-- Recruitment Operations Core Phase A: source, ownership, follow-up and derived attention.
-- Additive only. Do not run outside the approved NONPROD migration procedure.
begin;

do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidates') is null
     or to_regclass('public.contractors') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.staff_profiles') is null
     or to_regprocedure('private.can_manage_recruitment()') is null
     or to_regprocedure('private.set_updated_at()') is null then
    raise exception 'Phase A prerequisites are missing';
  end if;
  if to_regclass('public.recruitment_source_vocabulary') is not null
     or to_regprocedure('public.admin_get_recruitment_attention(integer,integer)') is not null then
    raise exception 'Phase A objects already exist; inspect partial/manual changes instead of re-running';
  end if;
end;
$$;

create table public.recruitment_source_vocabulary (
  source_type text primary key check (source_type in (
    'public_website','candidate_portal','employer_portal','contractor_portal',
    'whatsapp_campaign','admin_manual','referral','campus','iti','csc_vle',
    'field_sourcing','external_job_lead')),
  label text not null,
  active boolean not null default true
);

insert into public.recruitment_source_vocabulary(source_type,label) values
 ('public_website','Public website'),('candidate_portal','Candidate portal'),
 ('employer_portal','Employer portal'),('contractor_portal','Contractor portal'),
 ('whatsapp_campaign','WhatsApp campaign'),('admin_manual','Admin manual'),
 ('referral','Referral'),('campus','Campus'),('iti','ITI'),('csc_vle','CSC / VLE'),
 ('field_sourcing','Field sourcing'),('external_job_lead','External job lead');
alter table public.recruitment_source_vocabulary enable row level security;

alter table public.employer_requirements
  add column source_type text not null default 'admin_manual',
  add column source_detail text,
  add column source_reference text,
  add column attributed_at timestamptz not null default now(),
  add column owner_staff_user_id uuid references public.staff_profiles(user_id) on delete set null,
  add column owner_assigned_at timestamptz,
  add column owner_assigned_by uuid references auth.users(id) on delete set null,
  add column next_action text,
  add column follow_up_due_at timestamptz,
  add column qualified_at timestamptz,
  add column lost_reason text,
  add column operational_updated_at timestamptz not null default now();

alter table public.candidates
  add column acquisition_source_type text not null default 'admin_manual',
  add column acquisition_source_detail text,
  add column acquisition_source_reference text,
  add column acquisition_attributed_at timestamptz not null default now(),
  add column owner_staff_user_id uuid references public.staff_profiles(user_id) on delete set null,
  add column owner_assigned_at timestamptz,
  add column owner_assigned_by uuid references auth.users(id) on delete set null,
  add column next_action text,
  add column follow_up_due_at timestamptz;

alter table public.contractors
  add column acquisition_source_type text not null default 'admin_manual',
  add column acquisition_source_detail text,
  add column acquisition_source_reference text,
  add column acquisition_attributed_at timestamptz not null default now(),
  add column owner_staff_user_id uuid references public.staff_profiles(user_id) on delete set null,
  add column owner_assigned_at timestamptz,
  add column owner_assigned_by uuid references auth.users(id) on delete set null,
  add column next_action text,
  add column follow_up_due_at timestamptz;

alter table public.candidate_applications drop constraint if exists candidate_applications_source_type_check;
alter table public.candidate_applications add constraint candidate_applications_source_type_check check (source_type in (
  'direct','contractor','admin','whatsapp','campus','referral',
  'public_website','candidate_portal','employer_portal','contractor_portal',
  'whatsapp_campaign','admin_manual','iti','csc_vle','field_sourcing','external_job_lead'));

alter table public.employer_requirements add constraint recruitment_requirement_source_type_check check (source_type in ('public_website','candidate_portal','employer_portal','contractor_portal','whatsapp_campaign','admin_manual','referral','campus','iti','csc_vle','field_sourcing','external_job_lead'));
alter table public.candidates add constraint recruitment_candidate_source_type_check check (acquisition_source_type in ('public_website','candidate_portal','employer_portal','contractor_portal','whatsapp_campaign','admin_manual','referral','campus','iti','csc_vle','field_sourcing','external_job_lead'));
alter table public.contractors add constraint recruitment_contractor_source_type_check check (acquisition_source_type in ('public_website','candidate_portal','employer_portal','contractor_portal','whatsapp_campaign','admin_manual','referral','campus','iti','csc_vle','field_sourcing','external_job_lead'));
alter table public.employer_requirements add constraint recruitment_requirement_source_detail_check check (source_detail is null or length(btrim(source_detail)) between 1 and 200);
alter table public.candidates add constraint recruitment_candidate_source_detail_check check (acquisition_source_detail is null or length(btrim(acquisition_source_detail)) between 1 and 200);
alter table public.contractors add constraint recruitment_contractor_source_detail_check check (acquisition_source_detail is null or length(btrim(acquisition_source_detail)) between 1 and 200);
alter table public.employer_requirements add constraint recruitment_requirement_source_reference_check check (source_reference is null or length(btrim(source_reference)) between 1 and 500);
alter table public.candidates add constraint recruitment_candidate_source_reference_check check (acquisition_source_reference is null or length(btrim(acquisition_source_reference)) between 1 and 500);
alter table public.contractors add constraint recruitment_contractor_source_reference_check check (acquisition_source_reference is null or length(btrim(acquisition_source_reference)) between 1 and 500);

create index recruitment_requirements_owner_due_idx on public.employer_requirements(owner_staff_user_id, follow_up_due_at);
create index recruitment_candidates_owner_due_idx on public.candidates(owner_staff_user_id, follow_up_due_at);
create index recruitment_contractors_owner_due_idx on public.contractors(owner_staff_user_id, follow_up_due_at);
create index recruitment_requirements_source_idx on public.employer_requirements(source_type, created_at desc);
create index recruitment_candidates_source_idx on public.candidates(acquisition_source_type, created_at desc);
create index recruitment_contractors_source_idx on public.contractors(acquisition_source_type, created_at desc);

create or replace function private.recruitment_owner_allowed(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_user_id is not null and exists (
    select 1 from public.staff_profiles sp join public.staff_roles sr on sr.user_id=sp.user_id
    where sp.user_id=p_user_id and sp.status='active' and sr.status='active'
      and sr.role in ('super_admin','admin','recruiter','operations')
  );
$$;
revoke all on function private.recruitment_owner_allowed(uuid) from public, anon, authenticated;

create or replace function public.admin_assign_requirement_owner(p_requirement_id uuid,p_owner_staff_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if p_owner_staff_user_id is not null and not (select private.recruitment_owner_allowed(p_owner_staff_user_id)) then raise exception 'Owner must be an active recruitment staff member'; end if;
  update public.employer_requirements set owner_staff_user_id=p_owner_staff_user_id,owner_assigned_at=case when p_owner_staff_user_id is null then null else clock_timestamp() end,owner_assigned_by=case when p_owner_staff_user_id is null then null else actor end,operational_updated_at=clock_timestamp() where id=p_requirement_id;
  if not found then raise exception 'Requirement was not found'; end if; return true;
end; $$;

create or replace function public.admin_assign_candidate_owner(p_candidate_id uuid,p_owner_staff_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if p_owner_staff_user_id is not null and not (select private.recruitment_owner_allowed(p_owner_staff_user_id)) then raise exception 'Owner must be an active recruitment staff member'; end if;
  update public.candidates set owner_staff_user_id=p_owner_staff_user_id,owner_assigned_at=case when p_owner_staff_user_id is null then null else clock_timestamp() end,owner_assigned_by=case when p_owner_staff_user_id is null then null else actor end where id=p_candidate_id;
  if not found then raise exception 'Candidate was not found'; end if; return true;
end; $$;

create or replace function public.admin_assign_contractor_owner(p_contractor_id uuid,p_owner_staff_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if p_owner_staff_user_id is not null and not (select private.recruitment_owner_allowed(p_owner_staff_user_id)) then raise exception 'Owner must be an active recruitment staff member'; end if;
  update public.contractors set owner_staff_user_id=p_owner_staff_user_id,owner_assigned_at=case when p_owner_staff_user_id is null then null else clock_timestamp() end,owner_assigned_by=case when p_owner_staff_user_id is null then null else actor end where id=p_contractor_id;
  if not found then raise exception 'Contractor was not found'; end if; return true;
end; $$;

create or replace function public.admin_set_requirement_follow_up(p_requirement_id uuid,p_next_action text,p_follow_up_due_at timestamptz)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if length(coalesce(btrim(p_next_action),''))>240 then raise exception 'Next action is too long'; end if;
  update public.employer_requirements set next_action=nullif(btrim(coalesce(p_next_action,'')),''),follow_up_due_at=p_follow_up_due_at,operational_updated_at=clock_timestamp() where id=p_requirement_id;
  if not found then raise exception 'Requirement was not found'; end if; return true;
end; $$;

create or replace function public.admin_set_candidate_follow_up(p_candidate_id uuid,p_next_action text,p_follow_up_due_at timestamptz)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if length(coalesce(btrim(p_next_action),''))>240 then raise exception 'Next action is too long'; end if;
  update public.candidates set next_action=nullif(btrim(coalesce(p_next_action,'')),''),follow_up_due_at=p_follow_up_due_at where id=p_candidate_id;
  if not found then raise exception 'Candidate was not found'; end if; return true;
end; $$;

create or replace function public.admin_set_contractor_follow_up(p_contractor_id uuid,p_next_action text,p_follow_up_due_at timestamptz)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if length(coalesce(btrim(p_next_action),''))>240 then raise exception 'Next action is too long'; end if;
  update public.contractors set next_action=nullif(btrim(coalesce(p_next_action,'')),''),follow_up_due_at=p_follow_up_due_at where id=p_contractor_id;
  if not found then raise exception 'Contractor was not found'; end if; return true;
end; $$;

create or replace function public.admin_list_recruitment_attention(p_limit integer default 50,p_offset integer default 0)
returns table(entity_type text,entity_id uuid,reference text,source_type text,next_action text,owner_staff_user_id uuid,due_at timestamptz,reason text,severity text,age_days integer)
language sql stable security definer set search_path = '' as $$
  with rows as (
    select 'requirement'::text entity_type,r.id entity_id,r.requirement_code reference,r.source_type,r.next_action,r.owner_staff_user_id,r.follow_up_due_at due_at,
      case when r.owner_staff_user_id is null then 'Unassigned requirement' when r.requirement_stage='draft' then 'Awaiting qualification' else 'Requirement follow-up due' end reason,
      case when r.follow_up_due_at is not null and r.follow_up_due_at<clock_timestamp() then 'high' else 'normal' end severity,
      greatest(0,(extract(epoch from (clock_timestamp()-coalesce(r.created_at,r.operational_updated_at)))/86400)::integer) age_days
    from public.employer_requirements r where r.requirement_stage not in ('closed','cancelled') and (r.owner_staff_user_id is null or r.follow_up_due_at<=clock_timestamp() or r.requirement_stage='draft')
    union all
    select 'candidate',c.id,c.id::text,c.acquisition_source_type,c.next_action,c.owner_staff_user_id,c.follow_up_due_at,
      case when c.owner_staff_user_id is null then 'Unassigned candidate' when c.profile_completion_status<>'complete' then 'Profile incomplete' else 'Candidate follow-up due' end,
      case when c.follow_up_due_at is not null and c.follow_up_due_at<clock_timestamp() then 'high' else 'normal' end,
      greatest(0,(extract(epoch from (clock_timestamp()-c.created_at))/86400)::integer)
    from public.candidates c where c.status<>'inactive' and (c.owner_staff_user_id is null or c.follow_up_due_at<=clock_timestamp() or c.profile_completion_status<>'complete')
    union all
    select 'contractor',c.id,c.id::text,c.acquisition_source_type,c.next_action,c.owner_staff_user_id,c.follow_up_due_at,
      case when c.owner_staff_user_id is null then 'Unassigned contractor' when c.account_status='pending' then 'Awaiting approval' else 'Contractor follow-up due' end,
      case when c.follow_up_due_at is not null and c.follow_up_due_at<clock_timestamp() then 'high' else 'normal' end,
      greatest(0,(extract(epoch from (clock_timestamp()-c.created_at))/86400)::integer)
    from public.contractors c where c.account_status not in ('rejected','suspended') and (c.owner_staff_user_id is null or c.follow_up_due_at<=clock_timestamp() or c.account_status='pending')
    union all
    select 'application',a.id,a.id::text,a.source_type,null,null,null,
      case when a.application_status='joining_pending' then 'Joining pending' else 'Application aging' end,
      case when a.application_status='joining_pending' then 'high' else 'normal' end,
      greatest(0,(extract(epoch from (clock_timestamp()-a.updated_at))/86400)::integer)
    from public.candidate_applications a where a.application_status in ('applied','screening','shortlisted','selected','joining_pending') and a.updated_at<clock_timestamp()-interval '2 days'
  ) select * from rows order by case when severity='high' then 0 else 1 end,due_at nulls first,age_days desc,entity_id limit least(greatest(coalesce(p_limit,50),1),100) offset greatest(coalesce(p_offset,0),0);
$$;

create or replace function public.admin_correct_requirement_source(p_requirement_id uuid,p_source_type text,p_source_detail text,p_source_reference text,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if not exists(select 1 from public.recruitment_source_vocabulary where source_type=p_source_type and active) then raise exception 'Unsupported source type'; end if;
  if length(coalesce(btrim(p_reason),'')) not between 1 and 500 then raise exception 'Correction reason is required'; end if;
  update public.employer_requirements set source_type=p_source_type,source_detail=nullif(btrim(p_source_detail),''),source_reference=nullif(btrim(p_source_reference),'') where id=p_requirement_id;
  if not found then raise exception 'Requirement was not found'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(actor,'staff','recruitment.source_corrected','employer_requirement',p_requirement_id,'admin',jsonb_build_object('source_type',p_source_type,'reason',btrim(p_reason)));
  return true;
end; $$;

create or replace function public.admin_correct_candidate_source(p_candidate_id uuid,p_source_type text,p_source_detail text,p_source_reference text,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if not exists(select 1 from public.recruitment_source_vocabulary where source_type=p_source_type and active) then raise exception 'Unsupported source type'; end if;
  if length(coalesce(btrim(p_reason),'')) not between 1 and 500 then raise exception 'Correction reason is required'; end if;
  update public.candidates set acquisition_source_type=p_source_type,acquisition_source_detail=nullif(btrim(p_source_detail),''),acquisition_source_reference=nullif(btrim(p_source_reference),'') where id=p_candidate_id;
  if not found then raise exception 'Candidate was not found'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(actor,'staff','recruitment.source_corrected','candidate',p_candidate_id,'admin',jsonb_build_object('source_type',p_source_type,'reason',btrim(p_reason)));
  return true;
end; $$;

create or replace function public.admin_correct_contractor_source(p_contractor_id uuid,p_source_type text,p_source_detail text,p_source_reference text,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if not (select private.can_manage_recruitment()) then raise exception 'Recruitment access is required'; end if;
  if not exists(select 1 from public.recruitment_source_vocabulary where source_type=p_source_type and active) then raise exception 'Unsupported source type'; end if;
  if length(coalesce(btrim(p_reason),'')) not between 1 and 500 then raise exception 'Correction reason is required'; end if;
  update public.contractors set acquisition_source_type=p_source_type,acquisition_source_detail=nullif(btrim(p_source_detail),''),acquisition_source_reference=nullif(btrim(p_source_reference),'') where id=p_contractor_id;
  if not found then raise exception 'Contractor was not found'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(actor,'staff','recruitment.source_corrected','contractor',p_contractor_id,'admin',jsonb_build_object('source_type',p_source_type,'reason',btrim(p_reason)));
  return true;
end; $$;

create or replace function public.admin_list_recruitment_source_options()
returns table(source_type text,label text) language sql stable security definer set search_path = '' as $$
  select source_type,label from public.recruitment_source_vocabulary where active order by label;
$$;

revoke all on public.recruitment_source_vocabulary from public, anon, authenticated;
grant execute on function public.admin_assign_requirement_owner(uuid,uuid) to authenticated;
grant execute on function public.admin_assign_candidate_owner(uuid,uuid) to authenticated;
grant execute on function public.admin_assign_contractor_owner(uuid,uuid) to authenticated;
grant execute on function public.admin_set_requirement_follow_up(uuid,text,timestamptz) to authenticated;
grant execute on function public.admin_set_candidate_follow_up(uuid,text,timestamptz) to authenticated;
grant execute on function public.admin_set_contractor_follow_up(uuid,text,timestamptz) to authenticated;
grant execute on function public.admin_list_recruitment_attention(integer,integer) to authenticated;
grant execute on function public.admin_correct_requirement_source(uuid,text,text,text,text) to authenticated;
grant execute on function public.admin_correct_candidate_source(uuid,text,text,text,text) to authenticated;
grant execute on function public.admin_correct_contractor_source(uuid,text,text,text,text) to authenticated;
grant execute on function public.admin_list_recruitment_source_options() to authenticated;

revoke update(source_type,source_detail,source_reference,attributed_at,owner_staff_user_id,owner_assigned_at,owner_assigned_by,next_action,follow_up_due_at,qualified_at,lost_reason,operational_updated_at) on public.employer_requirements from authenticated;
revoke update(acquisition_source_type,acquisition_source_detail,acquisition_source_reference,acquisition_attributed_at,owner_staff_user_id,owner_assigned_at,owner_assigned_by,next_action,follow_up_due_at) on public.candidates from authenticated;
revoke update(acquisition_source_type,acquisition_source_detail,acquisition_source_reference,acquisition_attributed_at,owner_staff_user_id,owner_assigned_at,owner_assigned_by,next_action,follow_up_due_at) on public.contractors from authenticated;

commit;
