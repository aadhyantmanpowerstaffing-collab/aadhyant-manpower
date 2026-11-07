-- Server-side idempotency and spend guard for the Supabase Auth Send SMS hook.
-- This stores only keyed hashes, never phone numbers or OTP values.
-- Apply before deploying and enabling the candidate-auth-whatsapp-hook.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.candidate_whatsapp_otp_dispatches (
  code_hash text primary key check (code_hash ~ '^[a-f0-9]{64}$'),
  phone_hash text not null check (phone_hash ~ '^[a-f0-9]{64}$'),
  delivery_state text not null default 'reserved'
    check (delivery_state in ('reserved', 'sent', 'failed')),
  reserved_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  provider_message_id text
);

alter table private.candidate_whatsapp_otp_dispatches enable row level security;
revoke all on table private.candidate_whatsapp_otp_dispatches
  from public, anon, authenticated;

create index if not exists candidate_whatsapp_otp_dispatches_phone_reserved_idx
  on private.candidate_whatsapp_otp_dispatches (phone_hash, reserved_at desc);

create or replace function public.candidate_otp_dispatch_reserve(
  p_phone_hash text,
  p_code_hash text
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_has_existing boolean := false;
  v_existing_state text;
  v_existing_reserved_at timestamptz;
  v_recent_dispatches integer;
begin
  if p_phone_hash is null or p_code_hash is null
    or p_phone_hash !~ '^[a-f0-9]{64}$'
    or p_code_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid OTP dispatch token';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('candidate-auth-otp:' || p_phone_hash, 0)
  );

  select d.delivery_state, d.reserved_at
    into v_existing_state, v_existing_reserved_at
    from private.candidate_whatsapp_otp_dispatches d
    where d.code_hash = p_code_hash
    for update;
  v_has_existing := found;
  if v_has_existing and v_existing_reserved_at >= now() - interval '10 minutes' then
    if v_existing_state = 'sent' then
      return 'sent';
    end if;
    -- Never send a second copy if a prior delivery outcome is uncertain.
    return 'in_progress';
  end if;

  select count(*)
    into v_recent_dispatches
    from private.candidate_whatsapp_otp_dispatches d
    where d.phone_hash = p_phone_hash
      and d.reserved_at >= now() - interval '24 hours';
  if v_recent_dispatches >= 3 then
    return 'limited';
  end if;

  -- A six-digit Auth code can eventually recur. Once the idempotency window
  -- has passed, recycle its keyed-hash row so a later valid Auth event is not
  -- silently suppressed forever.
  if v_has_existing then
    update private.candidate_whatsapp_otp_dispatches d
      set phone_hash = p_phone_hash,
          delivery_state = 'reserved',
          reserved_at = now(),
          updated_at = now(),
          provider_message_id = null
      where d.code_hash = p_code_hash;
    return 'reserved';
  end if;

  insert into private.candidate_whatsapp_otp_dispatches (code_hash, phone_hash)
  values (p_code_hash, p_phone_hash);
  return 'reserved';
end;
$$;

create or replace function public.candidate_otp_dispatch_complete(
  p_code_hash text,
  p_provider_message_id text
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_state text;
begin
  if p_code_hash is null or p_provider_message_id is null
    or p_code_hash !~ '^[a-f0-9]{64}$'
    or p_provider_message_id !~ '^wamid\.'
    or length(p_provider_message_id) > 512 then
    raise exception 'Invalid OTP dispatch completion';
  end if;

  update private.candidate_whatsapp_otp_dispatches d
    set delivery_state = 'sent',
        provider_message_id = p_provider_message_id,
        updated_at = now()
    where d.code_hash = p_code_hash
      and d.delivery_state = 'reserved';
  if found then
    return 'sent';
  end if;

  select d.delivery_state
    into v_existing_state
    from private.candidate_whatsapp_otp_dispatches d
    where d.code_hash = p_code_hash;
  if v_existing_state = 'sent' then
    return 'sent';
  end if;
  return 'rejected';
end;
$$;

create or replace function public.candidate_otp_dispatch_fail(
  p_code_hash text
) returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_code_hash is null or p_code_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid OTP dispatch token';
  end if;

  update private.candidate_whatsapp_otp_dispatches d
    set delivery_state = 'failed',
        updated_at = now()
    where d.code_hash = p_code_hash
      and d.delivery_state = 'reserved';
  if found then
    return 'failed';
  end if;
  return 'ignored';
end;
$$;

revoke all on function public.candidate_otp_dispatch_reserve(text, text)
  from public, anon, authenticated;
revoke all on function public.candidate_otp_dispatch_complete(text, text)
  from public, anon, authenticated;
revoke all on function public.candidate_otp_dispatch_fail(text)
  from public, anon, authenticated;
grant execute on function public.candidate_otp_dispatch_reserve(text, text) to service_role;
grant execute on function public.candidate_otp_dispatch_complete(text, text) to service_role;
grant execute on function public.candidate_otp_dispatch_fail(text) to service_role;

commit;
