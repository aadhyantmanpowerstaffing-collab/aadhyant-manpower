-- Keep consent provenance while using the canonical audit source vocabulary.
begin;
create or replace function private.save_candidate_alert_choices(p_candidate_id uuid,p_general boolean,p_same_day boolean,p_job_location text,p_source text)
returns void language plpgsql security definer set search_path='' as $$
declare c public.candidates%rowtype; w public.whatsapp_contacts%rowtype; stamp timestamptz:=clock_timestamp();
begin
 if p_general is null or p_same_day is null or p_source not in ('candidate_portal','whatsapp_web') or p_job_location is null or length(p_job_location)>160 then raise exception 'Choose Yes or No separately for both alert types';end if;
 select * into strict c from public.candidates where id=p_candidate_id for update;
 if c.mobile !~ '^[6-9][0-9]{9}$' or c.profile_status<>'active' or c.status='inactive'
 or (select count(*) from public.candidates other where other.mobile=c.mobile or other.whatsapp_number=c.mobile)<>1 then raise exception 'Candidate mobile requires review';end if;
 perform pg_advisory_xact_lock(hashtextextended('w6-mobile:'||c.mobile,0));
 select * into w from public.whatsapp_contacts where provider='whatsapp' and (indian_mobile_key=c.mobile or candidate_id=c.id) order by id limit 1 for update;
 if found and (w.indian_mobile_key<>c.mobile or w.resolution_status in ('blocked','ambiguous') or (w.candidate_id is not null and w.candidate_id<>c.id)) then raise exception 'WhatsApp identity requires review';end if;
 if w.id is null then
  insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status)
  values('+91'||c.mobile,c.mobile,c.id,'resolved') returning * into w;
 end if;
 if (p_general or p_same_day) and ((w.marketing_consent_status='opted_out' and w.opt_out_reason_category is distinct from 'candidate_choice') or w.transactional_contact_status='suppressed') then raise exception 'WhatsApp STOP is active; contact Aadhyant to review re-enrolment';end if;
 insert into private.candidate_alert_choices(candidate_id,general_alerts,same_day_alerts,current_job_location,source,chosen_at)
 values(c.id,p_general,p_same_day,btrim(p_job_location),p_source,stamp)
 on conflict(candidate_id) do update set general_alerts=excluded.general_alerts,same_day_alerts=excluded.same_day_alerts,current_job_location=excluded.current_job_location,source=excluded.source,chosen_at=case when row(candidate_alert_choices.general_alerts,candidate_alert_choices.same_day_alerts,candidate_alert_choices.current_job_location) is distinct from row(excluded.general_alerts,excluded.same_day_alerts,excluded.current_job_location) then excluded.chosen_at else candidate_alert_choices.chosen_at end;
 insert into private.same_day_preferences(candidate_id,enabled,changed_at) values(c.id,p_same_day,stamp)
 on conflict(candidate_id) do update set enabled=excluded.enabled,changed_at=case when same_day_preferences.enabled is distinct from excluded.enabled then excluded.changed_at else same_day_preferences.changed_at end;
 update public.whatsapp_contacts set candidate_id=c.id,resolution_status='resolved',
 marketing_consent_status=case when p_general or p_same_day then 'opted_in' else 'opted_out' end,
 consent_source=p_source,consent_scope='all_job_alerts',consent_recorded_at=case when w.marketing_consent_status='opted_in' and (p_general or p_same_day) then w.consent_recorded_at else stamp end,consent_policy_version='candidate-alert-choices-v1',
 opted_out_at=case when not(p_general or p_same_day) then coalesce(w.opted_out_at,stamp) end,
 opt_out_source=case when not(p_general or p_same_day) then coalesce(w.opt_out_source,p_source) end,
 opt_out_reason_category=case when not(p_general or p_same_day) then coalesce(w.opt_out_reason_category,'candidate_choice') end,
 updated_at=stamp where id=w.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),case when p_source='candidate_portal' then 'candidate' else 'service' end,'candidate.alert_choices_saved','candidate',c.id,case when p_source='candidate_portal' then 'candidate' else 'whatsapp' end,
 jsonb_build_object('general_alerts',p_general,'same_day_alerts',p_same_day,'policy','candidate-alert-choices-v1'));
end; $$;

revoke all on function private.save_candidate_alert_choices(uuid,boolean,boolean,text,text) from public,anon,authenticated,service_role;
commit;
