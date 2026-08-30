-- Batch D: remove legacy browser direct-write paths after canonical RPC hardening.

begin;

do $$
declare
  authenticated_oid oid := (select oid from pg_roles where rolname='authenticated');
  application_columns text[];
  signature text;
begin
  if authenticated_oid is null or not exists(select 1 from pg_roles where rolname='anon') then
    raise exception 'Batch D direct-write preflight failed: browser roles are missing';
  end if;

  if to_regclass('public.candidate_applications') is null
     or to_regclass('public.candidate_joinings') is null then
    raise exception 'Batch D direct-write preflight failed: target tables are missing';
  end if;
  if exists(
    select 1 from pg_class
    where oid in ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass)
      and not relrowsecurity
  ) then
    raise exception 'Batch D direct-write preflight failed: target table RLS is disabled';
  end if;

  foreach signature in array array[
    'public.create_recruitment_joining(uuid,date,text,text,uuid)',
    'public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid)',
    'public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid)',
    'public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)'
  ] loop
    if to_regprocedure(signature) is null then
      raise exception 'Batch D direct-write preflight failed: canonical RPC % is missing',signature;
    end if;
    if not exists(
      select 1 from pg_proc p
      where p.oid=to_regprocedure(signature)
        and p.prosecdef
        and exists(
          select 1 from unnest(coalesce(p.proconfig,'{}'::text[])) config
          where split_part(config,'=',1)='search_path'
            and btrim(split_part(config,'=',2),'"')=''
        )
    ) then
      raise exception 'Batch D direct-write preflight failed: canonical RPC % security configuration drifted',signature;
    end if;
    if not has_function_privilege('authenticated',signature,'execute')
       or has_function_privilege('anon',signature,'execute')
       or exists(
         select 1
         from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
         where p.oid=to_regprocedure(signature) and acl.grantee=0 and acl.privilege_type='EXECUTE'
       ) then
      raise exception 'Batch D direct-write preflight failed: canonical RPC % grant drifted',signature;
    end if;
  end loop;

  if to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') is null
     or not has_function_privilege('authenticated','public.admin_update_candidate_application(uuid,text,text)','execute')
     or has_function_privilege('anon','public.admin_update_candidate_application(uuid,text,text)','execute') then
    raise exception 'Batch D direct-write preflight failed: legacy application RPC contract drifted';
  end if;

  if not has_table_privilege('authenticated','public.candidate_applications','select')
     or not has_table_privilege('authenticated','public.candidate_applications','insert')
     or not has_table_privilege('authenticated','public.candidate_applications','update')
     or has_table_privilege('authenticated','public.candidate_applications','delete')
     or not has_table_privilege('authenticated','public.candidate_joinings','select')
     or not has_table_privilege('authenticated','public.candidate_joinings','insert')
     or not has_table_privilege('authenticated','public.candidate_joinings','update')
     or has_table_privilege('authenticated','public.candidate_joinings','delete') then
    raise exception 'Batch D direct-write preflight failed: authenticated target table privileges drifted';
  end if;

  select coalesce(array_agg(a.attname order by a.attname),'{}'::text[])
  into application_columns
  from pg_attribute a
  cross join lateral aclexplode(a.attacl) acl
  where a.attrelid='public.candidate_applications'::regclass
    and a.attnum>0 and not a.attisdropped
    and acl.grantee=authenticated_oid and acl.privilege_type='UPDATE';
  if application_columns<>array['correlation_id','source_reference']::text[] then
    raise exception 'Batch D direct-write preflight failed: application column UPDATE grants drifted: %',application_columns;
  end if;
  if exists(
    select 1 from pg_attribute a
    cross join lateral aclexplode(a.attacl) acl
    where a.attrelid='public.candidate_joinings'::regclass
      and a.attnum>0 and not a.attisdropped
      and acl.grantee=authenticated_oid and acl.privilege_type in ('INSERT','UPDATE','DELETE')
  ) then
    raise exception 'Batch D direct-write preflight failed: unexpected joining column privileges exist';
  end if;

  if has_table_privilege('anon','public.candidate_applications','insert,update,delete')
     or has_table_privilege('anon','public.candidate_joinings','insert,update,delete')
     or exists(
       select 1 from pg_class c
       cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
       where c.oid in ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass)
         and acl.grantee=0 and acl.privilege_type in ('INSERT','UPDATE','DELETE')
     ) then
    raise exception 'Batch D direct-write preflight failed: anonymous or PUBLIC target mutation privilege exists';
  end if;

  if (select count(*) from pg_policy where polrelid in
      ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass))<>6 then
    raise exception 'Batch D direct-write preflight failed: target policy count drifted';
  end if;
  if (select count(*) from pg_policy
      where polrelid='public.candidate_applications'::regclass
        and polname='M7 admins read applications' and polcmd='r' and polpermissive
        and polroles=array[authenticated_oid]
        and regexp_replace(lower(pg_get_expr(polqual,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin'
        and polwithcheck is null)<>1
     or (select count(*) from pg_policy
      where polrelid='public.candidate_applications'::regclass
        and polname='M7 admins create applications' and polcmd='a' and polpermissive
        and polroles=array[authenticated_oid] and polqual is null
        and regexp_replace(lower(pg_get_expr(polwithcheck,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin')<>1
     or (select count(*) from pg_policy
      where polrelid='public.candidate_applications'::regclass
        and polname='M7 admins update applications' and polcmd='w' and polpermissive
        and polroles=array[authenticated_oid]
        and regexp_replace(lower(pg_get_expr(polqual,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin'
        and regexp_replace(lower(pg_get_expr(polwithcheck,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin')<>1
     or (select count(*) from pg_policy
      where polrelid='public.candidate_joinings'::regclass
        and polname='M7 admins read joinings' and polcmd='r' and polpermissive
        and polroles=array[authenticated_oid]
        and regexp_replace(lower(pg_get_expr(polqual,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin'
        and polwithcheck is null)<>1
     or (select count(*) from pg_policy
      where polrelid='public.candidate_joinings'::regclass
        and polname='M7 admins create joinings' and polcmd='a' and polpermissive
        and polroles=array[authenticated_oid] and polqual is null
        and regexp_replace(lower(pg_get_expr(polwithcheck,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin')<>1
     or (select count(*) from pg_policy
      where polrelid='public.candidate_joinings'::regclass
        and polname='M7 admins update joinings' and polcmd='w' and polpermissive
        and polroles=array[authenticated_oid]
        and regexp_replace(lower(pg_get_expr(polqual,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin'
        and regexp_replace(lower(pg_get_expr(polwithcheck,polrelid)),'[()[:space:]]','','g')='selectprivate.is_adminasis_admin')<>1 then
    raise exception 'Batch D direct-write preflight failed: exact M7 policy contracts drifted';
  end if;

  if exists(
    select 1 from pg_policy
    where polrelid in ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass)
      and polcmd in ('a','w','d','*')
      and polname not in ('M7 admins create applications','M7 admins update applications',
                          'M7 admins create joinings','M7 admins update joinings')
  ) then
    raise exception 'Batch D direct-write preflight failed: unexpected target write policy exists';
  end if;

  if to_regprocedure('public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)') is null
     or not has_function_privilege('authenticated','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or has_function_privilege('anon','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or exists(
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       where p.oid='public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)'::regprocedure
         and acl.grantee=0 and acl.privilege_type='EXECUTE'
     ) then
    raise exception 'Batch D direct-write preflight failed: compatibility wrapper pre-state drifted';
  end if;
end;
$$;

revoke insert, update on table public.candidate_applications from authenticated;
revoke update(source_reference, correlation_id) on public.candidate_applications from authenticated;
revoke insert, update on table public.candidate_joinings from authenticated;

drop policy "M7 admins create applications" on public.candidate_applications;
drop policy "M7 admins update applications" on public.candidate_applications;
drop policy "M7 admins create joinings" on public.candidate_joinings;
drop policy "M7 admins update joinings" on public.candidate_joinings;

revoke execute on function public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid) from public, anon, authenticated;

do $$
declare
  signature text;
begin
  if not has_table_privilege('authenticated','public.candidate_applications','select')
     or has_table_privilege('authenticated','public.candidate_applications','insert,update,delete')
     or exists(
       select 1 from pg_attribute a
       where a.attrelid='public.candidate_applications'::regclass and a.attnum>0 and not a.attisdropped
         and has_column_privilege('authenticated','public.candidate_applications',a.attname,'update')
     )
     or has_column_privilege('authenticated','public.candidate_applications','source_reference','update')
     or has_column_privilege('authenticated','public.candidate_applications','correlation_id','update') then
    raise exception 'Batch D direct-write postcondition failed: application privilege boundary is invalid';
  end if;
  if not has_table_privilege('authenticated','public.candidate_joinings','select')
     or has_table_privilege('authenticated','public.candidate_joinings','insert,update,delete')
     or exists(
       select 1 from pg_attribute a
       where a.attrelid='public.candidate_joinings'::regclass and a.attnum>0 and not a.attisdropped
         and has_column_privilege('authenticated','public.candidate_joinings',a.attname,'update')
     ) then
    raise exception 'Batch D direct-write postcondition failed: joining privilege boundary is invalid';
  end if;

  if (select count(*) from pg_policy where polrelid in
      ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass))<>2
     or not exists(select 1 from pg_policy where polrelid='public.candidate_applications'::regclass
       and polname='M7 admins read applications' and polcmd='r')
     or not exists(select 1 from pg_policy where polrelid='public.candidate_joinings'::regclass
       and polname='M7 admins read joinings' and polcmd='r')
     or exists(select 1 from pg_policy where polrelid in
       ('public.candidate_applications'::regclass,'public.candidate_joinings'::regclass) and polcmd in ('a','w','d','*')) then
    raise exception 'Batch D direct-write postcondition failed: target policy boundary is invalid';
  end if;

  if to_regprocedure('public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)') is null
     or has_function_privilege('authenticated','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or has_function_privilege('anon','public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)','execute')
     or exists(
       select 1 from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
       where p.oid='public.upsert_recruitment_joining(uuid,date,date,text,text,text,uuid)'::regprocedure
         and acl.grantee=0 and acl.privilege_type='EXECUTE'
     ) then
    raise exception 'Batch D direct-write postcondition failed: compatibility wrapper boundary is invalid';
  end if;

  foreach signature in array array[
    'public.create_recruitment_joining(uuid,date,text,text,uuid)',
    'public.transition_recruitment_joining(uuid,text,timestamp with time zone,text,date,date,text,text,uuid)',
    'public.update_recruitment_joining_details(uuid,text,timestamp with time zone,date,text,text,uuid)',
    'public.correct_recruitment_joining(uuid,timestamp with time zone,text,date,date,text,text,text,uuid)',
    'public.admin_update_candidate_application(uuid,text,text)'
  ] loop
    if not has_function_privilege('authenticated',signature,'execute')
       or has_function_privilege('anon',signature,'execute')
       or exists(
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
         where p.oid=to_regprocedure(signature) and acl.grantee=0 and acl.privilege_type='EXECUTE'
       ) then
      raise exception 'Batch D direct-write postcondition failed: canonical RPC % grant changed',signature;
    end if;
  end loop;

  foreach signature in array array[
    'private.can_manage_joinings()',
    'private.can_correct_joinings()',
    'private.joining_application_status(text)',
    'private.validate_candidate_joining_dates()'
  ] loop
    if has_function_privilege('authenticated',signature,'execute')
       or has_function_privilege('anon',signature,'execute')
       or exists(
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
         where p.oid=to_regprocedure(signature) and acl.grantee=0 and acl.privilege_type='EXECUTE'
       ) then
      raise exception 'Batch D direct-write postcondition failed: private helper % is browser-accessible',signature;
    end if;
  end loop;
end;
$$;

commit;
