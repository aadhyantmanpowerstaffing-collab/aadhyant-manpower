begin;
-- Keep recruitment and registered-job nonces independent in canonical state.
alter table private.whatsapp_automatic_dispatch_state add column recruitment_key_hash bytea;
create function public.console_verify_recruitment_wake(p_key text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if p_key is null or p_key !~ '^[a-f0-9]{64}$' then return false;end if;
 update private.whatsapp_automatic_dispatch_state set recruitment_key_hash=sha256(convert_to(gen_random_uuid()::text,'UTF8'))
 where singleton and recruitment_key_hash=sha256(convert_to(p_key,'UTF8'))
 and recruitment_last_requested_at>clock_timestamp()-interval '5 minutes';
 return found;
end;$$;
revoke all on function public.console_verify_recruitment_wake(text) from public,anon,authenticated,service_role;
grant execute on function public.console_verify_recruitment_wake(text) to service_role;
create or replace function private.wake_direct_recruitment_worker() returns bigint
language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_automatic_dispatch_state%rowtype; token text; rid bigint;
begin
 if not exists(select 1 from private.whatsapp_console_config where singleton
  and recruitment_updates_enabled and not interview_notifications_enabled) then return null;end if;
 select * into strict s from private.whatsapp_automatic_dispatch_state where singleton for update;
 if s.recruitment_last_requested_at>clock_timestamp()-interval '60 seconds' then return null;end if;
 token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 rid:=net.http_post(url:='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/wanotifier-outbox-worker',
  body:='{"kind":"recruitment_updates"}'::jsonb,
  headers:=jsonb_build_object('Content-Type','application/json','x-whatsapp-wake-key',token),timeout_milliseconds:=150000);
 update private.whatsapp_automatic_dispatch_state set recruitment_key_hash=sha256(convert_to(token,'UTF8')),recruitment_last_requested_at=clock_timestamp(),
  recruitment_last_request_id=rid,recruitment_last_error=null where singleton;
 return rid;
exception when others then
 update private.whatsapp_automatic_dispatch_state set recruitment_last_error='recruitment_wake_unavailable' where singleton;
 return null;
end;$$;
revoke all on function private.wake_direct_recruitment_worker() from public,anon,authenticated,service_role;
commit;
