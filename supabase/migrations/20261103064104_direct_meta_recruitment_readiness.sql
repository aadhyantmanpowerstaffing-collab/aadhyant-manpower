begin;
-- Called only by the service worker after fresh Meta ownership/template checks.
-- Refreshing readiness never enables sending or changes the selected language.
create function public.console_refresh_recruitment_template_verification(p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 update private.whatsapp_console_config set recruitment_templates_verified_at=clock_timestamp()
 where singleton and sender_ready and phone_number_id=p_phone_id and business_account_id=p_account_id
 and recruitment_updates_enabled and not interview_notifications_enabled
 and verified_at>clock_timestamp()-interval '5 minutes';
 return found;
end;$$;
revoke all on function public.console_refresh_recruitment_template_verification(text,text) from public,anon,authenticated,service_role;
grant execute on function public.console_refresh_recruitment_template_verification(text,text) to service_role;
commit;
