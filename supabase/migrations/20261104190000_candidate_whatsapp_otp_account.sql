begin;
-- Supabase Auth owns OTP issuance, expiry, rate limits and session creation.
-- This switch is deliberately off until an approved Authentication template is tested.
create table private.candidate_phone_auth_config(singleton boolean primary key default true check(singleton),enabled boolean not null default false);
insert into private.candidate_phone_auth_config default values;
alter table private.candidate_phone_auth_config enable row level security;
revoke all on private.candidate_phone_auth_config from public,anon,authenticated,service_role;
create table private.candidate_phone_auth_deliveries(
 hook_id text primary key check(length(hook_id) between 1 and 200),
 user_id uuid not null references auth.users(id),
 state text not null check(state in ('started','accepted','review')),
 created_at timestamptz not null default clock_timestamp());
create index candidate_phone_auth_deliveries_user_created_idx on private.candidate_phone_auth_deliveries(user_id,created_at desc);
alter table private.candidate_phone_auth_deliveries enable row level security;
revoke all on private.candidate_phone_auth_deliveries from public,anon,authenticated,service_role;

-- Keep an OTP-linked Candidate profile mobile bound to the Auth-verified phone.
-- A profile edit cannot silently desynchronize future OTP login eligibility.
create function private.guard_candidate_phone_auth_mobile_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $mobile_guard$
declare
 normalized_phone text;
 verified_phone text;
begin
 if old.user_id is null
    or old.mobile_verified is distinct from true
    or new.mobile is not distinct from old.mobile then
  return new;
 end if;

 select regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')
 into normalized_phone
 from auth.users u
 where u.id = old.user_id
   and u.phone_confirmed_at is not null
   and not coalesce(u.is_anonymous, false)
   and (u.banned_until is null or u.banned_until <= clock_timestamp());

 if normalized_phone is not null
    and length(normalized_phone) = 12
    and left(normalized_phone, 2) = '91'
    and substring(normalized_phone from 3 for 1) in ('6', '7', '8', '9') then
  verified_phone := right(normalized_phone, 10);
 else
  verified_phone := null;
 end if;

 if verified_phone is distinct from new.mobile then
  raise exception 'Verify the new WhatsApp number before changing your Candidate mobile number'
    using errcode = '42501';
 end if;
 return new;
end;
$mobile_guard$;

revoke all on function private.guard_candidate_phone_auth_mobile_change() from public,anon,authenticated,service_role;
create trigger candidates_guard_candidate_phone_auth_mobile_change
before update of mobile on public.candidates
for each row execute function private.guard_candidate_phone_auth_mobile_change();


create function public.get_candidate_phone_auth_status() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.candidate_phone_auth_config where singleton and enabled);
$$;
revoke all on function public.get_candidate_phone_auth_status() from public,anon,authenticated,service_role;
grant execute on function public.get_candidate_phone_auth_status() to anon,authenticated;

create function public.claim_candidate_phone_auth_delivery(p_hook_id text,p_user_id uuid,p_phone text)
returns text language plpgsql security definer set search_path='' as $$
declare outcome text;
begin
 if not exists(select 1 from private.candidate_phone_auth_config where singleton and enabled)
 or p_hook_id is null or length(p_hook_id) not between 1 and 200 or p_phone !~ '^\+91[6-9][0-9]{9}$'
 or not exists(select 1 from auth.users where id=p_user_id and ltrim(phone,'+')=ltrim(p_phone,'+'))
 or not (
  exists(select 1 from public.candidates c join public.platform_users pu on pu.user_id=c.user_id
   where c.user_id=p_user_id and c.mobile=right(p_phone,10) and c.mobile_verified is true and c.profile_status='active' and c.status<>'inactive'
   and pu.account_type='candidate' and pu.account_status='active')
  or exists(select 1 from private.whatsapp_web_registrations s
   join public.whatsapp_outbound_messages o on o.id=s.reply_id
   where o.destination=p_phone and o.registration_web_token is not null
   and s.token_hash=sha256(convert_to(o.registration_web_token,'UTF8'))
   and s.completed_at is null and s.expires_at>clock_timestamp()
   and private.web_registration_context(o.registration_web_token) is not null)
 ) then raise exception 'Phone authentication unavailable';end if;
 -- Serialize per-user claims so parallel Auth requests cannot bypass cooldown.
 perform pg_advisory_xact_lock(hashtextextended('candidate-phone-otp:'||p_user_id::text,0));
 select state into outcome from private.candidate_phone_auth_deliveries where hook_id=p_hook_id and user_id=p_user_id;
 if found then return case when outcome='accepted' then 'accepted' else 'review' end;end if;
 if exists(select 1 from private.candidate_phone_auth_deliveries
   where user_id=p_user_id and created_at>clock_timestamp()-interval '60 seconds') then
  raise exception 'Phone authentication cooldown active';
 end if;
 -- No raw code, payload, phone or provider URL is persisted in this ledger.
 insert into private.candidate_phone_auth_deliveries(hook_id,user_id,state) values(p_hook_id,p_user_id,'started');
 return 'send';
end;$$;
create function public.finish_candidate_phone_auth_delivery(p_hook_id text,p_user_id uuid,p_accepted boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 update private.candidate_phone_auth_deliveries set state=case when p_accepted is true then 'accepted' else 'review' end
 where hook_id=p_hook_id and user_id=p_user_id and state='started';
 return found;
end;$$;
revoke all on function public.claim_candidate_phone_auth_delivery(text,uuid,text),public.finish_candidate_phone_auth_delivery(text,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.claim_candidate_phone_auth_delivery(text,uuid,text),public.finish_candidate_phone_auth_delivery(text,uuid,boolean) to service_role;

create function private.bind_whatsapp_candidate_phone_account(p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
declare u auth.users%rowtype;s private.whatsapp_web_registrations%rowtype;o public.whatsapp_outbound_messages%rowtype;c public.candidates%rowtype; mobile text;
begin
 if auth.uid() is null then raise exception 'Verify your WhatsApp number first';end if;
 select * into u from auth.users where id=auth.uid() for update;
 if not found or u.phone_confirmed_at is null or coalesce(u.is_anonymous,false) or ltrim(u.phone,'+') !~ '^91[6-9][0-9]{9}$'
 or (u.banned_until is not null and u.banned_until>clock_timestamp()) then raise exception 'Verified phone account required';end if;
 mobile:=right(u.phone,10);
 select * into s from private.whatsapp_web_registrations where token_hash=sha256(convert_to(p_token,'UTF8')) for update;
 if not found or s.completed_at is null or private.web_registration_context(p_token) is null then raise exception 'Registration link unavailable';end if;
 select * into strict o from public.whatsapp_outbound_messages where id=s.reply_id;
 if o.destination is distinct from '+'||ltrim(u.phone,'+') then raise exception 'Use the WhatsApp number that received this link';end if;
 select c0.* into c from public.candidates c0 join public.whatsapp_contacts w on w.candidate_id=c0.id where w.id=o.contact_id for update of c0;
 if not found or c.mobile is distinct from mobile or c.profile_status<>'active' or c.status='inactive' then raise exception 'Candidate account needs review';end if;
 -- Never transfer an existing portal identity, or claim an imported profile by phone alone.
 if (c.user_id is not null and c.user_id<>u.id) or (c.user_id is null and c.acquisition_source_reference is distinct from 'whatsapp_web:'||s.inbound_id::text)
 or exists(select 1 from public.candidates where user_id=u.id and id<>c.id)
 or exists(select 1 from public.platform_users where user_id=u.id and (account_type<>'candidate' or account_status<>'active' or c.user_id is distinct from u.id))
 or exists(select 1 from public.admin_users where user_id=u.id)
 or exists(select 1 from public.staff_profiles where user_id=u.id)
 or exists(select 1 from public.staff_roles where user_id=u.id)
 or exists(select 1 from public.company_users where user_id=u.id)
 or exists(select 1 from public.contractor_users where user_id=u.id) then raise exception 'Candidate account needs review';end if;
 insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status)
 values(u.id,'candidate',c.full_name,mobile,null,'active') on conflict(user_id) do nothing;
 update public.candidates set user_id=u.id,mobile_verified=true where id=c.id and (user_id is distinct from u.id or not mobile_verified);
 if found then
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(u.id,'candidate','candidate.phone_portal_linked','candidate',c.id,'candidate',jsonb_build_object('method','phone_otp'));
 end if;
 return true;
end;$$;
revoke all on function private.bind_whatsapp_candidate_phone_account(text) from public,anon,authenticated,service_role;

alter function public.submit_whatsapp_registration_form(text,jsonb,jsonb) rename to submit_whatsapp_registration_before_phone_account;
alter function public.submit_whatsapp_registration_before_phone_account(text,jsonb,jsonb) set schema private;
revoke all on function private.submit_whatsapp_registration_before_phone_account(text,jsonb,jsonb) from public,anon,authenticated,service_role;
create function public.submit_whatsapp_registration_form(p_token text,p_profile jsonb,p_optional jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; enabled boolean;phone text;
begin
 select cfg.enabled into enabled from private.candidate_phone_auth_config cfg where singleton;
 if enabled then
  select '+'||ltrim(u.phone,'+') into phone from auth.users u where u.id=auth.uid() and u.phone_confirmed_at is not null and not coalesce(u.is_anonymous,false);
  if phone is null or not exists(select 1 from private.whatsapp_web_registrations s join public.whatsapp_outbound_messages o on o.id=s.reply_id
    where s.token_hash=sha256(convert_to(p_token,'UTF8')) and o.destination=phone) then raise exception 'Verify the WhatsApp number that received this link';end if;
 end if;
 result:=private.submit_whatsapp_registration_before_phone_account(p_token,p_profile,p_optional);
 if enabled then perform private.bind_whatsapp_candidate_phone_account(p_token);result:=result||jsonb_build_object('portal_account_ready',true);end if;
 return result;
end;$$;
revoke all on function public.submit_whatsapp_registration_form(text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.submit_whatsapp_registration_form(text,jsonb,jsonb) to anon,authenticated;

create or replace function public.get_whatsapp_registration_form(p_token text)
returns jsonb language sql security definer set search_path='' as $$
 select private.web_registration_context(p_token)||jsonb_build_object('phone_account_enabled',public.get_candidate_phone_auth_status());
$$;
commit;
