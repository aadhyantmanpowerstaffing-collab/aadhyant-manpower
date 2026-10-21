begin;

-- Keep ordinary preference saves unable to clear STOP. Only this separately
-- confirmed, authenticated self-service action can remove an inbound user STOP.
create function public.restart_candidate_whatsapp_alerts(
 p_general boolean,p_same_day boolean,p_current_job_location text,
 p_confirmed boolean,p_operation_id uuid,p_expected_user_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id(); c public.candidates%rowtype;
 w public.whatsapp_contacts%rowtype; previous jsonb; stamp timestamptz:=clock_timestamp();
begin
 if auth.uid() is null or cid is null or p_expected_user_id is distinct from auth.uid() then raise exception 'Active Candidate access required' using errcode='42501';end if;
 if p_confirmed is not true or p_operation_id is null or p_general is null or p_same_day is null
 or not(p_general or p_same_day) or p_current_job_location is null or length(p_current_job_location)>160
 then raise exception 'Confirm your new consent and choose at least one alert type';end if;
 select * into strict c from public.candidates where id=cid for update;
 if c.profile_status<>'active' or c.status='inactive' or c.mobile !~ '^[6-9][0-9]{9}$'
 or (select count(*) from public.candidates x where x.mobile=c.mobile or x.whatsapp_number=c.mobile)<>1
 then raise exception 'Candidate mobile requires review';end if;
 perform pg_advisory_xact_lock(hashtextextended('w6-mobile:'||c.mobile,0));
 if (select count(*) from public.whatsapp_contacts x where x.provider='whatsapp' and (x.indian_mobile_key=c.mobile or x.candidate_id=cid))<>1
 then raise exception 'WhatsApp identity requires review';end if;
 select * into strict w from public.whatsapp_contacts where provider='whatsapp'
 and (indian_mobile_key=c.mobile or candidate_id=cid) for update;
 if w.indian_mobile_key is distinct from c.mobile or w.candidate_id is distinct from cid
 or w.resolution_status<>'resolved' then raise exception 'WhatsApp identity requires review';end if;
 select metadata into previous from public.audit_logs where action='candidate.alerts_restarted'
 and entity_id=cid and metadata->>'operation_id'=p_operation_id::text limit 1;
 if found then
  if previous->>'contact_id' is distinct from w.id::text or previous->>'general_alerts' is distinct from p_general::text
  or previous->>'same_day_alerts' is distinct from p_same_day::text
  or previous->>'location_digest' is distinct from md5(btrim(p_current_job_location))
  then raise exception 'Restart request does not match its confirmation';end if;
  if w.marketing_consent_status<>'opted_in' or w.transactional_contact_status='suppressed'
  then raise exception 'Restart request already used. Open a new confirmation after STOP';end if;
  return jsonb_build_object('saved',true,'restarted',false);
 end if;
 if w.marketing_consent_status<>'opted_out' or w.opt_out_reason_category is distinct from 'user_stop'
 or w.opt_out_source is distinct from 'whatsapp_inbound'
 then raise exception 'This contact cannot restart alerts here. Contact Aadhyant for review';end if;
 -- Returning transactional status to unknown removes the user STOP without
 -- granting transactional permission. Marketing consent comes from the choices below.
 update public.whatsapp_contacts set marketing_consent_status='unknown',transactional_contact_status='unknown',
 opted_out_at=null,opt_out_source=null,opt_out_reason_category=null,updated_at=stamp where id=w.id;
 perform private.save_candidate_alert_choices(cid,p_general,p_same_day,p_current_job_location,'candidate_portal');
 update public.whatsapp_contacts set consent_policy_version='candidate-alert-restart-v1',consent_recorded_at=stamp where id=w.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'candidate','candidate.alerts_restarted','candidate',cid,'candidate',
 jsonb_build_object('operation_id',p_operation_id,'contact_id',w.id,'general_alerts',p_general,'same_day_alerts',p_same_day,
 'location_digest',md5(btrim(p_current_job_location)),'previous_reason','user_stop','policy','candidate-alert-restart-v1'));
 return jsonb_build_object('saved',true,'restarted',true);
end;$$;
revoke all on function public.restart_candidate_whatsapp_alerts(boolean,boolean,text,boolean,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.restart_candidate_whatsapp_alerts(boolean,boolean,text,boolean,uuid,uuid) to authenticated;

alter function public.get_candidate_alert_choices() rename to get_candidate_alert_choices_before_reenrolment;
revoke all on function public.get_candidate_alert_choices_before_reenrolment() from public,anon,authenticated,service_role;
create function public.get_candidate_alert_choices() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;cid uuid:=private.current_candidate_portal_id(); can_restart boolean;
begin
 result:=public.get_candidate_alert_choices_before_reenrolment();
 select exists(select 1 from public.candidates c join public.whatsapp_contacts w on w.candidate_id=c.id
 where c.id=cid and c.profile_status='active' and c.status<>'inactive' and w.provider='whatsapp'
 and w.indian_mobile_key=c.mobile and w.resolution_status='resolved'
 and w.marketing_consent_status='opted_out' and w.opt_out_reason_category='user_stop' and w.opt_out_source='whatsapp_inbound'
 and (select count(*) from public.candidates x where x.mobile=c.mobile or x.whatsapp_number=c.mobile)=1
 and (select count(*) from public.whatsapp_contacts x where x.provider='whatsapp' and (x.candidate_id=cid or x.indian_mobile_key=c.mobile))=1)
 into can_restart;
 return result||jsonb_build_object('can_restart_alerts',can_restart);
end;$$;
revoke all on function public.get_candidate_alert_choices() from public,anon,authenticated,service_role;
grant execute on function public.get_candidate_alert_choices() to authenticated;
commit;
