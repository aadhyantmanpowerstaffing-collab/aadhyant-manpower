-- MILESTONE 8A: company onboarding, company-scoped reads, and admin approval
-- Apply only after 007_platform_roles_architecture.sql has completed successfully.

begin;

do $$
begin
  if to_regclass('public.platform_users') is null
     or to_regclass('public.companies') is null
     or to_regclass('public.company_users') is null
     or to_regclass('public.admin_users') is null then
    raise exception 'Milestone 7 prerequisite tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null then
    raise exception 'Milestone 7 admin authorization function is missing';
  end if;
  if to_regprocedure('private.handle_company_signup()') is not null
     or to_regprocedure('public.set_company_account_status(uuid,text)') is not null
     or exists (select 1 from pg_trigger where tgname = 'on_auth_user_created_company_onboarding')
     or exists (select 1 from pg_policies where schemaname = 'public' and policyname like 'M8A %') then
    raise exception 'Milestone 8A objects already exist; inspect database state instead of re-running';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'companies'
      and column_name = any (array[
        'contact_person', 'workforce_size', 'onboarding_notes', 'onboarding_consent_at'
      ])
  ) then
    raise exception 'Milestone 8A company columns already exist; inspect database state before proceeding';
  end if;
end;
$$;

alter table public.companies add column contact_person text;
alter table public.companies add column workforce_size text;
alter table public.companies add column onboarding_notes text;
alter table public.companies add column onboarding_consent_at timestamptz;

alter table public.companies add constraint companies_contact_person_check
  check (contact_person is null or length(btrim(contact_person)) between 1 and 160);
alter table public.companies add constraint companies_workforce_size_check
  check (workforce_size is null or workforce_size in (
    '1-10', '11-50', '51-200', '201-500', '501-1000', '1000+'
  ));

create or replace function private.handle_company_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  legal_name text;
  contact_name text;
  mobile_number text;
  industry_name text;
  city_name text;
  state_name text;
  gstin_value text;
  website_value text;
  address_value text;
  workforce_value text;
  notes_value text;
  company_id uuid;
begin
  if metadata ->> 'onboarding_type' is distinct from 'company' then
    return new;
  end if;

  legal_name := btrim(coalesce(metadata ->> 'company_name', ''));
  contact_name := btrim(coalesce(metadata ->> 'contact_person', ''));
  mobile_number := btrim(coalesce(metadata ->> 'mobile', ''));
  industry_name := nullif(btrim(coalesce(metadata ->> 'industry', '')), '');
  city_name := btrim(coalesce(metadata ->> 'city', ''));
  state_name := btrim(coalesce(metadata ->> 'state', ''));
  gstin_value := nullif(upper(btrim(coalesce(metadata ->> 'gstin', ''))), '');
  website_value := nullif(btrim(coalesce(metadata ->> 'website', '')), '');
  address_value := nullif(btrim(coalesce(metadata ->> 'address', '')), '');
  workforce_value := nullif(btrim(coalesce(metadata ->> 'workforce_size', '')), '');
  notes_value := nullif(btrim(coalesce(metadata ->> 'onboarding_notes', '')), '');

  if legal_name = '' or length(legal_name) > 240 then
    raise exception 'A valid company name is required';
  end if;
  if contact_name = '' or length(contact_name) > 160 then
    raise exception 'A valid contact person is required';
  end if;
  if mobile_number !~ '^[6-9][0-9]{9}$' then
    raise exception 'A valid Indian mobile number is required';
  end if;
  if city_name = '' or length(city_name) > 160
     or state_name = '' or length(state_name) > 160 then
    raise exception 'A valid city and state are required';
  end if;
  if coalesce((metadata ->> 'consent')::boolean, false) is not true then
    raise exception 'Company onboarding consent is required';
  end if;
  if gstin_value is not null
     and gstin_value !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then
    raise exception 'GSTIN format is invalid';
  end if;
  if workforce_value is not null
     and workforce_value not in ('1-10', '11-50', '51-200', '201-500', '501-1000', '1000+') then
    raise exception 'Workforce size is invalid';
  end if;
  if exists (select 1 from public.platform_users where user_id = new.id)
     or exists (select 1 from public.company_users where user_id = new.id) then
    raise exception 'An account profile already exists for this user';
  end if;

  insert into public.platform_users (
    user_id, account_type, display_name, mobile, email, account_status
  ) values (
    new.id, 'company', contact_name, mobile_number, new.email, 'pending'
  );

  insert into public.companies (
    legal_name, industry, gstin, website, main_phone, main_email, address,
    city, state, contact_person, workforce_size, onboarding_notes,
    onboarding_consent_at, verification_status, account_status
  ) values (
    legal_name, industry_name, gstin_value, website_value, mobile_number,
    new.email, address_value, city_name, state_name, contact_name,
    workforce_value, notes_value, now(), 'pending', 'pending'
  ) returning id into company_id;

  insert into public.company_users (
    company_id, user_id, role, status
  ) values (
    company_id, new.id, 'owner', 'pending'
  );

  return new;
end;
$$;

revoke all on function private.handle_company_signup() from public, anon, authenticated;

create trigger on_auth_user_created_company_onboarding
after insert on auth.users
for each row execute function private.handle_company_signup();

create or replace function public.set_company_account_status(
  p_company_id uuid,
  p_account_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_users integer;
begin
  if (select auth.uid()) is null or not (select private.is_admin()) then
    raise exception 'Approved administrator access is required';
  end if;
  if p_account_status not in ('pending', 'active', 'suspended', 'rejected') then
    raise exception 'Invalid company account status';
  end if;
  if not exists (select 1 from public.companies where id = p_company_id) then
    raise exception 'Company account was not found';
  end if;

  update public.companies
  set account_status = p_account_status,
      verification_status = case
        when p_account_status = 'active' then 'verified'
        when p_account_status = 'rejected' then 'rejected'
        else verification_status
      end
  where id = p_company_id;

  update public.platform_users as pu
  set account_status = p_account_status
  where pu.account_type = 'company'
    and exists (
      select 1 from public.company_users as cu
      where cu.company_id = p_company_id and cu.user_id = pu.user_id
    );
  get diagnostics affected_users = row_count;
  if affected_users = 0 then
    raise exception 'Company has no linked platform user';
  end if;

  update public.company_users
  set status = case when p_account_status = 'active' then 'active'
                    when p_account_status = 'pending' then 'pending'
                    else 'suspended' end
  where company_id = p_company_id;
end;
$$;

revoke all on function public.set_company_account_status(uuid, text) from public, anon;
grant execute on function public.set_company_account_status(uuid, text) to authenticated;

create policy "M8A company reads own platform account"
on public.platform_users for select to authenticated
using (user_id = (select auth.uid()) and account_type = 'company');

create policy "M8A company reads own memberships"
on public.company_users for select to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.platform_users as pu
    where pu.user_id = (select auth.uid()) and pu.account_type = 'company'
  )
);

create policy "M8A company reads member company"
on public.companies for select to authenticated
using (
  exists (
    select 1
    from public.company_users as cu
    join public.platform_users as pu on pu.user_id = cu.user_id
    where cu.company_id = companies.id
      and cu.user_id = (select auth.uid())
      and pu.account_type = 'company'
      and pu.account_status = 'active'
      and cu.status = 'active'
  )
);

commit;
