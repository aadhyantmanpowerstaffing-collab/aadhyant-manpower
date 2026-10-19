-- Full recipient numbers are requested for the existing Admin-only delivery report.
-- Keep existing access checks, pagination, masked compatibility field and canonical receipts.
create or replace function public.admin_console_report(p_campaign_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() or not exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null) then raise exception 'Console campaign required'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select cr.id,w.provider_address mobile,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,
 coalesce(o.state,cr.recipient_status) status,o.sent_at,o.delivered_at,o.read_at,o.failed_at,o.last_error_category failure,
 o.next_attempt_at from public.whatsapp_campaign_recipients cr join public.whatsapp_contacts w on w.id=cr.whatsapp_contact_id
 left join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=p_campaign_id
 order by cr.created_at,cr.id limit 100 offset p_offset)t);
end; $$;

revoke all on function public.admin_console_report(uuid,integer) from public,anon,service_role;
grant execute on function public.admin_console_report(uuid,integer) to authenticated;
