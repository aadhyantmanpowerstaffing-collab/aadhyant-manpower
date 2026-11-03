begin;
-- Owner-requested exception to Admin contact masking. Keep the same Admin
-- authorization, filtered/paginated contact set and interview permission fields.
create or replace function public.admin_console_contacts(p_list text default null,p_tag text default null,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if auth.uid() is null or not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 rows:=public.admin_console_contacts_before_interview_permission(p_list,p_tag,p_offset);
 return coalesce((select jsonb_agg(e.value||jsonb_build_object(
 'full_name',coalesce(nullif(btrim(c.full_name),''),nullif(btrim(w.imported_profile->>'Name'),''),'Contact'),
 'mobile','+91'||w.indian_mobile_key,
 'interview_permission',w.transactional_contact_status,'candidate_linked',w.candidate_id is not null,
 'interview_permission_received_at',w.transactional_permission_recorded_at) order by e.ordinality)
 from jsonb_array_elements(rows) with ordinality e(value,ordinality)
 join public.whatsapp_contacts w on w.id=(e.value->>'contact_id')::uuid
 left join public.candidates c on c.id=w.candidate_id),'[]'::jsonb);
end;$$;
revoke all on function public.admin_console_contacts(text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_contacts(text,text,integer) to authenticated;
commit;
