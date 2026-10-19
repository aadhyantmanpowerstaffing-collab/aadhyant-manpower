-- pg_net transport headers contain only a short-lived single-use wake capability.
begin;
create or replace function public.console_verify_automatic_wake(p_key text) returns boolean language plpgsql volatile security definer set search_path='' as $$
begin
 if p_key is null or p_key !~ '^[a-f0-9]{64}$' then return false;end if;
 update private.whatsapp_automatic_dispatch_state set key_hash=sha256(convert_to(gen_random_uuid()::text,'UTF8'))
 where singleton and key_hash=sha256(convert_to(p_key,'UTF8')) and last_requested_at>clock_timestamp()-interval '5 minutes';
 return found;
end;$$;
create or replace function private.wake_registered_alert_worker() returns bigint language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_automatic_dispatch_state%rowtype; token text; rid bigint;
begin
 if not exists(select 1 from private.whatsapp_console_config where singleton and automatic_alerts_enabled) then return null;end if;
 if not exists(select 1 from private.whatsapp_job_publications where outcome='template_unavailable' and authorized_by is not null and campaign_id is null)
 and not exists(select 1 from public.whatsapp_campaigns where audience_mode='registered_alerts' and campaign_status in ('queued','sending') and cancelled_at is null) then return null;end if;
 select * into strict s from private.whatsapp_automatic_dispatch_state where singleton for update;
 if s.last_requested_at>clock_timestamp()-interval '5 seconds' then return null;end if;
 token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 rid:=net.http_post(url:='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/whatsapp-outbox-worker',
 body:='{"automatic":true}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-whatsapp-wake-key',token),timeout_milliseconds:=150000);
 update private.whatsapp_automatic_dispatch_state set key_hash=sha256(convert_to(token,'UTF8')),last_requested_at=clock_timestamp(),last_request_id=rid,last_error=null where singleton;
 return rid;
exception when others then
 -- Preserve the canonical job transaction; the minute timer retries this wake, never a provider send.
 update private.whatsapp_automatic_dispatch_state set last_error='dispatch_wake_unavailable' where singleton;
 return null;
end;$$;
revoke all on function public.console_verify_automatic_wake(text),private.wake_registered_alert_worker() from public,anon,authenticated,service_role;
grant execute on function public.console_verify_automatic_wake(text) to service_role;
commit;
