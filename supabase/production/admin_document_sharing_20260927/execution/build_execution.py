"""Package the already-tested SQL without modifying it. No database or network."""
from pathlib import Path
import json,hashlib,re,shutil
P=Path(__file__).resolve().parent
sql=['preflight_read_only.sql','forward_proposed.sql','postcheck_read_only.sql']
expected=json.loads((P.parent/'manifest.json').read_text())['files']
for name in sql:
    source=P.parent/name
    assert hashlib.sha256(source.read_bytes()).hexdigest()==expected[name],name
    shutil.copyfile(source,P/name)
pins=sql+['Execution.Core.psm1','test_execution_parser.ps1']+[f'fixtures/{n}-success.txt' for n in ['preflight','forward','postcheck']]
runner=(P/'START_APPROVED_UPGRADE.ps1').read_text()
for name in pins:
    digest=hashlib.sha256((P/name).read_bytes()).hexdigest()
    runner,count=re.subn(r"('"+re.escape(name)+r"' = ')[^']*'",lambda m:m[1]+digest+"'",runner)
    assert count==1,name
(P/'START_APPROVED_UPGRADE.ps1').write_text(runner)
files=pins+['START_APPROVED_UPGRADE.ps1','README.md','validation.json']
(P/'execution_manifest.json').write_text(json.dumps({'scope':'Proposed Admin documents/joining-details upgrade; explicit Production approval required','files':[
    {'path':n,'sha256':hashlib.sha256((P/n).read_bytes()).hexdigest(),'bytes':(P/n).stat().st_size} for n in files
]},indent=2)+'\n')
print('GUARDED_EXECUTION_PACKAGE_BUILT')
