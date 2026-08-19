-- Run only against isolated disposable Supabase with migrations through 017.
-- All identities, staff changes, and audit rows roll back.

\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('81000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-bootstrap@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-super-a@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-super-b@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-admin@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-recruiter@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-operations@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-viewer@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-inactive@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-revoked@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-nonmember@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-company@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-contractor@test.local','x','{}','{}',now(),now()),
('81000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2-new-staff@test.local','x','{}','{}',now(),now());

insert into public.admin_users(user_id) values('81000000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values
('81000000-0000-0000-0000-000000000002','W2 Super A','active'),
('81000000-0000-0000-0000-000000000003','W2 Super B','inactive'),
('81000000-0000-0000-0000-000000000004','W2 Admin','active'),
('81000000-0000-0000-0000-000000000005','W2 Recruiter','active'),
('81000000-0000-0000-0000-000000000006','W2 Operations','active'),
('81000000-0000-0000-0000-000000000007','W2 Viewer','active'),
('81000000-0000-0000-0000-000000000008','W2 Inactive','suspended'),
('81000000-0000-0000-0000-000000000009','W2 Revoked','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('81000000-0000-0000-0000-000000000002','super_admin','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000002','viewer','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000003','super_admin','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000004','admin','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000005','recruiter','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000006','operations','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000007','viewer','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000008','viewer','active','81000000-0000-0000-0000-000000000001'),
('81000000-0000-0000-0000-000000000009','viewer','revoked','81000000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('81000000-0000-0000-0000-000000000011','company','W2 Company','w2-company@test.local','active'),
('81000000-0000-0000-0000-000000000012','contractor','W2 Contractor','w2-contractor@test.local','active');

do $$
begin
  perform set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',true);
  if not private.has_staff_role('super_admin') or not private.has_staff_role('viewer') then
    raise exception 'Matching or multiple active role membership failed';
  end if;
  if private.has_staff_role('admin') then raise exception 'Different role matched'; end if;

  perform set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000009',true);
  if private.has_staff_role('viewer') then raise exception 'Revoked role matched'; end if;

  perform set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000008',true);
  if private.has_staff_role('viewer') then raise exception 'Suspended profile role matched'; end if;

  perform set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000010',true);
  if private.has_staff_role('viewer') then raise exception 'Identity without staff profile matched'; end if;

  perform set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000011',true);
  if private.has_staff_role('viewer') then raise exception 'Tenant identity role matched'; end if;

  perform set_config('request.jwt.claim.sub','',true);
  if private.has_staff_role('viewer') then raise exception 'Anonymous role matched'; end if;
end;
$$;

do $$
begin
  if has_table_privilege('authenticated','public.staff_profiles','SELECT')
     or has_table_privilege('authenticated','public.staff_profiles','INSERT')
     or has_table_privilege('authenticated','public.staff_profiles','UPDATE')
     or has_table_privilege('authenticated','public.staff_roles','SELECT')
     or has_table_privilege('authenticated','public.staff_roles','INSERT')
     or has_table_privilege('authenticated','public.staff_roles','UPDATE') then
    raise exception 'Authenticated retains direct staff-table privileges';
  end if;
  if has_table_privilege('authenticated','public.audit_logs','INSERT')
     or has_table_privilege('anon','public.audit_logs','INSERT') then
    raise exception 'Browser role can forge audit rows';
  end if;
  if has_function_privilege('anon','public.get_current_staff_session()','EXECUTE')
     or has_function_privilege('anon','public.list_internal_staff()','EXECUTE')
     or has_function_privilege('anon','public.grant_staff_role(uuid,text,uuid)','EXECUTE') then
    raise exception 'Anonymous can execute W2 staff RPCs';
  end if;
  if (
    select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('get_current_staff_session','list_internal_staff','create_internal_staff','update_internal_staff_profile','set_staff_active_state','grant_staff_role','revoke_staff_role')
      and p.prosecdef
      and exists (
        select 1 from unnest(p.proconfig) config
        where split_part(config,'=',1)='search_path' and btrim(split_part(config,'=',2),'"')=''
      )
  ) <> 7 then raise exception 'W2 RPC security configuration is invalid'; end if;
  if has_function_privilege('authenticated','private.current_staff_profile_id()','EXECUTE')
     or has_function_privilege('authenticated','private.can_manage_staff()','EXECUTE') then
    raise exception 'Authenticated can execute private W2 helpers';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000005',true);
do $$
begin
  begin
    update public.staff_profiles set display_name='Forged' where user_id='81000000-0000-0000-0000-000000000005';
    raise exception 'Direct staff profile write succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.staff_roles(user_id,role,status)
    values('81000000-0000-0000-0000-000000000005','viewer','active');
    raise exception 'Direct staff role insert succeeded';
  exception when insufficient_privilege then null; end;
  begin
    update public.staff_roles set status='revoked'
    where user_id='81000000-0000-0000-0000-000000000005' and role='recruiter';
    raise exception 'Direct staff role update succeeded';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.staff_roles
    where user_id='81000000-0000-0000-0000-000000000005' and role='recruiter';
    raise exception 'Direct staff role delete succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source)
    values('81000000-0000-0000-0000-000000000005','staff','forged','staff_profile','admin');
    raise exception 'Direct audit write succeeded';
  exception when insufficient_privilege then null; end;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
do $$ declare session_record record; created_id uuid; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized or not session_record.bootstrap_admin
     or not session_record.admin_shell_access or not session_record.staff_management_access
     or session_record.staff_profile_id is not null then
    raise exception 'Bootstrap Admin compatibility failed';
  end if;
  created_id := public.create_internal_staff('w2-new-staff@test.local','W2 New Staff',null);
  if created_id <> '81000000-0000-0000-0000-000000000013' then raise exception 'Staff bootstrap creation failed'; end if;
  perform public.grant_staff_role(created_id,'viewer',null);
  perform public.update_internal_staff_profile(created_id,'W2 New Staff Updated',null);
  perform public.set_staff_active_state(created_id,'inactive',null);
  perform public.set_staff_active_state(created_id,'active',null);
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000002',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized or session_record.bootstrap_admin
     or not session_record.staff_management_access or session_record.roles <> array['super_admin','viewer']::text[] then
    raise exception 'Super Admin authorization failed';
  end if;
  if (select count(*) from public.list_internal_staff()) <> 9 then raise exception 'Super Admin staff listing failed'; end if;
  begin perform public.revoke_staff_role('81000000-0000-0000-0000-000000000002','super_admin',null); raise exception 'Final Super Admin removal succeeded';
  exception when raise_exception then if sqlerrm='Final Super Admin removal succeeded' then raise; end if; end;
  begin perform public.set_staff_active_state('81000000-0000-0000-0000-000000000002','suspended',null); raise exception 'Final Super Admin suspension succeeded';
  exception when raise_exception then if sqlerrm='Final Super Admin suspension succeeded' then raise; end if; end;
  begin perform public.set_staff_active_state('81000000-0000-0000-0000-000000000002','inactive',null); raise exception 'Final Super Admin deactivation succeeded';
  exception when raise_exception then if sqlerrm='Final Super Admin deactivation succeeded' then raise; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000004',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized or not session_record.staff_management_access
     or session_record.roles <> array['admin']::text[] then raise exception 'Admin authorization failed'; end if;
  perform public.grant_staff_role('81000000-0000-0000-0000-000000000009','viewer',null);
  begin perform public.grant_staff_role('81000000-0000-0000-0000-000000000009','admin',null); raise exception 'Admin granted elevated role';
  exception when raise_exception then if sqlerrm='Admin granted elevated role' then raise; end if; end;
  begin perform public.revoke_staff_role('81000000-0000-0000-0000-000000000002','super_admin',null); raise exception 'Admin revoked elevated role';
  exception when raise_exception then if sqlerrm='Admin revoked elevated role' then raise; end if; end;
  begin perform public.set_staff_active_state('81000000-0000-0000-0000-000000000002','inactive',null); raise exception 'Admin disabled elevated staff';
  exception when raise_exception then if sqlerrm='Admin disabled elevated staff' then raise; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000005',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized or session_record.staff_management_access or session_record.roles <> array['recruiter']::text[] then raise exception 'Recruiter authorization failed'; end if;
  begin perform public.list_internal_staff(); raise exception 'Recruiter listed staff'; exception when raise_exception then if sqlerrm='Recruiter listed staff' then raise; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000006',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized or session_record.staff_management_access or session_record.roles <> array['operations']::text[] then raise exception 'Operations authorization failed'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000007',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized or session_record.staff_management_access or session_record.roles <> array['viewer']::text[] then raise exception 'Viewer authorization failed'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000008',true);
do $$ declare session_record record; begin select * into session_record from public.get_current_staff_session(); if session_record.authorized then raise exception 'Inactive staff acquired access'; end if; end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000010',true);
do $$ declare session_record record; begin select * into session_record from public.get_current_staff_session(); if session_record.authorized then raise exception 'Non-member acquired access'; end if; end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000011',true);
do $$ declare session_record record; begin select * into session_record from public.get_current_staff_session(); if session_record.authorized then raise exception 'Company user acquired internal staff access'; end if; end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000012',true);
do $$ declare session_record record; begin select * into session_record from public.get_current_staff_session(); if session_record.authorized then raise exception 'Contractor user acquired internal staff access'; end if; end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000009',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if not session_record.authorized then raise exception 'Granted role did not authorize immediately'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000004',true);
select public.revoke_staff_role('81000000-0000-0000-0000-000000000009','viewer',null);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000009',true);
do $$ declare session_record record; begin
  select * into session_record from public.get_current_staff_session();
  if session_record.authorized then raise exception 'Revoked role retained access'; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','81000000-0000-0000-0000-000000000001',true);
select public.set_staff_active_state('81000000-0000-0000-0000-000000000003','active',null);
select public.revoke_staff_role('81000000-0000-0000-0000-000000000002','super_admin',null);
reset role;
do $$ begin
  if not exists(select 1 from public.staff_roles where user_id='81000000-0000-0000-0000-000000000002' and role='super_admin' and status='revoked') then
    raise exception 'Super Admin revocation with a replacement failed';
  end if;
end $$;

do $$
begin
  if not exists(select 1 from public.audit_logs where actor_user_id='81000000-0000-0000-0000-000000000001' and action='internal_staff.profile_created' and entity_type='staff_profile' and entity_id='81000000-0000-0000-0000-000000000013' and source='admin') then raise exception 'Profile creation audit missing'; end if;
  if not exists(select 1 from public.audit_logs where actor_user_id='81000000-0000-0000-0000-000000000001' and action='internal_staff.profile_updated' and entity_type='staff_profile' and entity_id='81000000-0000-0000-0000-000000000013' and source='admin') then raise exception 'Profile update audit missing'; end if;
  if not exists(select 1 from public.audit_logs where actor_user_id='81000000-0000-0000-0000-000000000001' and action='internal_staff.status_changed' and entity_type='staff_profile' and entity_id='81000000-0000-0000-0000-000000000013' and source='admin') then raise exception 'Profile status audit missing'; end if;
  if not exists(select 1 from public.audit_logs where actor_user_id='81000000-0000-0000-0000-000000000001' and action='internal_staff.role_granted' and entity_type='staff_profile' and entity_id='81000000-0000-0000-0000-000000000013' and source='admin' and metadata->>'role'='viewer') then raise exception 'Role grant audit missing'; end if;
  if not exists(select 1 from public.audit_logs where actor_user_id='81000000-0000-0000-0000-000000000004' and action='internal_staff.role_revoked' and entity_type='staff_profile' and entity_id='81000000-0000-0000-0000-000000000009' and source='admin' and metadata->>'role'='viewer') then raise exception 'Role revocation audit missing'; end if;
  if exists(select 1 from public.staff_profiles sp join public.platform_users pu on pu.user_id=sp.user_id) then raise exception 'Tenant identity became internal staff'; end if;
  if exists(select 1 from pg_policies where schemaname='public' and tablename in ('staff_profiles','staff_roles')) then raise exception 'Direct staff-table policy remains'; end if;
  if exists(select 1 from pg_policies where schemaname='public' and policyname in ('M8B active company reads own requirements','M8C active contractor reads assigned requirements','M8C active contractor reads own assignments')) then raise exception 'Migration 015 tenant boundary regressed'; end if;
end;
$$;

rollback;
\echo 'W2 INTERNAL STAFF AUTHORIZATION TESTS PASSED'
