import test from 'node:test';import assert from 'node:assert/strict';
import {verifyWorker} from '../supabase/functions/recruitment-reels/auth.ts';
import {handleReels} from '../supabase/functions/recruitment-reels/index.ts';
const sha='a'.repeat(40),now=Date.now();
const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',hash:'SHA-256',modulusLength:2048,publicExponent:new Uint8Array([1,0,1])},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'test',use:'sig'};
const encode=(v:unknown)=>Buffer.from(JSON.stringify(v)).toString('base64url');
async function token(changes={}){const p={iss:'https://token.actions.githubusercontent.com',aud:'aadhyant-reels',exp:Math.floor(now/1000)+300,iat:Math.floor(now/1000),repository_id:'1327419126',repository_owner_id:'314520724',repository:'aadhyantmanpowerstaffing-collab/aadhyant-manpower',ref:'refs/heads/main',workflow_ref:'aadhyantmanpowerstaffing-collab/aadhyant-manpower/.github/workflows/recruitment-reels.yml@refs/heads/main',workflow_sha:sha,event_name:'schedule',runner_environment:'github-hosted',run_id:'1',run_attempt:'1',...changes};const data=encode({alg:'RS256',kid:'test'})+'.'+encode(p);return data+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(data))).toString('base64url');}
const fetcher=async()=>Response.json({keys:[jwk]});
test('GitHub OIDC requires signed, unexpired exact repo, branch, workflow and approved source identity',async()=>{
assert.equal(await verifyWorker(await token(),sha,fetcher as typeof fetch,now),'1:1');
for(const changes of [{exp:1},{iat:Math.floor(now/1000)-1000},{aud:'wrong'},{repository_id:'other'},{repository_owner_id:'other'},{ref:'refs/heads/feature'},{workflow_sha:'b'.repeat(40)},{event_name:'pull_request'},{runner_environment:'self-hosted'},{workflow_ref:'other.yml'}])await assert.rejects(verifyWorker(await token(changes),sha,fetcher as typeof fetch,now));
const signed=await token();await assert.rejects(verifyWorker(signed.slice(0,-8)+'AAAAAAAA',sha,fetcher as typeof fetch,now));
});
test('unauthenticated endpoint rejects before any database access and invalid admin ID is bounded',async()=>{
let calls=0;const noFetch=async()=>{calls++;throw Error('Unexpected fetch');};const get=()=>'';
assert.equal((await handleReels(new Request('https://example.test',{method:'POST'}),get,noFetch as typeof fetch)).status,401);assert.equal(calls,0);
assert.equal((await handleReels(new Request('https://example.test',{method:'POST',headers:{origin:'https://aadhyantmanpower.in',authorization:'Bearer test'},body:JSON.stringify({id:'../../other'})}),k=>k==='SUPABASE_SERVICE_ROLE_KEY'?'server-key':'',noFetch as typeof fetch)).status,400);assert.equal(calls,0);
});
