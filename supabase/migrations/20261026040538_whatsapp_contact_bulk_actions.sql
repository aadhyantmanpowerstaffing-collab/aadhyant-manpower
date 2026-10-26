-- Only unused imported contacts can be permanently removed. No message sends.
begin;
create function public.admin_console_delete_contacts(p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid; w public.whatsapp_contacts%rowtype; n integer:=0; kept integer:=0;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if cardinality(p_ids) is null or cardinality(p_ids) not between 1 and 500 or array_position(p_ids,null) is not null then raise exception 'Choose 1 to 500 contacts'; end if;
 -- Lock in stable order. Preserve consent, suppression and canonical history.
 for v_id in select distinct x from unnest(p_ids) x order by x loop
  select * into w from public.whatsapp_contacts where id=v_id for update;
  if not found then continue; end if;
  if w.candidate_id is not null or w.resolution_status<>'unresolved'
   or w.marketing_consent_status<>'unknown' or w.transactional_contact_status<>'unknown'
   or w.consent_recorded_at is not null or w.opted_out_at is not null
   or w.last_inbound_at is not null or w.last_outbound_at is not null
   or w.imported_profile='{}'::jsonb or w.sharing_subscription<>'{}'::jsonb
   or exists(select 1 from public.whatsapp_inbound_messages where contact_id=v_id)
   or exists(select 1 from public.whatsapp_outbound_messages where contact_id=v_id)
   or exists(select 1 from public.whatsapp_campaign_recipients where whatsapp_contact_id=v_id)
  then kept:=kept+1;continue;end if;
  begin
   delete from public.whatsapp_contacts where id=v_id;
   n:=n+1;
  exception when foreign_key_violation then kept:=kept+1;
  end;
 end loop;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.console_contacts_deleted','whatsapp_contact','admin_console',jsonb_build_object('deleted',n,'kept',kept));
 return jsonb_build_object('deleted',n,'kept',kept);
end; $$;
revoke all on function public.admin_console_delete_contacts(uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_delete_contacts(uuid[]) to authenticated;
commit;
