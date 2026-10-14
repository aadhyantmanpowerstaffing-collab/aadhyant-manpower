begin;
alter table private.whatsapp_console_config add column registration_flow_id text,
 add column registration_flow_hash text,add column registration_flow_verified_at timestamptz;
alter table public.whatsapp_outbound_messages add column registration_flow_token text unique,
 add column registration_flow_id text,add column registration_flow_hash text,
 add constraint registration_flow_binding_check check (
 (registration_flow_token is null and registration_flow_id is null and registration_flow_hash is null)
 or (registration_flow_token is not null and registration_flow_id is not null and registration_flow_hash is not null and purpose='interested_registration' and message_type='session_text' and registration_flow_token ~ '^[a-f0-9]{64}$'
 and registration_flow_id ~ '^[0-9]{8,40}$' and registration_flow_hash ~ '^[a-f0-9]{64}$'));

create function public.console_registration_flow_configuration()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('flow_id',registration_flow_id,'flow_hash',registration_flow_hash,
 'ready',registration_flow_id is not null and registration_flow_verified_at>clock_timestamp()-interval '24 hours',
 'account_id',business_account_id) from private.whatsapp_console_config where singleton;
$$;
create function public.console_verify_registration_flow(p_flow_id text,p_flow_hash text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_flow_id is null or p_flow_id !~ '^[0-9]{8,40}$' or p_flow_hash is null or p_flow_hash !~ '^[a-f0-9]{64}$' then raise exception 'Verified published Flow required';end if;
 update private.whatsapp_console_config set registration_flow_id=p_flow_id,registration_flow_hash=p_flow_hash,registration_flow_verified_at=clock_timestamp()
 where singleton and sender_ready and business_account_id=p_account_id and verified_at>clock_timestamp()-interval '24 hours';
 if not found then raise exception 'Verified sender required';end if;
 return true;
end;$$;
create function public.admin_console_registration_flow()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return jsonb_build_object('ready',(select registration_flow_id is not null and registration_flow_verified_at>clock_timestamp()-interval '24 hours' from private.whatsapp_console_config where singleton));
end;$$;

-- Preserve reviewed registration-link fallback and its lease/dedupe checks.
alter function public.console_claim_registration_reply(uuid,text) rename to claim_registration_reply_v1;
alter function public.claim_registration_reply_v1(uuid,text) set schema private;
revoke all on function private.claim_registration_reply_v1(uuid,text) from public,anon,authenticated,service_role;
create function public.console_claim_registration_reply(p_inbound_message_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,message_type text,purpose text,consent_class text,template_variables jsonb,flow_id text,flow_token text)
language plpgsql security definer set search_path='' as $$
declare row record; config private.whatsapp_console_config%rowtype;
begin
 select * into config from private.whatsapp_console_config where singleton for share;
 for row in select * from private.claim_registration_reply_v1(p_inbound_message_id,p_worker_id) loop
  if config.registration_flow_id is not null and config.registration_flow_verified_at>clock_timestamp()-interval '24 hours' then
   update public.whatsapp_outbound_messages set registration_flow_token=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),
   registration_flow_id=config.registration_flow_id,registration_flow_hash=config.registration_flow_hash
   where id=row.message_id;
  end if;
  return query select o.id,o.destination,o.message_type,o.purpose,o.consent_class,o.template_variables,o.registration_flow_id,o.registration_flow_token
  from public.whatsapp_outbound_messages o where o.id=row.message_id;
 end loop;
end;$$;
alter function public.console_registration_boundary(uuid,text,text,text) rename to registration_boundary_v1;
alter function public.registration_boundary_v1(uuid,text,text,text) set schema private;
revoke all on function private.registration_boundary_v1(uuid,text,text,text) from public,anon,authenticated,service_role;
create function public.console_registration_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform private.registration_boundary_v1(p_message_id,p_worker_id,p_phone_id,p_account_id);
 if exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and registration_flow_token is not null)
 and not exists(select 1 from public.whatsapp_outbound_messages o join private.whatsapp_console_config c on c.singleton
 where o.id=p_message_id and o.registration_flow_id=c.registration_flow_id and o.registration_flow_hash=c.registration_flow_hash
 and c.registration_flow_verified_at>clock_timestamp()-interval '24 hours') then raise exception 'Registration Flow changed';end if;
 return true;
end;$$;

create function public.console_process_registration_flow(p_inbound_message_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; reply public.whatsapp_outbound_messages%rowtype;
 w public.whatsapp_contacts%rowtype; cr public.whatsapp_campaign_recipients%rowtype; p jsonb;
 candidate uuid; app uuid; matches integer; years integer; alerts boolean; original uuid;
begin
 select * into strict m from public.whatsapp_inbound_messages where id=p_inbound_message_id for update;
 if m.processing_status='processed' and m.application_id is not null then return jsonb_build_object('status','already_processed','application_id',m.application_id);end if;
 if m.message_type<>'flow' or m.action_id is distinct from 'REGISTRATION_SUBMIT'
 or not exists(select 1 from public.whatsapp_webhook_events e where e.id=m.webhook_event_id and e.signature_verified) then raise exception 'Signed registration response required';end if;
 select * into reply from public.whatsapp_outbound_messages where registration_flow_token=m.correlation_key and contact_id=m.contact_id
 and purpose='interested_registration' and state in ('sent','delivered','read') for update;
 if not found or m.provider_timestamp is null or m.provider_timestamp<reply.created_at-interval '10 seconds'
 or m.provider_timestamp>reply.created_at+interval '24 hours' or m.provider_timestamp>clock_timestamp() then raise exception 'Registration binding unavailable or expired';end if;
 if exists(select 1 from public.whatsapp_inbound_messages where correlation_key=m.correlation_key and id<>m.id and processing_status='processed') then
  update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=clock_timestamp(),last_error_category='registration_duplicate',last_error_code='flow_already_completed' where id=m.id;
  return jsonb_build_object('status','already_completed');
 end if;
 select o.id into original from public.whatsapp_inbound_messages interested join public.whatsapp_outbound_messages o
 on o.provider_message_id=interested.correlation_key and o.contact_id=interested.contact_id where interested.id=reply.correlation_id;
 select * into cr from public.whatsapp_campaign_recipients where outbound_message_id=original and whatsapp_contact_id=m.contact_id;
 if not found then raise exception 'Job correlation unavailable';end if;
 perform 1 from public.employer_requirements where id=reply.requirement_id for share;
 if not found or not private.vacancy_is_application_eligible(reply.requirement_id) then raise exception 'Job is not available';end if;
 select * into strict w from public.whatsapp_contacts where id=m.contact_id for update;
 if w.resolution_status in ('blocked','ambiguous') or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed'
 or w.provider_address<>reply.destination then raise exception 'Contact requires review';end if;
 p:=m.redacted_response;
 if jsonb_typeof(p) is distinct from 'object' or p->>'form_kind' is distinct from 'aadhyant_registration_v1'
 or p->>'consent_policy_version' is distinct from 'wa-registration-alerts-v1'
 or p->'registration_consent' is distinct from 'true'::jsonb or jsonb_typeof(p->'job_alert_consent') is distinct from 'boolean'
 or exists(select 1 from jsonb_object_keys(p) k where k not in ('form_kind','consent_policy_version','registration_consent','job_alert_consent',
 'full_name','age','gender','state','district','current_village_city','highest_qualification','course_trade_specialization','experience_status','interview_available'))
 or coalesce(p->>'age','') !~ '^[0-9]{1,2}$' then raise exception 'Registration details or consent are invalid';end if;
 years:=(p->>'age')::integer;alerts:=(p->>'job_alert_consent')::boolean;
 if years not between 16 and 75 or coalesce(length(btrim(p->>'full_name')),0) not between 1 and 160
 or coalesce(length(btrim(p->>'state')),0) not between 1 and 160
 or coalesce(length(btrim(p->>'district')),0) not between 1 and 160
 or coalesce(length(btrim(p->>'current_village_city')),0) not between 1 and 200
 or coalesce(length(btrim(p->>'course_trade_specialization')),0) not between 1 and 160
 or p->>'gender' is null or p->>'gender' not in ('Male','Female','Other / Prefer not to say')
 or p->>'highest_qualification' is null or p->>'highest_qualification' not in ('Below 10th','10th','12th','ITI','Diploma','Graduate','Post Graduate','Other')
 or p->>'experience_status' is null or p->>'experience_status' not in ('Fresher','Experienced')
 or p->>'interview_available' is null or p->>'interview_available' not in ('Yes','No') then raise exception 'Registration details are invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended('r11-candidate:'||w.indian_mobile_key,0));
 perform pg_advisory_xact_lock(hashtextextended('w6-mobile:'||w.indian_mobile_key,0));
 select count(*),min(id::text)::uuid into matches,candidate from public.candidates where mobile=w.indian_mobile_key or whatsapp_number=w.indian_mobile_key;
 if matches>1 then raise exception 'Candidate identity requires review';end if;
 if matches=1 then
  if not exists(select 1 from public.candidates where id=candidate and mobile=w.indian_mobile_key and lower(btrim(full_name))=lower(btrim(p->>'full_name')) and age=years and status<>'inactive' and profile_status='active')
  or (w.candidate_id is not null and w.candidate_id<>candidate) then raise exception 'Candidate identity requires review';end if;
 else
  if w.candidate_id is not null then raise exception 'Candidate identity requires review';end if;
  insert into public.candidates(full_name,age,gender,mobile,whatsapp_number,current_location,district,state,highest_qualification,specialization,candidate_type,
  interview_available,consent,profile_status,profile_completion_status,acquisition_source_type,acquisition_source_reference)
  values(btrim(p->>'full_name'),years,p->>'gender',w.indian_mobile_key,w.indian_mobile_key,btrim(p->>'current_village_city'),btrim(p->>'district'),btrim(p->>'state'),
  p->>'highest_qualification',btrim(p->>'course_trade_specialization'),p->>'experience_status',p->>'interview_available',true,'active','incomplete','whatsapp_campaign','whatsapp_flow:'||m.id) returning id into candidate;
 end if;
 insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,source_reference,correlation_id)
 values(candidate,reply.requirement_id,'whatsapp','interested','whatsapp_flow:'||m.id,m.id)
 on conflict(candidate_id,requirement_id) do nothing returning id into app;
 if app is null then select id into strict app from public.candidate_applications where candidate_id=candidate and requirement_id=reply.requirement_id;end if;
 update public.whatsapp_contacts set candidate_id=candidate,resolution_status='resolved',
 imported_profile=imported_profile||jsonb_build_object('Name',btrim(p->>'full_name'),'Age',years,'Gender',p->>'gender','State',p->>'state','District',p->>'district'),updated_at=clock_timestamp() where id=w.id;
 if alerts and (w.consent_recorded_at is null or m.provider_timestamp>w.consent_recorded_at) then
  update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source='whatsapp_flow',consent_scope='all_job_alerts',consent_recorded_at=m.provider_timestamp,
  consent_policy_version='wa-registration-alerts-v1',sharing_subscription=jsonb_build_object('scope','all','locations','[]'::jsonb,'trades','[]'::jsonb,'policy','wa-registration-alerts-v1'),updated_at=clock_timestamp() where id=w.id;
 end if;
 update public.whatsapp_inbound_messages set processing_status='processed',processed_at=clock_timestamp(),campaign_recipient_id=cr.id,application_id=app,last_error_category=null,last_error_code=null,
 redacted_response=jsonb_build_object('form_kind','aadhyant_registration_v1','consent_policy_version','wa-registration-alerts-v1','registration_consent',true,'job_alert_consent',alerts) where id=m.id;
 insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
 values('service','whatsapp.flow_registration_completed','candidate_application',app,'whatsapp',m.id,
 jsonb_build_object('candidate_id',candidate,'requirement_id',reply.requirement_id,'contact_id',w.id,'job_alerts_selected',alerts,'consent_policy_version','wa-registration-alerts-v1','flow_id',reply.registration_flow_id,'flow_hash',reply.registration_flow_hash));
 return jsonb_build_object('status','registered','application_id',app,'job_alerts_selected',alerts);
end;$$;

create function public.console_registration_flow_failure(p_inbound_message_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 update public.whatsapp_inbound_messages set processing_status='failed',processed_at=clock_timestamp(),last_error_category='registration_review_required',last_error_code='validation_or_identity_or_job'
 where id=p_inbound_message_id and message_type='flow' and action_id='REGISTRATION_SUBMIT' and processing_status<>'processed';
 return true;
end;$$;
revoke all on function public.console_registration_flow_failure(uuid) from public,anon,authenticated,service_role;
grant execute on function public.console_registration_flow_failure(uuid) to service_role;

create or replace function public.admin_console_replies(p_campaign_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset';end if;
 return (with linked as (
 select m.*,o.id original_id from public.whatsapp_inbound_messages m join public.whatsapp_outbound_messages o on o.provider_message_id=m.correlation_key and o.contact_id=m.contact_id
 union all
 select m.*,original.id original_id from public.whatsapp_inbound_messages m
 join public.whatsapp_outbound_messages reply on reply.registration_flow_token=m.correlation_key and reply.contact_id=m.contact_id
 join public.whatsapp_inbound_messages interested on interested.id=reply.correlation_id
 join public.whatsapp_outbound_messages original on original.provider_message_id=interested.correlation_key and original.contact_id=interested.contact_id
 where m.message_type='flow' and m.action_id='REGISTRATION_SUBMIT'
 ) select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select m.id,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,m.action_id,m.processing_status,m.last_error_category,m.application_id,m.provider_timestamp,
 reply.state registration_reply_status,reply.last_error_category registration_reply_error,
 case when m.action_id='REGISTRATION_SUBMIT' then m.redacted_response->'job_alert_consent' else null end job_alert_consent
 from linked m join public.whatsapp_contacts w on w.id=m.contact_id
 join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=m.original_id
 join public.whatsapp_campaigns c on c.id=cr.campaign_id
 left join public.whatsapp_outbound_messages reply on reply.idempotency_key='interested-registration:'||m.original_id
 where c.id=p_campaign_id and c.console_template_id is not null
 order by m.created_at desc,m.id limit 100 offset p_offset)t);
end;$$;

revoke all on function public.console_registration_flow_configuration(),public.console_verify_registration_flow(text,text,text),public.admin_console_registration_flow(),public.console_claim_registration_reply(uuid,text),public.console_registration_boundary(uuid,text,text,text),public.console_process_registration_flow(uuid) from public,anon,authenticated,service_role;
grant execute on function public.console_registration_flow_configuration(),public.console_verify_registration_flow(text,text,text),public.console_claim_registration_reply(uuid,text),public.console_registration_boundary(uuid,text,text,text),public.console_process_registration_flow(uuid) to service_role;
grant execute on function public.admin_console_registration_flow() to authenticated;
commit;
