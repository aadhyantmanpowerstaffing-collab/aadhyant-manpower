"""Deterministic local packaging; no remote connections, installed-migration edits or replay."""
import json,re,hashlib
from pathlib import Path
P=Path(__file__).resolve().parent
cat=json.loads((P/'catalog.json').read_text())
source=(P/'contracts.sql').read_text()
q=lambda s:"'"+str(s).replace("'","''")+"'"
qi=lambda s:'"'+s.replace('"','""')+'"'
js=lambda o:q(json.dumps(o,separators=(',',':')))+'::jsonb'
write=lambda n,s:(P/n).write_text(s)
targets=[]
for m in re.finditer(r'CREATE FUNCTION ([\w.]+)\((.*?)\)\s*RETURNS ([\s\S]*?)\s*LANGUAGE (\w+)([\s\S]*?)AS \$\$([\s\S]*?)\$\$;',source):
 name,args,result,lang,options,body=m.groups();parts=[a.strip().split() for a in args.split(',') if a.strip()]
 identity=name+'('+','.join(a[1] for a in parts)+')'
 result=re.sub(r'\s+',' ',result).replace('TABLE(', 'TABLE(');result=re.sub(r',\s*',', ',result)
 targets.append(dict(identity=identity,name=name.split('.')[1],schema=name.split('.')[0],args=[a[0] for a in parts],result=result,lang=lang,volatility='s' if 'STABLE' in options else 'v',hash=hashlib.md5(body.encode()).hexdigest(),browser=name.startswith('public.') or name=='private.can_read_shared_candidate_resume'))
assert len(targets)==11,len(targets)
base_deps=[{k:f[k] for k in ['identity','hash','security_definer','owner','authenticated','anon','proconfig']} for f in cat['functions']]
expected_tables=[{k:t[k] for k in ['identity','rls','columns','constraints']} for t in cat['tables'] if t['identity'].startswith('public.')]
# The resume feature only reads requirement identity/ownership/stage; unrelated vacancy business checks are not repair preconditions.
for t in expected_tables:
 if t['identity']=='public.employer_requirements': t['constraints']=[c for c in t['constraints'] if c['type'] in ('p','f','u')]
col="""(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped)"""
cons="""(SELECT jsonb_agg(jsonb_build_object('name',conname,'type',contype,'definition',pg_get_constraintdef(oid),'validated',convalidated) ORDER BY conname) FROM pg_constraint WHERE conrelid=c.oid AND (c.oid<>to_regclass('public.employer_requirements') OR contype IN ('p','f','u')))"""
policy_query="""SELECT jsonb_agg(jsonb_build_object('name',policyname,'roles',roles,'cmd',cmd,'qual',qual,'with_check',with_check) ORDER BY policyname) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname<>'Recipients read Admin shared resumes'"""
base=f"""WITH deps AS (SELECT * FROM jsonb_to_recordset({js(base_deps)}) AS x(identity text,hash text,security_definer boolean,owner text,authenticated boolean,anon boolean,proconfig text[])),
 tables AS (SELECT * FROM jsonb_to_recordset({js(expected_tables)}) AS x(identity text,rls boolean,columns jsonb,constraints jsonb)),
 prerequisites AS (
 SELECT 'executor'::text check_name,current_user='postgres' ok
 UNION ALL SELECT 'helper:'||e.identity,coalesce(md5(p.prosrc)=e.hash AND p.prosecdef=e.security_definer AND pg_get_userbyid(p.proowner)=e.owner AND coalesce(p.proconfig,ARRAY[]::text[])=coalesce(e.proconfig,ARRAY[]::text[]) AND has_function_privilege('authenticated',p.oid,'EXECUTE')=e.authenticated AND has_function_privilege('anon',p.oid,'EXECUTE')=e.anon,false) FROM deps e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.identity)
 UNION ALL SELECT 'table:'||e.identity,coalesce(c.relrowsecurity=e.rls AND {col}=e.columns AND {cons}=e.constraints,false) FROM tables e LEFT JOIN pg_class c ON c.oid=to_regclass(e.identity)
 UNION ALL SELECT 'storage_rls',coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('storage.objects')),false)
 UNION ALL SELECT 'storage_baseline',coalesce(({policy_query}),'[]'::jsonb)={js(cat['storage_policies'])}
 UNION ALL SELECT 'private_bucket',EXISTS(SELECT 1 FROM storage.buckets WHERE id='candidate-private' AND public=false AND file_size_limit=10485760 AND (SELECT array_agg(m ORDER BY m) FROM unnest(allowed_mime_types)m)=ARRAY['application/pdf','image/jpeg','image/png'])
 UNION ALL SELECT 'documents_acl',NOT EXISTS(SELECT 1 FROM (VALUES('anon'),('authenticated'))r(role_name) CROSS JOIN (VALUES('SELECT'),('INSERT'),('UPDATE'),('DELETE'))v(privilege) WHERE has_table_privilege(r.role_name,'public.candidate_documents',v.privilege))
)"""
collision=' AND '.join([f"NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname={q(t['schema'])} AND p.proname={q(t['name'])})" for t in targets])
pre=base+f""", checks AS(SELECT * FROM prerequisites UNION ALL SELECT 'new_object_collision',to_regclass('private.candidate_resume_shares') IS NULL AND {collision} AND NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='Recipients read Admin shared resumes'))
 SELECT 'TENANT_RESUME_PREFLIGHT' AS marker,CASE WHEN bool_and(ok) THEN 'PASS' ELSE 'FAIL' END AS status,coalesce(string_agg(check_name,',' ORDER BY check_name) FILTER(WHERE NOT ok),'none') AS failed_checks FROM checks"""
post=base+f""", targets AS(SELECT * FROM jsonb_to_recordset({js(targets)}) AS x(identity text,name text,schema text,args text[],result text,lang text,volatility text,hash text,browser boolean)), checks AS(
 SELECT * FROM prerequisites
 UNION ALL SELECT 'function:'||e.identity,coalesce(md5(p.prosrc)=e.hash AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres' AND p.provolatile::text=e.volatility AND p.proargnames[1:p.pronargs]=e.args AND pg_get_function_result(p.oid)=e.result AND (SELECT lanname FROM pg_language WHERE oid=p.prolang)=e.lang AND p.proconfig=ARRAY['search_path=""'] AND has_function_privilege('authenticated',p.oid,'EXECUTE')=e.browser AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE') AND (SELECT count(*) FROM pg_proc pp JOIN pg_namespace n ON n.oid=pp.pronamespace WHERE n.nspname=e.schema AND pp.proname=e.name)=1,false) FROM targets e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.identity)
 UNION ALL SELECT 'sharing_table_security',coalesce((SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('private.candidate_resume_shares')),false) AND NOT EXISTS(SELECT 1 FROM (VALUES('anon'),('authenticated'))r(role_name) CROSS JOIN (VALUES('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'))v(privilege) WHERE has_table_privilege(r.role_name,to_regclass('private.candidate_resume_shares'),v.privilege))
 UNION ALL SELECT 'sharing_policy',EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='Recipients read Admin shared resumes' AND cmd='SELECT' AND roles=ARRAY['authenticated']::name[] AND qual='((bucket_id = ''candidate-private''::text) AND private.can_read_shared_candidate_resume(name))' AND with_check IS NULL)
) SELECT 'TENANT_RESUME_POSTCHECK' AS marker,CASE WHEN bool_and(ok) THEN 'PASS' ELSE 'FAIL' END AS status,coalesce(string_agg(check_name,',' ORDER BY check_name) FILTER(WHERE NOT ok),'none') AS failed_checks FROM checks"""
table_model=json.loads((P/'sharing_table_contract.json').read_text())
assert table_model['source_sha256']==hashlib.sha256(source.encode()).hexdigest(),'Regenerate the local sharing-table contract after changing contracts.sql'
shape=f" UNION ALL SELECT 'sharing_table_shape',coalesce((SELECT {col}={js(table_model['columns'])} AND {cons}={js(table_model['constraints'])} AND pg_get_userbyid(c.relowner)='postgres' FROM pg_class c WHERE c.oid=to_regclass('private.candidate_resume_shares')),false) AND NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='private' AND tablename='candidate_resume_shares')\n"
post=post.replace(") SELECT 'TENANT_RESUME_POSTCHECK'",shape+") SELECT 'TENANT_RESUME_POSTCHECK'")
write('preflight_read_only.sql','BEGIN READ ONLY;\n'+pre+';\nROLLBACK;\n')
write('postcheck_read_only.sql','BEGIN READ ONLY;\n'+post+';\nROLLBACK;\n')
guard=lambda query: "DO $guard$ DECLARE v_resume_gate_result record; BEGIN FOR v_resume_gate_result IN "+query+" LOOP IF v_resume_gate_result.status<>'PASS' THEN RAISE EXCEPTION 'Resume package guard failed: %',v_resume_gate_result.failed_checks; END IF; END LOOP; END $guard$;\n"
acl='\n'.join(f"ALTER FUNCTION {t['identity']} OWNER TO postgres;\nREVOKE ALL ON FUNCTION {t['identity']} FROM PUBLIC,anon,authenticated;"+(f"\nGRANT EXECUTE ON FUNCTION {t['identity']} TO authenticated;" if t['browser'] else '') for t in targets)
write('forward_proposed.sql',"-- PROPOSED. No Production approval for this new scope yet. Do not execute remotely.\nBEGIN;\nSET LOCAL lock_timeout='5s';\nSET LOCAL statement_timeout='45s';\n"+guard(pre)+source+'\n'+acl+'\n'+guard(post)+"NOTIFY pgrst,'reload schema';\nCOMMIT;\nSELECT 'TENANT_RESUME_REPAIR=COMMITTED';\n")
write('rollback_guarded.sql',"-- Separate approval required. Retain consent/release/audit evidence.\nBEGIN;\nSET LOCAL lock_timeout='5s';\n"+guard(post)+'DROP POLICY "Recipients read Admin shared resumes" ON storage.objects;\n'+'\n'.join('DROP FUNCTION '+t['identity']+' RESTRICT;' for t in reversed(targets))+"\nNOTIFY pgrst,'reload schema';\nCOMMIT;\nSELECT 'TENANT_RESUME_ROLLBACK=COMMITTED';\n")
# Exact captured columns/constraints/helper bodies; SQL engine fixture only.
f=["-- LOCAL SQL ENGINE ONLY. Captured catalogs; synthetic SQL principals, not Auth/Storage services.","CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA storage; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE supabase_auth_admin; CREATE ROLE supabase_storage_admin; GRANT USAGE ON SCHEMA public,auth,private,storage TO anon,authenticated,supabase_auth_admin,supabase_storage_admin; CREATE TYPE storage.buckettype AS ENUM ('STANDARD','ANALYTICS','VECTOR');"]
for t in cat['tables']:
 columns=[]
 for c in t['columns']:
  s=qi(c['name'])+' '+c['type']
  if c['generated']:s+=' GENERATED ALWAYS AS ('+c['default']+') STORED'
  elif c['default']:s+=' DEFAULT '+c['default']
  if c['not_null']:s+=' NOT NULL'
  columns.append(s)
 f.append('CREATE TABLE '+t['identity']+'('+','.join(columns)+');')
for is_fk in [False,True]:
 for t in cat['tables']:
  for c in t['constraints'] or []:
   if (c['type']=='f')==is_fk:f.append('ALTER TABLE '+t['identity']+' ADD CONSTRAINT '+qi(c['name'])+' '+c['definition']+';')
for t in cat['tables']:
 if t['rls']:f.append('ALTER TABLE '+t['identity']+' ENABLE ROW LEVEL SECURITY;')
 for idx in t['indexes'] or []:f.append(idx+';')
order=['auth.uid()','storage.foldername(text)','private.set_updated_at()','private.is_admin()','private.is_bootstrap_recruitment_admin()','private.current_staff_profile_id()','private.current_staff_roles()','private.has_staff_role(text)','private.current_candidate_portal_id()','private.current_company_portal_id(boolean)','private.current_contractor_portal_id(boolean)','private.can_verify_candidate_documents()','private.is_current_candidate_storage_path(text)','private.can_read_candidate_storage_object(text)','private.can_delete_candidate_storage_object(text)','public.admin_list_candidate_documents(uuid)','public.admin_get_candidate_document_access(uuid)','public.admin_review_candidate_document(uuid,text,text)']
for identity in order:
 d=next(x for x in cat['functions'] if x['identity']==identity)
 def escape(m):return 'AS E'+q(m.group(1).replace('\\','\\\\').replace('\r','\\r').replace('\n','\\n').replace('\t','\\t'))
 definition=re.sub(r'AS \$function\$([\s\S]*?)\$function\$',escape,d['definition']).replace('\r\n','\n')
 f.extend([definition+';',f'ALTER FUNCTION {identity} OWNER TO {qi(d["owner"])};',f'REVOKE ALL ON FUNCTION {identity} FROM PUBLIC,anon,authenticated;'])
 for role in ['anon','authenticated']:
  if d[role]:f.append(f'GRANT EXECUTE ON FUNCTION {identity} TO {role};')
for t in cat['tables']:
 for tr in t['triggers'] or []:
  if tr['function_identity']=='private.set_updated_at()':f.append(tr['definition']+';')
for p in cat['storage_policies']:
 s='CREATE POLICY '+qi(p['name'])+' ON storage.objects FOR '+p['cmd']+' TO '+','.join(qi(r) for r in p['roles'])
 if p['qual']:s+=' USING ('+p['qual']+')'
 if p['with_check']:s+=' WITH CHECK ('+p['with_check']+')'
 f.append(s+';')
f.append("GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated; INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('candidate-private','candidate-private',false,10485760,ARRAY['application/pdf','image/jpeg','image/png']); ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon,authenticated,service_role;")
write('fixture_sql_engine_only.sql','\n'.join(f)+'\n')
files=['sharing_table_contract.json','contracts.sql','forward_proposed.sql','preflight_read_only.sql','postcheck_read_only.sql','rollback_guarded.sql','fixture_sql_engine_only.sql']
write('manifest.json',json.dumps({'status':'LOCAL_DRAFT_NOT_APPROVED_FOR_PRODUCTION','project_ref':'wsuctjhbqiedttfnwjvf','targets':targets,'files':{n:hashlib.sha256((P/n).read_bytes()).hexdigest() for n in files}},indent=2)+'\n')
print('PACKAGE_BUILT: 1 private table, 6 public RPCs, 5 private helpers, 1 SELECT policy')
