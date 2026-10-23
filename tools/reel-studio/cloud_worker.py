"""Bounded GitHub-hosted worker. OIDC replaces any stored service-role credential."""
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.parse
import urllib.request

ENDPOINT='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/recruitment-reels'

def token():
    url=os.environ['ACTIONS_ID_TOKEN_REQUEST_URL']+'&audience='+urllib.parse.quote('aadhyant-reels')
    request=urllib.request.Request(url,headers={'Authorization':'Bearer '+os.environ['ACTIONS_ID_TOKEN_REQUEST_TOKEN']})
    with urllib.request.urlopen(request,timeout=30) as response:
        return json.load(response)['value']

def call(payload=None,video=None,job=None):
    headers={'Authorization':'Bearer '+token(),'Content-Type':'application/json'}
    data=json.dumps(payload).encode()
    if video is not None:
        data=video.read_bytes()
        if not 100<len(data)<=25_000_000: raise ValueError('Video size outside limits')
        headers.update({'Content-Type':'video/mp4','X-Job-Id':job['id'],'X-Claim-Token':job['claim']})
    req=urllib.request.Request(ENDPOINT,data=data,headers=headers,method='POST')
    with urllib.request.urlopen(req,timeout=120) as response: return json.load(response)

def main():
    if len(sys.argv)!=3 or sys.argv[1] not in ('claim','render'): raise ValueError('Expected claim/render and a local job path')
    path=Path(sys.argv[2])
    if sys.argv[1]=='claim':
        job=call({'action':'claim'})['job']
        if job:
            path.write_text(json.dumps(job),encoding='utf-8');path.chmod(0o600)
        print('Video queued for rendering.' if job else 'No video pending.')
        return
    job=json.loads(path.read_text())
    try:
        from studio import render
        with tempfile.TemporaryDirectory(prefix='reel-cloud-') as tmp:
            output=Path(tmp)/'reel.mp4'
            render(job['payload'],output)
            result=call(video=output,job=job)
            if result.get('ready') is not True: raise ValueError('Completion not confirmed')
        print('Video ready in the portal.')
    except Exception:
        # Report only safe status. Never print remote bodies, claims, credentials or payloads.
        try: call({'action':'fail','id':job['id'],'claim':job['claim']})
        except Exception: pass
        print('Video generation failed; bounded retry will be handled by the queue.',file=sys.stderr)
        sys.exit(1)
    finally:
        path.unlink(missing_ok=True)

if __name__=='__main__':main()
