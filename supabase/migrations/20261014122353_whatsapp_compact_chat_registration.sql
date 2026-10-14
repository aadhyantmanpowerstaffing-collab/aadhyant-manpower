begin;
alter table private.whatsapp_console_config add column compact_chat_enabled boolean not null default false;
alter table private.whatsapp_registration_chats add column intake_mode text not null default 'legacy' check(intake_mode in ('legacy','compact'));
-- Existing sessions retain their original prompt semantics. New sessions switch only after the reviewed runtime is deployed.
create function private.parse_compact_registration_group(p_step integer,p_text text)
returns jsonb language plpgsql immutable security definer set search_path='' as $$
declare parts text[]; gender text; qualification text; experience text; interview text;
begin
 if p_text is null or length(p_text)>1600 or p_text ~* '(https?://|www\.)' then return null;end if;
 parts:=case when position('|' in p_text)>0 then string_to_array(p_text,'|') else string_to_array(replace(p_text,E'\r',''),E'\n') end;
 parts:=array(select btrim(v) from unnest(parts) v);
 if exists(select 1 from unnest(parts) v where v='' or v ~ '[[:cntrl:]]') then return null;end if;
 if p_step=1 then
  if cardinality(parts)<>6 or length(parts[1])>160 or parts[2] !~ '^[0-9]{1,2}$' then return null;end if;
  if parts[2]::integer not between 16 and 75 or length(parts[4])>160 or length(parts[5])>160 or length(parts[6])>200 then return null;end if;
  gender:=case lower(parts[3]) when 'male' then 'Male' when 'female' then 'Female' when 'other' then 'Other / Prefer not to say' when 'other / prefer not to say' then 'Other / Prefer not to say' end;
  if gender is null then return null;end if;
  return jsonb_build_object('full_name',parts[1],'age',parts[2],'gender',gender,'state',parts[4],'district',parts[5],'current_village_city',parts[6]);
 elsif p_step=2 then
  if cardinality(parts)<>4 or length(parts[2])>160 then return null;end if;
  qualification:=case lower(parts[1]) when 'below 10th' then 'Below 10th' when '10th' then '10th' when '12th' then '12th' when 'iti' then 'ITI' when 'diploma' then 'Diploma' when 'graduate' then 'Graduate' when 'post graduate' then 'Post Graduate' when 'other' then 'Other' end;
  experience:=case lower(parts[3]) when 'fresher' then 'Fresher' when 'experienced' then 'Experienced' end;
  interview:=case lower(parts[4]) when 'yes' then 'Yes' when 'no' then 'No' end;
  if qualification is null or experience is null or interview is null then return null;end if;
  return jsonb_build_object('highest_qualification',qualification,'course_trade_specialization',parts[2],'experience_status',experience,'interview_available',interview);
 end if;
 return null;
end;$$;
revoke all on function private.parse_compact_registration_group(integer,text) from public,anon,authenticated,service_role;
create or replace function private.queue_registration_chat(p_session uuid,p_inbound uuid,p_kind text default 'question',p_invalid boolean default false)
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
 jsonb_build_object('session_id',s.id,'mode',s.intake_mode,'step',s.step,'kind',p_kind,'invalid',p_invalid,'requirement_code',code,
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

create or replace function public.console_process_registration_chat(p_inbound_message_id uuid,p_text text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; s private.whatsapp_registration_chats%rowtype;
 original public.whatsapp_outbound_messages%rowtype; prompt public.whatsapp_outbound_messages%rowtype;
 w public.whatsapp_contacts%rowtype; rec uuid; answer text; key text; choice integer; parts text[]; rid uuid; result jsonb; valid boolean:=false; compact boolean; consent_step integer; grouped jsonb;
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
  insert into private.whatsapp_registration_chats(contact_id,requirement_id,original_outbound_id,start_inbound_id,last_input_at,expires_at,intake_mode)
  values(m.contact_id,original.requirement_id,original.id,m.id,m.provider_timestamp,m.provider_timestamp+interval '24 hours',case when (select compact_chat_enabled from private.whatsapp_console_config where singleton) then 'compact' else 'legacy' end) returning * into s;
  rid:=private.queue_registration_chat(s.id,m.id);
  return jsonb_build_object('handled',true,'status','started','outbound_id',rid);
 end if;
 if not private.vacancy_is_application_eligible(s.requirement_id) then
  update private.whatsapp_registration_chats set status='review',answers='{}',updated_at=clock_timestamp() where id=s.id;
  update public.whatsapp_inbound_messages set registration_chat_id=s.id,registration_chat_processed_at=clock_timestamp(),processing_status='failed',last_error_category='registration_review_required',last_error_code='job_unavailable' where id=m.id;
  return jsonb_build_object('handled',true,'status','job_unavailable');
 end if;
 compact:=s.intake_mode='compact';consent_step:=case when compact then 3 else 11 end;
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
 key:=case when compact and s.step=3 then 'job_alert_consent' else keys[s.step+1] end;
 if m.message_type in ('button','list') and m.correlation_key=prompt.provider_message_id then
  parts:=string_to_array(coalesce(m.action_id,''),'|');
  if array_length(parts,1)=4 and parts[1]='REGCHAT' and parts[2]=s.id::text and parts[3]=s.step::text and parts[4] ~ '^[1-8]$' then
   choice:=parts[4]::integer;
   if compact then
    answer:=case when s.step in (0,3) then case choice when 1 then 'Yes' when 2 then 'No' end else null end;
   else case s.step
    when 0,11 then answer:=case choice when 1 then 'Yes' when 2 then 'No' end;
    when 3 then answer:=(array['Male','Female','Other / Prefer not to say'])[choice];
    when 4 then answer:=(array['Below 10th','10th','12th','ITI','Diploma','Graduate','Post Graduate','Other'])[choice];
    when 9 then answer:=(array['Fresher','Experienced'])[choice];
    when 10 then answer:=(array['Yes','No'])[choice];
    else answer:=null;
   end case;end if;
  else return jsonb_build_object('handled',true,'status','stale_button');end if;
 elsif m.message_type<>'text' then return jsonb_build_object('handled',true,'status','unsupported');
 end if;
 -- Consent requires the exact current signed button, never a bare text Yes.
 if s.step=0 or s.step=consent_step then
  valid:=m.message_type='button' and choice in (1,2) and answer in ('Yes','No');
 elsif compact then
  grouped:=case when m.message_type='text' then private.parse_compact_registration_group(s.step,answer) else null end;
  valid:=grouped is not null;
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
 if compact and s.step in (1,2) then s.answers:=s.answers||grouped;
 else s.answers:=s.answers||jsonb_build_object(key,case when s.step=0 or s.step=consent_step then to_jsonb(answer='Yes') else to_jsonb(answer) end);end if;
 if s.step=consent_step then
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

create or replace function private.registration_chat_eligible(p_message_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages o
 join private.whatsapp_registration_chats s on s.id=o.registration_chat_id and s.prompt_outbound_id=o.id and coalesce(o.template_variables->>'mode','legacy')=s.intake_mode
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

commit;
