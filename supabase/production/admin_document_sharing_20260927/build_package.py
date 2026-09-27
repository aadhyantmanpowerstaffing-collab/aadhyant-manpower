"""Build a guarded forward-only upgrade; never connect to a database."""
from pathlib import Path
import re,json,hashlib
P=Path(__file__).resolve().parent
R=P.parents[2]
old=P.parent/'tenant_resume_access_20260926'
q=lambda x:"'"+x.replace("'","''")+"'"
source=(P/'contracts.sql').read_text()
functions=[]
for m in re.finditer(r'CREATE (?:OR REPLACE )?FUNCTION ([\w.]+)\((.*?)\)\s*RETURNS ([\s\S]*?)\s*LANGUAGE (\w+)([\s\S]*?)AS \$\$([\s\S]*?)\$\$;',source):
 name,args,result,language,options,body=m.groups()
 identity=name+'('+','.join(a.strip().split()[1] for a in args.split(',') if a.strip())+')'
 functions.append(dict(identity=identity,hash=hashlib.md5(body.encode()).hexdigest(),browser=name.startswith('public.'),volatility='s' if 'STABLE' in options else 'v',language=language))
assert len(functions)==17,len(functions)
legacy=(old/'postcheck_read_only.sql').read_text().removeprefix('BEGIN READ ONLY;\n').split(") SELECT 'TENANT_RESUME_POSTCHECK'")[0]+')'
foundation=(R/'supabase/migrations/023_candidate_portal_foundation.sql').read_text()
extract=lambda name:re.search(r'create function '+re.escape(name)+r'\([\s\S]*?\$\$;',foundation,re.I).group()
update=extract('public.update_candidate_onboarding_details')
get=extract('public.get_candidate_onboarding_details')
bodyhash=lambda s:hashlib.md5(s.split('$$')[1].encode()).hexdigest()
additional=f"""
 IF to_regclass('public.candidate_onboarding_details') IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.candidate_onboarding_details') AND relrowsecurity AND pg_get_userbyid(relowner)='postgres') THEN RAISE EXCEPTION 'Canonical onboarding table with RLS required'; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('public.candidate_onboarding_details') AND attname IN ('bank_account_number','sharing_revision') AND NOT attisdropped)
 OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('private.candidate_resume_shares') AND attname='authorization_mode' AND NOT attisdropped) THEN RAISE EXCEPTION 'Upgrade collision; do not replay'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text)') AND md5(prosrc)={q(bodyhash(update))} AND prosecdef AND pg_get_userbyid(proowner)='postgres')
 OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.get_candidate_onboarding_details()') AND md5(prosrc)={q(bodyhash(get))}) THEN RAISE EXCEPTION 'Onboarding source contract mismatch; collect exact deployed definition'; END IF;
 IF has_any_column_privilege('authenticated','public.candidate_onboarding_details','SELECT,INSERT,UPDATE,REFERENCES') OR has_any_column_privilege('anon','public.candidate_onboarding_details','SELECT,INSERT,UPDATE,REFERENCES') THEN RAISE EXCEPTION 'Unexpected browser onboarding privileges'; END IF;
"""
guard="DO $guard$ DECLARE failed text; BEGIN\n"+legacy+" SELECT string_agg(check_name,',' ORDER BY check_name) INTO failed FROM checks WHERE NOT coalesce(ok,false);\n IF failed IS NOT NULL THEN RAISE EXCEPTION 'Resume baseline mismatch: %',failed; END IF;\n"+additional+"END $guard$;\n"
(P/'preflight_read_only.sql').write_text("BEGIN READ ONLY;\nSET LOCAL statement_timeout='30s';\n"+guard+"SELECT 'ADMIN_DOCUMENT_PREFLIGHT=PASS';\nROLLBACK;\n")
acl='\n'.join(f"ALTER FUNCTION {f['identity']} OWNER TO postgres;\nREVOKE ALL ON FUNCTION {f['identity']} FROM PUBLIC,anon,authenticated;"+(f"\nGRANT EXECUTE ON FUNCTION {f['identity']} TO authenticated;" if f['browser'] else '') for f in functions)+'\n'
checks=[]
for f in functions:
 checks.append(f"SELECT {q(f['identity'])} name,EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure({q(f['identity'])}) AND md5(p.prosrc)={q(f['hash'])} AND p.prosecdef AND p.provolatile={q(f['volatility'])} AND l.lanname={q(f['language'])} AND pg_get_userbyid(p.proowner)='postgres' AND (p.proconfig @> ARRAY['search_path='] OR p.proconfig @> ARRAY['search_path=\"\"']) AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND has_function_privilege('authenticated',p.oid,'EXECUTE')={'true' if f['browser'] else 'false'}) ok")
# Pin unchanged authorization and Storage predicates as part of the new postcheck too.
oldsource=(old/'contracts.sql').read_text()
for name,identity,browser in [('private.resume_application_recipients','private.resume_application_recipients(uuid)',False),('private.current_resume_recipient','private.current_resume_recipient(text)',False),('private.can_read_shared_candidate_resume','private.can_read_shared_candidate_resume(text)',True)]:
 body=re.search(r'CREATE FUNCTION '+re.escape(name)+r'\([\s\S]*?AS \$\$([\s\S]*?)\$\$;',oldsource).group(1)
 checks.append(f"SELECT {q(identity)},EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure({q(identity)}) AND md5(prosrc)={q(hashlib.md5(body.encode()).hexdigest())} AND prosecdef AND pg_get_userbyid(proowner)='postgres' AND NOT has_function_privilege('anon',oid,'EXECUTE') AND has_function_privilege('authenticated',oid,'EXECUTE')={'true' if browser else 'false'})")
checks += ["""SELECT 'private_grants',EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('private.candidate_resume_shares') AND relrowsecurity) AND NOT has_any_column_privilege('authenticated','private.candidate_resume_shares','SELECT,INSERT,UPDATE,REFERENCES') AND NOT has_any_column_privilege('anon','private.candidate_resume_shares','SELECT,INSERT,UPDATE,REFERENCES')""",
"""SELECT 'onboarding_rls_acl',EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.candidate_onboarding_details') AND relrowsecurity) AND NOT has_any_column_privilege('authenticated','public.candidate_onboarding_details','SELECT,INSERT,UPDATE,REFERENCES') AND NOT has_any_column_privilege('anon','public.candidate_onboarding_details','SELECT,INSERT,UPDATE,REFERENCES')""",
"""SELECT 'new_constraints',(SELECT count(*)=4 AND bool_and(convalidated) FROM pg_constraint WHERE (conrelid=to_regclass('private.candidate_resume_shares') AND conname IN ('candidate_sharing_mode_check','candidate_sharing_item_check','candidate_sharing_item_unique')) OR (conrelid=to_regclass('public.candidate_onboarding_details') AND conname='candidate_onboarding_full_account_check'))""",
"""SELECT 'onboarding_revision_trigger',EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass('public.candidate_onboarding_details') AND tgname='candidate_onboarding_sharing_revision' AND tgenabled='O' AND tgfoid=to_regprocedure('private.rotate_onboarding_share_revision()'))""",
"""SELECT 'storage_recipient_policy',EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='Recipients read Admin shared resumes' AND cmd='SELECT' AND roles=ARRAY['authenticated']::name[] AND qual='((bucket_id = ''candidate-private''::text) AND private.can_read_shared_candidate_resume(name))')"""]
post="WITH checks AS (\n"+'\nUNION ALL\n'.join(checks)+"\n) SELECT string_agg(name,',' ORDER BY name) INTO failed FROM checks WHERE NOT coalesce(ok,false);"
postguard="DO $post$ DECLARE failed text; BEGIN\n"+post+"\nIF failed IS NOT NULL THEN RAISE EXCEPTION 'Document sharing postcheck mismatch: %',failed; END IF; END $post$;\n"
(P/'postcheck_read_only.sql').write_text("BEGIN READ ONLY;\nSET LOCAL statement_timeout='30s';\n"+postguard+"SELECT 'ADMIN_DOCUMENT_POSTCHECK=PASS';\nROLLBACK;\n")
(P/'forward_proposed.sql').write_text("BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='60s';\n"+guard+source+acl+postguard+"NOTIFY pgrst,'reload schema';\nCOMMIT;\nSELECT 'ADMIN_DOCUMENT_REPAIR=COMMITTED';\n")
# Source-faithful additional fixture definitions: local-only, not a Production migration replay.
onboarding=re.search(r'create table public.candidate_onboarding_details \([\s\S]*?\n\);',foundation,re.I).group()
fixture=onboarding+"\nCREATE TRIGGER candidate_onboarding_details_set_updated_at BEFORE UPDATE ON public.candidate_onboarding_details FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();\nALTER TABLE public.candidate_onboarding_details ENABLE ROW LEVEL SECURITY;\nREVOKE ALL ON public.candidate_onboarding_details FROM PUBLIC,anon,authenticated;\n"+get+'\n'+update+"\nREVOKE ALL ON FUNCTION public.get_candidate_onboarding_details(),public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text) FROM PUBLIC,anon;\nGRANT EXECUTE ON FUNCTION public.get_candidate_onboarding_details(),public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text) TO authenticated;\n"
(P/'fixture_onboarding.sql').write_text(fixture)
(P/'function_contracts.json').write_text(json.dumps(functions,indent=2)+'\n')
(P/'manifest.json').write_text(json.dumps({'scope':'Draft Admin document and joining-details upgrade. Production execution not authorized by this manifest.','base_commit':'7bb195d5574f8e994fe5d363b542f87d27594011','files':{n:hashlib.sha256((P/n).read_bytes()).hexdigest() for n in ['contracts.sql','forward_proposed.sql','preflight_read_only.sql','postcheck_read_only.sql','fixture_onboarding.sql','function_contracts.json']}},indent=2)+'\n')
print('DOCUMENT_PACKAGE_BUILT')
# Operational stop: revoke effective sharing, preserve documents, joining details and audit.
# No auto rollback on an error after commit, and no attempt to reconstruct dropped raw values.
pause="BEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='60s';\n"+postguard+"""REVOKE ALL ON FUNCTION public.admin_set_application_document_share(uuid,text,text,uuid,text,uuid,boolean) FROM authenticated;
WITH stopped AS (
 UPDATE private.candidate_resume_shares SET share_revoked_at=now(),revision=gen_random_uuid()
 WHERE shared_at IS NOT NULL AND share_revoked_at IS NULL RETURNING id
)
INSERT INTO public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
SELECT auth.uid(),'system','admin.candidate_item_share_revoked','candidate_item_share',id,'system',jsonb_build_object('shared',false) FROM stopped;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'ADMIN_DOCUMENT_SHARING_PAUSED=COMMITTED';
"""
(P/'pause_sharing_guarded.sql').write_text(pause)
m=json.loads((P/'manifest.json').read_text());m['files']['pause_sharing_guarded.sql']=hashlib.sha256(pause.encode()).hexdigest();(P/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
