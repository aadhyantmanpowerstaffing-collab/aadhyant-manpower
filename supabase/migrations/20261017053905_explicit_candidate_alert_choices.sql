begin;
create table private.candidate_alert_choices(
 candidate_id uuid primary key references public.candidates(id) on delete cascade,
 general_alerts boolean not null, same_day_alerts boolean not null,
 current_job_location text not null default '' check(length(current_job_location)<=160),
 source text not null check(source in ('candidate_portal','whatsapp_web')),
 policy_version text not null default 'candidate-alert-choices-v1',
 chosen_at timestamptz not null default clock_timestamp()
);
alter table private.candidate_alert_choices enable row level security;
revoke all on private.candidate_alert_choices from public,anon,authenticated,service_role;

create function private.candidate_is_sanand_local(p_candidate_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.candidates c left join private.candidate_alert_choices a on a.candidate_id=c.id
 where c.id=p_candidate_id and concat_ws(' ',c.current_location,c.preferred_job_location,a.current_job_location,
 (select array_to_string(cp.preferred_locations,' ') from public.candidate_preferences cp where cp.candidate_id=c.id)) ~* '(^|[^a-z])sanand([^a-z]|$)|સાણંદ')
$$;

create function private.save_candidate_alert_choices(p_candidate_id uuid,p_general boolean,p_same_day boolean,p_job_location text,p_source text)
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
 values(auth.uid(),case when p_source='candidate_portal' then 'candidate' else 'service' end,'candidate.alert_choices_saved','candidate',c.id,p_source,
 jsonb_build_object('general_alerts',p_general,'same_day_alerts',p_same_day,'policy','candidate-alert-choices-v1'));
end; $$;

create function public.save_candidate_alert_choices(p_general boolean,p_same_day boolean,p_current_job_location text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();begin
 if auth.uid() is null or cid is null then raise exception 'Active Candidate access required' using errcode='42501';end if;
 perform private.save_candidate_alert_choices(cid,p_general,p_same_day,p_current_job_location,'candidate_portal');
 return jsonb_build_object('saved',true,'general_alerts',p_general,'same_day_alerts',p_same_day);
end; $$;
create function public.get_candidate_alert_choices() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();a private.candidate_alert_choices%rowtype;begin
 if auth.uid() is null or cid is null then raise exception 'Active Candidate access required';end if;
 select * into a from private.candidate_alert_choices where candidate_id=cid;
 return jsonb_build_object('general_alerts',case when a.candidate_id is not null then a.general_alerts else (select case when marketing_consent_status='opted_in' then true when marketing_consent_status='opted_out' then false end from public.whatsapp_contacts where candidate_id=cid) end,
 'same_day_alerts',case when a.candidate_id is not null then a.same_day_alerts else (select enabled from private.same_day_preferences where candidate_id=cid) end,
 'current_job_location',coalesce(a.current_job_location,''),'sanand_eligible',private.candidate_is_sanand_local(cid));
end; $$;
revoke all on function private.candidate_is_sanand_local(uuid),private.save_candidate_alert_choices(uuid,boolean,boolean,text,text),public.save_candidate_alert_choices(boolean,boolean,text),public.get_candidate_alert_choices() from public,anon,authenticated,service_role;
grant execute on function public.save_candidate_alert_choices(boolean,boolean,text),public.get_candidate_alert_choices() to authenticated;

-- Independent per-job choices: same-day Yes does not subscribe someone to regular jobs.
create function private.job_alert_choice_allows(p_requirement_id uuid,p_contact_id uuid,p_stamp timestamptz default null) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_contacts w join public.employer_requirements r on r.id=p_requirement_id
 left join private.candidate_alert_choices a on a.candidate_id=w.candidate_id where w.id=p_contact_id and (p_stamp is null or ((a.candidate_id is null or a.chosen_at<=p_stamp) and not exists(select 1 from public.candidates pc where pc.id=w.candidate_id and nullif(to_jsonb(pc)->>'updated_at','')::timestamptz>p_stamp) and not exists(select 1 from public.candidate_preferences cp where cp.candidate_id=w.candidate_id and nullif(to_jsonb(cp)->>'updated_at','')::timestamptz>p_stamp))) and
 case when r.work_engagement='same_day_pay' then
  coalesce(a.same_day_alerts,(select enabled from private.same_day_preferences where candidate_id=w.candidate_id),false)
  and (a.candidate_id is null or private.candidate_is_sanand_local(w.candidate_id))
 else coalesce(a.general_alerts,true) end)
$$;
create or replace function private.prepare_registered_publication(p_requirement_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare pub private.whatsapp_job_publications%rowtype; req public.employer_requirements%rowtype;
 t public.whatsapp_template_catalog%rowtype; cid uuid; vars jsonb; stamp timestamptz; n integer;
begin
 select * into strict pub from private.whatsapp_job_publications where requirement_id=p_requirement_id for update;
 if pub.campaign_id is not null or pub.authorized_by is null or pub.outcome='disabled' then return;end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id;
 if not private.vacancy_is_application_eligible(req.id) or pub.job_snapshot is distinct from private.registered_alert_variables(req.id) then return;end if;
 vars:=pub.job_snapshot;stamp:=pub.published_at;
 select * into t from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v4' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found or not private.whatsapp_safe_flat_json(vars) or coalesce(vars->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or exists(select 1 from jsonb_each_text(vars) e where nullif(btrim(e.value),'') is null) then
 update private.whatsapp_job_publications set outcome='template_unavailable' where requirement_id=req.id;return;end if;
 insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,campaign_status,purpose,consent_class,template_name,template_language,template_version,
 criteria,created_by,approved_by,approved_at,queued_at,audience_frozen_at,audience_mode,console_template_id,console_template_snapshot)
 values(gen_random_uuid(),req.id,'Auto job alert: '||left(req.requirement_code,100),'queued','vacancy_campaign','marketing',t.name,t.language,t.version,'{}',
 pub.authorized_by,pub.authorized_by,stamp,stamp,stamp,'registered_alerts',t.id,
 jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons)) returning id into cid;
 insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
 select cid,w.candidate_id,w.id,'matched','included','["registered_all_job_alerts","no_matching_filter"]' from public.whatsapp_contacts w
 where private.registered_alert_contact_eligible(w.id) and private.same_day_alert_eligible(req.id,w.id,stamp) and private.job_alert_choice_allows(req.id,w.id,stamp) and w.consent_recorded_at<=stamp and w.created_at<=stamp and exists(select 1 from public.candidates pc where pc.id=w.candidate_id and pc.created_at<=stamp);
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(pub.authorized_by,'staff','whatsapp.automatic_campaign_prepared','whatsapp_campaign',cid,'whatsapp',jsonb_build_object('requirement_id',req.id,'audience_count',n,'standing_approval',true));
 update private.whatsapp_job_publications set campaign_id=cid,outcome=case when n=0 then 'empty' else 'queued' end where requirement_id=req.id;
 if n=0 then update public.whatsapp_campaigns set campaign_status='completed',completed_at=stamp where id=cid; end if;

end; $$;


alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_choices;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.whatsapp_vacancy_send_eligible_before_choices(p_message_id)
 and exists(select 1 from public.whatsapp_outbound_messages o where o.id=p_message_id and private.job_alert_choice_allows(o.requirement_id,o.contact_id))
$$;
revoke all on function private.job_alert_choice_allows(uuid,uuid,timestamptz),private.whatsapp_vacancy_send_eligible_before_choices(uuid),private.whatsapp_vacancy_send_eligible(uuid) from public,anon,authenticated,service_role;

-- Preserve the private-link validator, identity checks and exact replay receipt.
alter function public.submit_whatsapp_registration_form(text,jsonb,jsonb) rename to submit_whatsapp_registration_form_before_choices;
revoke all on function public.submit_whatsapp_registration_form_before_choices(text,jsonb,jsonb) from public,anon,authenticated,service_role;
create function public.submit_whatsapp_registration_form(p_token text,p_profile jsonb,p_optional jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_web_registrations%rowtype; v_result jsonb; cid uuid; same_day boolean; job_location text;begin
 if not(p_optional ? 'same_day_alert_consent') then return public.submit_whatsapp_registration_form_before_choices(p_token,p_profile,p_optional);end if;
 if jsonb_typeof(p_optional->'same_day_alert_consent') is distinct from 'boolean' or jsonb_typeof(p_profile->'job_alert_consent') is distinct from 'boolean'
 or jsonb_typeof(p_optional->'current_job_location') is distinct from 'string' or length(p_optional->>'current_job_location')>160 then raise exception 'Choose Yes or No separately for both alerts';end if;
 select * into s from private.whatsapp_web_registrations where token_hash=sha256(convert_to(p_token,'UTF8')) for update;
 if not found then raise exception 'Registration link unavailable';end if;
 if s.completed_at is not null then return public.submit_whatsapp_registration_form_before_choices(p_token,p_profile,p_optional-'same_day_alert_consent'-'current_job_location');end if;
 same_day:=(p_optional->>'same_day_alert_consent')::boolean;job_location:=p_optional->>'current_job_location';
 v_result:=public.submit_whatsapp_registration_form_before_choices(p_token,p_profile,p_optional-'same_day_alert_consent'-'current_job_location');
 select w.candidate_id into strict cid from public.whatsapp_outbound_messages o join public.whatsapp_contacts w on w.id=o.contact_id where o.id=s.reply_id;
 perform private.save_candidate_alert_choices(cid,(p_profile->>'job_alert_consent')::boolean,same_day,job_location,'whatsapp_web');
 v_result:=v_result||jsonb_build_object('same_day_alerts_selected',same_day);
 update private.whatsapp_web_registrations wr set result=v_result where wr.token_hash=s.token_hash;
 return v_result;
end; $$;
revoke all on function public.submit_whatsapp_registration_form(text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.submit_whatsapp_registration_form(text,jsonb,jsonb) to anon,authenticated;
commit;
