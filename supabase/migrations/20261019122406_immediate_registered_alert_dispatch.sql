-- Wake the canonical worker after publication commit; minute timer drains bounded batches.
begin;
create extension if not exists pg_net;
create extension if not exists pg_cron;
create table private.whatsapp_automatic_dispatch_state(
 singleton boolean primary key default true check(singleton),key_hash bytea not null,
 last_requested_at timestamptz,last_request_id bigint,last_error text
);
alter table private.whatsapp_automatic_dispatch_state enable row level security;
revoke all on private.whatsapp_automatic_dispatch_state from public,anon,authenticated,service_role;
do $$declare token text:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');begin
 if exists(select 1 from vault.secrets where name='aadhyant_automatic_dispatch_key') then raise exception 'Dispatch key already exists; review prior installation';end if;
 perform vault.create_secret(token,'aadhyant_automatic_dispatch_key','Canonical automatic alert worker wake credential');
 insert into private.whatsapp_automatic_dispatch_state(key_hash) values(sha256(convert_to(token,'UTF8')));
end;$$;
create function public.console_verify_automatic_wake(p_key text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(p_key ~ '^[a-f0-9]{64}$' and exists(select 1 from private.whatsapp_automatic_dispatch_state where singleton and key_hash=sha256(convert_to(p_key,'UTF8'))),false)
$$;
revoke all on function public.console_verify_automatic_wake(text) from public,anon,authenticated,service_role;
grant execute on function public.console_verify_automatic_wake(text) to service_role;
create function private.wake_registered_alert_worker() returns bigint language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_automatic_dispatch_state%rowtype; token text; rid bigint;
begin
 if not exists(select 1 from private.whatsapp_console_config where singleton and automatic_alerts_enabled) then return null;end if;
 if not exists(select 1 from private.whatsapp_job_publications where outcome='template_unavailable' and authorized_by is not null and campaign_id is null)
 and not exists(select 1 from public.whatsapp_campaigns where audience_mode='registered_alerts' and campaign_status in ('queued','sending') and cancelled_at is null) then return null;end if;
 select * into strict s from private.whatsapp_automatic_dispatch_state where singleton for update;
 if s.last_requested_at>clock_timestamp()-interval '5 seconds' then return null;end if;
 select decrypted_secret into strict token from vault.decrypted_secrets where name='aadhyant_automatic_dispatch_key';
 rid:=net.http_post(url:='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/whatsapp-outbox-worker',
 body:='{"automatic":true}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-whatsapp-wake-key',token),timeout_milliseconds:=150000);
 update private.whatsapp_automatic_dispatch_state set last_requested_at=clock_timestamp(),last_request_id=rid,last_error=null where singleton;
 return rid;
exception when others then
 -- Preserve the canonical job transaction; the minute timer retries this wake, never a provider send.
 update private.whatsapp_automatic_dispatch_state set last_error='dispatch_wake_unavailable' where singleton;
 return null;
end;$$;
create function private.wake_registered_alert_publication() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.authorized_by is not null and new.outcome in ('queued','template_unavailable') then
  if tg_op='INSERT' then perform private.wake_registered_alert_worker();
  elsif old.outcome is distinct from new.outcome then perform private.wake_registered_alert_worker();end if;
 end if;
 return new;
end;$$;
create trigger wake_registered_alert_publication after insert or update of outcome on private.whatsapp_job_publications
 for each row execute function private.wake_registered_alert_publication();
revoke all on function private.wake_registered_alert_worker(),private.wake_registered_alert_publication() from public,anon,authenticated,service_role;
select cron.schedule('aadhyant-automatic-alert-drain','* * * * *',$cron$select private.wake_registered_alert_worker();$cron$);
commit;
