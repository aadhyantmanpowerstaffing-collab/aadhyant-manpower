-- Separate Hindi video template. Installation preserves the current language and paused state.
begin;
alter table private.reel_config add column whatsapp_template_language text not null default 'en' check(whatsapp_template_language in ('en','hi'));
create function private.hindi_video_job_alert_body() returns text language sql immutable set search_path='' as $body$ select 'नमस्ते,
*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। हिंदी वीडियो देखें और नीचे जानकारी पढ़ें।

*नौकरी का विवरण*
• भर्ती संदर्भ: {{1}}
• कंपनी: {{2}}
• पद: {{3}}
• स्थान: {{4}}

*योग्यता*
{{5}}

*वेतन और ड्यूटी*
• CTC / वेतन: {{6}}
• अनुमानित हाथ में वेतन: {{7}}
• ओवरटाइम: {{8}}
• ड्यूटी: {{9}}

*सुविधाएँ*
{{10}}

पूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे बटन दबाएँ।
अधिक जानकारी या आवेदन के लिए 9586785800 पर कॉल करें।
अलर्ट बंद करने के लिए अलर्ट बंद करें दबाएँ या STOP लिखें।' $body$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_hindi_video;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 n:=public.console_sync_templates_before_hindi_video(p_rows);
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name='aadhyant_registered_job_video_hi_v1' and t.language='hi';
 update public.whatsapp_template_catalog t set compatible=t.body=private.hindi_video_job_alert_body() and t.buttons='[{"type": "URL", "text": "नौकरी देखें और आवेदन करें", "url": "https://aadhyantmanpower.in/jobs/?requirement={{1}}"}, {"type": "QUICK_REPLY", "text": "अलर्ट बंद करें"}]'::jsonb
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id and jsonb_array_length(r->'components')=3
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='HEADER' and c->>'format'='VIDEO')=1
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='BUTTONS')=1)
 where t.name='aadhyant_registered_job_video_hi_v1' and t.language='hi';return n;
end;$$;
create or replace function private.prepare_registered_publication(p_requirement_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare pub private.whatsapp_job_publications%rowtype; req public.employer_requirements%rowtype;
 t public.whatsapp_template_catalog%rowtype; cid uuid; vars jsonb; stamp timestamptz; n integer; video boolean; rid uuid; rendered text; k text; idx integer:=0; lang text;
begin
 select * into strict pub from private.whatsapp_job_publications where requirement_id=p_requirement_id for update;
 if pub.campaign_id is not null or pub.authorized_by is null or pub.outcome='disabled' then return;end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id;
 if not private.vacancy_is_application_eligible(req.id) or pub.job_snapshot is distinct from private.registered_alert_variables(req.id) then return;end if;
 vars:=pub.job_snapshot;stamp:=pub.published_at;
 select whatsapp_template_language into lang from private.reel_config where singleton;
 video:=coalesce((select whatsapp_delivery_enabled from private.reel_config where singleton),false) and vars->>'template_contract'='registered_summary_v4';
 if video then
  select j.id into rid from private.requirement_reels j where j.requirement_id=req.id and j.state='ready' and j.object_path is not null and j.payload=private.reel_payload(req.id) order by j.created_at desc limit 1;
  if rid is null then return;end if;
  rendered:=case when lang='hi' then private.hindi_video_job_alert_body() else private.video_job_alert_body() end;
  foreach k in array array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'] loop idx:=idx+1;rendered:=replace(rendered,'{{'||idx||'}}',vars->>k);end loop;
  if char_length(rendered)>1024 then return;end if;
 end if;
 select * into t from public.whatsapp_template_catalog where name=case when req.work_engagement='same_day_pay' then 'aadhyant_same_day_pay_hi_v1' when video then case when lang='hi' then 'aadhyant_registered_job_video_hi_v1' else 'aadhyant_registered_job_video_en_v1' end else 'aadhyant_registered_job_alert_v4' end and language=case when req.work_engagement='same_day_pay' then 'hi' when video then lang else 'en' end and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found or not private.whatsapp_safe_flat_json(vars) or coalesce(vars->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or exists(select 1 from jsonb_each_text(vars) e where nullif(btrim(e.value),'') is null) then
 update private.whatsapp_job_publications set outcome='template_unavailable' where requirement_id=req.id;return;end if;
 insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,campaign_status,purpose,consent_class,template_name,template_language,template_version,
 criteria,created_by,approved_by,approved_at,queued_at,audience_frozen_at,audience_mode,console_template_id,console_template_snapshot)
 values(gen_random_uuid(),req.id,'Auto job alert: '||left(req.requirement_code,100),'queued','vacancy_campaign','marketing',t.name,t.language,t.version,'{}',
 pub.authorized_by,pub.authorized_by,stamp,stamp,stamp,'registered_alerts',t.id,
 jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons)) returning id into cid;
 if video then insert into private.whatsapp_campaign_reels values(cid,rid);end if;
 insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
 select cid,w.candidate_id,w.id,'matched','included','["registered_all_job_alerts","no_matching_filter"]' from public.whatsapp_contacts w
 where private.registered_alert_contact_eligible(w.id) and private.same_day_alert_eligible(req.id,w.id,stamp) and private.job_alert_choice_allows(req.id,w.id,stamp) and w.consent_recorded_at<=stamp and w.created_at<=stamp and exists(select 1 from public.candidates pc where pc.id=w.candidate_id and pc.created_at<=stamp);
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(pub.authorized_by,'staff','whatsapp.automatic_campaign_prepared','whatsapp_campaign',cid,'whatsapp',jsonb_build_object('requirement_id',req.id,'audience_count',n,'standing_approval',true));
 update private.whatsapp_job_publications set campaign_id=cid,outcome=case when n=0 then 'empty' else 'queued' end where requirement_id=req.id;
 if n=0 then update public.whatsapp_campaigns set campaign_status='completed',completed_at=stamp where id=cid; end if;

end; $$;

create or replace function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if not private.whatsapp_vacancy_send_eligible_before_video(p_message_id) then return false;end if;
 if not exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and template_name in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1')) then return true;end if;
 return exists(select 1 from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id join private.whatsapp_campaign_reels b on b.campaign_id=cr.campaign_id join private.requirement_reels j on j.id=b.reel_id cross join private.reel_config cfg
 where o.id=p_message_id and cfg.singleton and cfg.whatsapp_delivery_enabled and j.requirement_id=o.requirement_id and j.state='ready' and j.object_path is not null and j.payload=private.reel_payload(o.requirement_id));
end;$$;
create or replace function public.console_claimed_reel_object(p_message_id uuid,p_worker_id text) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if not private.whatsapp_vacancy_send_eligible(p_message_id) then return null;end if;
 return (select j.object_path from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id join private.whatsapp_campaign_reels b on b.campaign_id=cr.campaign_id join private.requirement_reels j on j.id=b.reel_id
 where o.id=p_message_id and o.template_name in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') and o.state='sending' and o.send_phase='claimed' and o.lease_owner=p_worker_id and o.lease_expires_at>clock_timestamp());
end;$$;
create or replace function private.console_template_valid(p_campaign_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.console_template_valid_before_video(p_campaign_id) and exists(select 1 from public.whatsapp_campaigns c where c.id=p_campaign_id and (c.template_name not in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') or (c.audience_mode='registered_alerts' and exists(select 1 from private.whatsapp_campaign_reels b where b.campaign_id=c.id))))
$$;
create or replace function public.admin_set_reel_whatsapp_delivery(p_enabled boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_enabled is null then raise exception 'Choose enabled or paused';end if;
 if p_enabled and (not exists(select 1 from public.whatsapp_template_catalog where name=case when (select whatsapp_template_language from private.reel_config where singleton)='hi' then 'aadhyant_registered_job_video_hi_v1' else 'aadhyant_registered_job_video_en_v1' end and language=(select whatsapp_template_language from private.reel_config where singleton) and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours') or not exists(select 1 from private.reel_config where singleton and enabled) or not exists(select 1 from private.whatsapp_console_config where singleton and automatic_alerts_enabled and sender_ready and verified_at>clock_timestamp()-interval '24 hours' and automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes')) then raise exception 'Approved video template, Reel service and automatic sender required';end if;
 update private.reel_config set whatsapp_delivery_enabled=p_enabled where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata) values(auth.uid(),'staff','whatsapp.reel_delivery_configured','whatsapp_campaign','admin',jsonb_build_object('enabled',p_enabled));return true;
end;$$;
create function public.admin_set_reel_whatsapp_language(p_language text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_language is null or p_language not in ('en','hi') then raise exception 'Choose English or Hindi';end if;
 perform 1 from private.reel_config where singleton and not whatsapp_delivery_enabled for update;
 if not found then raise exception 'Pause video delivery before changing language';end if;
 update private.reel_config set whatsapp_template_language=p_language where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata) values(auth.uid(),'staff','whatsapp.reel_language_configured','whatsapp_campaign','admin',jsonb_build_object('language',p_language));return true;
end;$$;
revoke all on function private.hindi_video_job_alert_body(),public.console_sync_templates_before_hindi_video(jsonb),public.console_sync_templates(jsonb),public.admin_set_reel_whatsapp_language(text) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb) to service_role;
grant execute on function public.admin_set_reel_whatsapp_language(text) to authenticated;
commit;
