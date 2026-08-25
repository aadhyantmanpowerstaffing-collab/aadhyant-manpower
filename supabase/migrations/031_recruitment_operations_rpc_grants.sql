-- Recruitment Operations Core Phase A: correct installed RPC EXECUTE posture.
-- Additive privilege correction only; migration 030 is immutable.
begin;

do $$
declare
  signatures text[] := array[
    'public.admin_assign_requirement_owner(uuid,uuid)',
    'public.admin_assign_candidate_owner(uuid,uuid)',
    'public.admin_assign_contractor_owner(uuid,uuid)',
    'public.admin_set_requirement_follow_up(uuid,text,timestamptz)',
    'public.admin_set_candidate_follow_up(uuid,text,timestamptz)',
    'public.admin_set_contractor_follow_up(uuid,text,timestamptz)',
    'public.admin_list_recruitment_attention(integer,integer)',
    'public.admin_correct_requirement_source(uuid,text,text,text,text)',
    'public.admin_correct_candidate_source(uuid,text,text,text,text)',
    'public.admin_correct_contractor_source(uuid,text,text,text,text)',
    'public.admin_list_recruitment_source_options()'
  ];
  signature text;
begin
  if to_regclass('public.recruitment_source_vocabulary') is null
     or to_regprocedure('private.phase_a_sla()') is null
     or to_regprocedure('private.can_manage_recruitment_operations()') is null then
    raise exception 'Migration 030 Phase A prerequisites are missing';
  end if;
  foreach signature in array signatures loop
    if to_regprocedure(signature) is null then raise exception 'Expected Phase A RPC is missing: %', signature; end if;
    if not has_function_privilege('public', signature, 'execute') then raise exception 'Expected pre-correction PUBLIC EXECUTE posture is missing: %', signature; end if;
  end loop;
end;
$$;

revoke all on function public.admin_assign_requirement_owner(uuid,uuid) from public;
revoke all on function public.admin_assign_requirement_owner(uuid,uuid) from anon;
revoke all on function public.admin_assign_requirement_owner(uuid,uuid) from authenticated;
grant execute on function public.admin_assign_requirement_owner(uuid,uuid) to authenticated;
revoke all on function public.admin_assign_candidate_owner(uuid,uuid) from public;
revoke all on function public.admin_assign_candidate_owner(uuid,uuid) from anon;
revoke all on function public.admin_assign_candidate_owner(uuid,uuid) from authenticated;
grant execute on function public.admin_assign_candidate_owner(uuid,uuid) to authenticated;
revoke all on function public.admin_assign_contractor_owner(uuid,uuid) from public;
revoke all on function public.admin_assign_contractor_owner(uuid,uuid) from anon;
revoke all on function public.admin_assign_contractor_owner(uuid,uuid) from authenticated;
grant execute on function public.admin_assign_contractor_owner(uuid,uuid) to authenticated;
revoke all on function public.admin_set_requirement_follow_up(uuid,text,timestamptz) from public;
revoke all on function public.admin_set_requirement_follow_up(uuid,text,timestamptz) from anon;
revoke all on function public.admin_set_requirement_follow_up(uuid,text,timestamptz) from authenticated;
grant execute on function public.admin_set_requirement_follow_up(uuid,text,timestamptz) to authenticated;
revoke all on function public.admin_set_candidate_follow_up(uuid,text,timestamptz) from public;
revoke all on function public.admin_set_candidate_follow_up(uuid,text,timestamptz) from anon;
revoke all on function public.admin_set_candidate_follow_up(uuid,text,timestamptz) from authenticated;
grant execute on function public.admin_set_candidate_follow_up(uuid,text,timestamptz) to authenticated;
revoke all on function public.admin_set_contractor_follow_up(uuid,text,timestamptz) from public;
revoke all on function public.admin_set_contractor_follow_up(uuid,text,timestamptz) from anon;
revoke all on function public.admin_set_contractor_follow_up(uuid,text,timestamptz) from authenticated;
grant execute on function public.admin_set_contractor_follow_up(uuid,text,timestamptz) to authenticated;
revoke all on function public.admin_list_recruitment_attention(integer,integer) from public;
revoke all on function public.admin_list_recruitment_attention(integer,integer) from anon;
revoke all on function public.admin_list_recruitment_attention(integer,integer) from authenticated;
grant execute on function public.admin_list_recruitment_attention(integer,integer) to authenticated;
revoke all on function public.admin_correct_requirement_source(uuid,text,text,text,text) from public;
revoke all on function public.admin_correct_requirement_source(uuid,text,text,text,text) from anon;
revoke all on function public.admin_correct_requirement_source(uuid,text,text,text,text) from authenticated;
grant execute on function public.admin_correct_requirement_source(uuid,text,text,text,text) to authenticated;
revoke all on function public.admin_correct_candidate_source(uuid,text,text,text,text) from public;
revoke all on function public.admin_correct_candidate_source(uuid,text,text,text,text) from anon;
revoke all on function public.admin_correct_candidate_source(uuid,text,text,text,text) from authenticated;
grant execute on function public.admin_correct_candidate_source(uuid,text,text,text,text) to authenticated;
revoke all on function public.admin_correct_contractor_source(uuid,text,text,text,text) from public;
revoke all on function public.admin_correct_contractor_source(uuid,text,text,text,text) from anon;
revoke all on function public.admin_correct_contractor_source(uuid,text,text,text,text) from authenticated;
grant execute on function public.admin_correct_contractor_source(uuid,text,text,text,text) to authenticated;
revoke all on function public.admin_list_recruitment_source_options() from public;
revoke all on function public.admin_list_recruitment_source_options() from anon;
revoke all on function public.admin_list_recruitment_source_options() from authenticated;
grant execute on function public.admin_list_recruitment_source_options() to authenticated;

do $$
declare
  signatures text[] := array[
    'public.admin_assign_requirement_owner(uuid,uuid)','public.admin_assign_candidate_owner(uuid,uuid)','public.admin_assign_contractor_owner(uuid,uuid)',
    'public.admin_set_requirement_follow_up(uuid,text,timestamptz)','public.admin_set_candidate_follow_up(uuid,text,timestamptz)','public.admin_set_contractor_follow_up(uuid,text,timestamptz)',
    'public.admin_list_recruitment_attention(integer,integer)','public.admin_correct_requirement_source(uuid,text,text,text,text)','public.admin_correct_candidate_source(uuid,text,text,text,text)','public.admin_correct_contractor_source(uuid,text,text,text,text)','public.admin_list_recruitment_source_options()'
  ]; signature text; def text;
begin
  foreach signature in array signatures loop
    if has_function_privilege('public',signature,'execute') or has_function_privilege('anon',signature,'execute') or not has_function_privilege('authenticated',signature,'execute') then raise exception 'Migration 031 grant post-condition failed: %',signature; end if;
    select pg_get_functiondef(to_regprocedure(signature)) into def;
    if def not ilike '%security definer%' or def not ilike '%set search_path to ''''%' then raise exception 'Phase A function security posture changed: %',signature; end if;
  end loop;
end;
$$;

commit;
