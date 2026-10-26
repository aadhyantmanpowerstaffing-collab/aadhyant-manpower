-- Admin-only Inbox/Sent identity display; retain masked fields for compatibility.
begin;
create or replace function public.admin_console_inbox(p_folder text default 'inbox',p_filter text default 'all',p_search text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 if p_folder is null or p_folder not in ('inbox','sent') or p_filter is null or p_filter not in ('all','unread','attention','queued','sending','sent','delivered','read','failed')
 or p_search is null or p_search !~ '^[0-9]{0,4}$' or p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid inbox filter';end if;
 return (select coalesce(jsonb_agg(to_jsonb(t) order by t.latest_at desc,t.contact_id),'[]'::jsonb) from (
 select w.id contact_id,'+91'||w.indian_mobile_key mobile,
 coalesce(nullif(btrim(c.full_name),''),nullif(btrim(w.imported_profile->>'Name'),''),'Contact') full_name,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,
 left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
 w.marketing_consent_status consent,w.resolution_status,
 case when p_folder='sent' then o.latest_at else greatest(i.latest_at,o.latest_at) end latest_at,i.unread_count,
 i.attention or o.attention attention,
 case when p_folder='sent' then o.latest_state when i.latest_at>=coalesce(o.latest_at,'-infinity'::timestamptz) then 'received' else o.latest_state end latest_status,
 case when p_folder='sent' then 'outgoing' when i.latest_at>=coalesce(o.latest_at,'-infinity'::timestamptz) then 'incoming' else 'outgoing' end latest_direction
 from public.whatsapp_contacts w left join public.candidates c on c.id=w.candidate_id
 cross join lateral (select max(m.created_at) latest_at,count(*)::integer total,
 count(*) filter(where not exists(select 1 from private.whatsapp_inbox_reads r where r.user_id=auth.uid() and r.inbound_id=m.id))::integer unread_count,
 coalesce(bool_or(m.processing_status='failed' or m.last_error_category is not null or (m.processing_status in ('received','normalized') and m.action_id is null)),false) attention
 from public.whatsapp_inbound_messages m where m.contact_id=w.id) i
 cross join lateral (select max(m.created_at) latest_at,count(*)::integer total,
 coalesce(bool_or(m.state='failed'),false) attention,
 (array_agg(m.state order by m.created_at desc,m.id desc))[1] latest_state,
 coalesce(bool_or(m.state=p_filter),false) matches_state from public.whatsapp_outbound_messages m where m.contact_id=w.id) o
 where (p_search='' or right(w.indian_mobile_key,4) like '%'||p_search||'%')
 and case when p_folder='inbox' then i.total>0 else o.total>0 end
 and (p_filter='all' or (p_filter='unread' and i.unread_count>0) or (p_filter='attention' and (i.attention or o.attention))
 or (p_folder='sent' and p_filter in ('queued','sending','sent','delivered','read','failed') and o.matches_state))
 order by case when p_folder='sent' then o.latest_at else greatest(i.latest_at,o.latest_at) end desc,w.id limit 50 offset p_offset)t);
end;$$;


revoke all on function public.admin_console_inbox(text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_inbox(text,text,text,integer) to authenticated;
commit;
