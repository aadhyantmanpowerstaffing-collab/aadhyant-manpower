"""Build only the bounded read-only review; no database or network access."""
from pathlib import Path
import hashlib,json,re,shutil
P=Path(__file__).resolve().parent
shutil.copyfile(P.parent/'preflight_read_only.sql',P/'preflight_read_only.sql')
names=['preflight_read_only.sql','Review.Core.psm1','test_review_parser.ps1','fixtures/preflight-success.txt']
pins={n:hashlib.sha256((P/n).read_bytes()).hexdigest() for n in names}
runner=(P/'START_READ_ONLY_CHECK.ps1').read_text()
for name,h in pins.items():
    runner,count=re.subn(r"('"+re.escape(name)+r"' = ')[^']*'",lambda m:m[1]+h+"'",runner)
    assert count==1,name
(P/'START_READ_ONLY_CHECK.ps1').write_text(runner)
names+=['START_READ_ONLY_CHECK.ps1','README.md','validation.json']
(P/'review_manifest.json').write_text(json.dumps({'scope':'Read-only Production preflight; no write SQL included','files':[
    {'path':n,'sha256':hashlib.sha256((P/n).read_bytes()).hexdigest(),'bytes':(P/n).stat().st_size} for n in names
]},indent=2)+'\n')
print('READ_ONLY_REVIEW_PACKAGE_BUILT')
