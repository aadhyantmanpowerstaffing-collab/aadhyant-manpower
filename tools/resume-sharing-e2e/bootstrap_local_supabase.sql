-- FRESH LOCAL SUPABASE ONLY. Genuine managed Auth/Storage preserved.
BEGIN;
DO $$ BEGIN
 IF current_setting('aadhyant.resume_fixture',true) IS DISTINCT FROM 'local-only' THEN
  RAISE EXCEPTION 'Explicit disposable fixture context required';
 END IF;
 IF to_regclass('public.candidates') IS NOT NULL OR to_regclass('storage.objects') IS NULL OR to_regclass('auth.users') IS NULL THEN
  RAISE EXCEPTION 'Fresh genuine Supabase stack required';
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;
CREATE TABLE public.admin_users("user_id" uuid NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.audit_logs("id" uuid DEFAULT gen_random_uuid() NOT NULL,"actor_user_id" uuid,"actor_type" text NOT NULL,"action" text NOT NULL,"entity_type" text NOT NULL,"entity_id" uuid,"source" text NOT NULL,"correlation_id" uuid,"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.candidate_applications("id" uuid DEFAULT gen_random_uuid() NOT NULL,"candidate_id" uuid NOT NULL,"requirement_id" uuid NOT NULL,"requirement_contractor_id" uuid,"source_type" text DEFAULT 'direct'::text NOT NULL,"application_status" text DEFAULT 'applied'::text NOT NULL,"created_by" uuid,"applied_at" timestamp with time zone DEFAULT now() NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"admin_notes" text,"source_reference" text,"correlation_id" uuid);
CREATE TABLE public.candidate_documents("id" uuid DEFAULT gen_random_uuid() NOT NULL,"candidate_id" uuid NOT NULL,"document_type" text NOT NULL,"storage_object_name" text NOT NULL,"display_file_name" text NOT NULL,"mime_type" text NOT NULL,"file_size_bytes" bigint NOT NULL,"verification_status" text DEFAULT 'uploaded'::text NOT NULL,"verification_feedback" text,"active" boolean DEFAULT true NOT NULL,"uploaded_at" timestamp with time zone DEFAULT now() NOT NULL,"verified_at" timestamp with time zone,"verified_by" uuid,"replaced_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"review_started_at" timestamp with time zone,"review_started_by" uuid,"reviewed_at" timestamp with time zone,"reviewed_by" uuid);
CREATE TABLE public.candidates("id" uuid DEFAULT gen_random_uuid() NOT NULL,"full_name" text NOT NULL,"age" integer NOT NULL,"gender" text NOT NULL,"mobile" text NOT NULL,"whatsapp_number" text,"current_location" text NOT NULL,"district" text NOT NULL,"state" text NOT NULL,"highest_qualification" text NOT NULL,"specialization" text,"candidate_type" text NOT NULL,"total_experience" text,"previous_job_role" text,"interview_available" text NOT NULL,"preferred_job_location" text,"additional_information" text,"internal_notes" text,"consent" boolean NOT NULL,"status" text DEFAULT 'new'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"user_id" uuid,"profile_status" text DEFAULT 'registered'::text NOT NULL,"profile_completion_status" text DEFAULT 'incomplete'::text NOT NULL,"current_employment_status" text DEFAULT 'unknown'::text NOT NULL,"availability_status" text DEFAULT 'unknown'::text NOT NULL,"verified_at" timestamp with time zone,"acquisition_source_type" text DEFAULT 'admin_manual'::text NOT NULL,"acquisition_source_detail" text,"acquisition_source_reference" text,"acquisition_attributed_at" timestamp with time zone DEFAULT now() NOT NULL,"owner_staff_user_id" uuid,"owner_assigned_at" timestamp with time zone,"owner_assigned_by" uuid,"next_action" text,"follow_up_due_at" timestamp with time zone,"aadhaar_fingerprint" text,"aadhaar_last4" text,"mobile_verified" boolean DEFAULT false NOT NULL,"date_of_birth" date,"pincode" text);
CREATE TABLE public.companies("id" uuid DEFAULT gen_random_uuid() NOT NULL,"legal_name" text NOT NULL,"trade_name" text,"industry" text,"gstin" text,"cin" text,"website" text,"main_phone" text,"main_email" text,"address" text,"city" text,"district" text,"state" text,"pincode" text,"verification_status" text DEFAULT 'pending'::text NOT NULL,"account_status" text DEFAULT 'pending'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"contact_person" text,"workforce_size" text,"onboarding_notes" text,"onboarding_consent_at" timestamp with time zone);
CREATE TABLE public.company_users("company_id" uuid NOT NULL,"user_id" uuid NOT NULL,"role" text DEFAULT 'recruiter'::text NOT NULL,"status" text DEFAULT 'pending'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.contractor_users("contractor_id" uuid NOT NULL,"user_id" uuid NOT NULL,"role" text DEFAULT 'recruiter'::text NOT NULL,"status" text DEFAULT 'pending'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.contractors("id" uuid DEFAULT gen_random_uuid() NOT NULL,"agency_name" text NOT NULL,"owner_name" text,"gstin" text,"esic_code" text,"epfo_code" text,"labour_license_number" text,"main_phone" text,"main_email" text,"address" text,"city" text,"district" text,"state" text,"operating_locations" text[],"workforce_capacity" integer,"verification_status" text DEFAULT 'pending'::text NOT NULL,"account_status" text DEFAULT 'pending'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"website" text,"pincode" text,"manpower_categories" text[],"onboarding_notes" text,"onboarding_consent_at" timestamp with time zone,"acquisition_source_type" text DEFAULT 'admin_manual'::text NOT NULL,"acquisition_source_detail" text,"acquisition_source_reference" text,"acquisition_attributed_at" timestamp with time zone DEFAULT now() NOT NULL,"owner_staff_user_id" uuid,"owner_assigned_at" timestamp with time zone,"owner_assigned_by" uuid,"next_action" text,"follow_up_due_at" timestamp with time zone);
CREATE TABLE public.employer_requirements("id" uuid DEFAULT gen_random_uuid() NOT NULL,"company_name" text NOT NULL,"contact_person" text NOT NULL,"mobile" text NOT NULL,"email" text,"company_location" text NOT NULL,"job_role" text NOT NULL,"required_headcount" integer NOT NULL,"qualification" text,"iti_trade" text,"experience_requirement" text,"gender_preference" text,"salary_wage" text,"shift_details" text,"working_hours" text,"expected_joining_date" date,"accommodation" text,"canteen" text,"transport" text,"additional_notes" text,"internal_notes" text,"consent" boolean NOT NULL,"status" text DEFAULT 'new'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"requirement_code" text,"company_id" uuid,"created_by_user_id" uuid,"department" text,"job_location" text,"age_min" integer,"age_max" integer,"filled_positions" integer DEFAULT 0 NOT NULL,"salary_min" numeric(12,2),"salary_max" numeric(12,2),"overtime_details" text,"interview_location" text,"interview_date" timestamp with time zone,"requirement_visibility" text DEFAULT 'private'::text NOT NULL,"requirement_stage" text DEFAULT 'draft'::text NOT NULL,"published_at" timestamp with time zone,"closed_at" timestamp with time zone,"source_type" text DEFAULT 'admin_manual'::text NOT NULL,"source_detail" text,"source_reference" text,"attributed_at" timestamp with time zone DEFAULT now() NOT NULL,"owner_staff_user_id" uuid,"owner_assigned_at" timestamp with time zone,"owner_assigned_by" uuid,"next_action" text,"follow_up_due_at" timestamp with time zone,"qualified_at" timestamp with time zone,"lost_reason" text,"operational_updated_at" timestamp with time zone DEFAULT now() NOT NULL,"review_status" text,"review_feedback" text,"submitted_at" timestamp with time zone,"reviewed_at" timestamp with time zone,"reviewed_by" uuid,"payable_days" integer,"basic_da" numeric,"attendance_bonus" numeric,"monthly_bonus" numeric,"leave_amount" numeric,"other_fixed_earning" numeric,"gross_wages" numeric,"employee_pf" numeric,"employee_esic" numeric,"canteen_deduction" numeric,"other_deduction" numeric,"employer_pf" numeric,"employer_esic" numeric,"gratuity_provision" numeric,"bonus_provision" numeric,"leave_provision" numeric,"other_ctc_component" numeric,"approx_in_hand" numeric,"ctc" numeric,"accommodation_status" text,"accommodation_charge_amount" numeric,"accommodation_charge_basis" text,"compensation_cadence" text,"paid_leave_days_per_year" integer,"casual_leave_days_per_year" integer,"sick_leave_days_per_year" integer,"national_holiday_days_per_year" integer,"festival_holiday_days_per_year" integer,"working_days_per_week" integer,"weekly_off_count" integer,"overtime_rate" numeric,"overtime_rate_basis" text,"canteen_status" text,"canteen_charge_amount" numeric,"canteen_charge_basis" text,"transport_status" text,"transport_charge_amount" numeric,"transport_charge_basis" text,"employment_type" text,"payroll_type" text,"contract_duration_months" integer,"probation_period_months" integer,"training_period_days" integer,"notice_period_days" integer);
CREATE TABLE public.platform_users("user_id" uuid NOT NULL,"account_type" text NOT NULL,"display_name" text NOT NULL,"mobile" text,"email" text,"account_status" text DEFAULT 'pending'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.requirement_contractors("id" uuid DEFAULT gen_random_uuid() NOT NULL,"requirement_id" uuid NOT NULL,"contractor_id" uuid NOT NULL,"assigned_headcount" integer NOT NULL,"assignment_status" text DEFAULT 'assigned'::text NOT NULL,"assigned_by" uuid,"assigned_at" timestamp with time zone DEFAULT now() NOT NULL,"accepted_at" timestamp with time zone,"closed_at" timestamp with time zone,"internal_notes" text,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"declined_at" timestamp with time zone,"response_notes" text,"origin_type" text DEFAULT 'internal_assignment'::text NOT NULL,"submission_status" text,"review_feedback" text,"submitted_at" timestamp with time zone,"reviewed_at" timestamp with time zone,"reviewed_by" uuid);
CREATE TABLE public.staff_profiles("user_id" uuid NOT NULL,"display_name" text NOT NULL,"status" text DEFAULT 'active'::text NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public.staff_roles("user_id" uuid NOT NULL,"role" text NOT NULL,"status" text DEFAULT 'active'::text NOT NULL,"granted_by" uuid,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.admin_users ADD CONSTRAINT "admin_users_pkey" PRIMARY KEY (user_id);
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_action_check" CHECK (((length(btrim(action)) >= 1) AND (length(btrim(action)) <= 160)));
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_actor_type_check" CHECK ((actor_type = ANY (ARRAY['staff'::text, 'company'::text, 'contractor'::text, 'candidate'::text, 'anonymous'::text, 'system'::text, 'service'::text, 'migration'::text])));
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_entity_type_check" CHECK (((length(btrim(entity_type)) >= 1) AND (length(btrim(entity_type)) <= 160)));
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text));
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY (id);
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_source_check" CHECK ((source = ANY (ARRAY['admin'::text, 'company'::text, 'contractor'::text, 'candidate'::text, 'public'::text, 'whatsapp'::text, 'automation'::text, 'migration'::text, 'system'::text])));
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_admin_notes_length_check" CHECK (((admin_notes IS NULL) OR (length(admin_notes) <= 4000)));
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_application_status_check" CHECK ((application_status = ANY (ARRAY['interested'::text, 'applied'::text, 'screening'::text, 'shortlisted'::text, 'interview'::text, 'selected'::text, 'rejected'::text, 'joining_pending'::text, 'joined'::text, 'left'::text, 'cancelled'::text])));
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_candidate_id_requirement_id_key" UNIQUE (candidate_id, requirement_id);
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_check" CHECK (((source_type <> 'contractor'::text) OR (requirement_contractor_id IS NOT NULL)));
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_pkey" PRIMARY KEY (id);
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_source_reference_length_check" CHECK (((source_reference IS NULL) OR (length(source_reference) <= 500)));
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_source_type_check" CHECK ((source_type = ANY (ARRAY['direct'::text, 'contractor'::text, 'admin'::text, 'whatsapp'::text, 'campus'::text, 'referral'::text, 'public_website'::text, 'candidate_portal'::text, 'employer_portal'::text, 'contractor_portal'::text, 'whatsapp_campaign'::text, 'admin_manual'::text, 'iti'::text, 'csc_vle'::text, 'field_sourcing'::text, 'external_job_lead'::text])));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_display_file_name_check" CHECK (((length(btrim(display_file_name)) >= 1) AND (length(btrim(display_file_name)) <= 240)));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_document_type_check" CHECK ((document_type = ANY (ARRAY['resume'::text, 'aadhaar'::text, 'aadhaar_front'::text, 'aadhaar_back'::text, 'pan'::text, 'candidate_photo'::text, '10th_certificate'::text, '12th_certificate'::text, 'iti_certificate'::text, 'iti_marksheet'::text, 'diploma_certificate'::text, 'degree_certificate'::text, 'education_other'::text, 'experience_certificate'::text, 'previous_employment'::text, 'bank_proof'::text, 'bank_passbook'::text, 'cancelled_cheque'::text, 'driving_licence'::text, 'passport'::text, 'other'::text])));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_file_size_bytes_check" CHECK (((file_size_bytes >= 1) AND (file_size_bytes <= 10485760)));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_mime_type_check" CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text])));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_pkey" PRIMARY KEY (id);
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_storage_object_name_key" UNIQUE (storage_object_name);
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_verification_check" CHECK ((((verification_status = 'uploaded'::text) AND (review_started_at IS NULL) AND (review_started_by IS NULL) AND (reviewed_at IS NULL) AND (reviewed_by IS NULL) AND (verified_at IS NULL) AND (verified_by IS NULL) AND (verification_feedback IS NULL)) OR ((verification_status = 'under_verification'::text) AND (review_started_at IS NOT NULL) AND (review_started_by IS NOT NULL) AND (reviewed_at IS NULL) AND (reviewed_by IS NULL) AND (verified_at IS NULL) AND (verified_by IS NULL) AND (verification_feedback IS NULL)) OR ((verification_status = 'verified'::text) AND (review_started_at IS NOT NULL) AND (review_started_by IS NOT NULL) AND (reviewed_at IS NOT NULL) AND (reviewed_by IS NOT NULL) AND (verified_at IS NOT NULL) AND (verified_by IS NOT NULL) AND (reviewed_at = verified_at) AND (reviewed_by = verified_by) AND (verification_feedback IS NULL)) OR ((verification_status = 'reupload_required'::text) AND (review_started_at IS NOT NULL) AND (review_started_by IS NOT NULL) AND (reviewed_at IS NOT NULL) AND (reviewed_by IS NOT NULL) AND (verified_at IS NULL) AND (verified_by IS NULL) AND (verification_feedback IS NOT NULL))));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_verification_feedback_check" CHECK (((verification_feedback IS NULL) OR ((length(btrim(verification_feedback)) >= 1) AND (length(btrim(verification_feedback)) <= 1000))));
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_verification_status_check" CHECK ((verification_status = ANY (ARRAY['uploaded'::text, 'under_verification'::text, 'verified'::text, 'reupload_required'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_aadhaar_fingerprint_key" UNIQUE (aadhaar_fingerprint);
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_aadhaar_pair_check" CHECK ((((aadhaar_fingerprint IS NULL) AND (aadhaar_last4 IS NULL)) OR ((aadhaar_fingerprint ~ '^[0-9a-f]{64}$'::text) AND (aadhaar_last4 ~ '^[0-9]{4}$'::text))));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_age_check" CHECK (((age >= 16) AND (age <= 75)));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_availability_status_check" CHECK ((availability_status = ANY (ARRAY['available'::text, 'not_available'::text, 'open_to_opportunities'::text, 'unknown'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_candidate_type_check" CHECK ((candidate_type = ANY (ARRAY['Fresher'::text, 'Experienced'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_consent_check" CHECK ((consent = true));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_current_employment_status_check" CHECK ((current_employment_status = ANY (ARRAY['unemployed'::text, 'employed'::text, 'notice_period'::text, 'unknown'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_current_location_check" CHECK (((length(btrim(current_location)) >= 1) AND (length(btrim(current_location)) <= 200)));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_date_of_birth_check" CHECK (((date_of_birth IS NULL) OR ((date_of_birth >= ((CURRENT_DATE - '75 years'::interval))::date) AND (date_of_birth <= ((CURRENT_DATE - '16 years'::interval))::date))));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_district_check" CHECK (((length(btrim(district)) >= 1) AND (length(btrim(district)) <= 160)));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_full_name_check" CHECK (((length(btrim(full_name)) >= 1) AND (length(btrim(full_name)) <= 160)));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_gender_check" CHECK ((gender = ANY (ARRAY['Male'::text, 'Female'::text, 'Other / Prefer not to say'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_highest_qualification_check" CHECK ((highest_qualification = ANY (ARRAY['Below 10th'::text, '10th'::text, '12th'::text, 'ITI'::text, 'Diploma'::text, 'Graduate'::text, 'Post Graduate'::text, 'Other'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_interview_available_check" CHECK ((interview_available = ANY (ARRAY['Yes'::text, 'No'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_mobile_check" CHECK ((mobile ~ '^[6-9][0-9]{9}$'::text));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_pincode_check" CHECK (((pincode IS NULL) OR (pincode ~ '^[0-9]{6}$'::text)));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_pkey" PRIMARY KEY (id);
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_profile_completion_status_check" CHECK ((profile_completion_status = ANY (ARRAY['incomplete'::text, 'complete'::text, 'review_required'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_profile_status_check" CHECK ((profile_status = ANY (ARRAY['registered'::text, 'active'::text, 'inactive'::text, 'archived'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_state_check" CHECK (((length(btrim(state)) >= 1) AND (length(btrim(state)) <= 160)));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_status_check" CHECK ((status = ANY (ARRAY['new'::text, 'contacted'::text, 'shortlisted'::text, 'interview'::text, 'selected'::text, 'joined'::text, 'inactive'::text])));
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_user_id_key" UNIQUE (user_id);
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_whatsapp_number_check" CHECK (((whatsapp_number IS NULL) OR (whatsapp_number ~ '^[6-9][0-9]{9}$'::text)));
ALTER TABLE public.candidates ADD CONSTRAINT "recruitment_candidate_source_detail_check" CHECK (((acquisition_source_detail IS NULL) OR ((length(btrim(acquisition_source_detail)) >= 1) AND (length(btrim(acquisition_source_detail)) <= 200))));
ALTER TABLE public.candidates ADD CONSTRAINT "recruitment_candidate_source_reference_check" CHECK (((acquisition_source_reference IS NULL) OR ((length(btrim(acquisition_source_reference)) >= 1) AND (length(btrim(acquisition_source_reference)) <= 500))));
ALTER TABLE public.candidates ADD CONSTRAINT "recruitment_candidate_source_type_check" CHECK ((acquisition_source_type = ANY (ARRAY['public_website'::text, 'candidate_portal'::text, 'employer_portal'::text, 'contractor_portal'::text, 'whatsapp_campaign'::text, 'admin_manual'::text, 'referral'::text, 'campus'::text, 'iti'::text, 'csc_vle'::text, 'field_sourcing'::text, 'external_job_lead'::text])));
ALTER TABLE public.companies ADD CONSTRAINT "companies_account_status_check" CHECK ((account_status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'rejected'::text])));
ALTER TABLE public.companies ADD CONSTRAINT "companies_contact_person_check" CHECK (((contact_person IS NULL) OR ((length(btrim(contact_person)) >= 1) AND (length(btrim(contact_person)) <= 160))));
ALTER TABLE public.companies ADD CONSTRAINT "companies_legal_name_check" CHECK (((length(btrim(legal_name)) >= 1) AND (length(btrim(legal_name)) <= 240)));
ALTER TABLE public.companies ADD CONSTRAINT "companies_pincode_check" CHECK (((pincode IS NULL) OR (pincode ~ '^[0-9]{6}$'::text)));
ALTER TABLE public.companies ADD CONSTRAINT "companies_pkey" PRIMARY KEY (id);
ALTER TABLE public.companies ADD CONSTRAINT "companies_verification_status_check" CHECK ((verification_status = ANY (ARRAY['pending'::text, 'verified'::text, 'rejected'::text])));
ALTER TABLE public.companies ADD CONSTRAINT "companies_workforce_size_check" CHECK (((workforce_size IS NULL) OR (workforce_size = ANY (ARRAY['1-10'::text, '11-50'::text, '51-200'::text, '201-500'::text, '501-1000'::text, '1000+'::text]))));
ALTER TABLE public.company_users ADD CONSTRAINT "company_users_pkey" PRIMARY KEY (company_id, user_id);
ALTER TABLE public.company_users ADD CONSTRAINT "company_users_role_check" CHECK ((role = ANY (ARRAY['owner'::text, 'hr_admin'::text, 'recruiter'::text, 'viewer'::text])));
ALTER TABLE public.company_users ADD CONSTRAINT "company_users_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text])));
ALTER TABLE public.contractor_users ADD CONSTRAINT "contractor_users_pkey" PRIMARY KEY (contractor_id, user_id);
ALTER TABLE public.contractor_users ADD CONSTRAINT "contractor_users_role_check" CHECK ((role = ANY (ARRAY['owner'::text, 'manager'::text, 'recruiter'::text, 'coordinator'::text])));
ALTER TABLE public.contractor_users ADD CONSTRAINT "contractor_users_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text])));
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_account_status_check" CHECK ((account_status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'rejected'::text])));
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_agency_name_check" CHECK (((length(btrim(agency_name)) >= 1) AND (length(btrim(agency_name)) <= 240)));
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_pincode_check" CHECK (((pincode IS NULL) OR (pincode ~ '^[0-9]{6}$'::text)));
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_pkey" PRIMARY KEY (id);
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_verification_status_check" CHECK ((verification_status = ANY (ARRAY['pending'::text, 'verified'::text, 'rejected'::text])));
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_workforce_capacity_check" CHECK (((workforce_capacity IS NULL) OR (workforce_capacity >= 0)));
ALTER TABLE public.contractors ADD CONSTRAINT "recruitment_contractor_source_detail_check" CHECK (((acquisition_source_detail IS NULL) OR ((length(btrim(acquisition_source_detail)) >= 1) AND (length(btrim(acquisition_source_detail)) <= 200))));
ALTER TABLE public.contractors ADD CONSTRAINT "recruitment_contractor_source_reference_check" CHECK (((acquisition_source_reference IS NULL) OR ((length(btrim(acquisition_source_reference)) >= 1) AND (length(btrim(acquisition_source_reference)) <= 500))));
ALTER TABLE public.contractors ADD CONSTRAINT "recruitment_contractor_source_type_check" CHECK ((acquisition_source_type = ANY (ARRAY['public_website'::text, 'candidate_portal'::text, 'employer_portal'::text, 'contractor_portal'::text, 'whatsapp_campaign'::text, 'admin_manual'::text, 'referral'::text, 'campus'::text, 'iti'::text, 'csc_vle'::text, 'field_sourcing'::text, 'external_job_lead'::text])));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_accommodation_basis_check" CHECK (((accommodation_charge_basis IS NULL) OR (accommodation_charge_basis = ANY (ARRAY['per_day'::text, 'per_month'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_accommodation_charge_check" CHECK ((((accommodation_status IS NULL) AND (accommodation_charge_amount IS NULL) AND (accommodation_charge_basis IS NULL)) OR ((accommodation_status = 'chargeable'::text) AND (accommodation_charge_amount IS NOT NULL) AND (accommodation_charge_amount > (0)::numeric) AND (accommodation_charge_basis IS NOT NULL)) OR ((accommodation_status = ANY (ARRAY['not_available'::text, 'free'::text])) AND (accommodation_charge_amount IS NULL) AND (accommodation_charge_basis IS NULL))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_accommodation_check" CHECK (((accommodation IS NULL) OR (accommodation = ANY (ARRAY['Yes'::text, 'No'::text, 'Not Applicable'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_accommodation_status_check" CHECK (((accommodation_status IS NULL) OR (accommodation_status = ANY (ARRAY['not_available'::text, 'free'::text, 'chargeable'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_age_range_check" CHECK ((((age_min IS NULL) OR ((age_min >= 16) AND (age_min <= 75))) AND ((age_max IS NULL) OR ((age_max >= 16) AND (age_max <= 75))) AND ((age_min IS NULL) OR (age_max IS NULL) OR (age_min <= age_max))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_canteen_check" CHECK (((canteen IS NULL) OR (canteen = ANY (ARRAY['Yes'::text, 'No'::text, 'Not Applicable'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_canteen_terms_m050_check" CHECK (
CASE
    WHEN (canteen_status IS NULL) THEN ((canteen_charge_amount IS NULL) AND (canteen_charge_basis IS NULL))
    WHEN (canteen_status = 'chargeable'::text) THEN ((canteen_charge_amount IS NOT NULL) AND (canteen_charge_amount > (0)::numeric) AND (canteen_charge_basis IS NOT NULL) AND (canteen_charge_basis = ANY (ARRAY['per_day'::text, 'per_meal'::text, 'per_month'::text])))
    WHEN (canteen_status = ANY (ARRAY['free'::text, 'not_available'::text, 'not_applicable'::text])) THEN ((canteen_charge_amount IS NULL) AND (canteen_charge_basis IS NULL))
    ELSE false
END);
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_company_location_check" CHECK (((length(btrim(company_location)) >= 1) AND (length(btrim(company_location)) <= 300)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_company_name_check" CHECK (((length(btrim(company_name)) >= 1) AND (length(btrim(company_name)) <= 200)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_compensation_cadence_m050_check" CHECK (((compensation_cadence IS NULL) OR (compensation_cadence = ANY (ARRAY['monthly'::text, 'annual'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_consent_check" CHECK ((consent = true));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_contact_person_check" CHECK (((length(btrim(contact_person)) >= 1) AND (length(btrim(contact_person)) <= 160)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_employment_terms_m050_check" CHECK ((((employment_type IS NULL) OR (employment_type = ANY (ARRAY['permanent'::text, 'contract'::text, 'temporary'::text, 'trainee'::text, 'apprentice'::text]))) AND ((payroll_type IS NULL) OR (payroll_type = ANY (ARRAY['company'::text, 'contractor'::text, 'third_party'::text]))) AND ((contract_duration_months IS NULL) OR ((contract_duration_months >= 1) AND (contract_duration_months <= 120))) AND ((probation_period_months IS NULL) OR ((probation_period_months >= 1) AND (probation_period_months <= 24))) AND ((training_period_days IS NULL) OR ((training_period_days >= 1) AND (training_period_days <= 365))) AND ((notice_period_days IS NULL) OR ((notice_period_days >= 1) AND (notice_period_days <= 180))) AND ((contract_duration_months IS NULL) OR ((employment_type IS NOT NULL) AND (employment_type = 'contract'::text)))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_experience_requirement_check" CHECK (((experience_requirement IS NULL) OR (experience_requirement = ANY (ARRAY['Fresher'::text, 'Experienced'::text, 'Both'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_filled_positions_check" CHECK (((filled_positions >= 0) AND (filled_positions <= required_headcount)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_gender_preference_check" CHECK (((gender_preference IS NULL) OR (gender_preference = ANY (ARRAY['Any'::text, 'Male'::text, 'Female'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_job_role_check" CHECK (((length(btrim(job_role)) >= 1) AND (length(btrim(job_role)) <= 200)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_leave_days_m050_check" CHECK ((((paid_leave_days_per_year IS NULL) OR ((paid_leave_days_per_year >= 0) AND (paid_leave_days_per_year <= 366))) AND ((casual_leave_days_per_year IS NULL) OR ((casual_leave_days_per_year >= 0) AND (casual_leave_days_per_year <= 366))) AND ((sick_leave_days_per_year IS NULL) OR ((sick_leave_days_per_year >= 0) AND (sick_leave_days_per_year <= 366))) AND ((national_holiday_days_per_year IS NULL) OR ((national_holiday_days_per_year >= 0) AND (national_holiday_days_per_year <= 366))) AND ((festival_holiday_days_per_year IS NULL) OR ((festival_holiday_days_per_year >= 0) AND (festival_holiday_days_per_year <= 366)))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_mobile_check" CHECK ((mobile ~ '^[6-9][0-9]{9}$'::text));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_overtime_rate_m050_check" CHECK (
CASE
    WHEN (overtime_rate IS NULL) THEN (overtime_rate_basis IS NULL)
    WHEN (overtime_rate_basis IS NULL) THEN false
    WHEN (overtime_rate <= (0)::numeric) THEN false
    ELSE (overtime_rate_basis = ANY (ARRAY['per_hour'::text, 'per_day'::text, 'multiplier'::text]))
END);
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_payable_days_check" CHECK (((payable_days IS NULL) OR ((payable_days >= 1) AND (payable_days <= 31))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_pkey" PRIMARY KEY (id);
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_required_headcount_check" CHECK ((required_headcount > 0));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_requirement_code_key" UNIQUE (requirement_code);
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_review_feedback_check" CHECK (((review_feedback IS NULL) OR ((length(btrim(review_feedback)) >= 1) AND (length(btrim(review_feedback)) <= 2000))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_review_reason_check" CHECK (((review_status <> ALL (ARRAY['correction_required'::text, 'rejected'::text])) OR (review_feedback IS NOT NULL)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_review_status_check" CHECK (((review_status IS NULL) OR (review_status = ANY (ARRAY['draft'::text, 'pending_review'::text, 'correction_required'::text, 'approved'::text, 'rejected'::text, 'closed'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_salary_range_check" CHECK ((((salary_min IS NULL) OR (salary_min >= (0)::numeric)) AND ((salary_max IS NULL) OR (salary_max >= (0)::numeric)) AND ((salary_min IS NULL) OR (salary_max IS NULL) OR (salary_min <= salary_max))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_stage_check" CHECK ((requirement_stage = ANY (ARRAY['draft'::text, 'open'::text, 'on_hold'::text, 'filled'::text, 'closed'::text, 'cancelled'::text])));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_status_check" CHECK ((status = ANY (ARRAY['new'::text, 'contacted'::text, 'in_progress'::text, 'fulfilled'::text, 'closed'::text])));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_transport_check" CHECK (((transport IS NULL) OR (transport = ANY (ARRAY['Yes'::text, 'No'::text, 'Not Applicable'::text]))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_transport_terms_m050_check" CHECK (
CASE
    WHEN (transport_status IS NULL) THEN ((transport_charge_amount IS NULL) AND (transport_charge_basis IS NULL))
    WHEN (transport_status = 'chargeable'::text) THEN ((transport_charge_amount IS NOT NULL) AND (transport_charge_amount > (0)::numeric) AND (transport_charge_basis IS NOT NULL) AND (transport_charge_basis = ANY (ARRAY['per_day'::text, 'per_month'::text])))
    WHEN (transport_status = ANY (ARRAY['free'::text, 'not_available'::text, 'not_applicable'::text])) THEN ((transport_charge_amount IS NULL) AND (transport_charge_basis IS NULL))
    ELSE false
END);
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_visibility_check" CHECK ((requirement_visibility = ANY (ARRAY['private'::text, 'assigned'::text, 'public'::text])));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_wage_amounts_nonnegative_check" CHECK (((COALESCE(basic_da, (0)::numeric) >= (0)::numeric) AND (COALESCE(attendance_bonus, (0)::numeric) >= (0)::numeric) AND (COALESCE(monthly_bonus, (0)::numeric) >= (0)::numeric) AND (COALESCE(leave_amount, (0)::numeric) >= (0)::numeric) AND (COALESCE(other_fixed_earning, (0)::numeric) >= (0)::numeric) AND (COALESCE(gross_wages, (0)::numeric) >= (0)::numeric) AND (COALESCE(employee_pf, (0)::numeric) >= (0)::numeric) AND (COALESCE(employee_esic, (0)::numeric) >= (0)::numeric) AND (COALESCE(canteen_deduction, (0)::numeric) >= (0)::numeric) AND (COALESCE(other_deduction, (0)::numeric) >= (0)::numeric) AND (COALESCE(employer_pf, (0)::numeric) >= (0)::numeric) AND (COALESCE(employer_esic, (0)::numeric) >= (0)::numeric) AND (COALESCE(gratuity_provision, (0)::numeric) >= (0)::numeric) AND (COALESCE(bonus_provision, (0)::numeric) >= (0)::numeric) AND (COALESCE(leave_provision, (0)::numeric) >= (0)::numeric) AND (COALESCE(other_ctc_component, (0)::numeric) >= (0)::numeric) AND (COALESCE(approx_in_hand, (0)::numeric) >= (0)::numeric) AND (COALESCE(ctc, (0)::numeric) >= (0)::numeric)));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_wage_totals_check" CHECK ((((basic_da IS NULL) AND (attendance_bonus IS NULL) AND (monthly_bonus IS NULL) AND (leave_amount IS NULL) AND (other_fixed_earning IS NULL) AND (gross_wages IS NULL) AND (employee_pf IS NULL) AND (employee_esic IS NULL) AND (canteen_deduction IS NULL) AND (other_deduction IS NULL) AND (employer_pf IS NULL) AND (employer_esic IS NULL) AND (gratuity_provision IS NULL) AND (bonus_provision IS NULL) AND (leave_provision IS NULL) AND (other_ctc_component IS NULL) AND (approx_in_hand IS NULL) AND (ctc IS NULL)) OR ((gross_wages IS NOT NULL) AND (approx_in_hand IS NOT NULL) AND (ctc IS NOT NULL) AND (gross_wages = ((((COALESCE(basic_da, (0)::numeric) + COALESCE(attendance_bonus, (0)::numeric)) + COALESCE(monthly_bonus, (0)::numeric)) + COALESCE(leave_amount, (0)::numeric)) + COALESCE(other_fixed_earning, (0)::numeric))) AND (approx_in_hand = ((((gross_wages - COALESCE(employee_pf, (0)::numeric)) - COALESCE(employee_esic, (0)::numeric)) - COALESCE(canteen_deduction, (0)::numeric)) - COALESCE(other_deduction, (0)::numeric))) AND (ctc = ((((((gross_wages + COALESCE(employer_pf, (0)::numeric)) + COALESCE(employer_esic, (0)::numeric)) + COALESCE(gratuity_provision, (0)::numeric)) + COALESCE(bonus_provision, (0)::numeric)) + COALESCE(leave_provision, (0)::numeric)) + COALESCE(other_ctc_component, (0)::numeric))))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_work_week_m050_check" CHECK ((((working_days_per_week IS NULL) OR ((working_days_per_week >= 1) AND (working_days_per_week <= 7))) AND ((weekly_off_count IS NULL) OR ((weekly_off_count >= 0) AND (weekly_off_count <= 6))) AND ((working_days_per_week IS NULL) OR (weekly_off_count IS NULL) OR ((working_days_per_week + weekly_off_count) = 7))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "recruitment_requirement_lost_reason_check" CHECK (((lost_reason IS NULL) OR (((length(btrim(lost_reason)) >= 1) AND (length(btrim(lost_reason)) <= 500)) AND (requirement_stage = ANY (ARRAY['filled'::text, 'closed'::text, 'cancelled'::text])))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "recruitment_requirement_source_detail_check" CHECK (((source_detail IS NULL) OR ((length(btrim(source_detail)) >= 1) AND (length(btrim(source_detail)) <= 200))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "recruitment_requirement_source_reference_check" CHECK (((source_reference IS NULL) OR ((length(btrim(source_reference)) >= 1) AND (length(btrim(source_reference)) <= 500))));
ALTER TABLE public.employer_requirements ADD CONSTRAINT "recruitment_requirement_source_type_check" CHECK ((source_type = ANY (ARRAY['public_website'::text, 'candidate_portal'::text, 'employer_portal'::text, 'contractor_portal'::text, 'whatsapp_campaign'::text, 'admin_manual'::text, 'referral'::text, 'campus'::text, 'iti'::text, 'csc_vle'::text, 'field_sourcing'::text, 'external_job_lead'::text])));
ALTER TABLE public.platform_users ADD CONSTRAINT "platform_users_account_status_check" CHECK ((account_status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'rejected'::text])));
ALTER TABLE public.platform_users ADD CONSTRAINT "platform_users_account_type_check" CHECK ((account_type = ANY (ARRAY['company'::text, 'contractor'::text, 'candidate'::text])));
ALTER TABLE public.platform_users ADD CONSTRAINT "platform_users_display_name_check" CHECK (((length(btrim(display_name)) >= 1) AND (length(btrim(display_name)) <= 160)));
ALTER TABLE public.platform_users ADD CONSTRAINT "platform_users_mobile_check" CHECK (((mobile IS NULL) OR (mobile ~ '^[6-9][0-9]{9}$'::text)));
ALTER TABLE public.platform_users ADD CONSTRAINT "platform_users_pkey" PRIMARY KEY (user_id);
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_assigned_headcount_check" CHECK ((assigned_headcount > 0));
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_assignment_status_check" CHECK ((assignment_status = ANY (ARRAY['assigned'::text, 'accepted'::text, 'declined'::text, 'active'::text, 'completed'::text, 'cancelled'::text])));
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_id_requirement_key" UNIQUE (id, requirement_id);
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_origin_type_check" CHECK ((origin_type = ANY (ARRAY['internal_assignment'::text, 'contractor_submission'::text])));
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_pkey" PRIMARY KEY (id);
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_requirement_id_contractor_id_key" UNIQUE (requirement_id, contractor_id);
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_review_feedback_length_check" CHECK (((review_feedback IS NULL) OR (length(review_feedback) <= 2000)));
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_submission_shape_check" CHECK ((((origin_type = 'internal_assignment'::text) AND (submission_status IS NULL)) OR ((origin_type = 'contractor_submission'::text) AND (submission_status IS NOT NULL))));
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_submission_status_check" CHECK (((submission_status IS NULL) OR (submission_status = ANY (ARRAY['draft'::text, 'submitted'::text, 'under_review'::text, 'correction_required'::text, 'approved'::text, 'rejected'::text, 'closed'::text, 'cancelled'::text]))));
ALTER TABLE public.staff_profiles ADD CONSTRAINT "staff_profiles_display_name_check" CHECK (((length(btrim(display_name)) >= 1) AND (length(btrim(display_name)) <= 160)));
ALTER TABLE public.staff_profiles ADD CONSTRAINT "staff_profiles_pkey" PRIMARY KEY (user_id);
ALTER TABLE public.staff_profiles ADD CONSTRAINT "staff_profiles_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'inactive'::text])));
ALTER TABLE public.staff_roles ADD CONSTRAINT "staff_roles_pkey" PRIMARY KEY (user_id, role);
ALTER TABLE public.staff_roles ADD CONSTRAINT "staff_roles_role_check" CHECK ((role = ANY (ARRAY['super_admin'::text, 'admin'::text, 'recruiter'::text, 'operations'::text, 'viewer'::text])));
ALTER TABLE public.staff_roles ADD CONSTRAINT "staff_roles_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text])));
ALTER TABLE public.admin_users ADD CONSTRAINT "admin_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.audit_logs ADD CONSTRAINT "audit_logs_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_assignment_requirement_fkey" FOREIGN KEY (requirement_contractor_id, requirement_id) REFERENCES requirement_contractors(id, requirement_id) ON DELETE RESTRICT;
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_candidate_id_fkey" FOREIGN KEY (candidate_id) REFERENCES candidates(id) ON DELETE RESTRICT;
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.candidate_applications ADD CONSTRAINT "candidate_applications_requirement_id_fkey" FOREIGN KEY (requirement_id) REFERENCES employer_requirements(id) ON DELETE RESTRICT;
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_candidate_id_fkey" FOREIGN KEY (candidate_id) REFERENCES candidates(id) ON DELETE RESTRICT;
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_review_started_by_fkey" FOREIGN KEY (review_started_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.candidate_documents ADD CONSTRAINT "candidate_documents_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_owner_assigned_by_fkey" FOREIGN KEY (owner_assigned_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_owner_staff_user_id_fkey" FOREIGN KEY (owner_staff_user_id) REFERENCES staff_profiles(user_id) ON DELETE SET NULL;
ALTER TABLE public.candidates ADD CONSTRAINT "candidates_user_id_fkey" FOREIGN KEY (user_id) REFERENCES platform_users(user_id) ON DELETE SET NULL;
ALTER TABLE public.company_users ADD CONSTRAINT "company_users_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE RESTRICT;
ALTER TABLE public.company_users ADD CONSTRAINT "company_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES platform_users(user_id) ON DELETE RESTRICT;
ALTER TABLE public.contractor_users ADD CONSTRAINT "contractor_users_contractor_id_fkey" FOREIGN KEY (contractor_id) REFERENCES contractors(id) ON DELETE RESTRICT;
ALTER TABLE public.contractor_users ADD CONSTRAINT "contractor_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES platform_users(user_id) ON DELETE RESTRICT;
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_owner_assigned_by_fkey" FOREIGN KEY (owner_assigned_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.contractors ADD CONSTRAINT "contractors_owner_staff_user_id_fkey" FOREIGN KEY (owner_staff_user_id) REFERENCES staff_profiles(user_id) ON DELETE SET NULL;
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE RESTRICT;
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_created_by_user_id_fkey" FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_owner_assigned_by_fkey" FOREIGN KEY (owner_assigned_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_owner_staff_user_id_fkey" FOREIGN KEY (owner_staff_user_id) REFERENCES staff_profiles(user_id) ON DELETE SET NULL;
ALTER TABLE public.employer_requirements ADD CONSTRAINT "employer_requirements_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.platform_users ADD CONSTRAINT "platform_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_assigned_by_fkey" FOREIGN KEY (assigned_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_contractor_id_fkey" FOREIGN KEY (contractor_id) REFERENCES contractors(id) ON DELETE RESTRICT;
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_requirement_id_fkey" FOREIGN KEY (requirement_id) REFERENCES employer_requirements(id) ON DELETE RESTRICT;
ALTER TABLE public.requirement_contractors ADD CONSTRAINT "requirement_contractors_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.staff_profiles ADD CONSTRAINT "staff_profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE public.staff_roles ADD CONSTRAINT "staff_roles_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.staff_roles ADD CONSTRAINT "staff_roles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES staff_profiles(user_id) ON DELETE RESTRICT;
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
CREATE INDEX audit_logs_actor_created_idx ON public.audit_logs USING btree (actor_user_id, created_at DESC) WHERE (actor_user_id IS NOT NULL);
CREATE INDEX audit_logs_correlation_idx ON public.audit_logs USING btree (correlation_id) WHERE (correlation_id IS NOT NULL);
CREATE INDEX audit_logs_entity_created_idx ON public.audit_logs USING btree (entity_type, entity_id, created_at DESC);
ALTER TABLE public.candidate_applications ENABLE ROW LEVEL SECURITY;
CREATE INDEX candidate_applications_applied_at_idx ON public.candidate_applications USING btree (applied_at DESC);
CREATE INDEX candidate_applications_assignment_idx ON public.candidate_applications USING btree (requirement_contractor_id) WHERE (requirement_contractor_id IS NOT NULL);
CREATE INDEX candidate_applications_candidate_idx ON public.candidate_applications USING btree (candidate_id, created_at DESC);
CREATE INDEX candidate_applications_correlation_idx ON public.candidate_applications USING btree (correlation_id) WHERE (correlation_id IS NOT NULL);
CREATE INDEX candidate_applications_requirement_idx ON public.candidate_applications USING btree (requirement_id, application_status);
CREATE INDEX candidate_applications_status_created_idx ON public.candidate_applications USING btree (application_status, created_at DESC);
CREATE INDEX candidate_applications_updated_stage_idx ON public.candidate_applications USING btree (application_status, updated_at DESC);
ALTER TABLE public.candidate_documents ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX candidate_documents_active_single_idx ON public.candidate_documents USING btree (candidate_id, document_type) WHERE active;
CREATE INDEX candidate_documents_candidate_uploaded_idx ON public.candidate_documents USING btree (candidate_id, uploaded_at DESC);
CREATE INDEX candidate_documents_verification_idx ON public.candidate_documents USING btree (verification_status, uploaded_at);
ALTER TABLE public.candidates ENABLE ROW LEVEL SECURITY;
CREATE INDEX candidates_created_at_idx ON public.candidates USING btree (created_at DESC);
CREATE INDEX candidates_mobile_idx ON public.candidates USING btree (mobile);
CREATE INDEX candidates_status_idx ON public.candidates USING btree (status);
CREATE INDEX candidates_user_id_idx ON public.candidates USING btree (user_id) WHERE (user_id IS NOT NULL);
CREATE INDEX recruitment_candidates_owner_due_idx ON public.candidates USING btree (owner_staff_user_id, follow_up_due_at);
CREATE INDEX recruitment_candidates_source_idx ON public.candidates USING btree (acquisition_source_type, created_at DESC);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE INDEX companies_account_status_idx ON public.companies USING btree (account_status);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE INDEX company_users_user_id_idx ON public.company_users USING btree (user_id);
ALTER TABLE public.contractor_users ENABLE ROW LEVEL SECURITY;
CREATE INDEX contractor_users_user_id_idx ON public.contractor_users USING btree (user_id);
ALTER TABLE public.contractors ENABLE ROW LEVEL SECURITY;
CREATE INDEX contractors_account_status_idx ON public.contractors USING btree (account_status);
CREATE INDEX recruitment_contractors_owner_due_idx ON public.contractors USING btree (owner_staff_user_id, follow_up_due_at);
CREATE INDEX recruitment_contractors_source_idx ON public.contractors USING btree (acquisition_source_type, created_at DESC);
ALTER TABLE public.employer_requirements ENABLE ROW LEVEL SECURITY;
CREATE INDEX employer_requirements_company_id_idx ON public.employer_requirements USING btree (company_id) WHERE (company_id IS NOT NULL);
CREATE INDEX employer_requirements_created_at_idx ON public.employer_requirements USING btree (created_at DESC);
CREATE INDEX employer_requirements_review_queue_idx ON public.employer_requirements USING btree (review_status, submitted_at DESC, id) WHERE (review_status = ANY (ARRAY['pending_review'::text, 'correction_required'::text]));
CREATE INDEX employer_requirements_stage_created_idx ON public.employer_requirements USING btree (requirement_stage, created_at DESC);
CREATE INDEX employer_requirements_status_idx ON public.employer_requirements USING btree (status);
CREATE INDEX recruitment_requirements_owner_due_idx ON public.employer_requirements USING btree (owner_staff_user_id, follow_up_due_at);
CREATE INDEX recruitment_requirements_source_idx ON public.employer_requirements USING btree (source_type, created_at DESC);
ALTER TABLE public.platform_users ENABLE ROW LEVEL SECURITY;
CREATE INDEX platform_users_account_type_status_idx ON public.platform_users USING btree (account_type, account_status);
ALTER TABLE public.requirement_contractors ENABLE ROW LEVEL SECURITY;
CREATE INDEX requirement_contractors_contractor_idx ON public.requirement_contractors USING btree (contractor_id, assignment_status);
CREATE INDEX requirement_contractors_portal_status_idx ON public.requirement_contractors USING btree (contractor_id, submission_status, created_at DESC) WHERE (origin_type = 'contractor_submission'::text);
CREATE INDEX requirement_contractors_requirement_idx ON public.requirement_contractors USING btree (requirement_id, assignment_status);
ALTER TABLE public.staff_profiles ENABLE ROW LEVEL SECURITY;
CREATE INDEX staff_profiles_status_idx ON public.staff_profiles USING btree (status);
ALTER TABLE public.staff_roles ENABLE ROW LEVEL SECURITY;
CREATE INDEX staff_roles_role_status_idx ON public.staff_roles USING btree (role, status);
CREATE OR REPLACE FUNCTION private.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS E'\r\nbegin\r\n  new.updated_at = now();\r\n  return new;\r\nend;\r\n'
;
ALTER FUNCTION private.set_updated_at() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.set_updated_at() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\r\n  select exists (\r\n    select 1 from public.admin_users\r\n    where user_id = (select auth.uid())\r\n  );\r\n'
;
ALTER FUNCTION private.is_admin() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;
CREATE OR REPLACE FUNCTION private.is_bootstrap_recruitment_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select (select private.is_admin())\n    and (select auth.uid()) is not null\n    and not exists (select 1 from public.platform_users where user_id = (select auth.uid()));\n'
;
ALTER FUNCTION private.is_bootstrap_recruitment_admin() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.is_bootstrap_recruitment_admin() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.current_staff_profile_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select sp.user_id\n  from public.staff_profiles sp\n  where sp.user_id = (select auth.uid())\n    and sp.status = ''active''\n    and not exists (\n      select 1 from public.platform_users pu where pu.user_id = sp.user_id\n    )\n    and exists (\n      select 1 from public.staff_roles sr\n      where sr.user_id = sp.user_id and sr.status = ''active''\n    );\n'
;
ALTER FUNCTION private.current_staff_profile_id() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.current_staff_profile_id() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.current_staff_roles()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select coalesce(array_agg(sr.role order by sr.role), array[]::text[])\n  from public.staff_roles sr\n  where sr.user_id = (select private.current_staff_profile_id())\n    and sr.status = ''active'';\n'
;
ALTER FUNCTION private.current_staff_roles() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.current_staff_roles() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.has_staff_role(p_role text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select coalesce(p_role = any(private.current_staff_roles()), false);\n'
;
ALTER FUNCTION private.has_staff_role(text) OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.has_staff_role(text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.current_candidate_portal_id()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\ndeclare v_candidate_id uuid; v_count integer;\nbegin\n  if (select auth.uid()) is null then return null; end if;\n  select count(*), (array_agg(c.id))[1] into v_count,v_candidate_id\n  from public.candidates c\n  join public.platform_users pu on pu.user_id=c.user_id\n  where c.user_id=(select auth.uid()) and pu.account_type=''candidate''\n    and pu.account_status=''active'' and c.profile_status=''active'' and c.status<>''inactive'';\n  return case when v_count=1 then v_candidate_id else null end;\nend;\n'
;
ALTER FUNCTION private.current_candidate_portal_id() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.current_candidate_portal_id() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.current_company_portal_id(p_require_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\ndeclare v_company_id uuid; v_count integer;\nbegin\n  if auth.uid() is null then return null; end if;\n  select min(cu.company_id::text)::uuid, count(*)::integer into v_company_id, v_count\n  from public.company_users cu join public.platform_users pu on pu.user_id=cu.user_id\n    join public.companies c on c.id=cu.company_id\n  where cu.user_id=auth.uid() and pu.account_type=''company''\n    and (not p_require_active or (pu.account_status=''active'' and cu.status=''active'' and c.account_status=''active''));\n  if v_count=0 then return null; end if;\n  if v_count<>1 then raise exception ''Exactly one company membership is required''; end if;\n  return v_company_id;\nend;\n'
;
ALTER FUNCTION private.current_company_portal_id(boolean) OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.current_company_portal_id(boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.current_contractor_portal_id(p_require_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\ndeclare resolved uuid; membership_count integer;\nbegin\n  if (select auth.uid()) is null then return null; end if;\n  select min(cu.contractor_id::text)::uuid,count(*)::integer into resolved,membership_count\n  from public.contractor_users cu join public.platform_users pu on pu.user_id=cu.user_id\n    join public.contractors c on c.id=cu.contractor_id\n  where cu.user_id=(select auth.uid()) and pu.account_type=''contractor''\n    and (not p_require_active or (pu.account_status=''active'' and cu.status=''active'' and c.account_status=''active''));\n  if membership_count=0 then return null; end if;\n  if membership_count<>1 then raise exception ''Exactly one contractor membership is required''; end if;\n  return resolved;\nend '
;
ALTER FUNCTION private.current_contractor_portal_id(boolean) OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.current_contractor_portal_id(boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.can_verify_candidate_documents()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select (select private.is_bootstrap_recruitment_admin())\n    or (select private.has_staff_role(''super_admin''))\n    or (select private.has_staff_role(''admin''));\n'
;
ALTER FUNCTION private.can_verify_candidate_documents() OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.can_verify_candidate_documents() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.is_current_candidate_storage_path(p_object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select (select auth.uid()) is not null\n    and (select private.current_candidate_portal_id()) is not null\n    and (storage.foldername(p_object_name))[1]=(select auth.uid())::text;\n'
;
ALTER FUNCTION private.is_current_candidate_storage_path(text) OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.is_current_candidate_storage_path(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.is_current_candidate_storage_path(text) TO authenticated;
CREATE OR REPLACE FUNCTION private.can_read_candidate_storage_object(p_object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select (select auth.uid()) is not null\n    and (select private.can_verify_candidate_documents())\n    and exists(select 1 from public.candidate_documents d\n      where d.storage_object_name=p_object_name and d.active);\n'
;
ALTER FUNCTION private.can_read_candidate_storage_object(text) OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.can_read_candidate_storage_object(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_candidate_storage_object(text) TO authenticated;
CREATE OR REPLACE FUNCTION private.can_delete_candidate_storage_object(p_object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\n  select (select private.is_current_candidate_storage_path(p_object_name))\n    and not exists(select 1 from public.candidate_documents d\n      where d.storage_object_name=p_object_name and d.active);\n'
;
ALTER FUNCTION private.can_delete_candidate_storage_object(text) OWNER TO "postgres";
REVOKE ALL ON FUNCTION private.can_delete_candidate_storage_object(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.can_delete_candidate_storage_object(text) TO authenticated;
CREATE OR REPLACE FUNCTION public.admin_list_candidate_documents(p_candidate_id uuid)
 RETURNS TABLE(document_id uuid, document_type text, display_file_name text, mime_type text, file_size_bytes bigint, verification_status text, verification_feedback text, uploaded_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\nbegin\n  if not (select private.can_verify_candidate_documents()) then raise exception ''Candidate document verification access is required''; end if;\n  return query select d.id,d.document_type,d.display_file_name,d.mime_type,d.file_size_bytes,\n    d.verification_status,d.verification_feedback,d.uploaded_at from public.candidate_documents d\n  where d.candidate_id=p_candidate_id and d.active order by d.document_type;\nend;\n'
;
ALTER FUNCTION public.admin_list_candidate_documents(uuid) OWNER TO "postgres";
REVOKE ALL ON FUNCTION public.admin_list_candidate_documents(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_candidate_documents(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.admin_get_candidate_document_access(p_document_id uuid)
 RETURNS TABLE(bucket_name text, object_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS E'\nbegin\n  if not (select private.can_verify_candidate_documents()) then raise exception ''Candidate document verification access is required''; end if;\n  return query select ''candidate-private''::text,d.storage_object_name from public.candidate_documents d\n    where d.id=p_document_id and d.active;\nend;\n'
;
ALTER FUNCTION public.admin_get_candidate_document_access(uuid) OWNER TO "postgres";
REVOKE ALL ON FUNCTION public.admin_get_candidate_document_access(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_candidate_document_access(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.admin_review_candidate_document(p_document_id uuid, p_status text, p_feedback text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS E'\ndeclare\n  v_status text:=lower(btrim(coalesce(p_status,'''')));\n  v_feedback text:=nullif(btrim(p_feedback),'''');\n  v_candidate uuid;\n  v_prior text;\n  v_actor uuid:=(select auth.uid());\n  v_now timestamptz:=clock_timestamp();\n  v_action text;\nbegin\n  if not (select private.can_verify_candidate_documents()) then\n    raise exception ''Candidate document verification access is required'';\n  end if;\n  if v_status not in (''under_verification'',''verified'',''reupload_required'')\n     or length(coalesce(v_feedback,''''))>1000\n     or (v_status=''reupload_required'' and length(coalesce(v_feedback,''''))<5)\n     or (v_status in (''under_verification'',''verified'') and v_feedback is not null) then\n    raise exception ''Document review details are invalid'';\n  end if;\n\n  select d.candidate_id,d.verification_status into v_candidate,v_prior\n  from public.candidate_documents d where d.id=p_document_id and d.active for update;\n  if v_candidate is null then raise exception ''Candidate document was not found''; end if;\n\n  if v_status=''under_verification'' then\n    if v_prior<>''uploaded'' then raise exception ''Only an uploaded document can enter verification''; end if;\n    update public.candidate_documents d set verification_status=''under_verification'',\n      verification_feedback=null,review_started_at=v_now,review_started_by=v_actor,\n      reviewed_at=null,reviewed_by=null,verified_at=null,verified_by=null\n      where d.id=p_document_id;\n    v_action:=''candidate.document_review_started'';\n  elsif v_status=''verified'' then\n    if v_prior<>''under_verification'' then raise exception ''Only an under-verification document can be verified''; end if;\n    update public.candidate_documents d set verification_status=''verified'',\n      verification_feedback=null,reviewed_at=v_now,reviewed_by=v_actor,\n      verified_at=v_now,verified_by=v_actor where d.id=p_document_id;\n    v_action:=''candidate.document_verified'';\n  else\n    if v_prior<>''under_verification'' then raise exception ''Only an under-verification document can require re-upload''; end if;\n    update public.candidate_documents d set verification_status=''reupload_required'',\n      verification_feedback=v_feedback,reviewed_at=v_now,reviewed_by=v_actor,\n      verified_at=null,verified_by=null where d.id=p_document_id;\n    v_action:=''candidate.document_reupload_requested'';\n  end if;\n\n  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)\n  values(v_actor,''staff'',v_action,''candidate_document'',p_document_id,''admin'',jsonb_build_object(''status'',v_status));\n  return true;\nend;\n'
;
ALTER FUNCTION public.admin_review_candidate_document(uuid,text,text) OWNER TO "postgres";
REVOKE ALL ON FUNCTION public.admin_review_candidate_document(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_candidate_document(uuid,text,text) TO authenticated;
CREATE TRIGGER candidate_applications_set_updated_at BEFORE UPDATE ON public.candidate_applications FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER candidate_documents_set_updated_at BEFORE UPDATE ON public.candidate_documents FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER candidates_set_updated_at BEFORE UPDATE ON public.candidates FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER companies_set_updated_at BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER company_users_set_updated_at BEFORE UPDATE ON public.company_users FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER contractor_users_set_updated_at BEFORE UPDATE ON public.contractor_users FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER contractors_set_updated_at BEFORE UPDATE ON public.contractors FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER employer_requirements_set_updated_at BEFORE UPDATE ON public.employer_requirements FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER platform_users_set_updated_at BEFORE UPDATE ON public.platform_users FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER requirement_contractors_set_updated_at BEFORE UPDATE ON public.requirement_contractors FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER staff_profiles_set_updated_at BEFORE UPDATE ON public.staff_profiles FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE TRIGGER staff_roles_set_updated_at BEFORE UPDATE ON public.staff_roles FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();
CREATE POLICY "Candidate deletes own unregistered private uploads" ON storage.objects FOR DELETE TO "authenticated" USING (((bucket_id = 'candidate-private'::text) AND ( SELECT private.can_delete_candidate_storage_object(objects.name) AS can_delete_candidate_storage_object)));
CREATE POLICY "Candidate document verifiers read registered uploads" ON storage.objects FOR SELECT TO "authenticated" USING (((bucket_id = 'candidate-private'::text) AND ( SELECT private.can_read_candidate_storage_object(objects.name) AS can_read_candidate_storage_object)));
CREATE POLICY "Candidate inserts own private uploads" ON storage.objects FOR INSERT TO "authenticated" WITH CHECK (((bucket_id = 'candidate-private'::text) AND ( SELECT private.is_current_candidate_storage_path(objects.name) AS is_current_candidate_storage_path)));
CREATE POLICY "Candidate reads own private uploads" ON storage.objects FOR SELECT TO "authenticated" USING (((bucket_id = 'candidate-private'::text) AND ( SELECT private.is_current_candidate_storage_path(objects.name) AS is_current_candidate_storage_path)));
CREATE POLICY "Candidate updates own private uploads" ON storage.objects FOR UPDATE TO "authenticated" USING (((bucket_id = 'candidate-private'::text) AND ( SELECT private.is_current_candidate_storage_path(objects.name) AS is_current_candidate_storage_path))) WITH CHECK (((bucket_id = 'candidate-private'::text) AND ( SELECT private.is_current_candidate_storage_path(objects.name) AS is_current_candidate_storage_path)));
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated; INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('candidate-private','candidate-private',false,10485760,ARRAY['application/pdf','image/jpeg','image/png']); 
REVOKE ALL ON public.admin_users FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.audit_logs FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.candidate_applications FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.candidate_documents FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.candidates FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.companies FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.company_users FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.contractor_users FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.contractors FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.employer_requirements FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.platform_users FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.requirement_contractors FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.staff_profiles FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.staff_roles FROM PUBLIC,anon,authenticated;
create function public.register_candidate_document(p_document_type text,p_storage_object_name text,p_display_file_name text,
  p_mime_type text,p_file_size_bytes bigint)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_auth uuid:=(select auth.uid()); v_document uuid;
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  if p_storage_object_name !~ ('^'||v_auth::text||'/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,160}$')
     or p_display_file_name like '%/%' or p_display_file_name like '%\%' then raise exception 'Document details are invalid'; end if;
  if (p_document_type='resume' and p_mime_type<>'application/pdf')
     or (p_document_type='candidate_photo' and p_mime_type not in ('image/jpeg','image/png'))
     or (p_mime_type='application/pdf' and p_storage_object_name !~ '\.pdf$')
     or (p_mime_type='image/jpeg' and p_storage_object_name !~ '\.(jpg|jpeg)$')
     or (p_mime_type='image/png' and p_storage_object_name !~ '\.png$') then raise exception 'Document type and file format do not match'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='candidate-private' and o.name=p_storage_object_name
    and coalesce(o.metadata->>'mimetype','')=p_mime_type
    and coalesce(nullif(o.metadata->>'size',''),'0')::bigint=p_file_size_bytes) then raise exception 'Uploaded document could not be verified'; end if;
  update public.candidate_documents d set active=false,replaced_at=now() where d.candidate_id=v_id and d.document_type=p_document_type and d.active;
  insert into public.candidate_documents(candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes)
    values(v_id,p_document_type,p_storage_object_name,btrim(p_display_file_name),p_mime_type,p_file_size_bytes) returning id into v_document;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_auth,'candidate','candidate.document_uploaded','candidate_document',v_document,'candidate',jsonb_build_object('document_type',p_document_type));
  return v_document;
end;
$$;
REVOKE ALL ON FUNCTION public.register_candidate_document(text,text,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_candidate_document(text,text,text,text,bigint) TO authenticated;
COMMIT;
NOTIFY pgrst,'reload schema';
SELECT 'RESUME_FIXTURE_BOOTSTRAP=PASS';
