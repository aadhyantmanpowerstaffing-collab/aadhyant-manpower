-- Candidate phone OTP attempts are private server-side state.
-- Do not expose this table through the Data API or grant browser access.
create table if not exists public.candidate_phone_otp (
  phone text primary key check (phone ~ '^91[6-9][0-9]{9}$'),
  otp_hash text not null,
  expires_at timestamptz not null,
  last_sent_at timestamptz not null default now(),
  window_started_at timestamptz not null default now(),
  sends_in_window integer not null default 1,
  verify_attempts integer not null default 0,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.candidate_phone_otp enable row level security;
revoke all on public.candidate_phone_otp from public, anon, authenticated;
create index if not exists candidate_phone_otp_expiry_idx
  on public.candidate_phone_otp (expires_at);
comment on table public.candidate_phone_otp is
  'Server-only WhatsApp authentication challenges. OTP hashes must be keyed with a server secret.';
