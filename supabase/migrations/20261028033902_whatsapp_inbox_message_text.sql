-- Retain readable incoming messages in the canonical store, with Admin-only projection.
begin;
alter table public.whatsapp_inbound_messages drop constraint whatsapp_inbound_messages_safe_text_check;
alter table public.whatsapp_inbound_messages add constraint whatsapp_inbound_messages_safe_text_check check(safe_text is null or length(safe_text)<=4096);
create function private.whatsapp_inbox_display_text(p_text text) returns text
language plpgsql immutable set search_path='' as $$
declare result text;
begin
 if p_text is null or btrim(p_text)='' then return null; end if;
 -- Sensitive identity/financial records are never part of the Inbox transcript.
 if p_text ~* '(aadha+r|aadhar|bank|account[[:space:]_-]*(no|number)|uan|esic|password|otp|આધાર|બેંક|आधार|बैंक)' then
  return '[Sensitive details omitted]';
 end if;
 result:=regexp_replace(p_text,'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]','','g');
 result:=regexp_replace(result,'[0-9]([[:space:]-]*[0-9]){8,}','[Number omitted]','g');
 result:=regexp_replace(result,'https?://[^[:space:]]+','[Link omitted]','gi');
 return left(result,4096);
end;$$;
revoke all on function private.whatsapp_inbox_display_text(text) from public,anon,authenticated,service_role;

create or replace function public.record_whatsapp_inbound_message(p_webhook_event_id uuid,p_contact_id uuid,p_provider_message_id text,
  p_provider_timestamp timestamptz,p_message_type text,p_safe_text text default null,p_action_id text default null,
  p_correlation_key text default null,p_redacted_response jsonb default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_text text;
begin
  if not (select private.whatsapp_safe_flat_json(p_redacted_response)) then
    raise exception 'WhatsApp inbound metadata contains prohibited or unsupported fields';
  end if;
  -- Registration answers stay in the existing private registration workflow.
  if lower(btrim(p_message_type)) in ('text','button','list')
    and coalesce(p_action_id,'') not like 'REGCHAT|%'
    and not exists(select 1 from private.whatsapp_registration_chats where contact_id=p_contact_id and status='active') then
    v_text:=private.whatsapp_inbox_display_text(p_safe_text);
  end if;
  insert into public.whatsapp_inbound_messages(webhook_event_id,contact_id,provider_message_id,provider_timestamp,message_type,
    safe_text,action_id,correlation_key,redacted_response,processing_status)
  values(p_webhook_event_id,p_contact_id,pg_catalog.btrim(p_provider_message_id),p_provider_timestamp,
    pg_catalog.lower(pg_catalog.btrim(p_message_type)),v_text,p_action_id,p_correlation_key,p_redacted_response,'normalized')
  on conflict(provider_message_id) do update set provider_message_id=excluded.provider_message_id
    where whatsapp_inbound_messages.webhook_event_id=excluded.webhook_event_id
      and whatsapp_inbound_messages.contact_id=excluded.contact_id
      and whatsapp_inbound_messages.message_type=excluded.message_type returning id into v_id;
  if v_id is null then raise exception 'WhatsApp inbound idempotency key conflicts with existing message'; end if;
  update public.whatsapp_contacts set last_inbound_at=greatest(coalesce(last_inbound_at,'-infinity'::timestamptz),
    coalesce(p_provider_timestamp,pg_catalog.clock_timestamp())),updated_at=pg_catalog.clock_timestamp() where id=p_contact_id;
  return v_id;
end;
$$;


create or replace function public.admin_console_conversation(p_contact_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 if p_contact_id is null or not exists(select 1 from public.whatsapp_contacts where id=p_contact_id) then raise exception 'Contact unavailable';end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset';end if;
 return (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at,t.id,t.direction),'[]'::jsonb) from (
 select * from (
 select m.id,'incoming'::text direction,m.created_at,m.provider_timestamp event_at,m.processing_status status,
 case when m.registration_chat_id is not null or m.action_id like 'REGCHAT|%' then 'Registration response received — details kept in the registration record'
 when nullif(m.safe_text,'') is not null then private.whatsapp_inbox_display_text(m.safe_text)
 when m.message_type in ('unsupported','unknown') then 'Attachment or unsupported message received — preview unavailable'
 when m.action_id='POST_JOB' then 'POST JOB — vacancy form requested'
 when m.action_id='INTERESTED' then 'Interested in a vacancy'
 when m.action_id in ('STOP','STOP_ALERTS') then 'Stop alerts requested'
 when m.action_id='SUBSCRIBE_JOB_UPDATES' then 'Job-alert subscription response'
 else 'Message received — text was not saved for this message' end summary,
 null::text template_name,null::text purpose,null::text job_code,
 null::timestamptz sent_at,null::timestamptz delivered_at,null::timestamptz read_at,
 m.processing_status='failed' or m.last_error_category is not null attention,
 not exists(select 1 from private.whatsapp_inbox_reads r where r.user_id=auth.uid() and r.inbound_id=m.id) unread,
 null::text failure
 from public.whatsapp_inbound_messages m where m.contact_id=p_contact_id
 union all
 select o.id,'outgoing',o.created_at,coalesce(o.sent_at,o.created_at),o.state,
 case when o.purpose='operator_reply' then o.operator_reply_body when o.purpose='employer_post_job' then 'Vacancy posting reply: open https://aadhyantmanpower.in/post-job/ and sign in with your Company or Contractor account to submit for review.'
 when o.purpose='interested_registration' then 'Registration form invitation'
 when o.purpose='registration_chat' then 'WhatsApp registration step'
 when o.purpose='vacancy_campaign' then 'Job opportunity notification'
 else 'Outgoing WhatsApp message' end,
 case when o.purpose='operator_reply' then null else o.template_name end,o.purpose,e.requirement_code,o.sent_at,o.delivered_at,o.read_at,o.state='failed',false,
 case when o.send_phase='reconciliation_required' then 'Delivery outcome uncertain — review before retrying'
 when o.state='failed' then 'Failed — review required' else null end
 from public.whatsapp_outbound_messages o left join public.employer_requirements e on e.id=o.requirement_id where o.contact_id=p_contact_id
 ) u order by created_at desc,id desc,direction desc limit 100 offset p_offset)t);
end;$$;

revoke all on function public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb) to service_role;
revoke all on function public.admin_console_conversation(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_conversation(uuid,integer) to authenticated;
commit;
