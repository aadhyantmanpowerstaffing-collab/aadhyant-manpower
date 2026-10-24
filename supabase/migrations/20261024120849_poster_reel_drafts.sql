-- Admin-reviewed poster media reuse the existing private queue and worker.
begin;
alter table private.requirement_reels alter column requirement_id drop not null;
alter table private.requirement_reels add column poster_request_id uuid unique,
 add column reviewed_by uuid references auth.users(id);
alter table private.requirement_reels add constraint reel_source_check check (
 (requirement_id is not null and poster_request_id is null and reviewed_by is null)
 or (requirement_id is null and poster_request_id is not null and reviewed_by is not null));

create function private.reel_current_payload(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when requirement_id is not null then private.reel_payload(requirement_id)
 when reviewed_by is not null and poster_request_id is not null and fingerprint=md5(payload::text) then payload else null end
 from private.requirement_reels where id=p_id;
$$;
revoke all on function private.reel_current_payload(uuid) from public,anon,authenticated,service_role;

create function public.admin_queue_poster_reel(p_request_id uuid,p_title text,p_text text,p_poster text,p_reviewed boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare c private.reel_config%rowtype; p jsonb; j private.requirement_reels%rowtype; rid uuid;
begin
 if not public.admin_console_access() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501';end if;
 if p_reviewed is distinct from true or p_request_id is null then raise exception 'Review and confirm the Hindi narration first';end if;
 if p_title is null or length(trim(p_title)) not between 1 and 80 or p_text is null or length(trim(p_text)) not between 10 and 1800
 or p_text !~ '[ऀ-ॿ]' then raise exception 'Enter a heading and 10–1800 characters of reviewed Hindi narration';end if;
 if p_poster is null or length(p_poster) not between 100 and 900000 or p_poster !~ '^[A-Za-z0-9+/]+={0,2}$' then raise exception 'Choose a valid poster smaller than the supported limit';end if;
 if substring(decode(p_poster,'base64') from 1 for 3) <> decode('ffd8ff','hex') then raise exception 'JPEG poster required';end if;
 select * into strict c from private.reel_config where singleton;
 if not c.enabled then raise exception 'Reel service is paused';end if;
 p:=jsonb_build_object('title',trim(p_title),'text',trim(p_text),'poster',p_poster,'name',c.contact_name,'phone',c.contact_phone);
 perform pg_advisory_xact_lock(hashtext('admin-poster-reels'));
 select * into j from private.requirement_reels where poster_request_id=p_request_id;
 if found then
 if j.reviewed_by<>auth.uid() or j.payload is distinct from p then raise exception 'This request already contains different reviewed details';end if;
 return j.id;
 end if;
 if (select count(*) from private.requirement_reels where poster_request_id is not null and created_at>clock_timestamp()-interval '24 hours')>=c.daily_limit then raise exception 'Daily poster video limit reached';end if;
 insert into private.requirement_reels(requirement_id,poster_request_id,reviewed_by,fingerprint,payload)
 values(null,p_request_id,auth.uid(),md5(p::text),p) returning id into rid;
 return rid;
end;$$;
revoke all on function public.admin_queue_poster_reel(uuid,text,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.admin_queue_poster_reel(uuid,text,text,text,boolean) to authenticated;

create function public.admin_retry_poster_reel(p_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if not (select enabled from private.reel_config where singleton) then raise exception 'Reel service is paused';end if;
 update private.requirement_reels set state='queued',attempts=0,claim_token=null,lease_until=null,object_path=null,updated_at=clock_timestamp()
 where id=p_id and poster_request_id is not null and state='failed';
 return p_id;
end;$$;
revoke all on function public.admin_retry_poster_reel(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_retry_poster_reel(uuid) to authenticated;

create or replace function public.admin_reel_object(p_id uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare j private.requirement_reels%rowtype;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into j from private.requirement_reels where id=p_id and state='ready';
 if j.id is null or j.payload is distinct from private.reel_current_payload(j.id) then return null;end if;return j.object_path;
end;$$;

create or replace function public.reel_worker_claim(p_worker text) returns jsonb language plpgsql security definer set search_path='' as $$
declare j private.requirement_reels%rowtype;tok uuid:=gen_random_uuid();begin
 update private.reel_config set worker_seen_at=clock_timestamp() where singleton;
 if not (select enabled from private.reel_config where singleton) then return null;end if;
 update private.requirement_reels set state=case when attempts>=3 then 'failed' else 'queued' end,claim_token=null,lease_until=null,updated_at=clock_timestamp() where state='rendering' and lease_until<clock_timestamp();
 if (select count(*) from private.requirement_reels where attempts>0 and updated_at>clock_timestamp()-interval '24 hours') >= (select daily_limit from private.reel_config where singleton) then return null;end if;
 for j in select * from private.requirement_reels where state='queued' and attempts<3 order by created_at for update skip locked loop
 if j.payload is distinct from private.reel_current_payload(j.id) then update private.requirement_reels set state='cancelled',updated_at=clock_timestamp() where id=j.id;continue;end if;
 update private.requirement_reels set state='rendering',attempts=attempts+1,claim_token=tok,worker_id=p_worker,lease_until=clock_timestamp()+interval '15 minutes',updated_at=clock_timestamp() where id=j.id;
 return jsonb_build_object('id',j.id,'claim',tok,'payload',j.payload);end loop;return null;
end;$$;

create or replace function public.reel_worker_check(p_id uuid,p_claim uuid,p_worker text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.requirement_reels j where j.id=p_id and j.state='rendering' and j.claim_token=p_claim and j.worker_id=p_worker and j.lease_until>clock_timestamp() and j.payload=private.reel_current_payload(j.id))$$;

create or replace function public.admin_reels(p_requirement_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return jsonb_build_object('enabled',(select enabled from private.reel_config where singleton),'worker_seen_at',(select worker_seen_at from private.reel_config where singleton),'jobs',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select j.id,j.requirement_id,coalesce(r.requirement_code,'POSTER') as requirement_code,coalesce(r.company_name,'Uploaded poster') as company_name,coalesce(r.job_role,j.payload->>'title') as job_role,coalesce(r.job_location,'') as job_location,(j.poster_request_id is not null) as is_poster,j.state,j.attempts,j.created_at,j.updated_at from private.requirement_reels j left join public.employer_requirements r on r.id=j.requirement_id where (p_requirement_id is null or j.requirement_id=p_requirement_id) and j.state<>'cancelled' order by j.created_at desc limit 50) x));
end;$$;

commit;
