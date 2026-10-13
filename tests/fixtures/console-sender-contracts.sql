-- Read-only production contract snapshot, 13 October 2026; local fixtures only.
CREATE OR REPLACE FUNCTION public.mark_whatsapp_provider_call_started(p_message_id uuid, p_worker_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_outbound public.whatsapp_outbound_messages%rowtype;
begin
  select * into v_outbound from public.whatsapp_outbound_messages
    where id=p_message_id and state='sending' and send_phase='claimed'
      and lease_owner=pg_catalog.btrim(p_worker_id)
      and lease_expires_at>pg_catalog.clock_timestamp()
    for update;
  if not found then raise exception 'WhatsApp send lease is not ready for provider invocation'; end if;

  -- Match mark_sent's lock order: outbound first, then contact. Hold the contact
  -- while checking current opt-out state and committing the provider boundary.
  perform 1 from public.whatsapp_contacts where id=v_outbound.contact_id for share;
  if not found or not (select private.whatsapp_contact_allows_purpose(v_outbound.contact_id,v_outbound.consent_class)) then
    raise exception 'WhatsApp contact is suppressed before provider invocation';
  end if;
  -- Recheck after claim. A rejection rolls back this call and never authorizes Meta.
  -- This is a transaction-boundary check, not an atomic promise across HTTP.
  if v_outbound.purpose='vacancy_campaign' then
    if not private.whatsapp_vacancy_send_eligible(v_outbound.id) then
      raise exception 'WhatsApp vacancy or application eligibility changed before provider invocation';
    end if;
  end if;
  update public.whatsapp_outbound_messages set send_phase='provider_call_started',updated_at=pg_catalog.clock_timestamp()
    where id=p_message_id and lease_expires_at>pg_catalog.clock_timestamp();
  if not found then raise exception 'WhatsApp send lease expired before provider invocation'; end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_whatsapp_outbound_sent(p_message_id uuid, p_worker_id text, p_provider_message_id text, p_provider_timestamp timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.whatsapp_outbound_messages set provider_message_id=pg_catalog.btrim(p_provider_message_id),state='sent',send_phase='confirmed',
    sent_at=coalesce(p_provider_timestamp,pg_catalog.clock_timestamp()),lease_owner=null,lease_expires_at=null,
    last_error_category=null,last_error_code=null,updated_at=pg_catalog.clock_timestamp()
  where id=p_message_id and state='sending' and send_phase='provider_call_started' and lease_owner=pg_catalog.btrim(p_worker_id);
  if not found then raise exception 'WhatsApp send lease does not match'; end if;
  update public.whatsapp_contacts c set last_outbound_at=pg_catalog.clock_timestamp(),updated_at=pg_catalog.clock_timestamp()
    from public.whatsapp_outbound_messages o where o.id=p_message_id and c.id=o.contact_id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_whatsapp_outbound_failure(p_message_id uuid, p_worker_id text, p_error_category text, p_error_code text, p_failure_kind text, p_retry_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_kind text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_failure_kind,''))); v_attempt integer; v_max integer;
begin
  if v_kind not in ('transient','permanent','ambiguous') or pg_catalog.length(coalesce(p_error_category,'')) not between 1 and 80
    or pg_catalog.length(coalesce(p_error_code,'')) not between 1 and 120 then raise exception 'Safe WhatsApp failure details are required'; end if;
  select attempt_count,max_attempts into v_attempt,v_max from public.whatsapp_outbound_messages
    where id=p_message_id and state='sending' and lease_owner=pg_catalog.btrim(p_worker_id) for update;
  if not found then raise exception 'WhatsApp send lease does not match'; end if;
  if v_kind='transient' and v_attempt<v_max and p_retry_at is not null and p_retry_at>pg_catalog.clock_timestamp() then
    update public.whatsapp_outbound_messages set state='queued',send_phase='ready',next_attempt_at=p_retry_at,lease_owner=null,lease_expires_at=null,
      last_error_category=p_error_category,last_error_code=p_error_code,updated_at=pg_catalog.clock_timestamp() where id=p_message_id;
  else
    update public.whatsapp_outbound_messages set state='failed',send_phase=case when v_kind='ambiguous' then 'reconciliation_required' else 'terminal' end,
      failed_at=pg_catalog.clock_timestamp(),lease_owner=null,lease_expires_at=null,
      last_error_category=case when v_kind='ambiguous' then 'ambiguous_provider_outcome' else p_error_category end,last_error_code=p_error_code,
      updated_at=pg_catalog.clock_timestamp() where id=p_message_id;
    insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
      select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',o.id,'whatsapp',o.correlation_id,
        pg_catalog.jsonb_build_object('failure_kind',v_kind,'error_category',case when v_kind='ambiguous' then 'ambiguous_provider_outcome' else p_error_category end,'error_code',p_error_code)
      from public.whatsapp_outbound_messages o where o.id=p_message_id;
  end if; return true;
end;
$function$;
