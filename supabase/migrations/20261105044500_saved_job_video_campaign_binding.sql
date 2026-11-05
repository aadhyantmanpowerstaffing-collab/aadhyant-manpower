-- Opt-in private MP4 binding for approved manual job video campaigns.
-- Upgrade-safe: retain generated Reel campaigns and the canonical outbox/send guards.
begin;
create function public.admin_console_prepare_saved_job_video(
 p_job_id uuid,p_template_id uuid,p_media_id uuid,p_contact_ids uuid[],
 p_name text,p_operation uuid,p_scheduled_for timestamptz default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid; c public.whatsapp_campaigns%rowtype; v jsonb;
begin
 if auth.uid() is null or not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 -- Preview validates the exact approved template, saved private VIDEO and current published job.
 perform public.admin_console_preview_saved_job_video(p_job_id,p_template_id,p_media_id);
 v:=private.registered_alert_variables(p_job_id);
 -- This pre-video canonical entry point retains selected audience consent,
 -- suppression, idempotency, approval state and scheduled campaign semantics.
 cid:=public.admin_console_prepare_before_manual_video(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);
 select * into strict c from public.whatsapp_campaigns where id=cid for update;
 if c.criteria ? 'custom_job_video_media_id' then
  if c.criteria->>'custom_job_video_media_id' is distinct from p_media_id::text
   or c.criteria->'custom_job_video_snapshot' is distinct from v then raise exception 'Campaign video or vacancy changed';end if;
 elsif c.campaign_status<>'audience_ready' or c.criteria ? 'job_image_media_id'
       or exists(select 1 from private.whatsapp_campaign_reels where campaign_id=cid) then
  raise exception 'Fresh unbound campaign required';
 else
  update public.whatsapp_campaigns
  set criteria=criteria||jsonb_build_object('custom_job_video_media_id',p_media_id::text,'custom_job_video_snapshot',v)
  where id=cid;
 end if;
 return cid;
end;$$;

alter function private.console_template_valid(uuid) rename to console_template_valid_before_saved_video;
create function private.console_template_valid(p_campaign_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype; t public.whatsapp_template_catalog%rowtype; v jsonb;
begin
 select * into c from public.whatsapp_campaigns where id=p_campaign_id;
 if not found then return false;end if;
 if not (c.criteria ? 'custom_job_video_media_id') then
  return private.console_template_valid_before_saved_video(p_campaign_id);
 end if;
 if c.template_name not in ('aadhyant_registered_job_video_hi_v1','aadhyant_registered_job_video_en_v1')
   or c.requirement_id is null or c.audience_mode<>'selected_contacts'
   or c.template_version<>'1'
   or c.template_language<>case when c.template_name='aadhyant_registered_job_video_hi_v1' then 'hi' else 'en' end
   or c.promotion_media_id is not null
   or not private.vacancy_is_application_eligible(c.requirement_id)
   or exists(select 1 from private.whatsapp_campaign_reels where campaign_id=c.id) then return false;end if;
 select * into t from public.whatsapp_template_catalog
  where id=c.console_template_id and name=c.template_name and language=c.template_language and version=c.template_version
  and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found then return false;end if;
 if c.console_template_snapshot is distinct from jsonb_build_object('name',t.name,'language',t.language,
   'version',t.version,'body',t.body,'buttons',t.buttons) then return false;end if;
 if not exists(select 1 from private.whatsapp_console_media m
  where m.id::text=c.criteria->>'custom_job_video_media_id'
   and m.media_format='VIDEO' and m.byte_size between 100 and 16000000
   and m.object_path=m.id::text||'/'||m.id::text||'.mp4') then return false;end if;
 v:=private.registered_alert_variables(c.requirement_id);
 return c.criteria->'custom_job_video_snapshot'=v
    and v->>'template_contract'='registered_summary_v4'
    and private.whatsapp_safe_flat_json(v)
    and private.manual_video_render(c.template_name,v) is not null
    and char_length(private.manual_video_render(c.template_name,v))<=1024;
end;$$;

-- A video is signed only for a still-eligible, claimed outbox row. The prefix
-- makes the approved private bucket explicit without changing the RPC return type.
alter function public.console_claimed_reel_object(uuid,text) rename to console_claimed_reel_object_before_saved_video;
create function public.console_claimed_reel_object(p_message_id uuid,p_worker_id text)
returns text language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype; row_id uuid;
begin
 select c0.* into c from public.whatsapp_campaigns c0
 join public.whatsapp_campaign_recipients cr on cr.campaign_id=c0.id
 join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id
 where o.id=p_message_id;
 if not found or not (c.criteria ? 'custom_job_video_media_id') then
  return public.console_claimed_reel_object_before_saved_video(p_message_id,p_worker_id);
 end if;
 if not private.whatsapp_vacancy_send_eligible(p_message_id) then return null;end if;
 select m.id into row_id from private.whatsapp_console_media m
 join public.whatsapp_outbound_messages o on o.id=p_message_id
 where m.id::text=c.criteria->>'custom_job_video_media_id'
 and m.media_format='VIDEO' and m.byte_size between 100 and 16000000
 and o.state='sending' and o.send_phase='claimed'
 and o.lease_owner=p_worker_id and o.lease_expires_at>clock_timestamp();
 if row_id is null then return null;end if;
 return 'whatsapp-campaign-media/'||row_id::text||'/'||row_id::text||'.mp4';
end;$$;

revoke all on function public.admin_console_prepare_saved_job_video(uuid,uuid,uuid,uuid[],text,uuid,timestamptz),
 private.console_template_valid_before_saved_video(uuid),private.console_template_valid(uuid),
 public.console_claimed_reel_object_before_saved_video(uuid,text),
 public.console_claimed_reel_object(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_prepare_saved_job_video(uuid,uuid,uuid,uuid[],text,uuid,timestamptz) to authenticated;
grant execute on function public.console_claimed_reel_object(uuid,text) to service_role;
commit;
