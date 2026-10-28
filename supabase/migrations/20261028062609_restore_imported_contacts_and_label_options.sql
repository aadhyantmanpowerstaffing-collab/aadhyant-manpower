-- Re-import explicitly restores only the supplied identities; permissions/history stay intact.
begin;
create or replace function public.admin_import_sharing_contacts(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; phone text; target uuid; candidate uuid; matches integer; added integer:=0; reused integer:=0; restored integer:=0; changed integer:=0; seen text[]:='{}';
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 500
    or octet_length(p_rows::text)>1048576 then raise exception 'Import requires 1 to 500 rows'; end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    phone:=item->>'Mobile';
    if phone is null or phone !~ '^[6-9][0-9]{9}$' or coalesce(length(btrim(item->>'Name')),0) not between 1 and 160
      or (item->>'Age') is null or (item->>'Age') !~ '^[0-9]{1,2}$' or (item->>'Age')::integer not between 18 and 75
      or item->>'Gender' is null or item->>'Gender' not in ('Male','Female','Other / Prefer not to say')
      or coalesce(length(btrim(item->>'State')),0) not between 1 and 160
      or coalesce(length(btrim(item->>'District')),0) not between 1 and 160
      or length(coalesce(item->>'Email',''))>254 or jsonb_typeof(item) is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(item) k where k not in ('Name','Email','Mobile','Gender','Age','State','District'))
      then raise exception 'Invalid import row'; end if;
    if phone=any(seen) then reused:=reused+1; continue; end if;
    seen:=array_append(seen,phone);
    select count(distinct c.id),min(c.id::text)::uuid into matches,candidate from public.candidates c
      where c.profile_status='active' and c.status<>'inactive' and (c.mobile=phone or c.whatsapp_number=phone);
    insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,imported_profile)
      values('+91'||phone,phone,case when matches=1 then candidate else null end,
        case when matches=1 then 'resolved' when matches>1 then 'ambiguous' else 'unresolved' end,item-'Mobile')
      on conflict(provider,provider_address) do nothing returning id into target;
    if target is null then
      reused:=reused+1;
      update public.whatsapp_contacts set console_archived_at=null where provider='whatsapp' and provider_address='+91'||phone and console_archived_at is not null;
      get diagnostics changed=row_count; restored:=restored+changed;
      -- Preserve original identity, STOP, existing consent and subscriber choices.
      update public.whatsapp_contacts set imported_profile=item-'Mobile'
        where provider='whatsapp' and indian_mobile_key=phone and imported_profile='{}'::jsonb;
    else added:=added+1; end if;
    target:=null;
  end loop;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
    values(auth.uid(),'staff','whatsapp.sharing_contacts_imported','whatsapp_contact','admin',jsonb_build_object('added',added,'reused',reused,'restored',restored));
  return jsonb_build_object('added',added,'reused',reused,'restored',restored,'consent_changed',false,'queued',0);
end;
$$;

create or replace function public.admin_console_import_numbers(p_numbers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; phone text; candidate uuid; matches integer; target uuid; added integer:=0; reused integer:=0; restored integer:=0; changed integer:=0;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if jsonb_typeof(p_numbers) is distinct from 'array' or jsonb_array_length(p_numbers) not between 1 and 500 then raise exception 'Import 1 to 500 numbers'; end if;
 for v in select value from jsonb_array_elements(p_numbers) loop
  phone:=regexp_replace(v#>>'{}','[[:space:]()+-]','','g');
  if phone ~ '^91[6-9][0-9]{9}$' then phone:=substr(phone,3); end if;
  if jsonb_typeof(v)<>'string' or phone !~ '^[6-9][0-9]{9}$' then raise exception 'Invalid Indian mobile number'; end if;
  select count(distinct c.id),min(c.id::text)::uuid into matches,candidate from public.candidates c
   where c.profile_status='active' and c.status<>'inactive' and (c.mobile=phone or c.whatsapp_number=phone);
  target:=null;
  insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,imported_profile)
   values('+91'||phone,phone,case when matches=1 then candidate else null end,
    case when matches=1 then 'resolved' when matches>1 then 'ambiguous' else 'unresolved' end,'{"Source":"number_import"}')
   on conflict(provider,provider_address) do nothing returning id into target;
  if target is null then
   reused:=reused+1;
   update public.whatsapp_contacts set console_archived_at=null where provider='whatsapp' and provider_address='+91'||phone and console_archived_at is not null;
   get diagnostics changed=row_count; restored:=restored+changed;
  else added:=added+1;end if;
 end loop;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.numbers_imported','whatsapp_contact','admin',jsonb_build_object('added',added,'reused',reused,'restored',restored));
 return jsonb_build_object('added',added,'reused',reused,'restored',restored,'consent_changed',false,'queued',0);
end; $$;

create function public.admin_console_contact_labels()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
 return (
  with labels as (
   select k.kind,btrim(v.value #>> '{}') label
   from public.whatsapp_contacts w
   cross join (values ('Lists'),('Tags')) k(kind)
   cross join lateral jsonb_array_elements(case when jsonb_typeof(w.imported_profile->k.kind)='array' then w.imported_profile->k.kind else '[]'::jsonb end) v(value)
   where w.console_archived_at is null and jsonb_typeof(v.value)='string'
    and length(btrim(v.value #>> '{}')) between 1 and 60
  )
  select jsonb_build_object(
   'lists',coalesce((select jsonb_agg(label order by label) from (select distinct label from labels where kind='Lists') x),'[]'::jsonb),
   'tags',coalesce((select jsonb_agg(label order by label) from (select distinct label from labels where kind='Tags') x),'[]'::jsonb))
 );
end; $$;
revoke all on function public.admin_console_contact_labels() from public,anon,authenticated,service_role;
grant execute on function public.admin_console_contact_labels() to authenticated;
commit;
