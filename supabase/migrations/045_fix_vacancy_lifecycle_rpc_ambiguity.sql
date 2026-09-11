-- Batch 2 corrective migration: remove PL/pgSQL lifecycle-RPC identifier ambiguity.
-- Migration 044 is installed and immutable. This migration preserves its six public
-- callable signatures, authorization, lifecycle transitions, audit records, and
-- dependency guards while using unambiguous local identifiers.
begin;

create or replace function public.delete_company_portal_draft_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_company_id uuid; v_requirement public.employer_requirements%rowtype;
begin
  if v_actor is null or not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  v_company_id := (select private.current_company_portal_id(true));
  select r.* into v_requirement from public.employer_requirements r where r.id=p_requirement_id and r.company_id=v_company_id and r.source_type='employer_portal' for update;
  if v_requirement.id is null then raise exception 'Company vacancy was not found'; end if;
  if v_requirement.review_status<>'draft' or v_requirement.requirement_stage<>'draft' then raise exception 'Only a draft vacancy can be deleted'; end if;
  if private.vacancy_has_recruitment_dependencies(v_requirement.id,null) then raise exception 'Vacancies with recruitment dependencies cannot be deleted'; end if;
  delete from public.employer_requirements r where r.id=v_requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_actor,'company','company_vacancy_draft_deleted','employer_requirement',v_requirement.id,'company',jsonb_build_object('requirement_code',v_requirement.requirement_code));
  return true;
end;
$$;

create or replace function public.withdraw_company_portal_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_company_id uuid; v_requirement public.employer_requirements%rowtype;
begin
  if v_actor is null or not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  v_company_id := (select private.current_company_portal_id(true));
  select r.* into v_requirement from public.employer_requirements r where r.id=p_requirement_id and r.company_id=v_company_id and r.source_type='employer_portal' for update;
  if v_requirement.id is null then raise exception 'Company vacancy was not found'; end if;
  if v_requirement.review_status<>'pending_review' then raise exception 'Only a pending-review vacancy can be withdrawn'; end if;
  update public.employer_requirements r set review_status='closed',requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp()
    where r.id=v_requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_actor,'company','company_vacancy_withdrawn','employer_requirement',v_requirement.id,'company',jsonb_build_object('prior_review_status','pending_review'));
  return true;
end;
$$;

create or replace function public.close_company_portal_open_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_company_id uuid; v_requirement public.employer_requirements%rowtype;
begin
  if v_actor is null or not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  v_company_id := (select private.current_company_portal_id(true));
  select r.* into v_requirement from public.employer_requirements r where r.id=p_requirement_id and r.company_id=v_company_id and r.source_type='employer_portal' for update;
  if v_requirement.id is null then raise exception 'Company vacancy was not found'; end if;
  if v_requirement.review_status<>'approved' or v_requirement.requirement_stage<>'open' or v_requirement.requirement_visibility<>'public' then raise exception 'Only a published open vacancy can be closed'; end if;
  update public.employer_requirements r set review_status='closed',requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp()
    where r.id=v_requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_actor,'company','company_vacancy_closed','employer_requirement',v_requirement.id,'company',jsonb_build_object('prior_stage','open'));
  return true;
end;
$$;

create or replace function public.delete_contractor_portal_draft_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_contractor_id uuid; v_requirement public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype;
begin
  if v_actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  v_contractor_id := (select private.current_contractor_portal_id(true));
  select r.* into v_requirement from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
  select rc.* into v_link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' for update;
  if v_requirement.id is null or v_link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if v_link.submission_status<>'draft' or v_requirement.requirement_stage<>'draft' then raise exception 'Only a draft vacancy can be deleted'; end if;
  if private.vacancy_has_recruitment_dependencies(v_requirement.id,v_link.id) then raise exception 'Vacancies with recruitment dependencies cannot be deleted'; end if;
  delete from public.requirement_contractors rc where rc.id=v_link.id;
  delete from public.employer_requirements r where r.id=v_requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_actor,'contractor','contractor_vacancy_draft_deleted','employer_requirement',v_requirement.id,'contractor',jsonb_build_object('requirement_code',v_requirement.requirement_code));
  return true;
end;
$$;

create or replace function public.withdraw_contractor_portal_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_contractor_id uuid; v_requirement public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype;
begin
  if v_actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  v_contractor_id := (select private.current_contractor_portal_id(true));
  select r.* into v_requirement from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
  select rc.* into v_link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' for update;
  if v_requirement.id is null or v_link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if v_link.submission_status not in ('submitted','under_review') then raise exception 'Only a pending-review vacancy can be withdrawn'; end if;
  update public.requirement_contractors rc set submission_status='cancelled',closed_at=clock_timestamp() where rc.id=v_link.id;
  update public.employer_requirements r set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where r.id=v_requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_actor,'contractor','contractor_vacancy_withdrawn','employer_requirement',v_requirement.id,'contractor',jsonb_build_object('prior_submission_status',v_link.submission_status));
  return true;
end;
$$;

create or replace function public.close_contractor_portal_open_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_contractor_id uuid; v_requirement public.employer_requirements%rowtype; v_link public.requirement_contractors%rowtype;
begin
  if v_actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  v_contractor_id := (select private.current_contractor_portal_id(true));
  select r.* into v_requirement from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
  select rc.* into v_link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission' for update;
  if v_requirement.id is null or v_link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if v_link.submission_status<>'approved' or v_requirement.requirement_stage<>'open' or v_requirement.requirement_visibility<>'public' then raise exception 'Only a published open vacancy can be closed'; end if;
  update public.requirement_contractors rc set submission_status='closed',assignment_status='completed',closed_at=clock_timestamp() where rc.id=v_link.id;
  update public.employer_requirements r set review_status='closed',requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where r.id=v_requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_actor,'contractor','contractor_vacancy_closed','employer_requirement',v_requirement.id,'contractor',jsonb_build_object('prior_stage','open'));
  return true;
end;
$$;

-- CREATE OR REPLACE retains the M044 grants. Reassert the exact browser boundary
-- and make the migration fail closed if a function's security contract drifted.
revoke all on function public.delete_company_portal_draft_vacancy(uuid),public.withdraw_company_portal_vacancy(uuid),public.close_company_portal_open_vacancy(uuid),
  public.delete_contractor_portal_draft_vacancy(uuid),public.withdraw_contractor_portal_vacancy(uuid),public.close_contractor_portal_open_vacancy(uuid) from public,anon;
grant execute on function public.delete_company_portal_draft_vacancy(uuid),public.withdraw_company_portal_vacancy(uuid),public.close_company_portal_open_vacancy(uuid),
  public.delete_contractor_portal_draft_vacancy(uuid),public.withdraw_contractor_portal_vacancy(uuid),public.close_contractor_portal_open_vacancy(uuid) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('delete_company_portal_draft_vacancy','withdraw_company_portal_vacancy','close_company_portal_open_vacancy',
      'delete_contractor_portal_draft_vacancy','withdraw_contractor_portal_vacancy','close_contractor_portal_open_vacancy')
      and (not p.prosecdef or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%'
        or not has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))
  ) then
    raise exception 'Migration 045 vacancy lifecycle RPC security postcondition failed';
  end if;
end;
$$;

commit;
