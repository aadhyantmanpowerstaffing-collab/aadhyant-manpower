begin;
CREATE OR REPLACE FUNCTION public.console_claim_campaign_before_registered(p_campaign_id uuid, p_worker_id text)
 RETURNS TABLE(message_id uuid, destination text, template_name text, template_language text, template_version text, template_variables jsonb, purpose text, consent_class text, attempt_count integer, correlation_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_worker text:=pg_catalog.btrim(coalesce(p_worker_id,'')); v_batch integer:=least(greatest(10,1),100);
  v_lease integer:=least(greatest(120,15),900);
begin
  if not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then return; end if;
  if pg_catalog.length(v_worker) not between 1 and 160 then raise exception 'A valid worker identifier is required'; end if;
  with expired as (
    update public.whatsapp_outbound_messages o set state='failed',
      send_phase=case when o.send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
      failed_at=pg_catalog.clock_timestamp(),lease_owner=null,lease_expires_at=null,
      last_error_category=case when o.send_phase='provider_call_started' then 'ambiguous_provider_outcome' else 'attempts_exhausted' end,
      last_error_code=case when o.send_phase='provider_call_started' then 'lease_expired_after_provider_call' else 'lease_expired_at_attempt_limit' end,
      updated_at=pg_catalog.clock_timestamp()
    where exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id where cr.outbound_message_id=o.id and c.console_template_id is not null and (p_campaign_id is null or c.id=p_campaign_id)) and o.state='sending' and o.lease_expires_at<=pg_catalog.clock_timestamp()
      and (o.send_phase='provider_call_started' or (o.send_phase='claimed' and o.attempt_count>=o.max_attempts))
    returning o.id,o.correlation_id,o.last_error_category,o.last_error_code
  ) insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',e.id,'whatsapp',e.correlation_id,
      pg_catalog.jsonb_build_object('failure_kind',case when e.last_error_category='ambiguous_provider_outcome' then 'ambiguous' else 'exhausted' end,
        'error_category',e.last_error_category,'error_code',e.last_error_code) from expired e;
  -- Cheap indexed work check before any template/eligibility expansion. Never claim terminal rows.
  if not exists(select 1 from public.whatsapp_outbound_messages o
    where ((o.state='queued' and o.next_attempt_at<=clock_timestamp())
      or (o.state='sending' and o.send_phase='claimed' and o.lease_expires_at<=clock_timestamp() and o.provider_message_id is null))
      and o.attempt_count<o.max_attempts
      and exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id
       where cr.outbound_message_id=o.id and c.console_template_id is not null and (p_campaign_id is null or c.id=p_campaign_id))) then return; end if;
  return query with valid_campaigns as materialized (
    select c.id from public.whatsapp_campaigns c where c.console_template_id is not null
      and (p_campaign_id is null or c.id=p_campaign_id) and private.console_template_valid(c.id)
  ), claimable as (
    select o.id from public.whatsapp_outbound_messages o
    where exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id where cr.outbound_message_id=o.id and c.console_template_id is not null and (p_campaign_id is null or c.id=p_campaign_id) and c.id in (select vc.id from valid_campaigns vc)) and ((o.state='queued' and o.next_attempt_at<=pg_catalog.clock_timestamp())
      or (o.state='sending' and o.send_phase='claimed' and o.lease_expires_at<=pg_catalog.clock_timestamp()
        and o.provider_message_id is null))
      and (o.purpose <> 'vacancy_campaign' OR private.whatsapp_vacancy_send_eligible(o.id))
      and o.attempt_count<o.max_attempts and (select private.whatsapp_contact_allows_purpose(o.contact_id,o.consent_class))
    order by o.next_attempt_at,o.created_at,o.id for update skip locked limit v_batch
  ), claimed as (
    update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=o.attempt_count+1,lease_owner=v_worker,
      lease_expires_at=pg_catalog.clock_timestamp()+pg_catalog.make_interval(secs=>v_lease),updated_at=pg_catalog.clock_timestamp()
    from claimable c where o.id=c.id returning o.*
  ) select c.id,c.destination,c.template_name,c.template_language,c.template_version,c.template_variables,
    c.purpose,c.consent_class,c.attempt_count,c.correlation_id from claimed c;
end;
$function$;
revoke all on function public.console_claim_campaign_before_registered(uuid,text) from public,anon,authenticated,service_role;

create function private.console_campaign_delivery(p_campaign_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('total',count(*),
  'delivered',count(*) filter(where o.state in ('delivered','read')),
  'read',count(*) filter(where o.state='read'),
  'awaiting',count(*) filter(where o.state='sent'),
  'pending',count(*) filter(where o.state in ('queued','sending')),
  'sending',count(*) filter(where o.state='sending'),
  'review',count(*) filter(where o.state='failed' and o.send_phase='reconciliation_required'),
  'failed',count(*) filter(where o.state='failed' and o.send_phase is distinct from 'reconciliation_required'),
  'not_sent',count(*) filter(where o.id is null or o.state in ('cancelled','suppressed')),
  'checked_at',statement_timestamp())
 from public.whatsapp_campaign_recipients cr left join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id
 where cr.campaign_id=p_campaign_id;
$$;
revoke all on function private.console_campaign_delivery(uuid) from public,anon,authenticated,service_role;
create function public.admin_console_campaign_delivery(p_campaign_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() or auth.uid() is null or not exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null) then raise exception 'Console campaign required' using errcode='42501'; end if;
 return private.console_campaign_delivery(p_campaign_id);
end; $$;
revoke all on function public.admin_console_campaign_delivery(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_campaign_delivery(uuid) to authenticated;

create or replace function public.admin_console_campaigns(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select c.id,c.campaign_name,c.campaign_status,c.created_at,c.scheduled_for,c.requirement_id,r.requirement_code,r.job_role,
 c.template_name,c.template_language,c.console_template_snapshot,private.console_campaign_delivery(c.id) delivery,
 (select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id) audience_count,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='sent') sent,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='delivered') delivered,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='read') read,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='failed') failed
 from public.whatsapp_campaigns c join public.employer_requirements r on r.id=c.requirement_id
 where c.console_template_id is not null order by c.created_at desc,c.id limit 50 offset p_offset)t);
end; $$;

-- Full recipient numbers are requested for the existing Admin-only delivery report.
-- Keep existing access checks, pagination, masked compatibility field and canonical receipts.
create or replace function public.admin_console_report(p_campaign_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() or not exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null) then raise exception 'Console campaign required'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select cr.id,w.provider_address mobile,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,
 coalesce(o.state,cr.recipient_status) status,o.sent_at,o.delivered_at,o.read_at,o.failed_at,case when o.state='failed' then coalesce(o.last_error_category,e.provider_error_category) end failure,
 case when o.state='failed' then coalesce(o.last_error_code,e.provider_error_code) end failure_code,o.send_phase,
 o.next_attempt_at from public.whatsapp_campaign_recipients cr join public.whatsapp_contacts w on w.id=cr.whatsapp_contact_id
 left join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id left join lateral (select me.provider_error_code,me.provider_error_category from public.whatsapp_message_events me
 where me.outbound_message_id=o.id and me.status='failed' order by me.provider_timestamp desc,me.created_at desc,me.id desc limit 1) e on true where cr.campaign_id=p_campaign_id
 order by cr.created_at,cr.id limit 100 offset p_offset)t);
end; $$;


commit;
