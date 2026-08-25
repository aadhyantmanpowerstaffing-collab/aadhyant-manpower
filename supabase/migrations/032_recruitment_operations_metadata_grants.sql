-- Recruitment Operations Core Phase A: remove inherited browser UPDATE access.
-- Security-only correction; no data, RLS, function, or lifecycle changes.
begin;

do $$
begin
  if to_regclass('public.recruitment_source_vocabulary') is null
     or to_regprocedure('public.admin_list_recruitment_attention(integer,integer)') is null then
    raise exception 'Phase A 030/031 prerequisites are missing';
  end if;
  if not has_table_privilege('authenticated','public.contractors','UPDATE') then
    raise exception 'Expected inherited Contractor UPDATE posture is missing';
  end if;
  if has_table_privilege('authenticated','public.employer_requirements','UPDATE') or has_table_privilege('authenticated','public.candidates','UPDATE') then
    raise exception 'Unexpected broad UPDATE posture on Requirements or Candidates';
  end if;
end;
$$;

revoke update on public.contractors from authenticated;
revoke update on public.employer_requirements from authenticated;
revoke update on public.candidates from authenticated;

do $$
begin
  if has_table_privilege('authenticated','public.contractors','UPDATE')
     or has_table_privilege('authenticated','public.employer_requirements','UPDATE')
     or has_table_privilege('authenticated','public.candidates','UPDATE') then
    raise exception 'Broad authenticated UPDATE privilege remains after migration 032';
  end if;
  if exists(select 1 from information_schema.column_privileges where table_schema='public' and grantee='authenticated' and privilege_type='UPDATE' and table_name in ('employer_requirements','candidates','contractors') and column_name in ('source_type','source_detail','source_reference','attributed_at','acquisition_source_type','acquisition_source_detail','acquisition_source_reference','acquisition_attributed_at','owner_staff_user_id','owner_assigned_at','owner_assigned_by','next_action','follow_up_due_at','qualified_at','lost_reason','operational_updated_at')) then
    raise exception 'Phase A metadata UPDATE privilege remains after migration 032';
  end if;
  if has_function_privilege('anon','public.admin_list_recruitment_attention(integer,integer)','execute') or not has_function_privilege('authenticated','public.admin_list_recruitment_attention(integer,integer)','execute') then
    raise exception 'Phase A RPC grant posture changed unexpectedly';
  end if;
end;
$$;

commit;
