begin;
-- Off until the reviewed client, sender runtime and database have all been deployed.
alter table private.whatsapp_console_config add column registration_web_enabled boolean not null default false;
alter table public.whatsapp_outbound_messages add column registration_web_token text
 check(registration_web_token is null or (registration_web_token ~ '^[a-f0-9]{64}$' and purpose='interested_registration'));
create table private.whatsapp_web_registrations (
 token_hash bytea primary key,
 reply_id uuid not null unique references public.whatsapp_outbound_messages(id),
 inbound_id uuid not null unique references public.whatsapp_inbound_messages(id),
 expires_at timestamptz not null,
 completed_at timestamptz,
 result jsonb
);
alter table private.whatsapp_web_registrations enable row level security;
revoke all on private.whatsapp_web_registrations from public,anon,authenticated,service_role;

-- Retain the existing canonical validator/identity lock and Candidate/Application commit.
create or replace function private.complete_whatsapp_registration(p_inbound_id uuid,p_requirement_id uuid,p_recipient_id uuid,p_profile jsonb,p_source text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; w public.whatsapp_contacts%rowtype; p jsonb;
 candidate uuid; app uuid; matches integer; years integer; alerts boolean; v_policy text;
begin
 if p_source not in ('whatsapp_flow','whatsapp_chat','whatsapp_web') then raise exception 'Registration source invalid';end if;
 v_policy:=case when p_source='whatsapp_flow' then 'wa-registration-alerts-v1' when p_source='whatsapp_web' then 'wa-web-registration-alerts-v1' else 'wa-chat-registration-alerts-v1' end;
 select * into strict m from public.whatsapp_inbound_messages where id=p_inbound_id for update;
 if not exists(select 1 from public.whatsapp_webhook_events e where e.id=m.webhook_event_id and e.signature_verified)
 or m.provider_timestamp is null or m.provider_timestamp>clock_timestamp() or m.provider_timestamp<clock_timestamp()-interval '24 hours'
 then raise exception 'Signed current registration required';end if;
 perform 1 from public.employer_requirements where id=p_requirement_id for share;
 if not found or not private.vacancy_is_application_eligible(p_requirement_id) then raise exception 'Job is not available';end if;
 select * into strict w from public.whatsapp_contacts where id=m.contact_id for update;
 if w.resolution_status in ('blocked','ambiguous') or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed'
 then raise exception 'Contact requires review';end if;
 p:=p_profile;
 if jsonb_typeof(p) is distinct from 'object' or p->>'form_kind' is distinct from 'aadhyant_registration_v1'
 or p->>'consent_policy_version' is distinct from v_policy
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
  p->>'highest_qualification',btrim(p->>'course_trade_specialization'),p->>'experience_status',p->>'interview_available',true,'active','incomplete','whatsapp_campaign',p_source||':'||m.id) returning id into candidate;
 end if;
 insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,source_reference,correlation_id)
 values(candidate,p_requirement_id,'whatsapp','interested',p_source||':'||m.id,m.id)
 on conflict(candidate_id,requirement_id) do nothing returning id into app;
 if app is null then select id into strict app from public.candidate_applications where candidate_id=candidate and requirement_id=p_requirement_id;end if;
 update public.whatsapp_contacts set candidate_id=candidate,resolution_status='resolved',
 imported_profile=imported_profile||jsonb_build_object('Name',btrim(p->>'full_name'),'Age',years,'Gender',p->>'gender','State',p->>'state','District',p->>'district'),updated_at=clock_timestamp() where id=w.id;
 if alerts and (w.consent_recorded_at is null or (case when p_source='whatsapp_web' then clock_timestamp() else m.provider_timestamp end)>w.consent_recorded_at) then
  update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source=p_source,consent_scope='all_job_alerts',consent_recorded_at=case when p_source='whatsapp_web' then clock_timestamp() else m.provider_timestamp end,
  consent_policy_version=v_policy,sharing_subscription=jsonb_build_object('scope','all','locations','[]'::jsonb,'trades','[]'::jsonb,'policy',v_policy),updated_at=clock_timestamp() where id=w.id;
 end if;
 update public.whatsapp_inbound_messages set processing_status='processed',processed_at=clock_timestamp(),campaign_recipient_id=p_recipient_id,application_id=app,last_error_category=null,last_error_code=null,
 redacted_response=jsonb_build_object('form_kind','aadhyant_registration_v1','consent_policy_version',v_policy,'registration_consent',true,'job_alert_consent',alerts) where id=m.id;
 insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
 values('service',case when p_source='whatsapp_flow' then 'whatsapp.flow_registration_completed' when p_source='whatsapp_web' then 'whatsapp.web_registration_completed' else 'whatsapp.chat_registration_completed' end,
 'candidate_application',app,'whatsapp',m.id,jsonb_build_object('candidate_id',candidate,'requirement_id',p_requirement_id,'contact_id',w.id,
 'job_alerts_selected',alerts,'consent_policy_version',v_policy));
 return jsonb_build_object('status','registered','application_id',app,'job_alerts_selected',alerts);
end;$$;
revoke all on function private.complete_whatsapp_registration(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;


-- Preserve existing chat sessions; new Interested replies use the single-page form when enabled.
alter function public.console_process_registration_chat(uuid,text) rename to process_registration_chat_before_web;
alter function public.process_registration_chat_before_web(uuid,text) set schema private;
revoke all on function private.process_registration_chat_before_web(uuid,text) from public,anon,authenticated,service_role;
create function public.console_process_registration_chat(p_inbound_message_id uuid,p_text text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from private.whatsapp_console_config where singleton and registration_web_enabled)
 and exists(select 1 from public.whatsapp_inbound_messages where id=p_inbound_message_id and action_id='INTERESTED')
 and not exists(select 1 from private.whatsapp_registration_chats s join public.whatsapp_inbound_messages m on m.contact_id=s.contact_id
 where m.id=p_inbound_message_id and s.status='active' and s.expires_at>clock_timestamp())
 then return jsonb_build_object('handled',false);end if;
 return private.process_registration_chat_before_web(p_inbound_message_id,p_text);
end;$$;
revoke all on function public.console_process_registration_chat(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.console_process_registration_chat(uuid,text) to service_role;

alter function public.console_claim_registration_reply(uuid,text) rename to claim_registration_reply_before_web;
alter function public.claim_registration_reply_before_web(uuid,text) set schema private;
revoke all on function private.claim_registration_reply_before_web(uuid,text) from public,anon,authenticated,service_role;
create function public.console_claim_registration_reply(p_inbound_message_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,message_type text,purpose text,consent_class text,template_variables jsonb,flow_id text,flow_token text,web_token text)
language plpgsql security definer set search_path='' as $$
declare r record; enabled boolean; token text;
begin
 select registration_web_enabled into enabled from private.whatsapp_console_config where singleton for share;
 for r in select * from private.claim_registration_reply_before_web(p_inbound_message_id,p_worker_id) loop
  if enabled then
   token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
   update public.whatsapp_outbound_messages set registration_web_token=token,registration_flow_id=null,registration_flow_hash=null,registration_flow_token=null where id=r.message_id;
   insert into private.whatsapp_web_registrations(token_hash,reply_id,inbound_id,expires_at)
   select sha256(convert_to(token,'UTF8')),r.message_id,m.id,m.provider_timestamp+interval '24 hours'
   from public.whatsapp_inbound_messages m where m.id=p_inbound_message_id;
  end if;
  return query select o.id,o.destination,o.message_type,o.purpose,o.consent_class,o.template_variables,o.registration_flow_id,o.registration_flow_token,o.registration_web_token
  from public.whatsapp_outbound_messages o where o.id=r.message_id;
 end loop;
end;$$;
revoke all on function public.console_claim_registration_reply(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_registration_reply(uuid,text) to service_role;

-- A mode change after claim must not send an unusable private link.
alter function public.console_registration_boundary(uuid,text,text,text) rename to registration_boundary_before_web;
alter function public.registration_boundary_before_web(uuid,text,text,text) set schema private;
revoke all on function private.registration_boundary_before_web(uuid,text,text,text) from public,anon,authenticated,service_role;
create function public.console_registration_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and registration_web_token is not null)
 and not exists(select 1 from private.whatsapp_console_config where singleton and registration_web_enabled)
 then raise exception 'Registration form mode changed';end if;
 return private.registration_boundary_before_web(p_message_id,p_worker_id,p_phone_id,p_account_id);
end;$$;
revoke all on function public.console_registration_boundary(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.console_registration_boundary(uuid,text,text,text) to service_role;

-- This bearer capability is issued only by signed WhatsApp Interested ingress and a once-only outbox lease.
-- Public callers cannot supply or change the bound contact, phone or job. No profile data is returned.
create function private.web_registration_context(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_web_registrations%rowtype; o public.whatsapp_outbound_messages%rowtype; w public.whatsapp_contacts%rowtype; r public.employer_requirements%rowtype;
begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' or not exists(select 1 from private.whatsapp_console_config where singleton and registration_web_enabled) then return null;end if;
 select * into s from private.whatsapp_web_registrations where token_hash=sha256(convert_to(p_token,'UTF8'));
 if not found or s.expires_at<=clock_timestamp() then return null;end if;
 select * into o from public.whatsapp_outbound_messages where id=s.reply_id and registration_web_token=p_token and state in ('sent','delivered','read');
 if not found then return null;end if;
 select * into w from public.whatsapp_contacts where id=o.contact_id;
 if w.resolution_status in ('blocked','ambiguous') or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed'
 or w.provider_address is distinct from o.destination then return null;end if;
 select * into r from public.employer_requirements where id=o.requirement_id;
 if not private.vacancy_is_application_eligible(r.id) then return null;end if;
 return jsonb_build_object('status',case when s.completed_at is null then 'ready' else 'completed' end,
 'requirement_code',r.requirement_code,'job_role',r.job_role,'job_location',r.job_location,
 'phone_masked','+91XXXXXX'||right(w.indian_mobile_key,4),'expires_at',s.expires_at);
end;$$;
revoke all on function private.web_registration_context(text) from public,anon,authenticated,service_role;
create function public.get_whatsapp_registration_form(p_token text)
returns jsonb language sql security definer set search_path='' as $$select private.web_registration_context(p_token);$$;
revoke all on function public.get_whatsapp_registration_form(text) from public,anon,authenticated,service_role;
grant execute on function public.get_whatsapp_registration_form(text) to anon,authenticated;

create function public.submit_whatsapp_registration_form(p_token text,p_profile jsonb,p_optional jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_web_registrations%rowtype; o public.whatsapp_outbound_messages%rowtype;
 cr uuid; v_result jsonb; candidate uuid; was_new boolean;
begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Registration link unavailable';end if;
 select * into s from private.whatsapp_web_registrations where token_hash=sha256(convert_to(p_token,'UTF8')) for update;
 if not found or private.web_registration_context(p_token) is null then raise exception 'Registration link unavailable';end if;
 if s.completed_at is not null then return s.result;end if;
 select * into strict o from public.whatsapp_outbound_messages where id=s.reply_id;
 -- Lock contact and job before the final context check so STOP/job closure wins if committed first.
 perform 1 from public.whatsapp_contacts where id=o.contact_id for update;
 perform 1 from public.employer_requirements where id=o.requirement_id for share;
 if private.web_registration_context(p_token) is null then raise exception 'Registration link unavailable';end if;
 select cr0.id into cr from public.whatsapp_inbound_messages m
 join public.whatsapp_outbound_messages original on original.provider_message_id=m.correlation_key and original.contact_id=m.contact_id
 join public.whatsapp_campaign_recipients cr0 on cr0.outbound_message_id=original.id and cr0.whatsapp_contact_id=m.contact_id
 where m.id=s.inbound_id and original.requirement_id=o.requirement_id and m.contact_id=o.contact_id;
 if cr is null then raise exception 'Registration link unavailable';end if;
 if p_profile is null or octet_length(p_profile::text)>4096 then raise exception 'Registration details invalid';end if;
 if jsonb_typeof(p_optional) is distinct from 'object' or octet_length(p_optional::text)>1600
 or exists(select 1 from jsonb_object_keys(p_optional) k where k not in ('pincode','total_experience','previous_job_role','preferred_job_location'))
 or exists(select 1 from jsonb_each(p_optional) kv where jsonb_typeof(kv.value)<>'string' or length(kv.value#>>'{}')>160)
 or (coalesce(p_optional->>'pincode','')<>'' and p_optional->>'pincode' !~ '^[0-9]{6}$') then raise exception 'Optional details invalid';end if;
 select not exists(select 1 from public.candidates c join public.whatsapp_contacts w on w.id=o.contact_id
 where c.mobile=w.indian_mobile_key or c.whatsapp_number=w.indian_mobile_key) into was_new;
 v_result:=private.complete_whatsapp_registration(s.inbound_id,o.requirement_id,cr,p_profile,'whatsapp_web');
 select candidate_id into candidate from public.whatsapp_contacts where id=o.contact_id;
 -- Do not replace an existing Candidate's profile from a bearer link.
 if was_new then
  update public.candidates set pincode=nullif(btrim(p_optional->>'pincode'),''),
  total_experience=case when candidate_type='Experienced' then nullif(btrim(p_optional->>'total_experience'),'') end,
  previous_job_role=case when candidate_type='Experienced' then nullif(btrim(p_optional->>'previous_job_role'),'') end,
  preferred_job_location=nullif(btrim(p_optional->>'preferred_job_location'),'') where id=candidate and acquisition_source_reference='whatsapp_web:'||s.inbound_id;
 end if;
 -- No personal data or internal Candidate/Application IDs in the public receipt.
 v_result:=jsonb_build_object('status','registered','job_alerts_selected',p_profile->'job_alert_consent');
 update private.whatsapp_web_registrations set completed_at=clock_timestamp(),result=v_result where token_hash=s.token_hash;
 return v_result;
end;$$;
revoke all on function public.submit_whatsapp_registration_form(text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.submit_whatsapp_registration_form(text,jsonb,jsonb) to anon,authenticated;
commit;
