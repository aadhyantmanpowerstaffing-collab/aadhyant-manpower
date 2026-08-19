-- W2: internal staff authentication, role authorization, and audited management.

begin;

do $$
begin
  if to_regclass('public.admin_users') is null
     or to_regclass('public.platform_users') is null
     or to_regclass('public.staff_profiles') is null
     or to_regclass('public.staff_roles') is null
     or to_regclass('public.audit_logs') is null then
    raise exception 'W2 prerequisite identity tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('public.get_company_requirements()') is null
     or to_regprocedure('public.get_staffing_partner_assignments()') is null then
    raise exception 'W2 prerequisite authorization or migration 015 functions are missing';
  end if;
  if to_regprocedure('public.get_current_staff_session()') is not null
     or to_regprocedure('public.list_internal_staff()') is not null
     or to_regprocedure('public.create_internal_staff(text,text,uuid)') is not null
     or to_regprocedure('public.update_internal_staff_profile(uuid,text,uuid)') is not null
     or to_regprocedure('public.set_staff_active_state(uuid,text,uuid)') is not null
     or to_regprocedure('public.grant_staff_role(uuid,text,uuid)') is not null
     or to_regprocedure('public.revoke_staff_role(uuid,text,uuid)') is not null then
    raise exception 'W2 objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

create function private.current_staff_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select sp.user_id
  from public.staff_profiles sp
  where sp.user_id = (select auth.uid())
    and sp.status = 'active'
    and not exists (
      select 1 from public.platform_users pu where pu.user_id = sp.user_id
    )
    and exists (
      select 1 from public.staff_roles sr
      where sr.user_id = sp.user_id and sr.status = 'active'
    );
$$;

create function private.current_staff_roles()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(sr.role order by sr.role), array[]::text[])
  from public.staff_roles sr
  where sr.user_id = (select private.current_staff_profile_id())
    and sr.status = 'active';
$$;

create function private.has_staff_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_role = any((select private.current_staff_roles())), false);
$$;

create function private.can_access_admin_shell()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ((select private.is_admin()) and not exists (
        select 1 from public.platform_users pu where pu.user_id = (select auth.uid())
      ))
      or (select private.current_staff_profile_id()) is not null;
$$;

create function private.can_manage_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ((select private.is_admin()) and not exists (
        select 1 from public.platform_users pu where pu.user_id = (select auth.uid())
      ))
      or (select private.has_staff_role('super_admin'))
      or (select private.has_staff_role('admin'));
$$;

create function private.can_manage_elevated_roles()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ((select private.is_admin()) and not exists (
        select 1 from public.platform_users pu where pu.user_id = (select auth.uid())
      ))
      or (select private.has_staff_role('super_admin'));
$$;

revoke all on function private.current_staff_profile_id() from public, anon, authenticated;
revoke all on function private.current_staff_roles() from public, anon, authenticated;
revoke all on function private.has_staff_role(text) from public, anon, authenticated;
revoke all on function private.can_access_admin_shell() from public, anon, authenticated;
revoke all on function private.can_manage_staff() from public, anon, authenticated;
revoke all on function private.can_manage_elevated_roles() from public, anon, authenticated;

create function public.get_current_staff_session()
returns table (
  authorized boolean,
  bootstrap_admin boolean,
  staff_profile_id uuid,
  display_name text,
  active boolean,
  roles text[],
  admin_shell_access boolean,
  staff_management_access boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  bootstrap boolean;
  profile public.staff_profiles%rowtype;
  active_roles text[] := array[]::text[];
  shell_access boolean;
  management_access boolean;
begin
  if caller_id is null then
    raise exception 'Authenticated staff access is required';
  end if;

  bootstrap := (select private.is_admin()) and not exists (
    select 1 from public.platform_users pu where pu.user_id = caller_id
  );
  select sp.* into profile from public.staff_profiles sp where sp.user_id = caller_id;
  if profile.user_id is not null and profile.status = 'active'
     and not exists (select 1 from public.platform_users pu where pu.user_id = caller_id) then
    select coalesce(array_agg(sr.role order by sr.role), array[]::text[])
    into active_roles
    from public.staff_roles sr
    where sr.user_id = caller_id and sr.status = 'active';
  end if;

  shell_access := bootstrap or (
    profile.user_id is not null and profile.status = 'active'
    and cardinality(active_roles) > 0
    and not exists (select 1 from public.platform_users pu where pu.user_id = caller_id)
  );
  management_access := bootstrap
    or ('super_admin' = any(active_roles))
    or ('admin' = any(active_roles));

  return query select
    shell_access,
    bootstrap,
    profile.user_id,
    profile.display_name,
    coalesce(profile.status = 'active', false),
    active_roles,
    shell_access,
    shell_access and management_access;
end;
$$;

create function public.list_internal_staff()
returns table (
  user_id uuid,
  display_name text,
  email text,
  status text,
  roles text[],
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not (select private.can_manage_staff()) then
    raise exception 'Staff management access is required';
  end if;
  return query
  select
    sp.user_id,
    sp.display_name,
    au.email::text,
    sp.status,
    coalesce(array_agg(sr.role order by sr.role) filter (where sr.status = 'active'), array[]::text[]),
    sp.created_at,
    sp.updated_at
  from public.staff_profiles sp
  join auth.users au on au.id = sp.user_id
  left join public.staff_roles sr on sr.user_id = sp.user_id
  group by sp.user_id, sp.display_name, au.email, sp.status, sp.created_at, sp.updated_at
  order by sp.display_name, sp.user_id;
end;
$$;

create function public.create_internal_staff(
  p_email text,
  p_display_name text,
  p_correlation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_id uuid;
  normalized_email text := lower(btrim(coalesce(p_email, '')));
  normalized_name text := btrim(coalesce(p_display_name, ''));
begin
  if actor_id is null or not (select private.can_manage_staff()) then
    raise exception 'Staff management access is required';
  end if;
  if normalized_email = '' or normalized_name = '' or length(normalized_name) > 160 then
    raise exception 'A valid staff email and display name are required';
  end if;
  select au.id into target_id from auth.users au where lower(au.email) = normalized_email;
  if target_id is null then raise exception 'An existing Auth user is required'; end if;
  if exists (select 1 from public.platform_users pu where pu.user_id = target_id) then
    raise exception 'Tenant identities cannot become internal staff';
  end if;
  if exists (select 1 from public.staff_profiles sp where sp.user_id = target_id) then
    raise exception 'A staff profile already exists';
  end if;

  insert into public.staff_profiles(user_id, display_name, status)
  values(target_id, normalized_name, 'active');
  insert into public.audit_logs(actor_user_id, actor_type, action, entity_type, entity_id, source, correlation_id, metadata)
  values(actor_id, 'staff', 'internal_staff.profile_created', 'staff_profile', target_id, 'admin', p_correlation_id,
    jsonb_build_object('initial_status', 'active'));
  return target_id;
end;
$$;

create function public.update_internal_staff_profile(
  p_user_id uuid,
  p_display_name text,
  p_correlation_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_name text := btrim(coalesce(p_display_name, ''));
begin
  if actor_id is null or not (select private.can_manage_staff()) then
    raise exception 'Staff management access is required';
  end if;
  if p_user_id is null or normalized_name = '' or length(normalized_name) > 160 then
    raise exception 'A valid staff profile and display name are required';
  end if;
  if exists (
    select 1 from public.staff_roles sr
    where sr.user_id = p_user_id and sr.status = 'active' and sr.role in ('super_admin', 'admin')
  ) and not (select private.can_manage_elevated_roles()) then
    raise exception 'Elevated staff management access is required';
  end if;
  update public.staff_profiles set display_name = normalized_name where user_id = p_user_id;
  if not found then raise exception 'Staff profile was not found'; end if;
  insert into public.audit_logs(actor_user_id, actor_type, action, entity_type, entity_id, source, correlation_id, metadata)
  values(actor_id, 'staff', 'internal_staff.profile_updated', 'staff_profile', p_user_id, 'admin', p_correlation_id,
    jsonb_build_object('display_name_changed', true));
  return true;
end;
$$;

create function public.set_staff_active_state(
  p_user_id uuid,
  p_status text,
  p_correlation_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_status text := lower(btrim(coalesce(p_status, '')));
  previous_status text;
  target_is_elevated boolean;
  target_is_active_super boolean;
  other_active_supers integer;
begin
  if actor_id is null or not (select private.can_manage_staff()) then
    raise exception 'Staff management access is required';
  end if;
  if normalized_status not in ('active', 'suspended', 'inactive') then
    raise exception 'Unsupported staff status';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('w2-super-admin-roster', 0));
  select sp.status into previous_status from public.staff_profiles sp where sp.user_id = p_user_id for update;
  if previous_status is null then raise exception 'Staff profile was not found'; end if;
  select exists(select 1 from public.staff_roles sr where sr.user_id=p_user_id and sr.status='active' and sr.role in ('super_admin','admin')),
         exists(select 1 from public.staff_roles sr where sr.user_id=p_user_id and sr.status='active' and sr.role='super_admin')
  into target_is_elevated, target_is_active_super;
  if target_is_elevated and not (select private.can_manage_elevated_roles()) then
    raise exception 'Elevated staff management access is required';
  end if;
  if previous_status = 'active' and normalized_status <> 'active' and target_is_active_super then
    select count(*)::integer into other_active_supers
    from public.staff_profiles sp join public.staff_roles sr on sr.user_id=sp.user_id
    where sp.status='active' and sr.status='active' and sr.role='super_admin' and sp.user_id<>p_user_id;
    if other_active_supers = 0 then raise exception 'The final active super administrator cannot be disabled'; end if;
  end if;
  if previous_status = normalized_status then return true; end if;
  update public.staff_profiles set status=normalized_status where user_id=p_user_id;
  insert into public.audit_logs(actor_user_id, actor_type, action, entity_type, entity_id, source, correlation_id, metadata)
  values(actor_id, 'staff', 'internal_staff.status_changed', 'staff_profile', p_user_id, 'admin', p_correlation_id,
    jsonb_build_object('from_status', previous_status, 'to_status', normalized_status));
  return true;
end;
$$;

create function public.grant_staff_role(
  p_user_id uuid,
  p_role text,
  p_correlation_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_role text := lower(btrim(coalesce(p_role, '')));
begin
  if actor_id is null or not (select private.can_manage_staff()) then
    raise exception 'Staff management access is required';
  end if;
  if normalized_role not in ('super_admin','admin','recruiter','operations','viewer') then
    raise exception 'Unsupported staff role';
  end if;
  if normalized_role in ('super_admin','admin') and not (select private.can_manage_elevated_roles()) then
    raise exception 'Elevated role management access is required';
  end if;
  if not exists(select 1 from public.staff_profiles sp where sp.user_id=p_user_id) then
    raise exception 'Staff profile was not found';
  end if;
  if exists(select 1 from public.platform_users pu where pu.user_id=p_user_id) then
    raise exception 'Tenant identities cannot become internal staff';
  end if;
  insert into public.staff_roles(user_id, role, status, granted_by)
  values(p_user_id, normalized_role, 'active', actor_id)
  on conflict(user_id, role) do update set status='active', granted_by=excluded.granted_by;
  insert into public.audit_logs(actor_user_id, actor_type, action, entity_type, entity_id, source, correlation_id, metadata)
  values(actor_id, 'staff', 'internal_staff.role_granted', 'staff_profile', p_user_id, 'admin', p_correlation_id,
    jsonb_build_object('role', normalized_role));
  return true;
end;
$$;

create function public.revoke_staff_role(
  p_user_id uuid,
  p_role text,
  p_correlation_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  normalized_role text := lower(btrim(coalesce(p_role, '')));
  other_active_supers integer;
begin
  if actor_id is null or not (select private.can_manage_staff()) then
    raise exception 'Staff management access is required';
  end if;
  if normalized_role not in ('super_admin','admin','recruiter','operations','viewer') then
    raise exception 'Unsupported staff role';
  end if;
  if normalized_role in ('super_admin','admin') and not (select private.can_manage_elevated_roles()) then
    raise exception 'Elevated role management access is required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('w2-super-admin-roster', 0));
  if normalized_role='super_admin' and exists(
    select 1 from public.staff_profiles sp join public.staff_roles sr on sr.user_id=sp.user_id
    where sp.user_id=p_user_id and sp.status='active' and sr.role='super_admin' and sr.status='active'
  ) then
    select count(*)::integer into other_active_supers
    from public.staff_profiles sp join public.staff_roles sr on sr.user_id=sp.user_id
    where sp.status='active' and sr.status='active' and sr.role='super_admin' and sp.user_id<>p_user_id;
    if other_active_supers=0 then raise exception 'The final active super administrator role cannot be revoked'; end if;
  end if;
  update public.staff_roles set status='revoked' where user_id=p_user_id and role=normalized_role and status='active';
  if not found then raise exception 'Active staff role was not found'; end if;
  insert into public.audit_logs(actor_user_id, actor_type, action, entity_type, entity_id, source, correlation_id, metadata)
  values(actor_id, 'staff', 'internal_staff.role_revoked', 'staff_profile', p_user_id, 'admin', p_correlation_id,
    jsonb_build_object('role', normalized_role));
  return true;
end;
$$;

revoke all on function public.get_current_staff_session() from public, anon;
revoke all on function public.list_internal_staff() from public, anon;
revoke all on function public.create_internal_staff(text,text,uuid) from public, anon;
revoke all on function public.update_internal_staff_profile(uuid,text,uuid) from public, anon;
revoke all on function public.set_staff_active_state(uuid,text,uuid) from public, anon;
revoke all on function public.grant_staff_role(uuid,text,uuid) from public, anon;
revoke all on function public.revoke_staff_role(uuid,text,uuid) from public, anon;
grant execute on function public.get_current_staff_session() to authenticated;
grant execute on function public.list_internal_staff() to authenticated;
grant execute on function public.create_internal_staff(text,text,uuid) to authenticated;
grant execute on function public.update_internal_staff_profile(uuid,text,uuid) to authenticated;
grant execute on function public.set_staff_active_state(uuid,text,uuid) to authenticated;
grant execute on function public.grant_staff_role(uuid,text,uuid) to authenticated;
grant execute on function public.revoke_staff_role(uuid,text,uuid) to authenticated;

revoke all on public.staff_profiles from public, anon, authenticated;
revoke all on public.staff_roles from public, anon, authenticated;

drop policy "W1 admins read staff profiles" on public.staff_profiles;
drop policy "W1 admins create staff profiles" on public.staff_profiles;
drop policy "W1 admins update staff profiles" on public.staff_profiles;
drop policy "W1 admins read staff roles" on public.staff_roles;
drop policy "W1 admins create staff roles" on public.staff_roles;
drop policy "W1 admins update staff roles" on public.staff_roles;

commit;
