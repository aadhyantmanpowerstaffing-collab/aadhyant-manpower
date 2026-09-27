-- Upgrade the existing grant ledger. Keep legacy consent provenance and audit rows.
ALTER TABLE private.candidate_resume_shares
 ALTER COLUMN document_id DROP NOT NULL, ALTER COLUMN object_id DROP NOT NULL,
 ALTER COLUMN consent_by DROP NOT NULL, ALTER COLUMN consent_at DROP NOT NULL,
 ALTER COLUMN consent_at DROP DEFAULT,
 ADD COLUMN authorization_mode text NOT NULL DEFAULT 'candidate_consent_v1',
 ADD COLUMN item_kind text NOT NULL DEFAULT 'document',
 ADD COLUMN candidate_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 ADD COLUMN source_token text,
 ADD COLUMN item_key text GENERATED ALWAYS AS (CASE WHEN item_kind='document' THEN document_id::text ELSE item_kind END) STORED,
 ADD CONSTRAINT candidate_sharing_mode_check CHECK (
  (authorization_mode='candidate_consent_v1' AND item_kind='document' AND consent_by IS NOT NULL AND consent_at IS NOT NULL)
  OR (authorization_mode='admin_v2' AND candidate_user_id IS NOT NULL AND source_token IS NOT NULL)),
 ADD CONSTRAINT candidate_sharing_item_check CHECK (
  (item_kind='document' AND document_id IS NOT NULL AND object_id IS NOT NULL)
  OR (item_kind IN ('bank','uan','esic') AND document_id IS NULL AND object_id IS NULL AND authorization_mode='admin_v2')),
 ADD CONSTRAINT candidate_sharing_item_unique UNIQUE(application_id,item_key,recipient_type,recipient_id);
ALTER TABLE private.candidate_resume_shares ALTER COLUMN authorization_mode SET DEFAULT 'admin_v2';
ALTER TABLE public.candidate_onboarding_details
 ADD COLUMN bank_account_number text,
 ADD COLUMN sharing_revision uuid NOT NULL DEFAULT gen_random_uuid(),
 ADD CONSTRAINT candidate_onboarding_full_account_check CHECK(bank_account_number IS NULL OR (
  bank_account_number ~ '^[0-9]{6,20}$' AND bank_account_last4 IS NOT NULL AND bank_account_fingerprint IS NOT NULL
  AND right(bank_account_number,4)=bank_account_last4
  AND encode(sha256(convert_to(bank_account_number,'UTF8')),'hex')=bank_account_fingerprint));
-- No full number can be reconstructed from a historical hash. Existing rows stay NULL.
REVOKE ALL ON public.candidate_onboarding_details,private.candidate_resume_shares FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.rotate_onboarding_share_revision()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN NEW.sharing_revision:=gen_random_uuid(); RETURN NEW; END;
$$;
CREATE TRIGGER candidate_onboarding_sharing_revision BEFORE UPDATE ON public.candidate_onboarding_details
FOR EACH ROW EXECUTE FUNCTION private.rotate_onboarding_share_revision();

CREATE OR REPLACE FUNCTION public.update_candidate_onboarding_details(p_account_holder_name text,p_bank_name text,p_bank_account_number text,p_ifsc text,p_has_existing_uan boolean,p_uan_number text,p_has_existing_esic_ip boolean,p_esic_ip_number text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid:=private.current_candidate_portal_id();v_old public.candidate_onboarding_details%ROWTYPE;
 v_account text:=nullif(btrim(p_bank_account_number),'');v_uan text:=nullif(btrim(p_uan_number),'');v_esic text:=nullif(btrim(p_esic_ip_number),'');v_ifsc text:=upper(btrim(coalesce(p_ifsc,'')));
BEGIN
 IF v_id IS NULL THEN RAISE EXCEPTION 'Active Candidate Portal access is required'; END IF;
 -- Serialize first insert and updates for the same candidate as well as concurrent saves.
 PERFORM 1 FROM public.candidates WHERE id=v_id FOR UPDATE;
 SELECT * INTO v_old FROM public.candidate_onboarding_details WHERE candidate_id=v_id FOR UPDATE;
 v_account:=coalesce(v_account,v_old.bank_account_number);
 IF p_has_existing_uan THEN v_uan:=coalesce(v_uan,v_old.uan_number); ELSE v_uan:=NULL; END IF;
 IF p_has_existing_esic_ip THEN v_esic:=coalesce(v_esic,v_old.esic_ip_number); ELSE v_esic:=NULL; END IF;
 IF length(btrim(coalesce(p_account_holder_name,''))) NOT BETWEEN 1 AND 160
  OR length(btrim(coalesce(p_bank_name,''))) NOT BETWEEN 1 AND 160
  OR v_account IS NULL OR v_account !~ '^[0-9]{6,20}$' OR v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$'
  OR (p_has_existing_uan AND (v_uan IS NULL OR v_uan !~ '^[0-9]{12}$'))
  OR (p_has_existing_esic_ip AND (v_esic IS NULL OR v_esic !~ '^[0-9]{10,17}$')) THEN
  RAISE EXCEPTION 'Joining onboarding details are invalid';
 END IF;
 INSERT INTO public.candidate_onboarding_details(candidate_id,account_holder_name,bank_name,bank_account_number,bank_account_fingerprint,bank_account_last4,ifsc,has_existing_uan,uan_number,has_existing_esic_ip,esic_ip_number)
 VALUES(v_id,btrim(p_account_holder_name),btrim(p_bank_name),v_account,encode(sha256(convert_to(v_account,'UTF8')),'hex'),right(v_account,4),v_ifsc,coalesce(p_has_existing_uan,false),v_uan,coalesce(p_has_existing_esic_ip,false),v_esic)
 ON CONFLICT(candidate_id) DO UPDATE SET account_holder_name=excluded.account_holder_name,bank_name=excluded.bank_name,
 bank_account_number=excluded.bank_account_number,bank_account_fingerprint=excluded.bank_account_fingerprint,bank_account_last4=excluded.bank_account_last4,ifsc=excluded.ifsc,
 has_existing_uan=excluded.has_existing_uan,uan_number=excluded.uan_number,has_existing_esic_ip=excluded.has_existing_esic_ip,esic_ip_number=excluded.esic_ip_number;
 INSERT INTO public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 VALUES(auth.uid(),'candidate','candidate.onboarding_details_updated','candidate',v_id,'candidate',jsonb_build_object('bank_updated',true,'uan_declared',coalesce(p_has_existing_uan,false),'esic_declared',coalesce(p_has_existing_esic_ip,false)));
 RETURN true;
END;
$$;

CREATE FUNCTION private.application_sharing_candidate_active(p_application_id uuid,p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.candidate_applications a JOIN public.candidates c ON c.id=a.candidate_id
 JOIN public.platform_users u ON u.user_id=c.user_id AND u.account_type='candidate' AND u.account_status='active'
 WHERE a.id=p_application_id AND c.user_id=p_user_id AND c.profile_status='active' AND c.status<>'inactive'
 AND (SELECT count(*) FROM public.candidates owned WHERE owned.user_id=c.user_id AND owned.profile_status='active' AND owned.status<>'inactive')=1);
$$;

CREATE FUNCTION private.application_sharing_items(p_application_id uuid)
RETURNS TABLE(item_key text,item_kind text,document_id uuid,label text,mime_type text,available boolean,source_token text,object_id uuid,object_version text,object_updated_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 -- Older genuine Storage schemas have no delete-marker field. Present true/null values must remain unavailable.
 SELECT d.id::text,'document'::text,d.id,d.display_file_name,d.mime_type,
 d.verification_status='verified' AND o.id IS NOT NULL AND coalesce(to_jsonb(o)->'is_delete_marker','false'::jsonb)='false'::jsonb AND private.application_sharing_candidate_active(a.id,c.user_id),
 md5(jsonb_build_array(d.id,d.updated_at,d.verification_status,o.id,o.version,o.updated_at)::text),o.id,o.version,o.updated_at
 FROM public.candidate_applications a JOIN public.candidates c ON c.id=a.candidate_id
 JOIN public.candidate_documents d ON d.candidate_id=a.candidate_id AND d.active
 LEFT JOIN storage.objects o ON o.bucket_id='candidate-private' AND o.name=d.storage_object_name
 WHERE a.id=p_application_id AND d.mime_type IN ('application/pdf','image/jpeg','image/png')
 UNION ALL
 SELECT k.kind,k.kind,NULL::uuid,
 CASE k.kind WHEN 'bank' THEN CASE WHEN n.bank_account_number IS NULL THEN 'Bank details — full account number not saved' ELSE 'Bank details' END WHEN 'uan' THEN 'UAN (PF) details' ELSE 'ESIC details' END,
 NULL::text,
 private.application_sharing_candidate_active(a.id,c.user_id) AND CASE k.kind WHEN 'bank' THEN n.bank_account_number IS NOT NULL WHEN 'uan' THEN n.has_existing_uan IS NOT NULL ELSE n.has_existing_esic_ip IS NOT NULL END,
 n.sharing_revision::text,NULL::uuid,NULL::text,NULL::timestamptz
 FROM public.candidate_applications a JOIN public.candidates c ON c.id=a.candidate_id
 LEFT JOIN public.candidate_onboarding_details n ON n.candidate_id=a.candidate_id
 CROSS JOIN (VALUES('bank'::text),('uan'::text),('esic'::text)) k(kind) WHERE a.id=p_application_id;
$$;

CREATE OR REPLACE FUNCTION private.resume_share_effective(p_share_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM private.candidate_resume_shares s
 JOIN private.application_sharing_items(s.application_id) i ON i.item_key=s.item_key
 JOIN private.resume_application_recipients(s.application_id) r ON r.recipient_type=s.recipient_type AND r.recipient_id=s.recipient_id
 WHERE s.id=p_share_id AND s.shared_at IS NOT NULL AND s.share_revoked_at IS NULL AND i.available
 AND private.application_sharing_candidate_active(s.application_id,CASE WHEN s.authorization_mode='admin_v2' THEN s.candidate_user_id ELSE s.consent_by END)
 AND ((s.authorization_mode='admin_v2' AND i.source_token=s.source_token)
 OR (s.authorization_mode='candidate_consent_v1' AND s.consent_revoked_at IS NULL AND i.object_id=s.object_id
 AND i.object_version IS NOT DISTINCT FROM s.object_version AND i.object_updated_at IS NOT DISTINCT FROM s.object_updated_at)));
$$;

CREATE FUNCTION private.application_document_sharing_context(p_application_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('application_id',a.id,'requirement_code',r.requirement_code,'items',coalesce((
 SELECT jsonb_agg(jsonb_build_object('item_key',i.item_key,'item_kind',i.item_kind,'document_id',i.document_id,'label',i.label,'mime_type',i.mime_type,
 'available',i.available,'source_token',i.source_token,'recipient_type',t.recipient_type,'recipient_id',t.recipient_id,'recipient_name',t.recipient_name,
 'share_id',s.id,'revision',s.revision,'shared',private.resume_share_effective(s.id),'has_grant',s.shared_at IS NOT NULL AND s.share_revoked_at IS NULL)
 ORDER BY t.recipient_type,t.recipient_id,i.item_kind,i.label,i.item_key)
 FROM private.resume_application_recipients(a.id) t CROSS JOIN private.application_sharing_items(a.id) i
 LEFT JOIN private.candidate_resume_shares s ON s.application_id=a.id AND s.item_key=i.item_key AND s.recipient_type=t.recipient_type AND s.recipient_id=t.recipient_id),'[]'::jsonb))
 FROM public.candidate_applications a JOIN public.employer_requirements r ON r.id=a.requirement_id WHERE a.id=p_application_id;
$$;

CREATE FUNCTION public.admin_list_application_document_sharing(p_application_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_result jsonb;
BEGIN
 IF NOT coalesce(private.can_verify_candidate_documents(),false) THEN RAISE EXCEPTION 'Admin document sharing access is required'; END IF;
 v_result:=private.application_document_sharing_context(p_application_id);
 IF v_result IS NULL THEN RAISE EXCEPTION 'Application is not available'; END IF;
 RETURN v_result;
END;
$$;
CREATE FUNCTION public.get_candidate_document_sharing(p_requirement_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_candidate uuid:=private.current_candidate_portal_id();v_app uuid;
BEGIN
 IF v_candidate IS NULL THEN RAISE EXCEPTION 'Candidate access is required'; END IF;
 SELECT a.id INTO v_app FROM public.candidate_applications a JOIN public.employer_requirements r ON r.id=a.requirement_id WHERE a.candidate_id=v_candidate AND r.requirement_code=p_requirement_code;
 IF v_app IS NULL THEN RAISE EXCEPTION 'Application is not available'; END IF;
 RETURN private.application_document_sharing_context(v_app);
END;
$$;

CREATE FUNCTION public.admin_set_application_document_share(p_application_id uuid,p_item_key text,p_recipient_type text,p_recipient_id uuid,p_source_token text,p_revision uuid,p_share boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_app public.candidate_applications%ROWTYPE;v_user uuid;v_item record;v_grant private.candidate_resume_shares%ROWTYPE;v_id uuid;
BEGIN
 IF NOT coalesce(private.can_verify_candidate_documents(),false) OR p_share IS NULL THEN RAISE EXCEPTION 'Admin document sharing access is required'; END IF;
 SELECT * INTO v_app FROM public.candidate_applications WHERE id=p_application_id FOR UPDATE;
 IF v_app.id IS NULL THEN RAISE EXCEPTION 'Application is not available'; END IF;
 SELECT user_id INTO v_user FROM public.candidates WHERE id=v_app.candidate_id FOR SHARE;
 -- Source locks precede grant locks; changed values invalidate all earlier grants.
 PERFORM 1 FROM public.candidate_onboarding_details WHERE candidate_id=v_app.candidate_id FOR SHARE;
 PERFORM 1 FROM public.candidate_documents WHERE candidate_id=v_app.candidate_id AND id::text=p_item_key FOR SHARE;
 PERFORM 1 FROM storage.objects o JOIN public.candidate_documents d ON o.bucket_id='candidate-private' AND o.name=d.storage_object_name
 WHERE d.candidate_id=v_app.candidate_id AND d.id::text=p_item_key FOR SHARE OF o;
 SELECT * INTO v_grant FROM private.candidate_resume_shares s WHERE s.application_id=p_application_id AND s.item_key=p_item_key AND s.recipient_type=p_recipient_type AND s.recipient_id=p_recipient_id FOR UPDATE;
 IF v_grant.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Sharing details changed; reload this application'; END IF;
 IF NOT p_share THEN
  IF v_grant.id IS NULL OR v_grant.shared_at IS NULL OR v_grant.share_revoked_at IS NOT NULL THEN RETURN true; END IF;
  UPDATE private.candidate_resume_shares SET share_revoked_at=now(),revision=gen_random_uuid() WHERE id=v_grant.id;
  v_id:=v_grant.id;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM private.resume_application_recipients(p_application_id) r WHERE r.recipient_type=p_recipient_type AND r.recipient_id=p_recipient_id) THEN RAISE EXCEPTION 'Recipient is not available'; END IF;
  SELECT * INTO v_item FROM private.application_sharing_items(p_application_id) i WHERE i.item_key=p_item_key;
  IF NOT FOUND OR NOT coalesce(v_item.available,false) OR v_item.source_token IS DISTINCT FROM p_source_token THEN RAISE EXCEPTION 'Item is unavailable or changed; reload this application'; END IF;
  IF private.resume_share_effective(v_grant.id) THEN RETURN true; END IF;
  IF v_grant.id IS NULL THEN
   INSERT INTO private.candidate_resume_shares(application_id,document_id,item_kind,recipient_type,recipient_id,candidate_user_id,source_token,object_id,object_version,object_updated_at,shared_by,shared_at)
   VALUES(p_application_id,v_item.document_id,v_item.item_kind,p_recipient_type,p_recipient_id,v_user,v_item.source_token,v_item.object_id,v_item.object_version,v_item.object_updated_at,auth.uid(),now()) RETURNING id INTO v_id;
  ELSE
   UPDATE private.candidate_resume_shares SET authorization_mode='admin_v2',candidate_user_id=v_user,source_token=v_item.source_token,
   object_id=v_item.object_id,object_version=v_item.object_version,object_updated_at=v_item.object_updated_at,
   shared_by=auth.uid(),shared_at=now(),share_revoked_at=NULL,revision=gen_random_uuid() WHERE id=v_grant.id RETURNING id INTO v_id;
  END IF;
 END IF;
 INSERT INTO public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 VALUES(auth.uid(),'staff',CASE WHEN p_share THEN 'admin.candidate_item_shared' ELSE 'admin.candidate_item_share_revoked' END,'candidate_item_share',v_id,'admin',jsonb_build_object('shared',p_share));
 RETURN true;
END;
$$;

CREATE FUNCTION public.get_shared_application_items(p_application_id uuid,p_portal text)
RETURNS TABLE(item_key text,item_kind text,document_id uuid,label text,mime_type text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_recipient uuid:=private.current_resume_recipient(p_portal);
BEGIN
 IF v_recipient IS NULL THEN RAISE EXCEPTION 'Shared information access is not available'; END IF;
 RETURN QUERY SELECT i.item_key,i.item_kind,i.document_id,i.label,i.mime_type
 FROM private.candidate_resume_shares s JOIN private.application_sharing_items(s.application_id) i ON i.item_key=s.item_key
 WHERE s.application_id=p_application_id AND s.recipient_type=p_portal AND s.recipient_id=v_recipient AND private.resume_share_effective(s.id)
 ORDER BY i.item_kind,i.label,i.item_key;
END;
$$;
CREATE FUNCTION public.get_shared_application_document_access(p_application_id uuid,p_document_id uuid,p_portal text)
RETURNS TABLE(bucket_name text,object_name text,mime_type text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 RETURN QUERY SELECT 'candidate-private'::text,d.storage_object_name,d.mime_type FROM public.get_shared_application_items(p_application_id,p_portal) i
 JOIN public.candidate_documents d ON d.id=i.document_id WHERE d.id=p_document_id;
END;
$$;
CREATE FUNCTION private.application_joining_detail(p_application_id uuid,p_item_key text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE p_item_key WHEN 'bank' THEN jsonb_build_object('account_holder_name',n.account_holder_name,'bank_name',n.bank_name,'bank_account_number',n.bank_account_number,'bank_account_last4',n.bank_account_last4,'ifsc',n.ifsc,'full_account_available',n.bank_account_number IS NOT NULL)
 WHEN 'uan' THEN jsonb_build_object('has_existing_uan',n.has_existing_uan,'uan_number',n.uan_number)
 WHEN 'esic' THEN jsonb_build_object('has_existing_esic_ip',n.has_existing_esic_ip,'esic_ip_number',n.esic_ip_number) END
 FROM public.candidate_applications a JOIN public.candidate_onboarding_details n ON n.candidate_id=a.candidate_id WHERE a.id=p_application_id;
$$;
CREATE FUNCTION public.admin_get_application_joining_detail(p_application_id uuid,p_item_key text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT coalesce(private.can_verify_candidate_documents(),false) THEN RAISE EXCEPTION 'Admin document access is required'; END IF;
 IF p_item_key NOT IN ('bank','uan','esic') OR p_item_key IS NULL THEN RAISE EXCEPTION 'Joining detail is not available'; END IF;
 RETURN private.application_joining_detail(p_application_id,p_item_key);
END;
$$;
CREATE FUNCTION public.get_shared_application_joining_detail(p_application_id uuid,p_item_key text,p_portal text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_item_key NOT IN ('bank','uan','esic') OR NOT EXISTS(SELECT 1 FROM public.get_shared_application_items(p_application_id,p_portal) i WHERE i.item_key=p_item_key) THEN RAISE EXCEPTION 'Joining detail is not available'; END IF;
 RETURN private.application_joining_detail(p_application_id,p_item_key);
END;
$$;
-- Retire candidate-controlled consent and stale Admin mutation endpoints. No consent is forged.
CREATE OR REPLACE FUNCTION public.set_candidate_resume_consent(p_application_id uuid,p_document_id uuid,p_recipient_type text,p_recipient_id uuid,p_allow boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'Sharing is managed by Admin; reload this application'; END;
$$;
CREATE OR REPLACE FUNCTION public.admin_set_application_resume_share(p_consent_id uuid,p_revision uuid,p_share boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'Sharing has changed; reload this application'; END;
$$;
-- Legacy recipients may see only resumes, never the new document types/details through a stale UI.
CREATE OR REPLACE FUNCTION public.get_shared_application_resume(p_application_id uuid,p_portal text)
RETURNS TABLE(document_id uuid,display_file_name text,verification_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 RETURN QUERY SELECT d.id,d.display_file_name,d.verification_status FROM public.get_shared_application_items(p_application_id,p_portal) i
 JOIN public.candidate_documents d ON d.id=i.document_id WHERE d.document_type='resume';
END;
$$;
