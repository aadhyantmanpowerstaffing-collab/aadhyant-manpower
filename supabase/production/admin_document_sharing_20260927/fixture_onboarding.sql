create table public.candidate_onboarding_details (
  candidate_id uuid primary key references public.candidates(id) on delete restrict,
  account_holder_name text,
  bank_name text,
  bank_account_fingerprint text,
  bank_account_last4 text,
  ifsc text,
  has_existing_uan boolean,
  uan_number text,
  has_existing_esic_ip boolean,
  esic_ip_number text,
  documentation_override_approved boolean not null default false,
  documentation_override_reason text,
  documentation_override_by uuid references auth.users(id) on delete set null,
  documentation_override_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidate_onboarding_bank_pair_check check (
    (bank_account_fingerprint is null and bank_account_last4 is null)
    or (bank_account_fingerprint ~ '^[0-9a-f]{64}$' and bank_account_last4 ~ '^[0-9]{4}$')
  ),
  constraint candidate_onboarding_ifsc_check check (ifsc is null or ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  constraint candidate_onboarding_uan_check check (
    (has_existing_uan is distinct from true and uan_number is null)
    or (has_existing_uan is true and uan_number ~ '^[0-9]{12}$')
  ),
  constraint candidate_onboarding_esic_check check (
    (has_existing_esic_ip is distinct from true and esic_ip_number is null)
    or (has_existing_esic_ip is true and esic_ip_number ~ '^[0-9]{10,17}$')
  ),
  constraint candidate_onboarding_override_check check (
    (documentation_override_approved is false and documentation_override_reason is null
      and documentation_override_by is null and documentation_override_at is null)
    or (documentation_override_approved is true
      and length(btrim(documentation_override_reason)) between 10 and 1000
      and documentation_override_by is not null and documentation_override_at is not null)
  )
);
CREATE TRIGGER candidate_onboarding_details_set_updated_at BEFORE UPDATE ON public.candidate_onboarding_details FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
ALTER TABLE public.candidate_onboarding_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.candidate_onboarding_details FROM PUBLIC,anon,authenticated;
create function public.get_candidate_onboarding_details()
returns table(account_holder_name text,bank_name text,bank_account_masked text,ifsc text,has_existing_uan boolean,
  uan_masked text,has_existing_esic_ip boolean,esic_ip_masked text,documentation_override_approved boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select o.account_holder_name,o.bank_name,
    case when o.bank_account_last4 is null then null else 'XXXX XXXX '||o.bank_account_last4 end,o.ifsc,o.has_existing_uan,
    case when o.uan_number is null then null else 'XXXXXXXX'||right(o.uan_number,4) end,o.has_existing_esic_ip,
    case when o.esic_ip_number is null then null else repeat('X',greatest(length(o.esic_ip_number)-4,0))||right(o.esic_ip_number,4) end,
    o.documentation_override_approved from public.candidate_onboarding_details o where o.candidate_id=v_id;
end;
$$;
create function public.update_candidate_onboarding_details(p_account_holder_name text,p_bank_name text,p_bank_account_number text,
  p_ifsc text,p_has_existing_uan boolean,p_uan_number text,p_has_existing_esic_ip boolean,p_esic_ip_number text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_account text; v_ifsc text:=upper(btrim(coalesce(p_ifsc,'')));
  v_uan text:=regexp_replace(coalesce(p_uan_number,''),'[^0-9]','','g'); v_esic text:=regexp_replace(coalesce(p_esic_ip_number,''),'[^0-9]','','g');
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  v_account:=regexp_replace(coalesce(p_bank_account_number,''),'[^0-9]','','g');
  if length(btrim(coalesce(p_account_holder_name,''))) not between 1 and 160 or length(btrim(coalesce(p_bank_name,''))) not between 1 and 160
    or v_account !~ '^[0-9]{6,20}$' or v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$'
    or (coalesce(p_has_existing_uan,false) and v_uan !~ '^[0-9]{12}$')
    or (coalesce(p_has_existing_esic_ip,false) and v_esic !~ '^[0-9]{10,17}$') then raise exception 'Joining onboarding details are invalid'; end if;
  insert into public.candidate_onboarding_details(candidate_id,account_holder_name,bank_name,bank_account_fingerprint,
    bank_account_last4,ifsc,has_existing_uan,uan_number,has_existing_esic_ip,esic_ip_number)
  values(v_id,btrim(p_account_holder_name),btrim(p_bank_name),encode(extensions.digest(v_account,'sha256'),'hex'),right(v_account,4),v_ifsc,
    coalesce(p_has_existing_uan,false),case when p_has_existing_uan then v_uan else null end,
    coalesce(p_has_existing_esic_ip,false),case when p_has_existing_esic_ip then v_esic else null end)
  on conflict(candidate_id) do update set account_holder_name=excluded.account_holder_name,bank_name=excluded.bank_name,
    bank_account_fingerprint=excluded.bank_account_fingerprint,bank_account_last4=excluded.bank_account_last4,ifsc=excluded.ifsc,
    has_existing_uan=excluded.has_existing_uan,uan_number=excluded.uan_number,has_existing_esic_ip=excluded.has_existing_esic_ip,
    esic_ip_number=excluded.esic_ip_number;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'candidate','candidate.onboarding_details_updated','candidate',v_id,'candidate',jsonb_build_object('bank_updated',true,'uan_declared',coalesce(p_has_existing_uan,false),'esic_declared',coalesce(p_has_existing_esic_ip,false)));
  return true;
end;
$$;
REVOKE ALL ON FUNCTION public.get_candidate_onboarding_details(),public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_candidate_onboarding_details(),public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text) TO authenticated;
