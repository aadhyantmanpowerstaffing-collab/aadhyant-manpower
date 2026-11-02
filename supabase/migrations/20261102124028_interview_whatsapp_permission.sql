begin;
alter table public.whatsapp_contacts
 add column transactional_permission_source text,
 add column transactional_permission_recorded_at timestamptz,
 add column transactional_permission_policy text;

create function private.record_interview_permission(p_contact_id uuid,p_allowed boolean,p_source text,p_received_at timestamptz,p_actor text)
returns boolean language plpgsql security definer set search_path='' as $$
declare w public.whatsapp_contacts%rowtype;
begin
 if p_allowed is null or p_source is null or p_source not in ('phone_call','written_permission','in_person','candidate_portal')
 or p_received_at is null or p_received_at>clock_timestamp() or p_received_at<clock_timestamp()-interval '365 days'
 or p_actor not in ('staff','candidate') then raise exception 'Actual permission choice, source and date are required';end if;
 select * into strict w from public.whatsapp_contacts where id=p_contact_id for update;
 if w.resolution_status<>'resolved' or w.candidate_id is null or not exists(select 1 from public.candidates c where c.id=w.candidate_id and c.profile_status='active' and c.status<>'inactive' and c.mobile=w.indian_mobile_key)
 then raise exception 'Active Candidate identity requires review';end if;
 if p_allowed and (w.opted_out_at is not null or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed') then raise exception 'WhatsApp STOP is active; permission cannot override it';end if;
 if w.transactional_permission_recorded_at is not null and p_received_at<w.transactional_permission_recorded_at then raise exception 'Newer permission choice exists. Refresh before recording permission';end if;
 update public.whatsapp_contacts set transactional_contact_status=case when w.transactional_contact_status='suppressed' then 'suppressed' when p_allowed then 'allowed' else 'unknown' end,
 transactional_permission_source=p_source,transactional_permission_recorded_at=p_received_at,transactional_permission_policy='recruitment-updates-v1',updated_at=clock_timestamp() where id=w.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),p_actor,'whatsapp.interview_permission_recorded','whatsapp_contact',w.id,case when p_actor='staff' then 'admin' else 'candidate' end,
 jsonb_build_object('allowed',p_allowed,'received_at',p_received_at,'permission_source',p_source,'policy','recruitment-updates-v1'));
 return true;
end;$$;
create function public.admin_console_set_interview_permission(p_contact_id uuid,p_allowed boolean,p_source text,p_received_at timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_source is null or p_source not in ('phone_call','written_permission','in_person') then raise exception 'Actual permission source required';end if;
 return private.record_interview_permission(p_contact_id,p_allowed,p_source,p_received_at,'staff');
end;$$;
alter function public.admin_console_contacts(text,text,integer) rename to admin_console_contacts_before_interview_permission;
create function public.admin_console_contacts(p_list text default null,p_tag text default null,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if auth.uid() is null or not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 rows:=public.admin_console_contacts_before_interview_permission(p_list,p_tag,p_offset);
 return coalesce((select jsonb_agg(e.value||jsonb_build_object('interview_permission',w.transactional_contact_status,'candidate_linked',w.candidate_id is not null,
 'interview_permission_received_at',w.transactional_permission_recorded_at) order by e.ordinality)
 from jsonb_array_elements(rows) with ordinality e(value,ordinality) join public.whatsapp_contacts w on w.id=(e.value->>'contact_id')::uuid),'[]'::jsonb);
end;$$;
create function public.get_candidate_interview_permission()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();w public.whatsapp_contacts%rowtype;
begin
 if cid is null or auth.uid() is null then raise exception 'Active Candidate Portal access required' using errcode='42501';end if;
 select * into w from public.whatsapp_contacts where candidate_id=cid and provider='whatsapp';
 return jsonb_build_object('allowed',coalesce(w.resolution_status='resolved' and w.indian_mobile_key=(select mobile from public.candidates where id=cid) and w.transactional_contact_status='allowed' and w.marketing_consent_status<>'opted_out' and w.opted_out_at is null,false),
 'blocked',coalesce(w.transactional_contact_status='suppressed' or w.marketing_consent_status='opted_out' or w.opted_out_at is not null,false),
 'recorded_at',w.transactional_permission_recorded_at);
end;$$;
create function public.set_candidate_interview_permission(p_allowed boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();c public.candidates%rowtype;w public.whatsapp_contacts%rowtype;
begin
 if cid is null or auth.uid() is null then raise exception 'Active Candidate Portal access required' using errcode='42501';end if;
 if p_allowed is null then raise exception 'Choose whether to receive interview updates';end if;
 select * into strict c from public.candidates where id=cid for update;
 if c.mobile !~ '^[6-9][0-9]{9}$' or c.profile_status<>'active' or c.status='inactive'
 or (select count(*) from public.candidates other where other.mobile=c.mobile or other.whatsapp_number=c.mobile)<>1 then raise exception 'Candidate mobile requires review';end if;
 perform pg_advisory_xact_lock(hashtextextended('w6-mobile:'||c.mobile,0));
 select * into w from public.whatsapp_contacts where provider='whatsapp' and (indian_mobile_key=c.mobile or candidate_id=cid) order by id limit 1 for update;
 if found and (w.indian_mobile_key<>c.mobile or w.resolution_status in ('blocked','ambiguous') or (w.candidate_id is not null and w.candidate_id<>cid)) then raise exception 'WhatsApp identity requires review';end if;
 if w.id is null then
 insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status) values('+91'||c.mobile,c.mobile,cid,'resolved') returning * into w;
 elsif w.candidate_id is null and w.resolution_status='unresolved' then
 update public.whatsapp_contacts set candidate_id=cid,resolution_status='resolved' where id=w.id;
 end if;
 return private.record_interview_permission(w.id,p_allowed,'candidate_portal',clock_timestamp(),'candidate');
end;$$;
revoke all on function private.record_interview_permission(uuid,boolean,text,timestamptz,text),public.admin_console_set_interview_permission(uuid,boolean,text,timestamptz),public.admin_console_contacts_before_interview_permission(text,text,integer),public.admin_console_contacts(text,text,integer),public.get_candidate_interview_permission(),public.set_candidate_interview_permission(boolean) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_set_interview_permission(uuid,boolean,text,timestamptz),public.admin_console_contacts(text,text,integer),public.get_candidate_interview_permission(),public.set_candidate_interview_permission(boolean) to authenticated;
commit;
