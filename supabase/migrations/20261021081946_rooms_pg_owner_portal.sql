begin;
-- Accommodation has its own approval/ownership records; recruitment identities stay canonical.
create table private.room_owners (
 user_id uuid primary key references auth.users(id), display_name text not null check(length(display_name) between 2 and 120),
 phone text not null check(phone ~ '^[6-9][0-9]{9}$'), status text not null default 'pending' check(status in ('pending','active','suspended')),
 created_at timestamptz not null default now(), reviewed_at timestamptz, reviewed_by uuid references auth.users(id)
);
create table private.room_properties (
 id uuid primary key default gen_random_uuid(), request_key uuid not null, request_hash text not null, owner_id uuid not null references private.room_owners(user_id),
 title text not null check(length(title) between 3 and 160), property_type text not null check(property_type in ('pg','room','hostel')),
 area text not null check(length(area) between 2 and 160), address text not null check(length(address) between 5 and 500),
 rent numeric(10,2) not null check(rent>0 and rent<=1000000), deposit numeric(10,2) not null check(deposit>=0 and deposit<=10000000),
 unit text not null check(unit in ('bed','room')), suitable_for text not null check(suitable_for in ('boys','girls','family','any')),
 sharing integer not null check(sharing between 1 and 20), capacity integer not null check(capacity between 1 and 100000),
 available integer not null check(available>=0 and available<=capacity), facilities text not null default '' check(length(facilities)<=1000),
 rules text not null default '' check(length(rules)<=1000), map_url text not null default '' check(map_url='' or map_url ~ '^https://(www\.google\.com/maps[/?]|maps\.google\.com/|maps\.app\.goo\.gl/)[^[:space:]]+$'),
 photos jsonb not null default '[]', status text not null default 'pending' check(status in ('pending','approved','correction_required','rejected')),
 review_note text not null default '' check(length(review_note)<=1000), is_listed boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), availability_updated_at timestamptz not null default now(),
 reviewed_at timestamptz, reviewed_by uuid references auth.users(id)
);
create unique index room_properties_request_idx on private.room_properties(owner_id,request_key);
create index room_properties_owner_idx on private.room_properties(owner_id,created_at desc);
create index room_properties_browse_idx on private.room_properties(status,is_listed,availability_updated_at desc);
create table private.room_enquiries (
 id uuid primary key default gen_random_uuid(), property_id uuid not null references private.room_properties(id),
 candidate_id uuid not null references public.candidates(id), contact_phone text not null check(contact_phone ~ '^[6-9][0-9]{9}$'),
 message text not null check(length(message) between 1 and 600), contact_consent_at timestamptz not null,
 status text not null default 'new' check(status in ('new','contacted','closed','withdrawn')), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(property_id,candidate_id)
);
create index room_enquiries_candidate_idx on private.room_enquiries(candidate_id,created_at desc);
alter table private.room_owners enable row level security;
alter table private.room_properties enable row level security;
alter table private.room_enquiries enable row level security;
revoke all on private.room_owners,private.room_properties,private.room_enquiries from public,anon,authenticated;

create function public.room_owner_context() returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null then null else (select jsonb_build_object('user_id',o.user_id,'display_name',o.display_name,'phone',o.phone,'status',o.status) from private.room_owners o where o.user_id=auth.uid()) end;
$$;
create function public.register_room_owner(p_name text,p_phone text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null) then raise exception 'Confirm your email and sign in first';end if;
 if exists(select 1 from private.room_owners where user_id=auth.uid()) then return public.room_owner_context();end if;
 insert into private.room_owners(user_id,display_name,phone) values(auth.uid(),btrim(p_name),btrim(p_phone));
 return public.room_owner_context();
end;$$;
create function public.save_room_property(p_id uuid,p_data jsonb,p_request_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=coalesce(p_id,gen_random_uuid());v_photos jsonb:=coalesce(p_data->'photos','[]'::jsonb);v_photo jsonb;
begin
 if auth.uid() is null or not exists(select 1 from private.room_owners o where o.user_id=auth.uid() and o.status='active') then raise exception 'Owner account must be approved';end if;
 if jsonb_typeof(p_data)<>'object' or jsonb_typeof(v_photos)<>'array' or jsonb_array_length(v_photos)>3 then raise exception 'Use up to three photos';end if;
 for v_photo in select value from jsonb_array_elements(v_photos) loop
  if jsonb_typeof(v_photo)<>'string' or length(v_photo#>>'{}')>180000 or (v_photo#>>'{}') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+=*$' then raise exception 'Use compressed JPEG photos';end if;
 end loop;
 if p_request_key is null then raise exception 'Request identity required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_key::text,0));
 if p_id is null then
  select id into v_id from private.room_properties where owner_id=auth.uid() and request_key=p_request_key;
  if found then
   if not exists(select 1 from private.room_properties where id=v_id and request_hash=md5(p_data::text)) then raise exception 'Request conflicts with saved property';end if;return v_id;
  end if;v_id:=gen_random_uuid();
 end if;
 if p_id is not null then
  perform 1 from private.room_properties where id=p_id and owner_id=auth.uid() for update;
  if not found then raise exception 'Property not available';end if;
 end if;
 insert into private.room_properties(id,request_key,request_hash,owner_id,title,property_type,area,address,rent,deposit,unit,suitable_for,sharing,capacity,available,facilities,rules,map_url,photos)
 values(v_id,p_request_key,md5(p_data::text),auth.uid(),btrim(p_data->>'title'),p_data->>'property_type',btrim(p_data->>'area'),btrim(p_data->>'address'),(p_data->>'rent')::numeric,(p_data->>'deposit')::numeric,p_data->>'unit',p_data->>'suitable_for',(p_data->>'sharing')::integer,(p_data->>'capacity')::integer,(p_data->>'available')::integer,coalesce(p_data->>'facilities',''),coalesce(p_data->>'rules',''),coalesce(p_data->>'map_url',''),v_photos)
 on conflict(id) do update set title=excluded.title,property_type=excluded.property_type,area=excluded.area,address=excluded.address,rent=excluded.rent,deposit=excluded.deposit,unit=excluded.unit,suitable_for=excluded.suitable_for,sharing=excluded.sharing,capacity=excluded.capacity,available=excluded.available,facilities=excluded.facilities,rules=excluded.rules,map_url=excluded.map_url,photos=excluded.photos,status='pending',review_note='',reviewed_at=null,reviewed_by=null,updated_at=now(),availability_updated_at=now();
 return v_id;
end;$$;
create function public.update_room_availability(p_id uuid,p_available integer,p_listed boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_available is null or p_listed is null then raise exception 'Enter availability and listing choice';end if;
 update private.room_properties p set available=p_available,is_listed=p_listed,availability_updated_at=now(),updated_at=now()
 where p.id=p_id and p.owner_id=auth.uid() and exists(select 1 from private.room_owners o where o.user_id=auth.uid() and o.status='active');
 if not found then raise exception 'Property not available';end if;return true;
end;$$;
create function public.list_room_properties(p_scope text default 'public',p_area text default '',p_max_rent numeric default null,p_type text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_offset<0 or p_offset>10000 or p_scope not in ('public','owner','admin') or p_scope is null then raise exception 'Invalid request';end if;
 if p_scope='owner' and auth.uid() is null then raise exception 'Sign in first';end if;
 if p_scope='admin' and not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied';end if;
 return coalesce((select jsonb_agg(x.row) from (
 select jsonb_build_object('id',p.id,'title',p.title,'property_type',p.property_type,'area',p.area,'address',p.address,'rent',p.rent,'deposit',p.deposit,'unit',p.unit,'suitable_for',p.suitable_for,'sharing',p.sharing,'capacity',p.capacity,'available',p.available,'facilities',p.facilities,'rules',p.rules,'map_url',p.map_url,'photos',p.photos,'status',p.status,'review_note',p.review_note,'is_listed',p.is_listed,'availability_updated_at',p.availability_updated_at,'owner_status',o.status,'owner_id',case when p_scope='admin' then o.user_id else null end,'owner_name',case when p_scope in ('admin','owner') then o.display_name else null end) row
 from private.room_properties p join private.room_owners o on o.user_id=p.owner_id
 where ((p_scope='public' and p.status='approved' and o.status='active' and p.is_listed and p.available>0 and p.availability_updated_at>now()-interval '30 days') or (p_scope='owner' and p.owner_id=auth.uid()) or p_scope='admin')
 and (coalesce(p_area,'')='' or p.area ilike '%'||left(p_area,160)||'%') and (p_max_rent is null or p.rent<=p_max_rent) and (coalesce(p_type,'')='' or p.property_type=p_type)
 order by p.updated_at desc,p.id limit 12 offset p_offset) x),'[]'::jsonb);
end;$$;
create function public.list_room_owners() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',x.user_id,'display_name',x.display_name,'phone',left(x.phone,2)||'******'||right(x.phone,2),'status',x.status,'created_at',x.created_at)) from (select * from private.room_owners order by created_at desc limit 500) x),'[]'::jsonb);
end;$$;
create function public.review_room_record(p_kind text,p_id uuid,p_status text,p_note text default '') returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied';end if;
 if p_kind='owner' and p_status in ('active','suspended') then
 update private.room_owners set status=p_status,reviewed_at=now(),reviewed_by=auth.uid() where user_id=p_id;
 elsif p_kind='property' and p_status in ('approved','correction_required','rejected') then
 if p_status in ('correction_required','rejected') and length(btrim(coalesce(p_note,'')))<3 then raise exception 'Enter review feedback';end if;
 update private.room_properties set status=p_status,review_note=coalesce(p_note,''),reviewed_at=now(),reviewed_by=auth.uid(),updated_at=now() where id=p_id;
 else raise exception 'Invalid review';end if;
 if not found then raise exception 'Record not available';end if;return true;
end;$$;
create function public.send_room_enquiry(p_property uuid,p_phone text,p_message text,p_consent boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare v_candidate uuid:=private.current_candidate_portal_id();v_id uuid;
begin
 if v_candidate is null or p_consent is distinct from true then raise exception 'Candidate login and contact-sharing consent required';end if;
 perform 1 from private.room_properties p join private.room_owners o on o.user_id=p.owner_id where p.id=p_property and p.status='approved' and o.status='active' and p.is_listed and p.available>0 and p.availability_updated_at>now()-interval '30 days' for share of p,o;
 if not found then raise exception 'This property is not currently available';end if;
 insert into private.room_enquiries(property_id,candidate_id,contact_phone,message,contact_consent_at) values(p_property,v_candidate,btrim(p_phone),btrim(p_message),now())
 on conflict(property_id,candidate_id) do update set contact_phone=excluded.contact_phone,message=excluded.message,contact_consent_at=now(),status='new',updated_at=now()
 returning id into v_id;return v_id;
end;$$;
create function public.list_room_enquiries(p_scope text default 'candidate') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or p_scope not in ('candidate','owner') or p_scope is null then raise exception 'Sign in to the correct portal';end if;
 return coalesce((select jsonb_agg(x.row) from (
 select jsonb_build_object('id',e.id,'property_title',p.title,'area',p.area,'status',e.status,'message',case when p_scope='owner' and e.status='withdrawn' then 'Candidate withdrew this enquiry.' else e.message end,'created_at',e.created_at,'contact_phone',case when e.status<>'withdrawn' then e.contact_phone else null end) row
 from private.room_enquiries e join private.room_properties p on p.id=e.property_id
 where (p_scope='candidate' and e.candidate_id=private.current_candidate_portal_id()) or (p_scope='owner' and p.owner_id=auth.uid() and exists(select 1 from private.room_owners o where o.user_id=auth.uid() and o.status='active'))
 order by e.created_at desc limit 200) x),'[]'::jsonb);
end;$$;
create function public.update_room_enquiry(p_id uuid,p_status text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 update private.room_enquiries e set status=p_status,updated_at=now() where e.id=p_id and (
 (p_status='withdrawn' and e.candidate_id=private.current_candidate_portal_id()) or
 (p_status in ('contacted','closed') and e.status<>'withdrawn' and exists(select 1 from private.room_properties p join private.room_owners o on o.user_id=p.owner_id where p.id=e.property_id and o.user_id=auth.uid() and o.status='active')));
 if not found then raise exception 'Enquiry not available';end if;return true;
end;$$;
revoke all on function public.room_owner_context(),public.register_room_owner(text,text),public.save_room_property(uuid,jsonb,uuid),public.update_room_availability(uuid,integer,boolean),public.list_room_properties(text,text,numeric,text,integer),public.list_room_owners(),public.review_room_record(text,uuid,text,text),public.send_room_enquiry(uuid,text,text,boolean),public.list_room_enquiries(text),public.update_room_enquiry(uuid,text) from public,anon,authenticated;
grant execute on function public.list_room_properties(text,text,numeric,text,integer) to anon,authenticated;
grant execute on function public.room_owner_context(),public.register_room_owner(text,text),public.save_room_property(uuid,jsonb,uuid),public.update_room_availability(uuid,integer,boolean),public.list_room_owners(),public.review_room_record(text,uuid,text,text),public.send_room_enquiry(uuid,text,text,boolean),public.list_room_enquiries(text),public.update_room_enquiry(uuid,text) to authenticated;
commit;
