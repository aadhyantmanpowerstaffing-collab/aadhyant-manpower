-- Approved Hindi job-summary contract for operator-selected campaigns. No campaign is queued by installation.
begin;
create function private.hindi_registered_alert_body() returns text language sql immutable set search_path='' as $body$ select 'नमस्ते,
*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। नीचे विवरण देखें और काम ढूँढ रहे लोगों के साथ साझा करें।

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

पूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे नौकरी देखें बटन दबाएँ।

WhatsApp नौकरी अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।' $body$;
create function private.hindi_registered_alert_buttons() returns jsonb language sql immutable set search_path='' as $$select '[{"type": "URL", "text": "नौकरी देखें और आवेदन करें", "url": "https://aadhyantmanpower.in/jobs/?requirement={{1}}"}, {"type": "QUICK_REPLY", "text": "Stop alerts"}]'::jsonb$$;
create function private.hindi_registered_alert_render(p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare rendered text:=private.hindi_registered_alert_body();k text;n integer:=0;
begin
 foreach k in array array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'] loop n:=n+1;rendered:=replace(rendered,'{{'||n||'}}',coalesce(p_vars->>k,''));end loop;
 return rendered;
end;$$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_hindi_registered;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 n:=public.console_sync_templates_before_hindi_registered(p_rows);
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name='aadhyant_registered_job_alert_hi_v1' and t.language='hi';
 update public.whatsapp_template_catalog t set compatible=t.body=private.hindi_registered_alert_body() and t.buttons=private.hindi_registered_alert_buttons()
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
 and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BUTTONS')=1
 and not exists(select 1 from jsonb_array_elements(r->'components') b where b->>'type' not in ('BODY','BUTTONS')))
 where t.name='aadhyant_registered_job_alert_hi_v1' and t.language='hi';
 return n;
end;$$;
create function public.admin_console_preview_hindi_job_alert(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare vars jsonb; rendered text;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 vars:=private.registered_alert_variables(p_requirement_id);rendered:=private.hindi_registered_alert_render(vars);
 if vars->>'template_contract' is distinct from 'registered_summary_v4' or not private.whatsapp_safe_flat_json(vars) or char_length(rendered)>1024 then raise exception 'Hindi job summary exceeds supported limits or job type';end if;
 return jsonb_build_object('message',rendered);
end;$$;
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
  if campaign.template_name='aadhyant_registered_job_alert_hi_v1' then
    if campaign.template_language<>'hi' or campaign.template_version<>'1' or not private.console_template_valid(campaign.id) then raise exception 'Approved Hindi template required';end if;
    vars:=private.registered_alert_variables(req.id);
    if vars->>'template_contract' is distinct from 'registered_summary_v4' or not private.whatsapp_safe_flat_json(vars) or char_length(private.hindi_registered_alert_render(vars))>1024 then raise exception 'Hindi job summary exceeds supported limits or job type';end if;
  end if;
  for cr in select * from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included' order by id for update loop
    if not private.selected_job_contact_eligible(cr.whatsapp_contact_id,req.id) then raise exception 'Audience changed or suppressed'; end if;
    outbound:=public.enqueue_whatsapp_outbound_message(cr.whatsapp_contact_id,cr.candidate_id,req.id,'vacancy_campaign','marketing',
      campaign.template_name,campaign.template_language,campaign.template_version,
      case when campaign.template_name='aadhyant_registered_job_alert_hi_v1' then vars||jsonb_build_object('campaign_id',campaign.id::text,'recipient_id',cr.id::text) else jsonb_build_object('requirement_code',req.requirement_code,'job_role',req.job_role,'campaign_id',campaign.id::text,'recipient_id',cr.id::text,'action_id','INTERESTED') end,
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


alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_hindi_manual;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype;c public.whatsapp_campaigns%rowtype;rid uuid;vars jsonb;
begin
 if not private.whatsapp_vacancy_send_eligible_before_hindi_manual(p_message_id) then return false;end if;
 select * into strict o from public.whatsapp_outbound_messages where id=p_message_id;
 if o.template_name<>'aadhyant_registered_job_alert_hi_v1' then return true;end if;
 select camp.* into c from public.whatsapp_campaigns camp join public.whatsapp_campaign_recipients cr on cr.campaign_id=camp.id where cr.outbound_message_id=o.id;
 select id into rid from public.whatsapp_campaign_recipients where outbound_message_id=o.id;
 vars:=private.registered_alert_variables(o.requirement_id);
 return c.audience_mode='selected_contacts' and c.template_name=o.template_name and c.template_language='hi' and o.template_language='hi' and c.template_version='1' and o.template_version='1'
 and private.console_template_valid(c.id) and vars->>'template_contract'='registered_summary_v4' and private.whatsapp_safe_flat_json(vars)
 and char_length(private.hindi_registered_alert_render(vars))<=1024
 and o.template_variables=vars||jsonb_build_object('campaign_id',c.id::text,'recipient_id',rid::text);
end;$$;
-- Previously fetched metadata must be re-synced through the strict component validator.
update public.whatsapp_template_catalog set compatible=false where name='aadhyant_registered_job_alert_hi_v1';
revoke all on function private.hindi_registered_alert_body(),private.hindi_registered_alert_buttons(),private.hindi_registered_alert_render(jsonb),private.whatsapp_vacancy_send_eligible_before_hindi_manual(uuid),private.whatsapp_vacancy_send_eligible(uuid),public.console_sync_templates_before_hindi_registered(jsonb),public.console_sync_templates(jsonb),public.admin_console_preview_hindi_job_alert(uuid) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb) to service_role;
grant execute on function public.admin_console_preview_hindi_job_alert(uuid) to authenticated;
commit;
