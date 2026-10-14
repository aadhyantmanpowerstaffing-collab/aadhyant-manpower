begin;
-- Durable intake state only; all contacts, candidates, applications and sends remain canonical.
alter table private.whatsapp_console_config add column registration_chat_enabled boolean not null default false;
create table private.whatsapp_registration_chats (
 id uuid primary key default gen_random_uuid(), contact_id uuid not null references public.whatsapp_contacts(id),
 requirement_id uuid not null references public.employer_requirements(id),
 original_outbound_id uuid not null references public.whatsapp_outbound_messages(id),
 start_inbound_id uuid not null unique references public.whatsapp_inbound_messages(id),
 status text not null default 'active' check(status in ('active','completed','cancelled','expired','review')),
 step integer not null default 0 check(step between 0 and 12),
 answers jsonb not null default '{}' check(jsonb_typeof(answers)='object'),
 prompt_outbound_id uuid references public.whatsapp_outbound_messages(id),
 last_input_at timestamptz not null, expires_at timestamptz not null,
 reply_count integer not null default 0 check(reply_count between 0 and 60),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index whatsapp_registration_one_active on private.whatsapp_registration_chats(contact_id) where status='active';
create index whatsapp_registration_expiry on private.whatsapp_registration_chats(expires_at) where status='active';
alter table private.whatsapp_registration_chats enable row level security;
revoke all on private.whatsapp_registration_chats from public,anon,authenticated,service_role;
alter table public.whatsapp_inbound_messages add column registration_chat_id uuid references private.whatsapp_registration_chats(id),
 add column registration_chat_processed_at timestamptz,add column registration_chat_reply_id uuid references public.whatsapp_outbound_messages(id);
alter table public.whatsapp_outbound_messages add column registration_chat_id uuid references private.whatsapp_registration_chats(id);
alter table public.whatsapp_outbound_messages drop constraint whatsapp_outbound_messages_message_type_check;
alter table public.whatsapp_outbound_messages add constraint whatsapp_outbound_messages_message_type_check check (
 message_type='template' or (message_type='session_text' and consent_class='transactional' and template_version='1' and max_attempts=1
 and ((purpose='interested_registration' and template_name='aadhyant_interested_registration')
 or (purpose='registration_chat' and template_name='aadhyant_chat_registration' and registration_chat_id is not null))));

-- Shared reviewed canonical registration commit. Only the two validated ingress wrappers may call it.
create function private.complete_whatsapp_registration(p_inbound_id uuid,p_requirement_id uuid,p_recipient_id uuid,p_profile jsonb,p_source text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; w public.whatsapp_contacts%rowtype; p jsonb;
 candidate uuid; app uuid; matches integer; years integer; alerts boolean; v_policy text;
begin
 if p_source not in ('whatsapp_flow','whatsapp_chat') then raise exception 'Registration source invalid';end if;
 v_policy:=case when p_source='whatsapp_flow' then 'wa-registration-alerts-v1' else 'wa-chat-registration-alerts-v1' end;
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
 if alerts and (w.consent_recorded_at is null or m.provider_timestamp>w.consent_recorded_at) then
  update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source=p_source,consent_scope='all_job_alerts',consent_recorded_at=m.provider_timestamp,
  consent_policy_version=v_policy,sharing_subscription=jsonb_build_object('scope','all','locations','[]'::jsonb,'trades','[]'::jsonb,'policy',v_policy),updated_at=clock_timestamp() where id=w.id;
 end if;
 update public.whatsapp_inbound_messages set processing_status='processed',processed_at=clock_timestamp(),campaign_recipient_id=p_recipient_id,application_id=app,last_error_category=null,last_error_code=null,
 redacted_response=jsonb_build_object('form_kind','aadhyant_registration_v1','consent_policy_version',v_policy,'registration_consent',true,'job_alert_consent',alerts) where id=m.id;
 insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
 values('service',case when p_source='whatsapp_flow' then 'whatsapp.flow_registration_completed' else 'whatsapp.chat_registration_completed' end,
 'candidate_application',app,'whatsapp',m.id,jsonb_build_object('candidate_id',candidate,'requirement_id',p_requirement_id,'contact_id',w.id,
 'job_alerts_selected',alerts,'consent_policy_version',v_policy));
 return jsonb_build_object('status','registered','application_id',app,'job_alerts_selected',alerts);
end;$$;
revoke all on function private.complete_whatsapp_registration(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;

create or replace function public.console_process_registration_flow(p_inbound_message_id uuid)
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
 return private.complete_whatsapp_registration(m.id,reply.requirement_id,cr.id,m.redacted_response,'whatsapp_flow');
end;$$;

create function private.queue_registration_chat(p_session uuid,p_inbound uuid,p_kind text default 'question',p_invalid boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_registration_chats%rowtype; code text; rid uuid;
begin
 select * into strict s from private.whatsapp_registration_chats where id=p_session for update;
 if s.reply_count>=60 then
  update private.whatsapp_registration_chats set status='review',answers='{}',updated_at=clock_timestamp() where id=s.id;
  return null;
 end if;
 select requirement_code into code from public.employer_requirements where id=s.requirement_id;
 if code is null or code !~ '^[A-Z0-9_-]{1,64}$' then raise exception 'Job code invalid';end if;
 insert into public.whatsapp_outbound_messages(contact_id,requirement_id,purpose,consent_class,message_type,template_name,template_language,
 template_version,template_variables,destination,idempotency_key,correlation_id,max_attempts,registration_chat_id)
 select s.contact_id,s.requirement_id,'registration_chat','transactional','session_text','aadhyant_chat_registration','en','1',
 jsonb_build_object('session_id',s.id,'step',s.step,'kind',p_kind,'invalid',p_invalid,'requirement_code',code,
 'job_alerts_selected',case when p_kind='complete' then m.redacted_response->'job_alert_consent' else 'null'::jsonb end),
 w.provider_address,'registration-chat:'||p_inbound,p_inbound,1,s.id
 from public.whatsapp_contacts w join public.whatsapp_inbound_messages m on m.id=p_inbound where w.id=s.contact_id
 on conflict(idempotency_key) do nothing returning id into rid;
 if rid is null then select id into rid from public.whatsapp_outbound_messages where idempotency_key='registration-chat:'||p_inbound;end if;
 update private.whatsapp_registration_chats set prompt_outbound_id=rid,reply_count=reply_count+1,updated_at=clock_timestamp() where id=s.id;
 update public.whatsapp_inbound_messages set registration_chat_id=s.id,registration_chat_processed_at=clock_timestamp(),registration_chat_reply_id=rid where id=p_inbound;
 return rid;
end;$$;
revoke all on function private.queue_registration_chat(uuid,uuid,text,boolean) from public,anon,authenticated,service_role;

create function public.console_cancel_registration_chat(p_contact_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('wa-chat:'||p_contact_id,0));
 update private.whatsapp_registration_chats set status='cancelled',answers='{}',updated_at=clock_timestamp() where contact_id=p_contact_id and status='active';
 return true;
end;$$;

create function public.console_process_registration_chat(p_inbound_message_id uuid,p_text text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; s private.whatsapp_registration_chats%rowtype;
 original public.whatsapp_outbound_messages%rowtype; prompt public.whatsapp_outbound_messages%rowtype;
 w public.whatsapp_contacts%rowtype; rec uuid; answer text; key text; choice integer; parts text[]; rid uuid; result jsonb; valid boolean:=false;
 keys text[]:=array['registration_consent','full_name','age','gender','highest_qualification','course_trade_specialization',
 'state','district','current_village_city','experience_status','interview_available','job_alert_consent'];
begin
 if not exists(select 1 from private.whatsapp_console_config where singleton and registration_chat_enabled) then return jsonb_build_object('handled',false);end if;
 select * into strict m from public.whatsapp_inbound_messages where id=p_inbound_message_id;
 if not exists(select 1 from public.whatsapp_webhook_events e where e.id=m.webhook_event_id and e.signature_verified)
 or m.provider_timestamp is null or m.provider_timestamp>clock_timestamp() or m.provider_timestamp<clock_timestamp()-interval '24 hours'
 then return jsonb_build_object('handled',true,'status','invalid_ingress');end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-chat:'||m.contact_id,0));
 select * into strict m from public.whatsapp_inbound_messages where id=p_inbound_message_id for update;
 if m.registration_chat_processed_at is not null then return jsonb_build_object('handled',true,'status','replay','outbound_id',m.registration_chat_reply_id);end if;
 select * into s from private.whatsapp_registration_chats where contact_id=m.contact_id and status='active' for update;
 if found and s.expires_at<=clock_timestamp() then
  update private.whatsapp_registration_chats set status='expired',answers='{}',updated_at=clock_timestamp() where id=s.id;
  s.id:=null;
 end if;
 select * into strict w from public.whatsapp_contacts where id=m.contact_id;
 if w.resolution_status in ('blocked','ambiguous') or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed' then
  if s.id is not null then update private.whatsapp_registration_chats set status='cancelled',answers='{}',updated_at=clock_timestamp() where id=s.id;end if;
  return jsonb_build_object('handled',true,'status','suppressed');
 end if;
 if s.id is null then
  if m.action_id is distinct from 'INTERESTED' then return jsonb_build_object('handled',m.action_id like 'REGCHAT|%','status','no_session');end if;
  if m.last_error_category is distinct from 'registration_required' then return jsonb_build_object('handled',false);end if;
  select o.* into original from public.whatsapp_outbound_messages o where o.provider_message_id=m.correlation_key and o.contact_id=m.contact_id;
  select cr.id into rec from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id
  where cr.outbound_message_id=original.id and cr.whatsapp_contact_id=m.contact_id and cr.id=original.correlation_id
  and c.requirement_id=original.requirement_id and c.console_template_id is not null;
  if original.id is null or original.candidate_id is not null or original.state not in ('sent','delivered','read')
  or original.destination<>w.provider_address or rec is null or not private.vacancy_is_application_eligible(original.requirement_id)
  then return jsonb_build_object('handled',true,'status','unavailable');end if;
  insert into private.whatsapp_registration_chats(contact_id,requirement_id,original_outbound_id,start_inbound_id,last_input_at,expires_at)
  values(m.contact_id,original.requirement_id,original.id,m.id,m.provider_timestamp,m.provider_timestamp+interval '24 hours') returning * into s;
  rid:=private.queue_registration_chat(s.id,m.id);
  return jsonb_build_object('handled',true,'status','started','outbound_id',rid);
 end if;
 if not private.vacancy_is_application_eligible(s.requirement_id) then
  update private.whatsapp_registration_chats set status='review',answers='{}',updated_at=clock_timestamp() where id=s.id;
  update public.whatsapp_inbound_messages set registration_chat_id=s.id,registration_chat_processed_at=clock_timestamp(),processing_status='failed',last_error_category='registration_review_required',last_error_code='job_unavailable' where id=m.id;
  return jsonb_build_object('handled',true,'status','job_unavailable');
 end if;
 answer:=btrim(coalesce(p_text,''));
 if upper(answer) in ('CANCEL','STOP','UNSUBSCRIBE') then
  update private.whatsapp_registration_chats set status='cancelled',answers='{}',updated_at=clock_timestamp() where id=s.id;
  update public.whatsapp_inbound_messages set registration_chat_id=s.id,registration_chat_processed_at=clock_timestamp(),processing_status='ignored',processed_at=clock_timestamp(),last_error_category='registration_cancelled' where id=m.id;
  return jsonb_build_object('handled',true,'status','cancelled');
 end if;
 if upper(answer)='RESUME' or m.action_id='INTERESTED' then
  if m.provider_timestamp<=s.last_input_at then return jsonb_build_object('handled',true,'status','stale');end if;
  -- Explicit user resume creates a new once-only prompt; it never switches jobs.
  update private.whatsapp_registration_chats set last_input_at=m.provider_timestamp where id=s.id;
  rid:=private.queue_registration_chat(s.id,m.id);
  return jsonb_build_object('handled',true,'status','resumed','outbound_id',rid);
 end if;
 select * into prompt from public.whatsapp_outbound_messages where id=s.prompt_outbound_id for share;
 if prompt.state not in ('sent','delivered','read') or prompt.provider_message_id is null or prompt.sent_at is null then
  return jsonb_build_object('handled',true,'status','resume_required');
 end if;
 if (m.correlation_key is not null and m.correlation_key<>prompt.provider_message_id)
 or m.provider_timestamp<date_trunc('second',prompt.sent_at)
 or m.provider_timestamp<s.last_input_at
 or (m.message_type='text' and m.correlation_key is null and m.provider_timestamp<=s.last_input_at)
 then return jsonb_build_object('handled',true,'status','stale');end if;
 key:=keys[s.step+1];
 if m.message_type in ('button','list') and m.correlation_key=prompt.provider_message_id then
  parts:=string_to_array(coalesce(m.action_id,''),'|');
  if array_length(parts,1)=4 and parts[1]='REGCHAT' and parts[2]=s.id::text and parts[3]=s.step::text and parts[4] ~ '^[1-8]$' then
   choice:=parts[4]::integer;
   case s.step
    when 0,11 then answer:=case choice when 1 then 'Yes' when 2 then 'No' end;
    when 3 then answer:=(array['Male','Female','Other / Prefer not to say'])[choice];
    when 4 then answer:=(array['Below 10th','10th','12th','ITI','Diploma','Graduate','Post Graduate','Other'])[choice];
    when 9 then answer:=(array['Fresher','Experienced'])[choice];
    when 10 then answer:=(array['Yes','No'])[choice];
    else answer:=null;
   end case;
  else return jsonb_build_object('handled',true,'status','stale_button');end if;
 elsif m.message_type<>'text' then return jsonb_build_object('handled',true,'status','unsupported');
 end if;
 -- Consent requires the exact current signed button, never a bare text Yes.
 if s.step in (0,11) then
  valid:=m.message_type='button' and choice in (1,2) and answer in ('Yes','No');
 elsif s.step=2 then valid:=coalesce(answer,'') ~ '^[0-9]{1,2}$' and case when coalesce(answer,'') ~ '^[0-9]{1,2}$' then answer::integer between 16 and 75 else false end;
 elsif s.step=3 then valid:=answer in ('Male','Female','Other / Prefer not to say');
 elsif s.step=4 then valid:=answer in ('Below 10th','10th','12th','ITI','Diploma','Graduate','Post Graduate','Other');
 elsif s.step=9 then valid:=answer in ('Fresher','Experienced');
 elsif s.step=10 then valid:=answer in ('Yes','No');
 else valid:=m.message_type='text' and length(answer) between 1 and case when s.step=8 then 200 else 160 end
 and answer !~ '[[:cntrl:]]' and answer !~* '(https?://|www\.)';
 end if;
 update public.whatsapp_inbound_messages set registration_chat_id=s.id,registration_chat_processed_at=clock_timestamp() where id=m.id;
 if valid is distinct from true then
  rid:=private.queue_registration_chat(s.id,m.id,'question',true);
  return jsonb_build_object('handled',true,'status','invalid_answer','outbound_id',rid);
 end if;
 if s.step=0 and answer='No' then
  update private.whatsapp_registration_chats set status='cancelled',answers='{}',updated_at=clock_timestamp() where id=s.id;
  rid:=private.queue_registration_chat(s.id,m.id,'cancelled');
  return jsonb_build_object('handled',true,'status','cancelled','outbound_id',rid);
 end if;
 s.answers:=s.answers||jsonb_build_object(key,case when s.step in (0,11) then to_jsonb(answer='Yes') else to_jsonb(answer) end);
 if s.step=11 then
  select id into rec from public.whatsapp_campaign_recipients where outbound_message_id=s.original_outbound_id and whatsapp_contact_id=m.contact_id;
  begin
   result:=private.complete_whatsapp_registration(m.id,s.requirement_id,rec,s.answers||jsonb_build_object('form_kind','aadhyant_registration_v1','consent_policy_version','wa-chat-registration-alerts-v1'),'whatsapp_chat');
  exception when others then
   update private.whatsapp_registration_chats set status='review',answers='{}',updated_at=clock_timestamp() where id=s.id;
   update public.whatsapp_inbound_messages set processing_status='failed',processed_at=clock_timestamp(),last_error_category='registration_review_required',last_error_code='validation_or_identity_or_job' where id=m.id;
   rid:=private.queue_registration_chat(s.id,m.id,'review');
   return jsonb_build_object('handled',true,'status','review','outbound_id',rid);
  end;
  update private.whatsapp_registration_chats set status='completed',step=12,answers='{}',last_input_at=m.provider_timestamp,updated_at=clock_timestamp() where id=s.id;
  rid:=private.queue_registration_chat(s.id,m.id,'complete');
  return result||jsonb_build_object('handled',true,'outbound_id',rid);
 end if;
 update private.whatsapp_registration_chats set step=step+1,answers=s.answers,last_input_at=m.provider_timestamp,updated_at=clock_timestamp() where id=s.id;
 update public.whatsapp_inbound_messages set processing_status='normalized',processed_at=clock_timestamp(),last_error_category=null,last_error_code=null where id=m.id;
 rid:=private.queue_registration_chat(s.id,m.id);
 return jsonb_build_object('handled',true,'status','next_question','outbound_id',rid);
end;$$;

create function private.registration_chat_eligible(p_message_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages o
 join private.whatsapp_registration_chats s on s.id=o.registration_chat_id and s.prompt_outbound_id=o.id
 join public.whatsapp_inbound_messages m on m.id=o.correlation_id and m.contact_id=o.contact_id and m.registration_chat_id=s.id
 join public.whatsapp_webhook_events e on e.id=m.webhook_event_id and e.signature_verified
 join public.whatsapp_contacts w on w.id=o.contact_id
 where o.id=p_message_id and o.purpose='registration_chat' and o.consent_class='transactional' and o.message_type='session_text'
 and o.requirement_id=s.requirement_id and o.destination=w.provider_address and o.max_attempts=1
 and m.provider_timestamp<=clock_timestamp() and m.provider_timestamp>clock_timestamp()-interval '24 hours'
 and s.expires_at>clock_timestamp() and private.vacancy_is_application_eligible(s.requirement_id)
 and w.resolution_status not in ('blocked','ambiguous') and w.marketing_consent_status<>'opted_out' and w.transactional_contact_status<>'suppressed'
 and ((s.status='active' and o.template_variables->>'kind'='question' and (o.template_variables->>'step')::integer=s.step)
 or (s.status='completed' and o.template_variables->>'kind'='complete')
 or (s.status='cancelled' and o.template_variables->>'kind'='cancelled')
 or (s.status='review' and o.template_variables->>'kind'='review')));
$$;
revoke all on function private.registration_chat_eligible(uuid) from public,anon,authenticated,service_role;

create function public.console_claim_registration_chat(p_message_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,message_type text,purpose text,consent_class text,template_variables jsonb)
language plpgsql security definer set search_path='' as $$
declare contact uuid;
begin
 if p_worker_id is null or length(btrim(p_worker_id)) not between 1 and 160 then raise exception 'Worker required';end if;
 select o.contact_id into contact from public.whatsapp_outbound_messages o where o.id=p_message_id and o.purpose='registration_chat';
 if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-chat:'||contact,0));
 update public.whatsapp_outbound_messages set state='failed',send_phase=case when send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
 failed_at=clock_timestamp(),lease_owner=null,lease_expires_at=null,last_error_category='reply_lease_expired',last_error_code='no_automatic_retry',updated_at=clock_timestamp()
 where id=p_message_id and state='sending' and lease_expires_at<=clock_timestamp();
 if not exists(select 1 from private.whatsapp_console_config where singleton and registration_chat_enabled and sender_ready and verified_at>clock_timestamp()-interval '24 hours')
 or not private.registration_chat_eligible(p_message_id) then return;end if;
 return query update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=1,lease_owner=btrim(p_worker_id),
 lease_expires_at=clock_timestamp()+interval '120 seconds',updated_at=clock_timestamp()
 where o.id=p_message_id and o.state='queued' and o.send_phase='ready' and o.attempt_count=0
 returning o.id,o.destination,o.message_type,o.purpose,o.consent_class,o.template_variables;
end;$$;

create function public.console_registration_chat_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
declare contact uuid; sid uuid;
begin
 select contact_id,registration_chat_id into contact,sid from public.whatsapp_outbound_messages where id=p_message_id and purpose='registration_chat';
 if not found then raise exception 'Chat lease unavailable';end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-chat:'||contact,0));
 perform 1 from private.whatsapp_registration_chats where id=sid for share;
 perform 1 from public.whatsapp_outbound_messages where id=p_message_id and state='sending' and send_phase='claimed'
 and lease_owner=btrim(p_worker_id) and lease_expires_at>clock_timestamp() for update;
 if not found then raise exception 'Chat lease unavailable';end if;
 perform 1 from public.whatsapp_contacts where id=contact for share;
 perform 1 from public.employer_requirements r join public.whatsapp_outbound_messages o on o.requirement_id=r.id where o.id=p_message_id for share of r;
 perform 1 from private.whatsapp_console_config where singleton and registration_chat_enabled and sender_ready and phone_number_id=p_phone_id
 and business_account_id=p_account_id and verified_at>clock_timestamp()-interval '24 hours' for share;
 if not found or not private.registration_chat_eligible(p_message_id) then raise exception 'Chat eligibility changed';end if;
 update public.whatsapp_outbound_messages set send_phase='provider_call_started',updated_at=clock_timestamp() where id=p_message_id and lease_expires_at>clock_timestamp();
 if not found then raise exception 'Chat lease expired';end if;
 return true;
end;$$;
revoke all on function public.console_cancel_registration_chat(uuid),public.console_process_registration_chat(uuid,text),public.console_claim_registration_chat(uuid,text),public.console_registration_chat_boundary(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.console_cancel_registration_chat(uuid),public.console_process_registration_chat(uuid,text),public.console_claim_registration_chat(uuid,text),public.console_registration_chat_boundary(uuid,text,text,text) to service_role;
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
 union all
 select m.*,s.original_outbound_id original_id from public.whatsapp_inbound_messages m
 join private.whatsapp_registration_chats s on s.id=m.registration_chat_id
 where m.action_id is distinct from 'INTERESTED'
 ) select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select m.id,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,m.action_id,m.processing_status,m.last_error_category,m.application_id,m.provider_timestamp,
 reply.state registration_reply_status,reply.last_error_category registration_reply_error,
 case when m.action_id='REGISTRATION_SUBMIT' or m.registration_chat_id is not null then m.redacted_response->'job_alert_consent' else null end job_alert_consent,
 case when m.registration_chat_id is not null then 'chat' else 'form_or_link' end registration_channel,
 s.status registration_status,s.step registration_step
 from linked m join public.whatsapp_contacts w on w.id=m.contact_id
 join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=m.original_id
 join public.whatsapp_campaigns c on c.id=cr.campaign_id
 left join private.whatsapp_registration_chats s on s.id=m.registration_chat_id
 left join public.whatsapp_outbound_messages reply on
 (m.registration_chat_id is null and reply.idempotency_key='interested-registration:'||m.original_id)
 or (m.registration_chat_id is not null and reply.id=coalesce(m.registration_chat_reply_id,s.prompt_outbound_id))
 where c.id=p_campaign_id and c.console_template_id is not null
 order by m.created_at desc,m.id limit 100 offset p_offset)t);
end;$$;

create or replace function public.admin_console_registration_flow()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return (select jsonb_build_object('ready',registration_flow_id is not null and registration_flow_verified_at>clock_timestamp()-interval '24 hours',
 'chat_enabled',registration_chat_enabled) from private.whatsapp_console_config where singleton);
end;$$;
commit;
