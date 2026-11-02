-- Preserve canonical template identity when switching the verified provider account.
create or replace function public.console_sync_verified_template_subset(p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare preserved jsonb;n integer;
begin
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 100
 or (select count(distinct r->>'id') from jsonb_array_elements(p_rows) r)<>jsonb_array_length(p_rows)
 or (select count(distinct (r->>'name',r->>'language')) from jsonb_array_elements(p_rows) r)<>jsonb_array_length(p_rows)
 then raise exception 'Verified distinct template subset required';end if;
 lock table public.whatsapp_template_catalog in share row exclusive mode;
 -- A provider-account migration can retain names while changing Meta IDs.
 -- Keep the canonical UUID and all campaign foreign keys; never guess by ID alone.
 if exists(select 1 from jsonb_array_elements(p_rows) r join public.whatsapp_template_catalog t on t.meta_id=r->>'id'
 where t.name is distinct from r->>'name' or t.language is distinct from r->>'language') then raise exception 'Verified template identity conflicts';end if;
 update public.whatsapp_template_catalog t set meta_id=r->>'id'
 from jsonb_array_elements(p_rows) r where t.name=r->>'name' and t.language=r->>'language' and t.meta_id is distinct from r->>'id';
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'status',t.status,'compatible',t.compatible,'synced_at',t.synced_at,'buttons',t.buttons)),'[]') into preserved
 from public.whatsapp_template_catalog t where not exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id);
 n:=public.console_sync_templates(p_rows);
 update public.whatsapp_template_catalog t set status=p.status,compatible=p.compatible,synced_at=p.synced_at,buttons=p.buttons
 from jsonb_to_recordset(preserved) as p(id uuid,status text,compatible boolean,synced_at timestamptz,buttons jsonb) where t.id=p.id;
 return n;
end;$$;
revoke all on function public.console_sync_verified_template_subset(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_verified_template_subset(jsonb) to service_role;
