begin;

revoke execute on function public.admin_assign_requirement_owner(uuid,uuid)
  from public, anon;

revoke execute on function public.admin_assign_candidate_owner(uuid,uuid)
  from public, anon;

revoke execute on function public.admin_assign_contractor_owner(uuid,uuid)
  from public, anon;

revoke execute on function public.admin_set_requirement_follow_up(uuid,text,timestamp with time zone)
  from public, anon;

revoke execute on function public.admin_set_candidate_follow_up(uuid,text,timestamp with time zone)
  from public, anon;

revoke execute on function public.admin_set_contractor_follow_up(uuid,text,timestamp with time zone)
  from public, anon;

revoke execute on function public.admin_list_recruitment_attention(integer,integer)
  from public, anon;

revoke execute on function public.admin_correct_requirement_source(uuid,text,text,text,text)
  from public, anon;

revoke execute on function public.admin_correct_candidate_source(uuid,text,text,text,text)
  from public, anon;

revoke execute on function public.admin_correct_contractor_source(uuid,text,text,text,text)
  from public, anon;

revoke execute on function public.admin_list_recruitment_source_options()
  from public, anon;

commit;
