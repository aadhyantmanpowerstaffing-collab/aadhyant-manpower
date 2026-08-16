-- MILESTONE 8C: contractor onboarding and controlled requirement assignments
-- Apply only after migrations 007, 008, and 009 have completed successfully.

begin;

do $$
begin
  if to_regclass('public.contractors') is null
     or to_regclass('public.contractor_users') is null
     or to_regclass('public.requirement_contractors') is null
     or to_regclass('public.employer_requirements') is null then
    raise exception 'Milestone 7 prerequisite contractor/assignment tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('private.current_active_company_id()') is null then
    raise exception 'Milestone 7/8B prerequisite functions are missing';
  end if;
  if to_regprocedure('private.handle_contractor_signup()') is not null
     or to_regprocedure('private.current_active_contractor_id()') is not null
     or to_regprocedure('public.set_contractor_account_status(uuid,text)') is not null
     or to_regprocedure('public.assign_requirement_contractor(uuid,uuid,integer,text)') is not null
     or to_regprocedure('public.respond_requirement_assignment(uuid,text,text)') is not null
     or to_regprocedure('public.set_requirement_assignment_status(uuid,text)') is not null
     or exists (select 1 from pg_trigger where tgname = 'on_auth_user_created_contractor_onboarding')
     or exists (select 1 from pg_policies where schemaname='public' and policyname like 'M8C %') then
    raise exception 'Milestone 8C objects already exist; inspect database state instead of re-running';
  end if;
  if exists (
    select 1 from information_schema.columns where table_schema='public' and
      ((table_name='contractors' and column_name in ('website','pincode','manpower_categories','onboarding_notes','onboarding_consent_at'))
       or (table_name='requirement_contractors' and column_name in ('declined_at','response_notes')))
  ) then raise exception 'Milestone 8C columns already exist; inspect database state'; end if;
end;
$$;

alter table public.contractors add column website text;
alter table public.contractors add column pincode text;
alter table public.contractors add column manpower_categories text[];
alter table public.contractors add column onboarding_notes text;
alter table public.contractors add column onboarding_consent_at timestamptz;
alter table public.contractors add constraint contractors_pincode_check
  check (pincode is null or pincode ~ '^[0-9]{6}$');

alter table public.requirement_contractors add column declined_at timestamptz;
alter table public.requirement_contractors add column response_notes text;

create or replace function private.handle_contractor_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  agency text; contact text; mobile_value text; capacity integer; contractor_id_value uuid;
  locations text[]; categories text[];
begin
  if metadata->>'onboarding_type' is distinct from 'contractor' then return new; end if;
  agency := btrim(coalesce(metadata->>'agency_name',''));
  contact := btrim(coalesce(metadata->>'contact_person',''));
  mobile_value := btrim(coalesce(metadata->>'mobile',''));
  if agency='' or length(agency)>240 then raise exception 'A valid agency name is required'; end if;
  if contact='' or length(contact)>160 then raise exception 'A valid contact person is required'; end if;
  if mobile_value !~ '^[6-9][0-9]{9}$' then raise exception 'A valid Indian mobile number is required'; end if;
  if btrim(coalesce(metadata->>'city',''))='' or btrim(coalesce(metadata->>'state',''))='' then raise exception 'City and state are required'; end if;
  if coalesce((metadata->>'consent')::boolean,false) is not true then raise exception 'Contractor onboarding consent is required'; end if;
  if nullif(metadata->>'workforce_capacity','') is not null then
    capacity := (metadata->>'workforce_capacity')::integer;
    if capacity < 0 or capacity > 1000000 then raise exception 'Workforce capacity is invalid'; end if;
  end if;
  if nullif(btrim(coalesce(metadata->>'gstin','')),'') is not null
     and upper(btrim(metadata->>'gstin')) !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then raise exception 'GSTIN format is invalid'; end if;
  if nullif(btrim(coalesce(metadata->>'pincode','')),'') is not null
     and btrim(metadata->>'pincode') !~ '^[0-9]{6}$' then raise exception 'Pincode is invalid'; end if;
  if exists(select 1 from public.platform_users where user_id=new.id)
     or exists(select 1 from public.contractor_users where user_id=new.id) then raise exception 'An account profile already exists for this user'; end if;
  select coalesce(array_agg(btrim(value)) filter(where btrim(value)<>''),array[]::text[])
    into locations from jsonb_array_elements_text(coalesce(metadata->'operating_locations','[]'::jsonb));
  select coalesce(array_agg(btrim(value)) filter(where btrim(value)<>''),array[]::text[])
    into categories from jsonb_array_elements_text(coalesce(metadata->'manpower_categories','[]'::jsonb));

  insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status)
  values(new.id,'contractor',contact,mobile_value,new.email,'pending');
  insert into public.contractors(agency_name,owner_name,gstin,esic_code,epfo_code,labour_license_number,
    main_phone,main_email,address,city,district,state,operating_locations,workforce_capacity,
    website,pincode,manpower_categories,onboarding_notes,onboarding_consent_at,verification_status,account_status)
  values(agency,contact,nullif(upper(btrim(coalesce(metadata->>'gstin',''))),''),nullif(btrim(coalesce(metadata->>'esic_code','')),''),
    nullif(btrim(coalesce(metadata->>'epfo_code','')),''),nullif(btrim(coalesce(metadata->>'labour_license_number','')),''),
    mobile_value,new.email,nullif(btrim(coalesce(metadata->>'address','')),''),btrim(metadata->>'city'),
    nullif(btrim(coalesce(metadata->>'district','')),''),btrim(metadata->>'state'),locations,capacity,
    nullif(btrim(coalesce(metadata->>'website','')),''),nullif(btrim(coalesce(metadata->>'pincode','')),''),categories,
    nullif(btrim(coalesce(metadata->>'notes','')),''),now(),'pending','pending') returning id into contractor_id_value;
  insert into public.contractor_users(contractor_id,user_id,role,status)
  values(contractor_id_value,new.id,'owner','pending');
  return new;
end;
$$;
revoke all on function private.handle_contractor_signup() from public,anon,authenticated;
create trigger on_auth_user_created_contractor_onboarding after insert on auth.users
for each row execute function private.handle_contractor_signup();

create or replace function private.current_active_contractor_id()
returns uuid language plpgsql stable security definer set search_path=''
as $$
declare result uuid; matches integer;
begin
  if (select auth.uid()) is null then return null; end if;
  select min(cu.contractor_id::text)::uuid,count(*)::integer into result,matches
  from public.contractor_users cu join public.platform_users pu on pu.user_id=cu.user_id
  join public.contractors c on c.id=cu.contractor_id
  where cu.user_id=(select auth.uid()) and pu.account_type='contractor'
    and pu.account_status='active' and cu.status='active' and c.account_status='active';
  if matches=0 then return null; end if;
  if matches<>1 then raise exception 'Exactly one active contractor membership is required'; end if;
  return result;
end;
$$;
revoke all on function private.current_active_contractor_id() from public,anon;
grant execute on function private.current_active_contractor_id() to authenticated;

create or replace function public.set_contractor_account_status(p_contractor_id uuid,p_account_status text)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if (select auth.uid()) is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_account_status not in ('pending','active','suspended','rejected') then raise exception 'Invalid contractor account status'; end if;
  update public.contractors set account_status=p_account_status,
    verification_status=case when p_account_status='active' then 'verified' when p_account_status='rejected' then 'rejected' else verification_status end
  where id=p_contractor_id;
  if not found then raise exception 'Contractor account was not found'; end if;
  update public.platform_users pu set account_status=p_account_status where pu.account_type='contractor'
    and exists(select 1 from public.contractor_users cu where cu.contractor_id=p_contractor_id and cu.user_id=pu.user_id);
  if not found then raise exception 'Contractor has no linked platform user'; end if;
  update public.contractor_users set status=case when p_account_status='active' then 'active' when p_account_status='pending' then 'pending' else 'suspended' end
  where contractor_id=p_contractor_id;
end;
$$;

create or replace function public.assign_requirement_contractor(p_requirement_id uuid,p_contractor_id uuid,p_assigned_headcount integer,p_internal_notes text default null)
returns public.requirement_contractors language plpgsql security definer set search_path=''
as $$
declare req public.employer_requirements%rowtype; allocated integer; result public.requirement_contractors%rowtype;
begin
  if (select auth.uid()) is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_assigned_headcount is null or p_assigned_headcount<=0 then raise exception 'Assigned headcount must be greater than zero'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_requirement_id::text,0));
  select * into req from public.employer_requirements where id=p_requirement_id for update;
  if req.id is null or req.company_id is null then raise exception 'Company requirement was not found'; end if;
  if req.requirement_stage<>'open' then raise exception 'Only open requirements can be assigned'; end if;
  if not exists(select 1 from public.contractors c where c.id=p_contractor_id and c.account_status='active'
    and exists(select 1 from public.contractor_users cu join public.platform_users pu on pu.user_id=cu.user_id
      where cu.contractor_id=c.id and cu.status='active' and pu.account_type='contractor' and pu.account_status='active')) then
    raise exception 'An active contractor account and membership are required';
  end if;
  select coalesce(sum(assigned_headcount),0)::integer into allocated from public.requirement_contractors
    where requirement_id=p_requirement_id and assignment_status in ('assigned','accepted','active');
  if p_assigned_headcount > req.required_headcount-req.filled_positions-allocated then raise exception 'Assignment exceeds remaining allocatable headcount'; end if;
  insert into public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,assignment_status,assigned_by,internal_notes)
  values(p_requirement_id,p_contractor_id,p_assigned_headcount,'assigned',(select auth.uid()),nullif(btrim(coalesce(p_internal_notes,'')),''))
  returning * into result;
  return result;
exception when unique_violation then raise exception 'This contractor already has assignment history for the requirement';
end;
$$;

create or replace function public.respond_requirement_assignment(p_assignment_id uuid,p_response text,p_reason text default null)
returns public.requirement_contractors language plpgsql security definer set search_path=''
as $$
declare contractor_id_value uuid; result public.requirement_contractors%rowtype;
begin
  contractor_id_value:=private.current_active_contractor_id();
  if contractor_id_value is null then raise exception 'An active contractor account and membership are required'; end if;
  if p_response not in ('accepted','declined') then raise exception 'Response must be accepted or declined'; end if;
  update public.requirement_contractors set assignment_status=p_response,
    accepted_at=case when p_response='accepted' then now() else null end,
    declined_at=case when p_response='declined' then now() else null end,
    response_notes=nullif(btrim(coalesce(p_reason,'')),'')
  where id=p_assignment_id and contractor_id=contractor_id_value and assignment_status='assigned'
  returning * into result;
  if result.id is null then raise exception 'Assignment was not found or cannot receive this response'; end if;
  return result;
end;
$$;

create or replace function public.set_requirement_assignment_status(p_assignment_id uuid,p_assignment_status text)
returns public.requirement_contractors language plpgsql security definer set search_path=''
as $$
declare result public.requirement_contractors%rowtype;
begin
  if (select auth.uid()) is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_assignment_status not in ('active','completed','cancelled') then raise exception 'Invalid admin assignment status'; end if;
  update public.requirement_contractors set assignment_status=p_assignment_status,
    closed_at=case when p_assignment_status in ('completed','cancelled') then now() else null end
  where id=p_assignment_id and (
    (p_assignment_status='active' and assignment_status='accepted')
    or (p_assignment_status='completed' and assignment_status='active')
    or (p_assignment_status='cancelled' and assignment_status in ('assigned','accepted','active')))
  returning * into result;
  if result.id is null then raise exception 'Assignment was not found or transition is invalid'; end if;
  return result;
end;
$$;

revoke all on function public.set_contractor_account_status(uuid,text) from public,anon;
revoke all on function public.assign_requirement_contractor(uuid,uuid,integer,text) from public,anon;
revoke all on function public.respond_requirement_assignment(uuid,text,text) from public,anon;
revoke all on function public.set_requirement_assignment_status(uuid,text) from public,anon;
grant execute on function public.set_contractor_account_status(uuid,text) to authenticated;
grant execute on function public.assign_requirement_contractor(uuid,uuid,integer,text) to authenticated;
grant execute on function public.respond_requirement_assignment(uuid,text,text) to authenticated;
grant execute on function public.set_requirement_assignment_status(uuid,text) to authenticated;

create policy "M8C contractor reads own platform account" on public.platform_users for select to authenticated
using(user_id=(select auth.uid()) and account_type='contractor');
create policy "M8C contractor reads own memberships" on public.contractor_users for select to authenticated
using(user_id=(select auth.uid()) and exists(select 1 from public.platform_users pu where pu.user_id=(select auth.uid()) and pu.account_type='contractor'));
create policy "M8C active contractor reads own profile" on public.contractors for select to authenticated
using(id=(select private.current_active_contractor_id()));
create policy "M8C active contractor reads own assignments" on public.requirement_contractors for select to authenticated
using(contractor_id=(select private.current_active_contractor_id()));
create policy "M8C active contractor reads assigned requirements" on public.employer_requirements for select to authenticated
using(exists(select 1 from public.requirement_contractors rc where rc.requirement_id=employer_requirements.id
  and rc.contractor_id=(select private.current_active_contractor_id())));

-- Contractor writes remain RPC-only. M7 admin policies remain unchanged.
-- Public requirement visibility never grants contractor operational access.

commit;
