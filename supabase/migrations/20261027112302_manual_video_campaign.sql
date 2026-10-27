begin;
create function private.manual_video_render(p_name text,p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare rendered text; k text; i int:=0;
begin
 rendered:=case p_name when 'aadhyant_registered_job_video_hi_v1' then private.hindi_video_job_alert_body() when 'aadhyant_registered_job_video_en_v1' then private.video_job_alert_body() else null end;
 foreach k in array array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'] loop i:=i+1; rendered:=replace(rendered,'{{'||i||'}}',p_vars->>k); end loop;
 return rendered;
end; $$;
create function public.admin_console_preview_manual_video(p_requirement_id uuid,p_template_name text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb; rendered text;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_template_name not in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') then raise exception 'Video template required';end if;
 if not private.vacancy_is_application_eligible(p_requirement_id) then raise exception 'Open job required';end if;
 v:=private.registered_alert_variables(p_requirement_id); rendered:=private.manual_video_render(p_template_name,v);
 if v->>'template_contract'<>'registered_summary_v4' or not private.whatsapp_safe_flat_json(v) or rendered is null or char_length(rendered)>1024 then raise exception 'Video summary is unavailable or exceeds limits';end if;
 return jsonb_build_object('message',rendered,'reel_ready',exists(select 1 from private.requirement_reels j where j.requirement_id=p_requirement_id and j.state='ready' and j.object_path is not null and j.payload=private.reel_payload(p_requirement_id)));
end; $$;
alter function public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz) rename to admin_console_prepare_before_manual_video;
create function public.admin_console_prepare(p_job_id uuid,p_template_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid,p_scheduled_for timestamptz default null) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; t text; rid uuid; previous uuid; v jsonb;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select name into strict t from public.whatsapp_template_catalog where id=p_template_id;
 if t in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') then
  if not coalesce((select enabled and whatsapp_delivery_enabled from private.reel_config where singleton),false) then raise exception 'Video delivery is paused';end if;
  select id into rid from private.requirement_reels where requirement_id=p_job_id and state='ready' and object_path is not null and payload=private.reel_payload(p_job_id) order by created_at desc limit 1;
  if rid is null then raise exception 'A current job video is required';end if;
  v:=private.registered_alert_variables(p_job_id);
  if v->>'template_contract'<>'registered_summary_v4' or not private.whatsapp_safe_flat_json(v) or private.manual_video_render(t,v) is null or char_length(private.manual_video_render(t,v))>1024 then raise exception 'Video summary is unavailable or exceeds limits';end if;
 end if;
 cid:=public.admin_console_prepare_before_manual_video(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);
 if rid is not null then
  select reel_id into previous from private.whatsapp_campaign_reels where campaign_id=cid;
  if previous is not null and previous<>rid then raise exception 'Campaign video changed; create a new campaign';end if;
  insert into private.whatsapp_campaign_reels(campaign_id,reel_id) values(cid,rid) on conflict(campaign_id) do nothing;
 end if;
 return cid;
end; $$;
create or replace function private.console_template_valid(p_campaign_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.console_template_valid_before_video(p_campaign_id) and exists(select 1 from public.whatsapp_campaigns c where c.id=p_campaign_id and (c.template_name not in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') or (c.audience_mode in ('registered_alerts','selected_contacts') and exists(select 1 from private.whatsapp_campaign_reels b join private.requirement_reels j on j.id=b.reel_id where b.campaign_id=c.id and j.requirement_id=c.requirement_id and j.state='ready' and j.object_path is not null and j.payload=private.reel_payload(c.requirement_id)))))
$$;
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
  if campaign.template_name in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') then
    if not private.console_template_valid(campaign.id) then raise exception 'Current video and approved template required'; end if;
    vars:=private.registered_alert_variables(req.id);
    if vars->>'template_contract'<>'registered_summary_v4' or not private.whatsapp_safe_flat_json(vars) or char_length(private.manual_video_render(campaign.template_name,vars))>1024 then raise exception 'Video job summary exceeds supported limits or job type'; end if;
  elsif campaign.template_name in ('aadhyant_registered_job_alert_hi_v1','aadhyant_registered_job_alert_hi_v2','aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2') then
    if campaign.template_language<>(case when campaign.template_name='aadhyant_registered_job_alert_v5' then 'en' else 'hi' end) or campaign.template_version<>'1' or not private.console_template_valid(campaign.id) then raise exception 'Approved Hindi template required';end if;
    vars:=private.registered_alert_variables(req.id);
    if vars->>'template_contract' is distinct from (case when campaign.template_name='aadhyant_same_day_pay_hi_v2' then 'same_day_hi_v1' else 'registered_summary_v4' end) or not private.whatsapp_safe_flat_json(vars) or char_length(case when campaign.template_name='aadhyant_registered_job_alert_hi_v1' then private.hindi_registered_alert_render(vars) else private.contact_alert_render(campaign.template_name,vars) end)>1024 then raise exception 'Hindi job summary exceeds supported limits or job type';end if;
  end if;
  for cr in select * from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included' order by id for update loop
    if not private.selected_job_contact_eligible(cr.whatsapp_contact_id,req.id) then raise exception 'Audience changed or suppressed'; end if;
    outbound:=public.enqueue_whatsapp_outbound_message(cr.whatsapp_contact_id,cr.candidate_id,req.id,'vacancy_campaign','marketing',
      campaign.template_name,campaign.template_language,campaign.template_version,
      case when campaign.template_name in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1','aadhyant_registered_job_alert_hi_v1','aadhyant_registered_job_alert_hi_v2','aadhyant_registered_job_alert_v5','aadhyant_same_day_pay_hi_v2') then vars||jsonb_build_object('campaign_id',campaign.id::text,'recipient_id',cr.id::text) else jsonb_build_object('requirement_code',req.requirement_code,'job_role',req.job_role,'campaign_id',campaign.id::text,'recipient_id',cr.id::text,'action_id','INTERESTED') end,
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

alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_manual_video;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype; c public.whatsapp_campaigns%rowtype; cr public.whatsapp_campaign_recipients%rowtype; vars jsonb;
begin
 select * into o from public.whatsapp_outbound_messages where id=p_message_id;
 if not found then return false; end if;
 select camp.* into c from public.whatsapp_campaigns camp join public.whatsapp_campaign_recipients rec on rec.campaign_id=camp.id where rec.outbound_message_id=o.id;
 if c.audience_mode is distinct from 'selected_contacts' or o.template_name not in ('aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1') then return private.whatsapp_vacancy_send_eligible_before_manual_video(p_message_id); end if;
 select * into strict cr from public.whatsapp_campaign_recipients where outbound_message_id=o.id;
 vars:=private.registered_alert_variables(c.requirement_id);
 return coalesce((select enabled and whatsapp_delivery_enabled from private.reel_config where singleton),false)
 and c.campaign_status in ('queued','sending') and c.approved_at is not null and c.queued_at is not null and c.cancelled_at is null
 and cr.recipient_status='queued' and cr.id=o.correlation_id and cr.whatsapp_contact_id=o.contact_id and cr.candidate_id is not distinct from o.candidate_id
 and o.requirement_id=c.requirement_id and private.vacancy_is_application_eligible(o.requirement_id) and private.selected_job_contact_eligible(o.contact_id,o.requirement_id)
 and o.purpose='vacancy_campaign' and o.consent_class='marketing' and o.template_name=c.template_name and o.template_language=c.template_language and o.template_version=c.template_version
 and c.template_version='1' and c.template_language=case when c.template_name='aadhyant_registered_job_video_hi_v1' then 'hi' else 'en' end
 and private.console_template_valid(c.id) and vars->>'template_contract'='registered_summary_v4' and private.whatsapp_safe_flat_json(vars)
 and private.manual_video_render(c.template_name,vars) is not null and char_length(private.manual_video_render(c.template_name,vars))<=1024
 and o.template_variables=vars||jsonb_build_object('campaign_id',c.id::text,'recipient_id',cr.id::text);
end; $$;
revoke all on function private.manual_video_render(text,jsonb),private.whatsapp_vacancy_send_eligible_before_manual_video(uuid),private.whatsapp_vacancy_send_eligible(uuid),public.admin_console_prepare_before_manual_video(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_console_preview_manual_video(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_console_preview_manual_video(uuid,text) to authenticated;
commit;
