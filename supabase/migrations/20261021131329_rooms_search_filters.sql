begin;
-- Additional public-search signature. Owner/Admin use the existing scoped RPC.
create function public.list_room_properties(p_filters jsonb,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare f jsonb:=p_filters; area_filter text; type_filter text; suitable_filter text;
 unit_filter text; facility_filter text; sort_filter text; max_rent numeric; max_sharing integer; result jsonb;
begin
 if f is null or jsonb_typeof(f)<>'object' or p_offset is null or p_offset<0 or p_offset>10000
 or exists(select 1 from jsonb_object_keys(f) k where k not in ('area','property_type','suitable_for','unit','facility','sort','max_rent','max_sharing'))
 then raise exception 'Invalid room search';end if;
 if exists(select 1 from jsonb_each(f) e where e.key not in ('max_rent','max_sharing') and jsonb_typeof(e.value)<>'string')
 or exists(select 1 from jsonb_each(f) e where e.key in ('max_rent','max_sharing') and jsonb_typeof(e.value) not in ('number','null'))
 then raise exception 'Invalid room search';end if;
 area_filter:=btrim(coalesce(f->>'area',''));type_filter:=coalesce(f->>'property_type','');suitable_filter:=coalesce(f->>'suitable_for','');
 unit_filter:=coalesce(f->>'unit','');facility_filter:=btrim(coalesce(f->>'facility',''));sort_filter:=coalesce(f->>'sort','recent');
 if length(area_filter)>160 or length(facility_filter)>80 or type_filter not in ('','pg','room','hostel')
 or suitable_filter not in ('','boys','girls','family','any') or unit_filter not in ('','bed','room')
 or sort_filter not in ('recent','rent_low','rent_high') then raise exception 'Invalid room search';end if;
 max_rent:=(f->>'max_rent')::numeric;
 if f->>'max_sharing' is not null and (f->>'max_sharing')!~ '^[0-9]+$' then raise exception 'Invalid sharing limit';end if;
 max_sharing:=(f->>'max_sharing')::integer;
 if max_rent is not null and (max_rent<1 or max_rent>1000000) or max_sharing is not null and (max_sharing<1 or max_sharing>20)
 then raise exception 'Invalid room search';end if;
 with eligible as (
 select p.* from private.room_properties p join private.room_owners o on o.user_id=p.owner_id
 where p.status='approved' and o.status='active' and p.is_listed and p.available>0 and p.availability_updated_at>now()-interval '30 days'
 and (area_filter='' or strpos(lower(p.area||' '||p.address),lower(area_filter))>0)
 and (type_filter='' or p.property_type=type_filter) and (max_rent is null or p.rent<=max_rent)
 and (suitable_filter='' or p.suitable_for=suitable_filter or p.suitable_for='any')
 and (unit_filter='' or p.unit=unit_filter) and (max_sharing is null or p.sharing<=max_sharing)
 and (facility_filter='' or strpos(lower(p.facilities),lower(facility_filter))>0)
 ), ordered as (
 select p.*,row_number() over(order by case when sort_filter='rent_low' then p.rent end asc,
 case when sort_filter='rent_high' then p.rent end desc,p.updated_at desc,p.id) position from eligible p
 ), selected as (select * from ordered order by position limit 12 offset p_offset)
 select jsonb_build_object('total',(select count(*) from eligible),'items',coalesce((select jsonb_agg(jsonb_build_object(
 'id',p.id,'title',p.title,'property_type',p.property_type,'area',p.area,'address',p.address,'rent',p.rent,'deposit',p.deposit,
 'unit',p.unit,'suitable_for',p.suitable_for,'sharing',p.sharing,'capacity',p.capacity,'available',p.available,
 'facilities',p.facilities,'rules',p.rules,'map_url',p.map_url,'photos',p.photos,'availability_updated_at',p.availability_updated_at
 ) order by p.position) from selected p),'[]'::jsonb)) into result;
 return result;
end;$$;
revoke all on function public.list_room_properties(jsonb,integer) from public,anon,authenticated,service_role;
grant execute on function public.list_room_properties(jsonb,integer) to anon,authenticated;
commit;
