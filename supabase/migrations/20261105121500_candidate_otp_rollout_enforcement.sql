-- FINAL CUTOVER ONLY.
-- Run this only after the deployed Edge Function, Auth Send SMS hook, five-minute
-- OTP expiry, CAPTCHA, and the enabled browser build have passed the approved
-- test plan. It disables the legacy anonymous registration bypass.
begin;

do $$
begin
  if to_regclass('private.candidate_whatsapp_otp_dispatches') is null then
    raise exception 'Candidate OTP dispatch guard must be installed first';
  end if;
  if to_regprocedure('public.register_authenticated_candidate(jsonb,text)') is null then
    raise exception 'Authenticated candidate registration must be installed first';
  end if;
end;
$$;

drop policy if exists "Public can submit candidate registrations" on public.candidates;
revoke insert on table public.candidates from public, anon, authenticated;
revoke execute on function public.register_candidate_requirement_interest(text, jsonb)
  from public, anon, authenticated;

commit;
