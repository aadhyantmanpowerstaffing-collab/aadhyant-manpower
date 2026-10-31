-- Source preparation only. Existing readiness switches remain off.
begin;
-- Historical notifications must remain closable after application linkage changes.
-- Validate linkage on identity writes, rather than on lease/failure transitions.
drop trigger bind_interview_whatsapp_notification on public.whatsapp_outbound_messages;
create trigger bind_interview_whatsapp_notification before insert or update of purpose,interview_id,correlation_id,candidate_id,requirement_id
 on public.whatsapp_outbound_messages for each row execute function private.bind_interview_whatsapp_notification();
create function private.interview_notification_current(p_message_id uuid)
returns boolean language sql volatile security definer set search_path='' as $$
 select exists(
 select 1 from public.whatsapp_outbound_messages o
 join public.interviews i on i.id=o.interview_id
 join public.candidate_applications a on a.id=i.application_id
 join public.candidates c on c.id=a.candidate_id
 join public.employer_requirements r on r.id=a.requirement_id
 join public.whatsapp_contacts w on w.id=o.contact_id
 join private.whatsapp_console_config cfg on cfg.singleton
 where o.id=p_message_id and o.purpose='interview_schedule' and o.consent_class='transactional'
 and i.status='scheduled' and i.scheduled_at>clock_timestamp()
 and a.application_status in ('interested','applied','screening','shortlisted','interview')
 and a.candidate_id=o.candidate_id and a.requirement_id=o.requirement_id and c.status<>'inactive'
 and w.candidate_id=c.id and w.resolution_status='resolved' and w.provider_address=o.destination
 and w.marketing_consent_status<>'opted_out' and private.whatsapp_contact_allows_purpose(w.id,'transactional')
 and (select count(*) from public.whatsapp_contacts wc where wc.candidate_id=c.id)=1
 and cfg.interview_notifications_enabled and cfg.interview_template_verified_at>clock_timestamp()-interval '24 hours'
 and cfg.interview_notification_language=o.template_language
 and o.template_variables=jsonb_build_object('requirement_code',r.requirement_code,'job_role',r.job_role,
 'interview_date',to_char(i.scheduled_at at time zone 'Asia/Kolkata','DD Mon YYYY'),
 'interview_time',to_char(i.scheduled_at at time zone 'Asia/Kolkata','HH12:MI AM'),
 'interview_mode',i.mode,'interview_location',coalesce(nullif(btrim(i.location),''),'See Candidate portal'),
 'candidate_instructions','Sign in to your Candidate account to review the latest schedule.')
 );
$$;

create function public.console_claim_interview_notifications(p_worker_id text)
returns table(message_id uuid,destination text,template_language text,template_variables jsonb)
language plpgsql security definer set search_path='' as $$
declare candidate record; worker text:=btrim(coalesce(p_worker_id,''));
begin
 if length(worker) not between 1 and 160 then raise exception 'Valid worker required';end if;
 update public.whatsapp_outbound_messages set state='failed',
 send_phase=case when send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
 last_error_category=case when send_phase='provider_call_started' then 'ambiguous_provider_outcome' else 'attempts_exhausted' end,
 last_error_code='interview_lease_expired',failed_at=clock_timestamp(),lease_owner=null,lease_expires_at=null,updated_at=clock_timestamp()
 where purpose='interview_schedule' and state='sending' and lease_expires_at<=clock_timestamp();
 if not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready
 and verified_at>clock_timestamp()-interval '24 hours' and interview_notifications_enabled) then return;end if;
 -- Lock schedules before outbox rows, matching the schedule-change trigger's lock order.
 for candidate in select i.id interview_id,o.id outbox_id from public.interviews i
 join public.whatsapp_outbound_messages o on o.interview_id=i.id
 where o.state='queued' and o.send_phase='ready' and o.attempt_count=0
 and o.next_attempt_at<=clock_timestamp() and o.purpose='interview_schedule'
 order by o.next_attempt_at,o.created_at,o.id limit 10 for share of i skip locked
 loop
  perform 1 from public.whatsapp_outbound_messages o where o.id=candidate.outbox_id
   and o.state='queued' and o.send_phase='ready' and o.attempt_count=0 for update skip locked;
  if found and private.interview_notification_current(candidate.outbox_id) then
   return query update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=1,
    lease_owner=worker,lease_expires_at=clock_timestamp()+interval '60 seconds',updated_at=clock_timestamp()
    where o.id=candidate.outbox_id returning o.id,o.destination,o.template_language,o.template_variables;
  end if;
 end loop;
end;$$;

create function public.console_interview_provider_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
declare interview_key uuid; application_key uuid; candidate_key uuid; requirement_key uuid; contact_key uuid;
begin
 select o.interview_id,o.contact_id into interview_key,contact_key from public.whatsapp_outbound_messages o
 where o.id=p_message_id and o.purpose='interview_schedule';
 if interview_key is null then raise exception 'Interview notification required';end if;
 select i.application_id into application_key from public.interviews i where i.id=interview_key for share;
 select a.candidate_id,a.requirement_id into candidate_key,requirement_key from public.candidate_applications a where a.id=application_key for share;
 perform 1 from public.candidates where id=candidate_key for share;
 perform 1 from public.employer_requirements where id=requirement_key for share;
 perform 1 from public.whatsapp_contacts where id=contact_key for share;
 perform 1 from private.whatsapp_console_config where singleton and sender_ready
 and phone_number_id=p_phone_id and business_account_id=p_account_id
 and verified_at>clock_timestamp()-interval '24 hours' for share;
 if not found then raise exception 'Verified sender required';end if;
 perform 1 from public.whatsapp_outbound_messages where id=p_message_id and state='sending' and send_phase='claimed'
 and lease_owner=btrim(p_worker_id) and lease_expires_at>clock_timestamp() and attempt_count=1 for update;
 if not found or not private.interview_notification_current(p_message_id) then raise exception 'Interview notification is no longer eligible';end if;
 return public.mark_whatsapp_provider_call_started(p_message_id,p_worker_id);
end;$$;
revoke all on function private.interview_notification_current(uuid),public.console_claim_interview_notifications(text),
 public.console_interview_provider_boundary(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_interview_notifications(text),public.console_interview_provider_boundary(uuid,text,text,text) to service_role;
commit;
