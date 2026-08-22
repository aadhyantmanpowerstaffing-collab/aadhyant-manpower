-- W6 migration-025 focused checkpoint: Candidate-only Storage DML and explicit review lifecycle.
\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89200000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-candidate-a@test.local','x','{}','{}',now(),now()),
('89200000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-candidate-b@test.local','x','{}','{}',now(),now()),
('89200000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-company@test.local','x','{}','{}',now(),now()),
('89200000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-contractor@test.local','x','{}','{}',now(),now()),
('89200000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-recruiter@test.local','x','{}','{}',now(),now()),
('89200000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-operations@test.local','x','{}','{}',now(),now()),
('89200000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w6-doc-admin@test.local','x','{}','{}',now(),now());

insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status) values
('89200000-0000-0000-0000-000000000001','candidate','W6 Document Candidate A','9876500921','w6-doc-candidate-a@test.local','active'),
('89200000-0000-0000-0000-000000000002','candidate','W6 Document Candidate B','9876500922','w6-doc-candidate-b@test.local','active'),
('89200000-0000-0000-0000-000000000003','company','W6 Document Company',null,'w6-doc-company@test.local','active'),
('89200000-0000-0000-0000-000000000004','contractor','W6 Document Contractor',null,'w6-doc-contractor@test.local','active');
insert into public.admin_users(user_id) values('89200000-0000-0000-0000-000000000007');
insert into public.staff_profiles(user_id,display_name,status) values
('89200000-0000-0000-0000-000000000005','W6 Document Recruiter','active'),
('89200000-0000-0000-0000-000000000006','W6 Document Operations','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('89200000-0000-0000-0000-000000000005','recruiter','active','89200000-0000-0000-0000-000000000007'),
('89200000-0000-0000-0000-000000000006','operations','active','89200000-0000-0000-0000-000000000007');
insert into public.companies(id,legal_name,verification_status,account_status) values
('89200000-0000-0000-0005-000000000001','W6 Document Synthetic Company','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
('89200000-0000-0000-0005-000000000001','89200000-0000-0000-0000-000000000003','owner','active');
insert into public.contractors(id,agency_name,verification_status,account_status) values
('89200000-0000-0000-0006-000000000001','W6 Document Synthetic Contractor','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
('89200000-0000-0000-0006-000000000001','89200000-0000-0000-0000-000000000004','owner','active');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,
  specialization,candidate_type,total_experience,interview_available,consent,status,user_id,profile_status,
  profile_completion_status,availability_status,aadhaar_fingerprint,aadhaar_last4,date_of_birth,pincode)
values
('89200000-0000-0000-0001-000000000001','W6 Document Candidate A',25,'Female','9876500921','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','3 years','Yes',true,'new','89200000-0000-0000-0000-000000000001','active','complete','open_to_opportunities',repeat('a',64),'1111','2001-01-01','600001'),
('89200000-0000-0000-0001-000000000002','W6 Document Candidate B',26,'Male','9876500922','Pune','Pune','Maharashtra','Diploma','Mechanical','Experienced','4 years','Yes',true,'new','89200000-0000-0000-0000-000000000002','active','complete','open_to_opportunities',repeat('b',64),'2222','2000-01-01','411001');
insert into public.candidate_preferences(candidate_id,source) values
('89200000-0000-0000-0001-000000000001','candidate'),
('89200000-0000-0000-0001-000000000002','candidate');

do $$
begin
  if (select count(*) from pg_policies p where p.schemaname='storage' and p.tablename='objects'
      and p.policyname in ('Candidate inserts own private uploads','Candidate reads own private uploads',
        'Candidate updates own private uploads','Candidate deletes own unregistered private uploads',
        'Candidate document verifiers read registered uploads'))<>5 then
    raise exception 'Corrected Candidate Storage policy set is incomplete';
  end if;
  if not has_function_privilege('authenticated','private.is_current_candidate_storage_path(text)','execute')
     or not has_function_privilege('authenticated','private.can_read_candidate_storage_object(text)','execute')
     or not has_function_privilege('authenticated','private.can_delete_candidate_storage_object(text)','execute')
     or has_function_privilege('anon','private.is_current_candidate_storage_path(text)','execute')
     or has_function_privilege('anon','private.can_read_candidate_storage_object(text)','execute')
     or has_function_privilege('anon','private.can_delete_candidate_storage_object(text)','execute') then
    raise exception 'Candidate Storage policy helper execution boundary failed';
  end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='candidate_documents'
      and column_name in ('review_started_at','review_started_by','reviewed_at','reviewed_by'))<>4 then
    raise exception 'Candidate document review attribution columns are incomplete';
  end if;
end;
$$;

-- Candidate A may manage only its own UID-prefixed private objects.
set local role authenticated;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000001',true);
insert into storage.objects(id,bucket_id,name,owner,metadata) values
('89200000-0000-0000-0007-000000000001','candidate-private','89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000001/resume.pdf','89200000-0000-0000-0000-000000000001','{"mimetype":"application/pdf","size":2048}'::jsonb),
('89200000-0000-0000-0007-000000000002','candidate-private','89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000002/pan.pdf','89200000-0000-0000-0000-000000000001','{"mimetype":"application/pdf","size":3072}'::jsonb),
('89200000-0000-0000-0007-000000000003','candidate-private','89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000003/other.pdf','89200000-0000-0000-0000-000000000001','{"mimetype":"application/pdf","size":1024}'::jsonb),
('89200000-0000-0000-0007-000000000004','candidate-private','89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000004/delete-me.pdf','89200000-0000-0000-0000-000000000001','{"mimetype":"application/pdf","size":512}'::jsonb);
do $$ declare affected integer; begin
  if (select count(*) from storage.objects o where o.bucket_id='candidate-private' and o.id in
      ('89200000-0000-0000-0007-000000000001','89200000-0000-0000-0007-000000000002',
       '89200000-0000-0000-0007-000000000003','89200000-0000-0000-0007-000000000004'))<>4 then
    raise exception 'Candidate A could not read own private objects';
  end if;
  update storage.objects set metadata=metadata||'{"coverage":"candidate-owned"}'::jsonb
    where id='89200000-0000-0000-0007-000000000004';
  get diagnostics affected=row_count;
  if affected<>1 then raise exception 'Candidate A could not update own private object'; end if;
  delete from storage.objects where id='89200000-0000-0000-0007-000000000004';
  get diagnostics affected=row_count;
  if affected<>1 then raise exception 'Candidate A could not delete own unregistered private object'; end if;
end $$;
select set_config('w6.doc.resume',public.register_candidate_document('resume',
  '89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000001/resume.pdf',
  'resume.pdf','application/pdf',2048)::text,true);
select set_config('w6.doc.pan',public.register_candidate_document('pan',
  '89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000002/pan.pdf',
  'pan.pdf','application/pdf',3072)::text,true);
select set_config('w6.doc.other',public.register_candidate_document('other',
  '89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000003/other.pdf',
  'other.pdf','application/pdf',1024)::text,true);
do $$ declare affected integer; begin
  delete from storage.objects where id='89200000-0000-0000-0007-000000000001';
  get diagnostics affected=row_count;
  if affected<>0 then raise exception 'Candidate deleted a registered active document object'; end if;
  begin
    perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);
    raise exception 'Candidate started own document review';
  exception when raise_exception then
    if sqlerrm='Candidate started own document review' then raise; end if;
  end;
end $$;

-- Candidate B cannot read or mutate Candidate A paths.
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000002',true);
do $$ declare affected integer; begin
  if exists(select 1 from storage.objects o where o.id='89200000-0000-0000-0007-000000000001') then
    raise exception 'Candidate B read Candidate A private object';
  end if;
  begin
    insert into storage.objects(id,bucket_id,name,owner,metadata) values
      ('89200000-0000-0000-0007-000000000012','candidate-private',
       '89200000-0000-0000-0000-000000000001/89200000-0000-0000-0008-000000000012/spoof.pdf',
       '89200000-0000-0000-0000-000000000002','{"mimetype":"application/pdf","size":100}'::jsonb);
    raise exception 'Candidate B inserted into Candidate A path';
  exception when insufficient_privilege then null; when raise_exception then
    if sqlerrm='Candidate B inserted into Candidate A path' then raise; end if;
  end;
  update storage.objects set metadata=metadata where id='89200000-0000-0000-0007-000000000001';
  get diagnostics affected=row_count;
  if affected<>0 then raise exception 'Candidate B updated Candidate A private object'; end if;
  delete from storage.objects where id='89200000-0000-0000-0007-000000000001';
  get diagnostics affected=row_count;
  if affected<>0 then raise exception 'Candidate B deleted Candidate A private object'; end if;
end $$;

-- Non-Candidate authenticated identities cannot create or read Candidate-private objects.
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000003',true);
do $$ begin
  begin insert into storage.objects(id,bucket_id,name,owner,metadata) values
    ('89200000-0000-0000-0007-000000000013','candidate-private','89200000-0000-0000-0000-000000000003/89200000-0000-0000-0008-000000000013/company.pdf','89200000-0000-0000-0000-000000000003','{"mimetype":"application/pdf","size":100}'::jsonb);
    raise exception 'Company inserted Candidate-private object'; exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Company inserted Candidate-private object' then raise; end if; end;
  if exists(select 1 from storage.objects where id='89200000-0000-0000-0007-000000000001') then raise exception 'Company read Candidate object'; end if;
end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000004',true);
do $$ begin
  begin insert into storage.objects(id,bucket_id,name,owner,metadata) values
    ('89200000-0000-0000-0007-000000000014','candidate-private','89200000-0000-0000-0000-000000000004/89200000-0000-0000-0008-000000000014/contractor.pdf','89200000-0000-0000-0000-000000000004','{"mimetype":"application/pdf","size":100}'::jsonb);
    raise exception 'Contractor inserted Candidate-private object'; exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Contractor inserted Candidate-private object' then raise; end if; end;
  if exists(select 1 from storage.objects where id='89200000-0000-0000-0007-000000000001') then raise exception 'Contractor read Candidate object'; end if;
end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000005',true);
do $$ begin
  begin insert into storage.objects(id,bucket_id,name,owner,metadata) values
    ('89200000-0000-0000-0007-000000000015','candidate-private','89200000-0000-0000-0000-000000000005/89200000-0000-0000-0008-000000000015/recruiter.pdf','89200000-0000-0000-0000-000000000005','{"mimetype":"application/pdf","size":100}'::jsonb);
    raise exception 'Recruiter inserted Candidate-private object'; exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Recruiter inserted Candidate-private object' then raise; end if; end;
  if exists(select 1 from storage.objects where id='89200000-0000-0000-0007-000000000001') then raise exception 'Recruiter read Candidate object'; end if;
end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000006',true);
do $$ begin
  begin insert into storage.objects(id,bucket_id,name,owner,metadata) values
    ('89200000-0000-0000-0007-000000000016','candidate-private','89200000-0000-0000-0000-000000000006/89200000-0000-0000-0008-000000000016/operations.pdf','89200000-0000-0000-0000-000000000006','{"mimetype":"application/pdf","size":100}'::jsonb);
    raise exception 'Operations inserted Candidate-private object'; exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Operations inserted Candidate-private object' then raise; end if; end;
  if exists(select 1 from storage.objects where id='89200000-0000-0000-0007-000000000001') then raise exception 'Operations read Candidate object'; end if;
end $$;

reset role;
set local role anon;
do $$ begin
  begin
    if exists(select 1 from storage.objects where id='89200000-0000-0000-0007-000000000001') then
      raise exception 'Anonymous read Candidate-private Storage';
    end if;
  exception when insufficient_privilege then null; when raise_exception then
    if sqlerrm='Anonymous read Candidate-private Storage' then raise; end if;
  end;
end $$;
reset role;

-- Authorized verifier may read registered objects only, never write or delete them.
set local role authenticated;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000007',true);
do $$ declare affected integer; begin
  if (select count(*) from storage.objects o where o.id in
      ('89200000-0000-0000-0007-000000000001','89200000-0000-0000-0007-000000000002','89200000-0000-0000-0007-000000000003'))<>3 then
    raise exception 'Authorized verifier could not read registered Candidate objects';
  end if;
  begin insert into storage.objects(id,bucket_id,name,owner,metadata) values
    ('89200000-0000-0000-0007-000000000017','candidate-private','89200000-0000-0000-0000-000000000007/89200000-0000-0000-0008-000000000017/admin.pdf','89200000-0000-0000-0000-000000000007','{"mimetype":"application/pdf","size":100}'::jsonb);
    raise exception 'Verifier inserted Candidate-private object'; exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Verifier inserted Candidate-private object' then raise; end if; end;
  update storage.objects set metadata=metadata where id='89200000-0000-0000-0007-000000000001';
  get diagnostics affected=row_count;
  if affected<>0 then raise exception 'Verifier updated Candidate object'; end if;
  delete from storage.objects where id='89200000-0000-0000-0007-000000000001';
  get diagnostics affected=row_count;
  if affected<>0 then raise exception 'Verifier deleted Candidate object'; end if;
end $$;

-- Exact review state machine and attribution.
do $$ begin
  if not public.admin_review_candidate_document(current_setting('w6.doc.resume')::uuid,'under_verification',null) then raise exception 'Review start failed'; end if;
  begin perform public.admin_review_candidate_document(current_setting('w6.doc.resume')::uuid,'reupload_required','bad');
    raise exception 'Short re-upload feedback was accepted'; exception when raise_exception then if sqlerrm='Short re-upload feedback was accepted' then raise; end if; end;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.candidate_documents d where d.id=current_setting('w6.doc.resume')::uuid
      and d.verification_status='under_verification' and d.review_started_by='89200000-0000-0000-0000-000000000007'
      and d.review_started_at is not null and d.reviewed_by is null and d.reviewed_at is null
      and d.verified_by is null and d.verified_at is null) then raise exception 'Review-start attribution failed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000007',true);
do $$ begin
  if not public.admin_review_candidate_document(current_setting('w6.doc.resume')::uuid,'verified',null) then raise exception 'Document verification failed'; end if;
  if not public.admin_review_candidate_document(current_setting('w6.doc.pan')::uuid,'under_verification',null) then raise exception 'Second review start failed'; end if;
  if not public.admin_review_candidate_document(current_setting('w6.doc.pan')::uuid,'reupload_required','Upload a clearer synthetic PAN image.') then raise exception 'Re-upload request failed'; end if;
  begin perform public.admin_review_candidate_document(current_setting('w6.doc.resume')::uuid,'under_verification',null);
    raise exception 'Verified document regressed to review'; exception when raise_exception then if sqlerrm='Verified document regressed to review' then raise; end if; end;
end $$;
reset role;

do $$ begin
  if not exists(select 1 from public.candidate_documents d where d.id=current_setting('w6.doc.resume')::uuid
      and d.verification_status='verified' and d.reviewed_by='89200000-0000-0000-0000-000000000007'
      and d.reviewed_at is not null and d.verified_by=d.reviewed_by and d.verified_at=d.reviewed_at) then raise exception 'Final verification attribution failed'; end if;
  if not exists(select 1 from public.candidate_documents d where d.id=current_setting('w6.doc.pan')::uuid
      and d.verification_status='reupload_required' and d.review_started_by='89200000-0000-0000-0000-000000000007'
      and d.reviewed_by='89200000-0000-0000-0000-000000000007' and d.reviewed_at is not null
      and d.verified_by is null and d.verified_at is null and length(d.verification_feedback) between 5 and 1000) then raise exception 'Re-upload attribution/feedback failed'; end if;
  if (select count(*) from public.audit_logs l where l.entity_type='candidate_document'
      and l.entity_id in (current_setting('w6.doc.resume')::uuid,current_setting('w6.doc.pan')::uuid)
      and l.action in ('candidate.document_review_started','candidate.document_verified','candidate.document_reupload_requested')
      and l.actor_user_id='89200000-0000-0000-0000-000000000007')<>4 then raise exception 'Document review audit events failed'; end if;
  if exists(select 1 from public.audit_logs l where l.entity_type='candidate_document'
      and l.entity_id in (current_setting('w6.doc.resume')::uuid,current_setting('w6.doc.pan')::uuid)
      and (l.metadata::text ~ '[0-9]{12}' or l.metadata::text ilike '%storage%' or l.metadata::text ilike '%signed%')) then
    raise exception 'Sensitive document review data leaked to audit metadata'; end if;
  if pg_get_function_result('public.list_candidate_portal_documents()'::regprocedure) ~* 'review_started|reviewed_by|verified_by|storage_object' then
    raise exception 'Candidate document projection exposes internal review identity or Storage path'; end if;
end $$;

-- Every unauthorized role is denied review-state mutation.
set local role authenticated;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000001',true);
do $$ begin begin perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);raise exception 'Candidate reviewed document';exception when raise_exception then if sqlerrm='Candidate reviewed document' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000003',true);
do $$ begin begin perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);raise exception 'Company reviewed document';exception when raise_exception then if sqlerrm='Company reviewed document' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000004',true);
do $$ begin begin perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);raise exception 'Contractor reviewed document';exception when raise_exception then if sqlerrm='Contractor reviewed document' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000005',true);
do $$ begin begin perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);raise exception 'Recruiter reviewed document';exception when raise_exception then if sqlerrm='Recruiter reviewed document' then raise;end if;end;end $$;
select set_config('request.jwt.claim.sub','89200000-0000-0000-0000-000000000006',true);
do $$ begin begin perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);raise exception 'Operations reviewed document';exception when raise_exception then if sqlerrm='Operations reviewed document' then raise;end if;end;end $$;
reset role;
set local role anon;
do $$ begin begin perform public.admin_review_candidate_document(current_setting('w6.doc.other')::uuid,'under_verification',null);raise exception 'Anonymous reviewed document';exception when insufficient_privilege then null;when raise_exception then if sqlerrm='Anonymous reviewed document' then raise;end if;end;end $$;
reset role;

do $$ begin
  if not exists(select 1 from public.candidate_documents d where d.id=current_setting('w6.doc.other')::uuid
      and d.verification_status='uploaded' and d.review_started_by is null and d.reviewed_by is null and d.verified_by is null) then
    raise exception 'Unauthorized review attempt changed document state'; end if;
end $$;

rollback;
