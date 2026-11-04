-- Local-only baseline fixture for the historical 2026-09-28 candidate preference migration.
-- Definitions are read from the current Production catalog for faithful local replay.
-- This file is never applied to Production and does not grant client privileges.
CREATE OR REPLACE FUNCTION public.get_candidate_whatsapp_alert_preference()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_candidate uuid := (SELECT private.current_candidate_portal_id());
  v_mobile text;
  v_profile_token text;
  v_contact public.whatsapp_contacts%rowtype;
  v_available boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR v_candidate IS NULL THEN
    RAISE EXCEPTION 'Active Candidate access is required' USING ERRCODE='42501';
  END IF;
  SELECT c.mobile,pg_catalog.md5(c.id::text||':'||c.user_id::text||':'||c.mobile)
    INTO STRICT v_mobile,v_profile_token FROM public.candidates c WHERE c.id=v_candidate;
  SELECT w.* INTO v_contact FROM public.whatsapp_contacts w
    WHERE w.provider='whatsapp' AND w.candidate_id=v_candidate;
  v_available := (SELECT count(*)=1 FROM public.candidates c
    WHERE c.mobile=v_mobile AND c.profile_status='active' AND c.status<>'inactive')
    AND (v_contact.id IS NULL OR (v_contact.indian_mobile_key=v_mobile AND v_contact.resolution_status='resolved'))
    AND NOT EXISTS (SELECT 1 FROM public.whatsapp_contacts w
      WHERE w.provider='whatsapp' AND w.indian_mobile_key=v_mobile
        AND (w.resolution_status IN ('blocked','ambiguous') OR w.candidate_id IS DISTINCT FROM v_candidate));
  RETURN pg_catalog.jsonb_build_object(
    'marketing_status',coalesce(v_contact.marketing_consent_status,'unknown'),
    'phone_masked','+91 ******'||pg_catalog.right(v_mobile,4),
    'updated_at',v_contact.updated_at,
    'profile_token',v_profile_token,
    'policy_version','candidate-job-alerts-v1',
    'enrollment_available',v_available,
    'effective_opt_in',coalesce(private.whatsapp_contact_allows_purpose(v_contact.id,'marketing'),false));
END $function$;

CREATE OR REPLACE FUNCTION public.set_candidate_whatsapp_alert_preference(p_opt_in boolean, p_expected_updated_at timestamp with time zone, p_policy_version text, p_profile_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_candidate uuid;
  v_mobile text;
  v_contact public.whatsapp_contacts%rowtype;
  v_before text;
  v_profile_token text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Active Candidate access is required' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.platform_users pu WHERE pu.user_id=v_user
    AND pu.account_type='candidate' AND pu.account_status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active Candidate access is required' USING ERRCODE='42501'; END IF;
  v_candidate := private.current_candidate_portal_id();
  IF v_candidate IS NULL THEN RAISE EXCEPTION 'Active Candidate access is required' USING ERRCODE='42501'; END IF;
  SELECT c.mobile,pg_catalog.md5(c.id::text||':'||c.user_id::text||':'||c.mobile)
    INTO STRICT v_mobile,v_profile_token FROM public.candidates c
    WHERE c.id=v_candidate AND c.user_id=v_user AND c.profile_status='active' AND c.status<>'inactive' FOR UPDATE;
  IF p_opt_in IS NULL OR p_policy_version IS DISTINCT FROM 'candidate-job-alerts-v1' THEN
    RAISE EXCEPTION 'Refresh WhatsApp preferences before saving' USING ERRCODE='22023';
  END IF;
  IF p_profile_token IS DISTINCT FROM v_profile_token THEN
    RAISE EXCEPTION 'Candidate profile changed; refresh before saving' USING ERRCODE='PT409';
  END IF;
  SELECT w.* INTO v_contact FROM public.whatsapp_contacts w
    WHERE w.provider='whatsapp' AND w.candidate_id=v_candidate FOR UPDATE;
  IF p_opt_in THEN
    IF (SELECT count(*) FROM public.candidates c WHERE c.mobile=v_mobile
        AND c.profile_status='active' AND c.status<>'inactive')<>1
       OR (v_contact.id IS NOT NULL AND
         (v_contact.indian_mobile_key<>v_mobile OR v_contact.resolution_status<>'resolved')) THEN
      RAISE EXCEPTION 'WhatsApp number requires account review' USING ERRCODE='22023';
    END IF;
    IF v_contact.id IS NULL THEN
      IF EXISTS (SELECT 1 FROM public.whatsapp_contacts w WHERE w.provider='whatsapp'
        AND w.provider_address='+91'||v_mobile) THEN
        RAISE EXCEPTION 'WhatsApp number requires account review' USING ERRCODE='22023';
      END IF;
      IF p_expected_updated_at IS NOT NULL THEN
        RAISE EXCEPTION 'WhatsApp preference changed; refresh before saving' USING ERRCODE='PT409';
      END IF;
      INSERT INTO public.whatsapp_contacts(provider,provider_address,indian_mobile_key,candidate_id,resolution_status)
        VALUES('whatsapp','+91'||v_mobile,v_mobile,v_candidate,'resolved')
        ON CONFLICT DO NOTHING RETURNING * INTO v_contact;
      IF NOT FOUND THEN RAISE EXCEPTION 'WhatsApp preference changed; refresh before saving' USING ERRCODE='PT409'; END IF;
    ELSIF v_contact.updated_at IS DISTINCT FROM p_expected_updated_at THEN
      RAISE EXCEPTION 'WhatsApp preference changed; refresh before saving' USING ERRCODE='PT409';
    END IF;
  ELSE
    IF v_contact.id IS NULL THEN RETURN public.get_candidate_whatsapp_alert_preference(); END IF;
    IF v_contact.updated_at IS DISTINCT FROM p_expected_updated_at THEN
      RAISE EXCEPTION 'WhatsApp preference changed; refresh before saving' USING ERRCODE='PT409';
    END IF;
  END IF;
  v_before := v_contact.marketing_consent_status;
  IF v_before=(CASE WHEN p_opt_in THEN 'opted_in' ELSE 'opted_out' END) THEN
    RETURN public.get_candidate_whatsapp_alert_preference();
  END IF;
  UPDATE public.whatsapp_contacts SET
    marketing_consent_status=CASE WHEN p_opt_in THEN 'opted_in' ELSE 'opted_out' END,
    consent_source=CASE WHEN p_opt_in THEN 'candidate_portal' ELSE consent_source END,
    consent_scope=CASE WHEN p_opt_in THEN 'vacancy_alerts' ELSE consent_scope END,
    consent_recorded_at=CASE WHEN p_opt_in THEN pg_catalog.clock_timestamp() ELSE consent_recorded_at END,
    consent_policy_version=CASE WHEN p_opt_in THEN p_policy_version ELSE consent_policy_version END,
    opted_out_at=CASE WHEN p_opt_in THEN NULL ELSE pg_catalog.clock_timestamp() END,
    opt_out_source=CASE WHEN p_opt_in THEN NULL ELSE 'candidate_portal' END,
    opt_out_reason_category=CASE WHEN p_opt_in THEN NULL ELSE 'job_alerts_disabled' END,
    updated_at=pg_catalog.clock_timestamp()
    WHERE id=v_contact.id;
  INSERT INTO public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    VALUES(v_user,'candidate','whatsapp.marketing_preference_changed','whatsapp_contact',v_contact.id,'candidate',
      pg_catalog.jsonb_build_object('opted_in',p_opt_in,'previous_status',v_before,'policy_version',p_policy_version));
  RETURN public.get_candidate_whatsapp_alert_preference();
END $function$;
