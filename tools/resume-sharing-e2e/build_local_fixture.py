"""Build the disposable fixture from captured source definitions. Never connect remotely."""
from pathlib import Path
import re
import runpy

here = Path(__file__).resolve().parent
repo = here.parent.parent
package = repo / 'supabase/production/tenant_resume_access_20260926'
model = runpy.run_path(str(package / 'build_package.py'))
statements = model['f']
out = ["""-- FRESH LOCAL SUPABASE ONLY. Genuine managed Auth/Storage preserved.
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
GRANT USAGE ON SCHEMA private TO authenticated;"""]
for statement in statements[2:]:
    # Statements may contain multiline function bodies: never split them by line.
    if re.match(r'(?:CREATE|ALTER) TABLE (?:auth|storage)\.', statement):
        continue
    if re.match(r'CREATE (?:UNIQUE )?INDEX', statement) and re.search(r' ON (?:auth|storage)\.', statement):
        continue
    if re.match(r'(?:CREATE OR REPLACE|ALTER|REVOKE ALL ON|GRANT EXECUTE ON) FUNCTION (?:auth|storage)\.', statement):
        continue
    statement = re.sub(r"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon,authenticated,service_role;", '', statement)
    out.append(statement)
for table in model['cat']['tables']:
    if table['identity'].startswith('public.'):
        out.append('REVOKE ALL ON '+table['identity']+' FROM PUBLIC,anon,authenticated;')
source = (repo / 'supabase/migrations/023_candidate_portal_foundation.sql').read_text()
match = re.search(r'create function public\.register_candidate_document\([\s\S]*?\$\$;', source, re.I)
assert match, 'Source registration contract missing'
out.append(match.group())
out.append("""REVOKE ALL ON FUNCTION public.register_candidate_document(text,text,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_candidate_document(text,text,text,text,bigint) TO authenticated;
COMMIT;
NOTIFY pgrst,'reload schema';
SELECT 'RESUME_FIXTURE_BOOTSTRAP=PASS';""")
(here / 'bootstrap_local_supabase.sql').write_text('\n'.join(out)+'\n')
print('MATERIALIZED_LOCAL_FIXTURE=PASS')
