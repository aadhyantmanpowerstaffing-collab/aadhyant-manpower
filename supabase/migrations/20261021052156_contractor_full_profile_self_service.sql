-- Extend the canonical Contractor profile API; tenant and approval boundaries remain authoritative.
begin;
create function public.update_contractor_portal_profile(p_profile jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare
 cid uuid; before_row public.contractors%rowtype; profile_key text; item jsonb;
 agency text:=nullif(btrim(p_profile->>'agency_name'),'');
 contact_email text:=nullif(lower(btrim(p_profile->>'main_email')),'');
 gst text:=nullif(upper(btrim(p_profile->>'gstin')),'');
 locations text[]; categories text[]; capacity integer; identity_changed boolean;
 allowed constant text[]:=array['agency_name','owner_name','main_phone','main_email','website','address','city','district','state','pincode','operating_locations','workforce_capacity','manpower_categories','gstin','esic_code','epfo_code','labour_license_number'];
begin
 cid:=(select private.current_contractor_portal_id(true));
 if cid is null or not (select private.can_edit_contractor_profile()) then raise exception 'Contractor profile management access is required'; end if;
 if p_profile is null or jsonb_typeof(p_profile)<>'object' then raise exception 'A profile object is required'; end if;
 for profile_key,item in select key,value from jsonb_each(p_profile) loop
   if not (profile_key=any(allowed)) then raise exception 'Unsupported profile field'; end if;
   if profile_key not in ('operating_locations','manpower_categories','workforce_capacity')
      and jsonb_typeof(item) not in ('string','null') then raise exception 'Profile text fields must contain text'; end if;
 end loop;
 if agency is null or length(agency)>240 then raise exception 'Firm / agency name is required (maximum 240 characters)'; end if;
 if nullif(btrim(p_profile->>'main_phone'),'') is null then raise exception 'A valid Indian mobile number is required'; end if;
 if contact_email is null or length(contact_email)>254 or contact_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'A valid contact email is required'; end if;
 if gst is not null and gst !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then raise exception 'Enter a valid 15-character GSTIN'; end if;
 foreach profile_key in array array['esic_code','epfo_code','labour_license_number'] loop
   if length(coalesce(btrim(p_profile->>profile_key),''))>100 then raise exception 'Registration details must not exceed 100 characters'; end if;
 end loop;
 if nullif(btrim(p_profile->>'website'),'') is not null and p_profile->>'website' !~* '^https?://[^[:space:]]+$' then raise exception 'Website must start with http:// or https://'; end if;
 foreach profile_key in array array['operating_locations','manpower_categories'] loop
   if jsonb_typeof(p_profile->profile_key) is distinct from 'array' then raise exception 'Locations and categories must be lists'; end if;
   if jsonb_array_length(p_profile->profile_key)>50 then raise exception 'A maximum of 50 list entries is allowed'; end if;
   for item in select value from jsonb_array_elements(p_profile->profile_key) loop
     if jsonb_typeof(item)<>'string' or length(btrim(item#>>'{}')) not between 1 and 200 then raise exception 'List entries must contain 1 to 200 characters'; end if;
   end loop;
 end loop;
 select coalesce(array_agg(btrim(value)),array[]::text[]) into locations from jsonb_array_elements_text(p_profile->'operating_locations');
 select coalesce(array_agg(btrim(value)),array[]::text[]) into categories from jsonb_array_elements_text(p_profile->'manpower_categories');
 if p_profile->>'workforce_capacity' is not null then
   if p_profile->>'workforce_capacity' !~ '^[0-9]{1,7}$' then raise exception 'Workforce capacity is invalid'; end if;
   capacity:=(p_profile->>'workforce_capacity')::integer;
 end if;
 select c.* into strict before_row from public.contractors c where c.id=cid for update;
 identity_changed:=agency is distinct from before_row.agency_name or gst is distinct from before_row.gstin
   or nullif(btrim(p_profile->>'esic_code'),'') is distinct from before_row.esic_code
   or nullif(btrim(p_profile->>'epfo_code'),'') is distinct from before_row.epfo_code
   or nullif(btrim(p_profile->>'labour_license_number'),'') is distinct from before_row.labour_license_number;
 perform public.update_contractor_portal_profile(p_profile->>'owner_name',p_profile->>'main_phone',p_profile->>'website',p_profile->>'address',
   p_profile->>'city',p_profile->>'district',p_profile->>'state',p_profile->>'pincode',locations,capacity,categories);
 update public.contractors as c set agency_name=agency,main_email=contact_email,gstin=gst,
   esic_code=nullif(btrim(p_profile->>'esic_code'),''),epfo_code=nullif(btrim(p_profile->>'epfo_code'),''),
   labour_license_number=nullif(btrim(p_profile->>'labour_license_number'),''),
   verification_status=case when identity_changed then 'pending' else c.verification_status end
 where c.id=cid;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values((select auth.uid()),'contractor','contractor_profile_updated','contractor',cid,'contractor',
   jsonb_build_object('changed_fields',(select jsonb_agg(key) from jsonb_each(p_profile) where value is distinct from to_jsonb(before_row)->key),
     'identity_review_required',identity_changed));
 return true;
end $$;
revoke all on function public.update_contractor_portal_profile(jsonb) from public,anon;
grant execute on function public.update_contractor_portal_profile(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
