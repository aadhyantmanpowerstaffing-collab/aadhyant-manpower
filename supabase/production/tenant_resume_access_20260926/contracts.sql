-- Additive Admin-controlled resume disclosure. Packaged with guards by build_package.py.
CREATE TABLE private.candidate_resume_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.candidate_applications(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL REFERENCES public.candidate_documents(id) ON DELETE RESTRICT,
  recipient_type text NOT NULL CHECK (recipient_type IN ('company','contractor')),
  recipient_id uuid NOT NULL,
  consent_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  consent_at timestamptz NOT NULL DEFAULT now(),
  consent_revoked_at timestamptz,
  consent_version text NOT NULL DEFAULT 'application-resume-v1' CHECK (consent_version='application-resume-v1'),
  revision uuid NOT NULL DEFAULT gen_random_uuid(),
  object_id uuid NOT NULL,
  object_version text,
  object_updated_at timestamptz,
  shared_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  shared_at timestamptz,
  share_revoked_at timestamptz,
  UNIQUE(application_id,document_id,recipient_type,recipient_id),
  CHECK ((shared_by IS NULL)=(shared_at IS NULL)),
  CHECK (share_revoked_at IS NULL OR shared_at IS NOT NULL)
);
CREATE INDEX candidate_resume_shares_document_idx ON private.candidate_resume_shares(document_id);
CREATE INDEX candidate_resume_shares_recipient_idx ON private.candidate_resume_shares(recipient_type,recipient_id) WHERE consent_revoked_at IS NULL AND shared_at IS NOT NULL AND share_revoked_at IS NULL;
ALTER TABLE private.candidate_resume_shares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.candidate_resume_shares FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.resume_application_recipients(p_application_id uuid)
RETURNS TABLE(recipient_type text,recipient_id uuid,recipient_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT 'company'::text,c.id,c.legal_name
  FROM public.candidate_applications a JOIN public.employer_requirements r ON r.id=a.requirement_id
  JOIN public.companies c ON c.id=r.company_id
  WHERE a.id=p_application_id AND c.account_status='active'
    AND a.application_status IN ('applied','screening','shortlisted','interview','selected','joining_pending','joined')
  UNION ALL
  SELECT 'contractor'::text,c.id,c.agency_name
  FROM public.candidate_applications a JOIN public.requirement_contractors rc ON rc.requirement_id=a.requirement_id
  JOIN public.contractors c ON c.id=rc.contractor_id
  WHERE a.id=p_application_id AND c.account_status='active' AND rc.origin_type='contractor_submission'
    AND rc.submission_status='approved' AND rc.assignment_status IN ('assigned','accepted','active','completed')
    AND a.application_status IN ('applied','screening','shortlisted','interview','selected','joining_pending','joined');
$$;

CREATE FUNCTION private.current_resume_recipient(p_portal text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN NULL; END IF;
  IF p_portal='company' THEN
    v_id:=private.current_company_portal_id(true);
    IF NOT EXISTS(SELECT 1 FROM public.company_users u WHERE u.company_id=v_id AND u.user_id=auth.uid()
      AND u.status='active' AND u.role IN ('owner','hr_admin','recruiter')) THEN RETURN NULL; END IF;
  ELSIF p_portal='contractor' THEN
    v_id:=private.current_contractor_portal_id(true);
    IF NOT EXISTS(SELECT 1 FROM public.contractor_users u WHERE u.contractor_id=v_id AND u.user_id=auth.uid()
      AND u.status='active' AND u.role IN ('owner','manager','recruiter')) THEN RETURN NULL; END IF;
  ELSE RETURN NULL;
  END IF;
  RETURN v_id;
END;
$$;

CREATE FUNCTION private.resume_share_effective(p_share_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(
  SELECT 1 FROM private.candidate_resume_shares s
  JOIN public.candidate_applications a ON a.id=s.application_id
  JOIN public.candidates c ON c.id=a.candidate_id
  JOIN public.platform_users pu ON pu.user_id=c.user_id AND pu.account_type='candidate' AND pu.account_status='active'
  JOIN public.candidate_documents d ON d.id=s.document_id AND d.candidate_id=a.candidate_id
  JOIN storage.objects o ON o.id=s.object_id AND o.bucket_id='candidate-private' AND o.name=d.storage_object_name
  JOIN private.resume_application_recipients(s.application_id) r ON r.recipient_type=s.recipient_type AND r.recipient_id=s.recipient_id
  WHERE s.id=p_share_id AND c.profile_status='active' AND c.status<>'inactive' AND c.user_id=s.consent_by
   AND (SELECT count(*) FROM public.candidates owned WHERE owned.user_id=c.user_id AND owned.profile_status='active' AND owned.status<>'inactive')=1
   AND s.consent_revoked_at IS NULL AND s.shared_at IS NOT NULL AND s.share_revoked_at IS NULL
   AND d.active AND d.document_type='resume' AND d.mime_type='application/pdf' AND d.verification_status='verified'
   AND o.version IS NOT DISTINCT FROM s.object_version AND o.updated_at IS NOT DISTINCT FROM s.object_updated_at
 );
$$;

CREATE FUNCTION private.resume_sharing_context(p_application_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object('application_id',a.id,'requirement_code',r.requirement_code,
  'recipients',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'recipient_type',t.recipient_type,'recipient_id',t.recipient_id,'recipient_name',t.recipient_name,
   'document_id',d.id,'file_name',d.display_file_name,'verified',coalesce(d.verification_status='verified',false),
   'consent_id',s.id,'revision',s.revision,
   'consented',coalesce(s.consent_revoked_at IS NULL AND s.consent_by=c.user_id AND s.object_id=o.id
      AND s.object_version IS NOT DISTINCT FROM o.version AND s.object_updated_at IS NOT DISTINCT FROM o.updated_at,false),
   'shared',coalesce(private.resume_share_effective(s.id),false),
   'has_grant',s.shared_at IS NOT NULL AND s.share_revoked_at IS NULL)
   ORDER BY t.recipient_type,t.recipient_id)
   FROM private.resume_application_recipients(a.id) t
   LEFT JOIN public.candidate_documents d ON d.candidate_id=a.candidate_id AND d.document_type='resume' AND d.active AND d.mime_type='application/pdf'
   LEFT JOIN storage.objects o ON o.bucket_id='candidate-private' AND o.name=d.storage_object_name
   LEFT JOIN private.candidate_resume_shares s ON s.application_id=a.id AND s.document_id=d.id AND s.recipient_type=t.recipient_type AND s.recipient_id=t.recipient_id),'[]'::jsonb))
 FROM public.candidate_applications a JOIN public.employer_requirements r ON r.id=a.requirement_id
 JOIN public.candidates c ON c.id=a.candidate_id WHERE a.id=p_application_id;
$$;

CREATE FUNCTION public.get_candidate_resume_sharing(p_requirement_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_candidate uuid:=private.current_candidate_portal_id();v_app uuid;
BEGIN
 IF v_candidate IS NULL THEN RAISE EXCEPTION 'Resume sharing access is required'; END IF;
 SELECT a.id INTO v_app FROM public.candidate_applications a JOIN public.employer_requirements r ON r.id=a.requirement_id
 WHERE a.candidate_id=v_candidate AND r.requirement_code=p_requirement_code;
 IF v_app IS NULL THEN RAISE EXCEPTION 'Application is not available'; END IF;
 RETURN private.resume_sharing_context(v_app);
END;
$$;

CREATE FUNCTION public.set_candidate_resume_consent(p_application_id uuid,p_document_id uuid,p_recipient_type text,p_recipient_id uuid,p_allow boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_candidate uuid:=private.current_candidate_portal_id();v_app public.candidate_applications%ROWTYPE;
 v_doc public.candidate_documents%ROWTYPE;v_obj storage.objects%ROWTYPE;v_share private.candidate_resume_shares%ROWTYPE;v_id uuid;v_action text;
BEGIN
 IF v_candidate IS NULL OR p_allow IS NULL THEN RAISE EXCEPTION 'Resume sharing access is required'; END IF;
 SELECT * INTO v_app FROM public.candidate_applications a WHERE a.id=p_application_id AND a.candidate_id=v_candidate FOR UPDATE;
 IF v_app.id IS NULL THEN RAISE EXCEPTION 'Application is not available'; END IF;
 SELECT * INTO v_share FROM private.candidate_resume_shares s WHERE s.application_id=p_application_id
  AND s.document_id=p_document_id AND s.recipient_type=p_recipient_type AND s.recipient_id=p_recipient_id FOR UPDATE;
 IF NOT p_allow THEN
  IF v_share.id IS NULL OR v_share.consent_revoked_at IS NOT NULL THEN RETURN true; END IF;
  UPDATE private.candidate_resume_shares SET consent_revoked_at=now(),revision=gen_random_uuid() WHERE id=v_share.id;
  v_id:=v_share.id;v_action:='candidate.resume_consent_revoked';
 ELSE
  IF NOT EXISTS(SELECT 1 FROM private.resume_application_recipients(p_application_id) r WHERE r.recipient_type=p_recipient_type AND r.recipient_id=p_recipient_id) THEN RAISE EXCEPTION 'Recipient is not available'; END IF;
  SELECT * INTO v_doc FROM public.candidate_documents d WHERE d.id=p_document_id AND d.candidate_id=v_candidate
   AND d.active AND d.document_type='resume' AND d.mime_type='application/pdf' FOR SHARE;
  IF v_doc.id IS NULL THEN RAISE EXCEPTION 'Active resume is required'; END IF;
  SELECT * INTO v_obj FROM storage.objects o WHERE o.bucket_id='candidate-private' AND o.name=v_doc.storage_object_name FOR SHARE;
  IF v_obj.id IS NULL THEN RAISE EXCEPTION 'Resume file is not available'; END IF;
  IF v_share.id IS NOT NULL AND v_share.consent_revoked_at IS NULL AND v_share.consent_by=auth.uid()
    AND v_share.object_id=v_obj.id AND v_share.object_version IS NOT DISTINCT FROM v_obj.version
    AND v_share.object_updated_at IS NOT DISTINCT FROM v_obj.updated_at THEN RETURN true; END IF;
  INSERT INTO private.candidate_resume_shares(application_id,document_id,recipient_type,recipient_id,consent_by,object_id,object_version,object_updated_at)
   VALUES(p_application_id,p_document_id,p_recipient_type,p_recipient_id,auth.uid(),v_obj.id,v_obj.version,v_obj.updated_at)
   ON CONFLICT(application_id,document_id,recipient_type,recipient_id) DO UPDATE SET
    consent_by=auth.uid(),consent_at=now(),consent_revoked_at=NULL,revision=gen_random_uuid(),
    object_id=EXCLUDED.object_id,object_version=EXCLUDED.object_version,object_updated_at=EXCLUDED.object_updated_at,
    shared_by=NULL,shared_at=NULL,share_revoked_at=NULL RETURNING id INTO v_id;
  v_action:='candidate.resume_consent_granted';
 END IF;
 INSERT INTO public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 VALUES(auth.uid(),'candidate',v_action,'resume_share',v_id,'candidate',jsonb_build_object('allowed',p_allow,'version','application-resume-v1'));
 RETURN true;
END;
$$;

CREATE FUNCTION public.admin_list_application_resume_sharing(p_application_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_result jsonb;
BEGIN
 IF NOT coalesce(private.can_verify_candidate_documents(),false) THEN RAISE EXCEPTION 'Admin resume sharing access is required'; END IF;
 v_result:=private.resume_sharing_context(p_application_id);
 IF v_result IS NULL THEN RAISE EXCEPTION 'Application is not available'; END IF;
 RETURN v_result;
END;
$$;

CREATE FUNCTION public.admin_set_application_resume_share(p_consent_id uuid,p_revision uuid,p_share boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_share private.candidate_resume_shares%ROWTYPE;v_app uuid;v_doc public.candidate_documents%ROWTYPE;v_candidate public.candidates%ROWTYPE;
BEGIN
 IF NOT coalesce(private.can_verify_candidate_documents(),false) OR p_share IS NULL THEN RAISE EXCEPTION 'Admin resume sharing access is required'; END IF;
 SELECT s.application_id INTO v_app FROM private.candidate_resume_shares s WHERE s.id=p_consent_id;
 PERFORM 1 FROM public.candidate_applications a WHERE a.id=v_app FOR UPDATE;
 SELECT * INTO v_share FROM private.candidate_resume_shares s WHERE s.id=p_consent_id FOR UPDATE;
 IF v_share.id IS NULL OR v_share.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'Sharing details changed; reload this application'; END IF;
 IF p_share THEN
  SELECT c.* INTO v_candidate FROM public.candidates c JOIN public.candidate_applications a ON a.candidate_id=c.id WHERE a.id=v_app;
  IF v_share.consent_revoked_at IS NOT NULL OR v_candidate.user_id IS DISTINCT FROM v_share.consent_by OR v_candidate.profile_status<>'active' OR v_candidate.status='inactive'
    OR (SELECT count(*) FROM public.candidates owned WHERE owned.user_id=v_candidate.user_id AND owned.profile_status='active' AND owned.status<>'inactive')<>1
    OR NOT EXISTS(SELECT 1 FROM public.platform_users pu WHERE pu.user_id=v_candidate.user_id AND pu.account_type='candidate' AND pu.account_status='active')
    OR NOT EXISTS(SELECT 1 FROM private.resume_application_recipients(v_app) r WHERE r.recipient_type=v_share.recipient_type AND r.recipient_id=v_share.recipient_id)
   THEN RAISE EXCEPTION 'Current Candidate consent and recipient access are required'; END IF;
  SELECT * INTO v_doc FROM public.candidate_documents d WHERE d.id=v_share.document_id AND d.candidate_id=v_candidate.id
   AND d.active AND d.document_type='resume' AND d.mime_type='application/pdf' AND d.verification_status='verified' FOR SHARE;
  IF v_doc.id IS NULL THEN RAISE EXCEPTION 'An active verified resume is required'; END IF;
  PERFORM 1 FROM storage.objects o WHERE o.id=v_share.object_id AND o.bucket_id='candidate-private' AND o.name=v_doc.storage_object_name
   AND o.version IS NOT DISTINCT FROM v_share.object_version AND o.updated_at IS NOT DISTINCT FROM v_share.object_updated_at FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Resume file changed; new consent is required'; END IF;
  IF v_share.shared_at IS NOT NULL AND v_share.share_revoked_at IS NULL THEN RETURN true; END IF;
  UPDATE private.candidate_resume_shares SET shared_by=auth.uid(),shared_at=now(),share_revoked_at=NULL,revision=gen_random_uuid() WHERE id=p_consent_id;
 ELSE
  IF v_share.shared_at IS NULL OR v_share.share_revoked_at IS NOT NULL THEN RETURN true; END IF;
  UPDATE private.candidate_resume_shares SET share_revoked_at=now(),revision=gen_random_uuid() WHERE id=p_consent_id;
 END IF;
 INSERT INTO public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 VALUES(auth.uid(),'staff',CASE WHEN p_share THEN 'admin.resume_shared' ELSE 'admin.resume_share_revoked' END,
  'resume_share',p_consent_id,'admin',jsonb_build_object('shared',p_share));
 RETURN true;
END;
$$;

CREATE FUNCTION public.get_shared_application_resume(p_application_id uuid,p_portal text)
RETURNS TABLE(document_id uuid,display_file_name text,verification_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_recipient uuid:=private.current_resume_recipient(p_portal);
BEGIN
 IF v_recipient IS NULL THEN RAISE EXCEPTION 'Resume access is not available'; END IF;
 RETURN QUERY SELECT d.id,d.display_file_name,d.verification_status FROM private.candidate_resume_shares s
 JOIN public.candidate_documents d ON d.id=s.document_id
 WHERE s.application_id=p_application_id AND s.recipient_type=p_portal AND s.recipient_id=v_recipient AND private.resume_share_effective(s.id);
END;
$$;

CREATE FUNCTION public.get_shared_application_resume_access(p_application_id uuid,p_document_id uuid,p_portal text)
RETURNS TABLE(bucket_name text,object_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 RETURN QUERY SELECT 'candidate-private'::text,d.storage_object_name FROM public.get_shared_application_resume(p_application_id,p_portal) a
 JOIN public.candidate_documents d ON d.id=a.document_id WHERE a.document_id=p_document_id;
END;
$$;

CREATE FUNCTION private.can_read_shared_candidate_resume(p_object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM private.candidate_resume_shares s JOIN public.candidate_documents d ON d.id=s.document_id
 WHERE d.storage_object_name=p_object_name AND s.recipient_id=private.current_resume_recipient(s.recipient_type)
  AND private.resume_share_effective(s.id));
$$;
CREATE POLICY "Recipients read Admin shared resumes" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='candidate-private' AND private.can_read_shared_candidate_resume(name));
