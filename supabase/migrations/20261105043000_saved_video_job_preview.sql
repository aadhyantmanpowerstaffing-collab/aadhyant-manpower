-- Read-only preview/validation for selecting a private MP4 in a future job campaign.
-- Does not create a campaign, grant storage access, alter a sender, or send messages.
begin;
create function public.admin_console_preview_saved_job_video(p_requirement_id uuid,p_template_id uuid,p_media_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t public.whatsapp_template_catalog%rowtype; v jsonb; m text;
begin
 if auth.uid() is null or not public.admin_console_access() then
  raise exception 'Admin access required' using errcode='42501';
 end if;
 if p_requirement_id is null or p_template_id is null or p_media_id is null then
  raise exception 'Choose a job, video template and saved MP4';
 end if;
 select * into t from public.whatsapp_template_catalog
 where id=p_template_id and name in ('aadhyant_registered_job_video_hi_v1','aadhyant_registered_job_video_en_v1')
 and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'
 and version='1' and language=case when name='aadhyant_registered_job_video_hi_v1' then 'hi' else 'en' end;
 if not found then raise exception 'Current approved VIDEO template required'; end if;
 if not exists(select 1 from private.whatsapp_console_media
               where id=p_media_id and media_format='VIDEO'
                 and byte_size between 100 and 16000000
                 and object_path=p_media_id::text||'/'||p_media_id::text||'.mp4') then
  raise exception 'Saved MP4 unavailable';
 end if;
 if not private.vacancy_is_application_eligible(p_requirement_id) then
  raise exception 'Published open job required';
 end if;
 v:=private.registered_alert_variables(p_requirement_id);
 m:=private.manual_video_render(t.name,v);
 if v->>'template_contract' is distinct from 'registered_summary_v4'
    or not private.whatsapp_safe_flat_json(v)
    or m is null or char_length(m)>1024 then
  raise exception 'Video job summary is unavailable or exceeds limits';
 end if;
 return jsonb_build_object('message',m,'media_id',p_media_id,'template_name',t.name,
  'job_id',p_requirement_id,'requires_admin_approval',true,
  'notice','Private media was validated; preparing a campaign still requires eligible recipients, Admin approval and an explicit send.');
end;$$;
revoke all on function public.admin_console_preview_saved_job_video(uuid,uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_console_preview_saved_job_video(uuid,uuid,uuid) to authenticated;
commit;
