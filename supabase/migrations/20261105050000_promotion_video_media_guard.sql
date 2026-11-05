-- Keep registration promotion media strictly VIDEO after the shared media store
-- gained image support. This is additive and preserves existing campaign/outbox flow.
begin;

alter function public.admin_console_prepare_promotion(uuid,uuid[],text,uuid)
  rename to admin_console_prepare_promotion_before_video_media_guard;
create function public.admin_console_prepare_promotion(
 p_media_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid
) returns uuid language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.admin_console_access() then
  raise exception 'Admin access required' using errcode='42501';
 end if;
 if p_media_id is null or not exists(
  select 1 from private.whatsapp_console_media m
  where m.id=p_media_id and m.media_format='VIDEO'
   and m.byte_size between 100 and 16000000
   and m.object_path=m.id::text||'/'||m.id::text||'.mp4'
 ) then
  raise exception 'Upload a valid MP4 video first';
 end if;
 return public.admin_console_prepare_promotion_before_video_media_guard(
  p_media_id,p_contact_ids,p_name,p_operation
 );
end;$$;

alter function private.console_template_valid(uuid)
  rename to console_template_valid_before_promotion_media_guard;
create function private.console_template_valid(p_campaign_id uuid)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;
begin
 if not private.console_template_valid_before_promotion_media_guard(p_campaign_id) then
  return false;
 end if;
 select * into c from public.whatsapp_campaigns where id=p_campaign_id;
 if not found then return false; end if;
 if c.promotion_media_id is null then return true; end if;
 return c.requirement_id is null
  and c.template_name='aadhyant_registration_video_hi_v1'
  and c.template_language='hi'
  and c.template_version='1'
  and exists(
   select 1 from private.whatsapp_console_media m
   where m.id=c.promotion_media_id and m.media_format='VIDEO'
    and m.byte_size between 100 and 16000000
    and m.object_path=m.id::text||'/'||m.id::text||'.mp4'
  );
end;$$;

create or replace function public.console_promotion_media_object(p_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select m.object_path from private.whatsapp_console_media m
 where m.id=p_id and m.media_format='VIDEO'
  and m.byte_size between 100 and 16000000
  and m.object_path=m.id::text||'/'||m.id::text||'.mp4'
$$;

revoke all on function public.admin_console_prepare_promotion_before_video_media_guard(uuid,uuid[],text,uuid),
 public.admin_console_prepare_promotion(uuid,uuid[],text,uuid),
 private.console_template_valid_before_promotion_media_guard(uuid),
 private.console_template_valid(uuid),
 public.console_promotion_media_object(uuid)
from public,anon,authenticated,service_role;
grant execute on function public.admin_console_prepare_promotion(uuid,uuid[],text,uuid) to authenticated;
grant execute on function public.console_promotion_media_object(uuid) to service_role;
commit;
