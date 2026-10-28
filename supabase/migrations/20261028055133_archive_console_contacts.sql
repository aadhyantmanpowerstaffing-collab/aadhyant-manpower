-- Remove contacts from manual contact selection without deleting identities or history.
begin;
alter table public.whatsapp_contacts add column console_archived_at timestamptz;

create function public.admin_console_archive_contacts(p_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if not public.admin_console_access() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
 if cardinality(p_ids) is null or cardinality(p_ids) not between 1 and 500 or array_position(p_ids,null) is not null then raise exception 'Choose 1 to 500 contacts'; end if;
 -- Stable locks serialize concurrent overlapping selections.
 perform id from public.whatsapp_contacts where id=any(p_ids) order by id for update;
 update public.whatsapp_contacts set console_archived_at=clock_timestamp()
 where id=any(p_ids) and console_archived_at is null;
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.console_contacts_archived','whatsapp_contact','admin',jsonb_build_object('archived',n));
 return jsonb_build_object('archived',n);
end; $$;
revoke all on function public.admin_console_archive_contacts(uuid[]) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_archive_contacts(uuid[]) to authenticated;

create or replace function public.admin_console_contacts(p_list text default null,p_tag text default null,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
  select w.id contact_id,left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
   '+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,w.candidate_id,
   w.marketing_consent_status consent,w.resolution_status,
   coalesce(w.imported_profile->'Lists','[]') lists,coalesce(w.imported_profile->'Tags','[]') tags,
   w.imported_profile->>'State' state,w.imported_profile->>'District' district
  from public.whatsapp_contacts w left join public.candidates c on c.id=w.candidate_id
  where w.console_archived_at is null and (p_list is null or coalesce(w.imported_profile->'Lists','[]')?p_list)
   and (p_tag is null or coalesce(w.imported_profile->'Tags','[]')?p_tag)
  order by w.created_at desc,w.id limit 100 offset p_offset)t);
end; $$;

create or replace function public.admin_console_audience(p_requirement_id uuid,p_source text default 'registered',p_view text default 'suggested',p_offset integer default 0,p_list text default null,p_tag text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare req public.employer_requirements%rowtype; result jsonb;
begin
 if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_source is null or p_source not in ('registered','contacts') or p_view is null or p_view not in ('suggested','all') or p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid audience query'; end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id and requirement_stage='open' and requirement_visibility='public';
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
  select w.id contact_id,w.candidate_id,
    left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
    case when w.id is null then 'Unavailable' else '+91XXXXXX'||right(w.indian_mobile_key,4) end mobile_masked,
    c.highest_qualification qualification,c.specialization trade,
    coalesce(c.current_location,w.imported_profile->>'District') location,
    w.marketing_consent_status consent,w.sharing_subscription->>'scope' alert_scope,
    private.selected_job_contact_eligible(w.id,req.id) eligible,
    case when w.id is null then 'WhatsApp contact unavailable' when w.resolution_status in ('blocked','ambiguous') then 'Contact blocked or ambiguous'
      when w.marketing_consent_status<>'opted_in' then 'Consent required'
      when w.candidate_id is not null and (c.profile_status<>'active' or c.status='inactive') then 'Inactive candidate'
      when exists(select 1 from public.candidate_applications a where a.candidate_id=w.candidate_id and a.requirement_id=req.id) then 'Already applied'
      when w.sharing_subscription<>'{}'::jsonb and not private.sharing_contact_eligible(w.id,req.id) then 'Subscriber preference does not match'
      when private.selected_job_contact_eligible(w.id,req.id) then 'Can select' else 'Contact needs review' end status,
    coalesce(m.suggested,false) suggested,m.reasons match_reasons
  from public.whatsapp_contacts w full join public.candidates c on c.id=w.candidate_id
  cross join lateral (select array_remove(array[
    case when nullif(btrim(req.qualification),'') is not null and lower(coalesce(c.highest_qualification,''))<>lower(req.qualification) then 'Qualification differs' end,
    case when nullif(btrim(req.iti_trade),'') is not null and lower(coalesce(c.specialization,''))<>lower(req.iti_trade) then 'Trade differs' end,
    case when req.experience_requirement is not null and req.experience_requirement<>'Both' and c.candidate_type is distinct from req.experience_requirement then 'Experience differs' end,
    case when nullif(btrim(coalesce(req.job_location,req.company_location)),'') is not null and
      lower(coalesce(c.current_location,''))<>lower(coalesce(req.job_location,req.company_location)) and
      lower(coalesce(c.district,''))<>lower(coalesce(req.job_location,req.company_location)) and
      lower(coalesce(c.state,''))<>lower(coalesce(req.job_location,req.company_location)) then 'Location differs' end
  ],null) reasons) reasons
  cross join lateral (select reasons.reasons, c.id is not null and cardinality(reasons.reasons)=0 suggested) m
  where w.console_archived_at is null and (w.provider='whatsapp' or w.id is null) and ((p_source='registered' and c.id is not null) or (p_source='contacts' and w.imported_profile<>'{}'::jsonb))
    and (p_view='all' or p_source='contacts' or m.suggested)
  and (nullif(btrim(p_list),'') is null or w.imported_profile->'Lists' ? btrim(p_list))
    and (nullif(btrim(p_tag),'') is null or w.imported_profile->'Tags' ? btrim(p_tag))
  order by m.suggested desc,w.created_at desc nulls last,w.id,c.id limit 100 offset p_offset
 ) t;
 return result;
end; $$;

create or replace function private.selected_job_contact_eligible(p_contact_id uuid,p_requirement_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_contacts w join public.employer_requirements r on r.id=p_requirement_id
 where w.console_archived_at is null and w.id=p_contact_id and w.provider='whatsapp' and w.resolution_status in ('resolved','unresolved')
 and w.marketing_consent_status='opted_in' and private.whatsapp_contact_allows_purpose(w.id,'marketing')
 and r.requirement_stage='open' and r.requirement_visibility='public' and private.vacancy_is_application_eligible(r.id)
 and (w.sharing_subscription='{}'::jsonb or private.sharing_contact_eligible(w.id,r.id))
 and (w.candidate_id is null or (w.resolution_status='resolved' and exists(select 1 from public.candidates c
   where c.id=w.candidate_id and c.profile_status='active' and c.status<>'inactive')
   and not exists(select 1 from public.candidate_applications a where a.candidate_id=w.candidate_id and a.requirement_id=r.id))));
$$;
commit;
