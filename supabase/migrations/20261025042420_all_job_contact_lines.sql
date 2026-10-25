-- Extend approved contact-line templates without replaying historical campaigns.
begin;
create function private.english_contact_alert_body() returns text language sql immutable set search_path='' as $body$ select 'Hello,

*Aadhyant Manpower & Staffing* has a new job opening. Review the summary below and share this opportunity with someone looking for work.

*Job details*
• Vacancy: {{1}}
• Company: {{2}}
• Role: {{3}}
• Location: {{4}}

*Qualification*
{{5}}

*Salary & duty*
• CTC / Salary: {{6}}
• Approx. take home: {{7}}
• Overtime: {{8}}
• Duty: {{9}}

*Benefits*
{{10}}

Tap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.

For more information or to apply for a job, call 9586785800.

To stop WhatsApp job alerts, tap Stop alerts or reply STOP.' $body$;
create function private.same_day_contact_alert_body() returns text language sql immutable set search_path='' as $body$ select '*रोकड़ी काम — उसी शाम भुगतान*
*Aadhyant Manpower & Staffing*

📍 *स्थान:* {{1}}
🛠️ *काम:* {{2}}
📅 *तारीख:* {{3}}
🕗 *समय:* {{4}}
👥 *ज़रूरत:* {{5}} लोग
💵 *मेहनताना:* {{6}} प्रति व्यक्ति, पूरी शिफ्ट का
✅ *भुगतान:* उसी दिन {{7}}

काम के लिए उपलब्ध हैं? नीचे बटन दबाकर आवेदन करें। कंपनी/ठेकेदार आपकी जगह की पुष्टि करेगा।

अधिक जानकारी या नौकरी के लिए आवेदन करने हेतु 9586785800 पर कॉल करें।

अलर्ट बंद करने के लिए *Stop alerts* दबाएँ या *STOP* लिखें।' $body$;
create function private.contact_alert_render(p_name text,p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare rendered text;k text;n integer:=0;keys text[];begin
 if p_name='aadhyant_registered_job_alert_hi_v2' then return private.hindi_contact_alert_render(p_vars);end if;
 if p_name='aadhyant_registered_job_alert_v5' then rendered:=private.english_contact_alert_body();keys:=array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'];
 elsif p_name='aadhyant_same_day_pay_hi_v2' then rendered:=private.same_day_contact_alert_body();keys:=array['job_location','job_role','work_date','shift','headcount','pay','payment'];
 else raise exception 'Unsupported contact template';end if;
 foreach k in array keys loop n:=n+1;rendered:=replace(rendered,'{{'||n||'}}',coalesce(p_vars->>k,''));end loop;return rendered;
end;$$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_all_contact;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 n:=public.console_sync_templates_before_all_contact(p_rows);
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name in ('aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2');
 update public.whatsapp_template_catalog t set compatible=
 ((t.name='aadhyant_registered_job_alert_v5' and t.language='en' and t.body=private.english_contact_alert_body() and t.buttons=private.registered_alert_buttons())
 or (t.name='aadhyant_same_day_pay_hi_v2' and t.language='hi' and t.body=private.same_day_contact_alert_body() and t.buttons=private.same_day_alert_buttons()))
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id and jsonb_array_length(r->'components')=2
 and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BUTTONS')=1)
 where t.name in ('aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2');return n;
end;$$;
create function public.admin_console_preview_contact_alert(p_requirement_id uuid,p_template_name text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare vars jsonb; rendered text;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 vars:=private.registered_alert_variables(p_requirement_id);rendered:=private.contact_alert_render(p_template_name,vars);
 if (vars->>'template_contract'='same_day_hi_v1') is distinct from (p_template_name='aadhyant_same_day_pay_hi_v2') or not private.whatsapp_safe_flat_json(vars) or char_length(rendered)>1024 then raise exception 'Job summary exceeds supported limits or job type';end if;
 return jsonb_build_object('message',rendered);
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
 select * into t from public.whatsapp_template_catalog where name=case when req.work_engagement='same_day_pay' then 'aadhyant_same_day_pay_hi_v2' when video then case when lang='hi' then 'aadhyant_registered_job_video_hi_v1' else 'aadhyant_registered_job_video_en_v1' end else 'aadhyant_registered_job_alert_v5' end and language=case when req.work_engagement='same_day_pay' then 'hi' when video then lang else 'en' end and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found or (not video and char_length(private.contact_alert_render(t.name,vars))>1024) or not private.whatsapp_safe_flat_json(vars) or coalesce(vars->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or exists(select 1 from jsonb_each_text(vars) e where nullif(btrim(e.value),'') is null) then
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


create or replace function public.admin_queue_selected_job_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; req public.employer_requirements%rowtype; cr public.whatsapp_campaign_recipients%rowtype; outbound uuid; total integer:=0; vars jsonb;
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into strict campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if campaign.audience_mode<>'selected_contacts' then raise exception 'Sharing campaign required'; end if;
  if campaign.campaign_status in ('queued','sending','completed') then
    return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=campaign.id and outbound_message_id is not null);
  end if;
  if campaign.campaign_status<>'approved' then raise exception 'Approved campaign required'; end if;
  select * into strict req from public.employer_requirements where id=campaign.requirement_id for share;
  if campaign.template_name in ('aadhyant_registered_job_alert_hi_v1','aadhyant_registered_job_alert_hi_v2','aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2') then
    if campaign.template_language<>(case when campaign.template_name='aadhyant_registered_job_alert_v5' then 'en' else 'hi' end) or campaign.template_version<>'1' or not private.console_template_valid(campaign.id) then raise exception 'Approved Hindi template required';end if;
    vars:=private.registered_alert_variables(req.id);
    if vars->>'template_contract' is distinct from (case when campaign.template_name='aadhyant_same_day_pay_hi_v2' then 'same_day_hi_v1' else 'registered_summary_v4' end) or not private.whatsapp_safe_flat_json(vars) or char_length(case when campaign.template_name='aadhyant_registered_job_alert_hi_v1' then private.hindi_registered_alert_render(vars) else private.contact_alert_render(campaign.template_name,vars) end)>1024 then raise exception 'Hindi job summary exceeds supported limits or job type';end if;
  end if;
  for cr in select * from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included' order by id for update loop
    if not private.selected_job_contact_eligible(cr.whatsapp_contact_id,req.id) then raise exception 'Audience changed or suppressed'; end if;
    outbound:=public.enqueue_whatsapp_outbound_message(cr.whatsapp_contact_id,cr.candidate_id,req.id,'vacancy_campaign','marketing',
      campaign.template_name,campaign.template_language,campaign.template_version,
      case when campaign.template_name in ('aadhyant_registered_job_alert_hi_v1','aadhyant_registered_job_alert_hi_v2','aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2') then vars||jsonb_build_object('campaign_id',campaign.id::text,'recipient_id',cr.id::text) else jsonb_build_object('requirement_code',req.requirement_code,'job_role',req.job_role,'campaign_id',campaign.id::text,'recipient_id',cr.id::text,'action_id','INTERESTED') end,
      'campaign:'||campaign.id::text||':recipient:'||cr.id::text,cr.id,3);
    update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=outbound where id=cr.id;
    total:=total+1;
  end loop;
  if total=0 then raise exception 'Empty audience'; end if;
  update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(auth.uid(),'staff','whatsapp.selected_job_campaign_queued','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('count',total));
  return total;
end;
$$;



alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_all_contact;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype;c public.whatsapp_campaigns%rowtype;rid uuid;vars jsonb;
begin
 if not private.whatsapp_vacancy_send_eligible_before_all_contact(p_message_id) then return false;end if;
 select * into strict o from public.whatsapp_outbound_messages where id=p_message_id;
 if o.template_name not in ('aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2') then return true;end if;
 select camp.* into c from public.whatsapp_campaigns camp join public.whatsapp_campaign_recipients cr on cr.campaign_id=camp.id where cr.outbound_message_id=o.id;
 select id into rid from public.whatsapp_campaign_recipients where outbound_message_id=o.id;
 vars:=private.registered_alert_variables(o.requirement_id);
 return c.audience_mode in ('selected_contacts','registered_alerts') and c.template_name=o.template_name
 and c.template_language=case when o.template_name='aadhyant_registered_job_alert_v5' then 'en' else 'hi' end
 and o.template_language=c.template_language and c.template_version='1' and o.template_version='1'
 and private.console_template_valid(c.id) and vars->>'template_contract'=case when o.template_name='aadhyant_same_day_pay_hi_v2' then 'same_day_hi_v1' else 'registered_summary_v4' end
 and private.whatsapp_safe_flat_json(vars) and char_length(private.contact_alert_render(o.template_name,vars))<=1024
 and o.template_variables=vars||jsonb_build_object('campaign_id',c.id::text,'recipient_id',rid::text);
end;$$;

create or replace function public.admin_console_automatic_alerts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select jsonb_build_object('enabled',automatic_alerts_enabled,'daily_limit',automatic_alerts_daily_limit,
 'worker_ready',automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes',
 'template_ready',exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v5' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'),
 'eligible_subscribers',(select count(*) from public.whatsapp_contacts w where private.registered_alert_contact_eligible(w.id)),
 'recent_publications',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
 select r.requirement_code,p.published_at,p.campaign_id,p.outcome,
 case when p.authorized_by is not null and p.job_snapshot is distinct from private.registered_alert_variables(r.id) then 'Job changed; pending messages paused' else null end attention
 from private.whatsapp_job_publications p join public.employer_requirements r on r.id=p.requirement_id order by p.published_at desc limit 25)x))
 from private.whatsapp_console_config where singleton);
end; $$;
create or replace function public.admin_console_set_automatic_alerts(p_enabled boolean,p_daily_limit integer default 100)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_enabled is null or p_daily_limit is null or p_daily_limit not between 10 and 1000 then raise exception 'Daily limit must be 10 to 1000'; end if;
 perform 1 from private.whatsapp_console_config where singleton for update;
 if p_enabled and (not exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v5' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours')
 or not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours' and automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes')) then
 raise exception 'Approved template, verified sender and running automatic worker required'; end if;
 update private.whatsapp_console_config set automatic_alerts_enabled=p_enabled,automatic_alerts_daily_limit=p_daily_limit,
 automatic_alerts_approved_by=case when p_enabled then auth.uid() else automatic_alerts_approved_by end,
 automatic_alerts_enabled_at=case when p_enabled then clock_timestamp() else automatic_alerts_enabled_at end where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.automatic_alerts_configured','whatsapp_campaign','admin',jsonb_build_object('enabled',p_enabled,'daily_limit',p_daily_limit));
 return true;
end; $$;

create or replace function public.admin_console_preview_full_job_alert(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare vars jsonb; rendered text;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 vars:=private.registered_alert_variables(p_requirement_id);rendered:=private.contact_alert_render(case when vars->>'template_contract'='same_day_hi_v1' then 'aadhyant_same_day_pay_hi_v2' else 'aadhyant_registered_job_alert_v5' end,vars);
 return jsonb_build_object('template_name',case when vars->>'template_contract'='same_day_hi_v1' then 'aadhyant_same_day_pay_hi_v2' else 'aadhyant_registered_job_alert_v5' end,
 'message',rendered,'within_limits',private.whatsapp_safe_flat_json(vars) and char_length(rendered)<=1024,'body_limit',1024,'body_characters',char_length(rendered),'detail_mode','summary_with_full_job_link');
end; $$;

revoke all on function private.english_contact_alert_body(),private.same_day_contact_alert_body(),private.contact_alert_render(text,jsonb),public.console_sync_templates_before_all_contact(jsonb),public.console_sync_templates(jsonb),public.admin_console_preview_contact_alert(uuid,text),private.whatsapp_vacancy_send_eligible_before_all_contact(uuid),private.whatsapp_vacancy_send_eligible(uuid) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb) to service_role;
grant execute on function public.admin_console_preview_contact_alert(uuid,text) to authenticated;
commit;
