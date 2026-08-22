-- W6 corrective migration: Candidate-only private Storage DML and explicit document review lifecycle.

begin;

do $$
begin
  if to_regclass('public.candidate_documents') is null
     or to_regprocedure('private.current_candidate_portal_id()') is null
     or to_regprocedure('private.can_verify_candidate_documents()') is null
     or to_regprocedure('public.admin_review_candidate_document(uuid,text,text)') is null
     or not exists(select 1 from storage.buckets b where b.id='candidate-private' and b.public=false) then
    raise exception 'W6 Candidate document correction prerequisites are missing';
  end if;
  if exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='candidate_documents'
      and column_name in ('review_started_at','review_started_by','reviewed_at','reviewed_by')) then
    raise exception 'W6 Candidate document review attribution already exists; inspect partial/manual changes';
  end if;
  if exists(select 1 from public.candidate_documents d where d.verification_status='under_verification') then
    raise exception 'Existing under-verification documents require explicit attribution review before migration 025';
  end if;
end;
$$;

alter table public.candidate_documents
  add column review_started_at timestamptz,
  add column review_started_by uuid references auth.users(id) on delete set null,
  add column reviewed_at timestamptz,
  add column reviewed_by uuid references auth.users(id) on delete set null;

alter table public.candidate_documents
  drop constraint candidate_documents_verification_check;

update public.candidate_documents d
set review_started_at=coalesce(d.verified_at,d.updated_at,d.uploaded_at),
    review_started_by=d.verified_by,
    reviewed_at=coalesce(d.verified_at,d.updated_at,d.uploaded_at),
    reviewed_by=d.verified_by,
    verified_by=case when d.verification_status='verified' then d.verified_by else null end
where d.verification_status in ('verified','reupload_required');

alter table public.candidate_documents
  add constraint candidate_documents_verification_check check (
    (verification_status='uploaded'
      and review_started_at is null and review_started_by is null
      and reviewed_at is null and reviewed_by is null
      and verified_at is null and verified_by is null and verification_feedback is null)
    or (verification_status='under_verification'
      and review_started_at is not null and review_started_by is not null
      and reviewed_at is null and reviewed_by is null
      and verified_at is null and verified_by is null and verification_feedback is null)
    or (verification_status='verified'
      and review_started_at is not null and review_started_by is not null
      and reviewed_at is not null and reviewed_by is not null
      and verified_at is not null and verified_by is not null
      and reviewed_at=verified_at and reviewed_by=verified_by
      and verification_feedback is null)
    or (verification_status='reupload_required'
      and review_started_at is not null and review_started_by is not null
      and reviewed_at is not null and reviewed_by is not null
      and verified_at is null and verified_by is null
      and verification_feedback is not null)
  );

create function private.is_current_candidate_storage_path(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (select private.current_candidate_portal_id()) is not null
    and (storage.foldername(p_object_name))[1]=(select auth.uid())::text;
$$;

create function private.can_read_candidate_storage_object(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (select private.can_verify_candidate_documents())
    and exists(select 1 from public.candidate_documents d
      where d.storage_object_name=p_object_name and d.active);
$$;

create function private.can_delete_candidate_storage_object(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select private.is_current_candidate_storage_path(p_object_name))
    and not exists(select 1 from public.candidate_documents d
      where d.storage_object_name=p_object_name and d.active);
$$;

revoke all on function private.is_current_candidate_storage_path(text) from public,anon,authenticated;
revoke all on function private.can_read_candidate_storage_object(text) from public,anon,authenticated;
revoke all on function private.can_delete_candidate_storage_object(text) from public,anon,authenticated;
grant execute on function private.is_current_candidate_storage_path(text) to authenticated;
grant execute on function private.can_read_candidate_storage_object(text) to authenticated;
grant execute on function private.can_delete_candidate_storage_object(text) to authenticated;

drop policy if exists "Candidate owns private uploads" on storage.objects;
drop policy if exists "Candidate reads private uploads" on storage.objects;
drop policy if exists "Candidate replaces private uploads" on storage.objects;
drop policy if exists "Candidate removes unregistered private uploads" on storage.objects;

create policy "Candidate inserts own private uploads" on storage.objects
for insert to authenticated
with check (bucket_id='candidate-private'
  and (select private.is_current_candidate_storage_path(name)));

create policy "Candidate reads own private uploads" on storage.objects
for select to authenticated
using (bucket_id='candidate-private'
  and (select private.is_current_candidate_storage_path(name)));

create policy "Candidate updates own private uploads" on storage.objects
for update to authenticated
using (bucket_id='candidate-private'
  and (select private.is_current_candidate_storage_path(name)))
with check (bucket_id='candidate-private'
  and (select private.is_current_candidate_storage_path(name)));

create policy "Candidate deletes own unregistered private uploads" on storage.objects
for delete to authenticated
using (bucket_id='candidate-private'
  and (select private.can_delete_candidate_storage_object(name)));

create policy "Candidate document verifiers read registered uploads" on storage.objects
for select to authenticated
using (bucket_id='candidate-private'
  and (select private.can_read_candidate_storage_object(name)));

create or replace function public.admin_review_candidate_document(p_document_id uuid,p_status text,p_feedback text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text:=lower(btrim(coalesce(p_status,'')));
  v_feedback text:=nullif(btrim(p_feedback),'');
  v_candidate uuid;
  v_prior text;
  v_actor uuid:=(select auth.uid());
  v_now timestamptz:=clock_timestamp();
  v_action text;
begin
  if not (select private.can_verify_candidate_documents()) then
    raise exception 'Candidate document verification access is required';
  end if;
  if v_status not in ('under_verification','verified','reupload_required')
     or length(coalesce(v_feedback,''))>1000
     or (v_status='reupload_required' and length(coalesce(v_feedback,''))<5)
     or (v_status in ('under_verification','verified') and v_feedback is not null) then
    raise exception 'Document review details are invalid';
  end if;

  select d.candidate_id,d.verification_status into v_candidate,v_prior
  from public.candidate_documents d where d.id=p_document_id and d.active for update;
  if v_candidate is null then raise exception 'Candidate document was not found'; end if;

  if v_status='under_verification' then
    if v_prior<>'uploaded' then raise exception 'Only an uploaded document can enter verification'; end if;
    update public.candidate_documents d set verification_status='under_verification',
      verification_feedback=null,review_started_at=v_now,review_started_by=v_actor,
      reviewed_at=null,reviewed_by=null,verified_at=null,verified_by=null
      where d.id=p_document_id;
    v_action:='candidate.document_review_started';
  elsif v_status='verified' then
    if v_prior<>'under_verification' then raise exception 'Only an under-verification document can be verified'; end if;
    update public.candidate_documents d set verification_status='verified',
      verification_feedback=null,reviewed_at=v_now,reviewed_by=v_actor,
      verified_at=v_now,verified_by=v_actor where d.id=p_document_id;
    v_action:='candidate.document_verified';
  else
    if v_prior<>'under_verification' then raise exception 'Only an under-verification document can require re-upload'; end if;
    update public.candidate_documents d set verification_status='reupload_required',
      verification_feedback=v_feedback,reviewed_at=v_now,reviewed_by=v_actor,
      verified_at=null,verified_by=null where d.id=p_document_id;
    v_action:='candidate.document_reupload_requested';
  end if;

  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(v_actor,'staff',v_action,'candidate_document',p_document_id,'admin',jsonb_build_object('status',v_status));
  return true;
end;
$$;

revoke all on function public.admin_review_candidate_document(uuid,text,text) from public,anon,authenticated;
grant execute on function public.admin_review_candidate_document(uuid,text,text) to authenticated;

commit;
