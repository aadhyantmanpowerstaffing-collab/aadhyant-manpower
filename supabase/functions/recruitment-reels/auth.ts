const issuer='https://token.actions.githubusercontent.com';
const decode=(s:string)=>Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
export async function verifyWorker(token:string,approvedSha:string,fetcher:typeof fetch=fetch,now=Date.now()):Promise<string>{
 if(!/^[a-f0-9]{40}$/.test(approvedSha)||token.length>20000)throw Error('Denied');
 const parts=token.split('.');if(parts.length!==3)throw Error('Denied');
 const header=JSON.parse(new TextDecoder().decode(decode(parts[0]))),p=JSON.parse(new TextDecoder().decode(decode(parts[1])));
 const seconds=Math.floor(now/1000);
 if(header.alg!=='RS256'||typeof header.kid!=='string'||p.iss!==issuer||p.aud!=='aadhyant-reels'||!Number.isFinite(p.exp)||p.exp<=seconds||!Number.isFinite(p.iat)||p.iat>seconds+30||seconds-p.iat>600||(p.nbf&&p.nbf>seconds+30)||p.repository_id!=='1327419126'||p.repository_owner_id!=='314520724'||p.repository!=='aadhyantmanpowerstaffing-collab/aadhyant-manpower'||p.ref!=='refs/heads/main'||p.workflow_ref!=='aadhyantmanpowerstaffing-collab/aadhyant-manpower/.github/workflows/recruitment-reels.yml@refs/heads/main'||p.workflow_sha!==approvedSha||!['schedule','workflow_dispatch'].includes(p.event_name)||p.runner_environment!=='github-hosted'||!/^\d+$/.test(p.run_id)||!/^\d+$/.test(p.run_attempt))throw Error('Denied');
 const response=await fetcher(issuer+'/.well-known/jwks',{redirect:'error',signal:AbortSignal.timeout(10000)});if(!response.ok)throw Error('Denied');
 const jwks=await response.json(),jwk=jwks.keys?.find((k:any)=>k.kid===header.kid&&k.kty==='RSA'&&k.use==='sig');if(!jwk)throw Error('Denied');
 const key=await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
 if(!await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,decode(parts[2]),new TextEncoder().encode(parts[0]+'.'+parts[1])))throw Error('Denied');
 return p.run_id+':'+p.run_attempt;
}
