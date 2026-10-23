import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
import {verifyWorker} from './auth.ts';
const origin='https://aadhyantmanpower.in',uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
export async function handleReels(req:Request,get:(k:string)=>string,fetcher:typeof fetch=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type,x-job-id,x-claim-token','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,data:unknown)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 const auth=req.headers.get('authorization')||'';if(!auth.startsWith('Bearer '))return reply(401,{error:'Authentication required'});
 try{
 const base=get('SUPABASE_URL'),key=runtimeServerKey(get),server={...serverDatabaseHeaders(key),'content-type':'application/json'};
 const rpc=async(name:string,data:unknown,h:Record<string,string>=server)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:h,body:JSON.stringify(data),redirect:'error',signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Request failed');return r.json();};
 if(req.headers.get('origin')===origin){
 if(Number(req.headers.get('content-length')||0)>1000)return reply(413,{error:'Request too large'});
 const body=await req.text();if(body.length>1000)return reply(413,{error:'Request too large'});
 const {id}=JSON.parse(body);if(!uuid.test(id))return reply(400,{error:'Choose a video'});
 const path=await rpc('admin_reel_object',{p_id:id},{authorization:auth,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'});
 if(!path)return reply(404,{error:'Video is not ready or the vacancy has changed'});
 const r=await fetcher(base+'/storage/v1/object/sign/recruitment-reels/'+path,{method:'POST',headers:server,body:JSON.stringify({expiresIn:300}),redirect:'error',signal:AbortSignal.timeout(15000)});
 if(!r.ok)throw Error('Preview unavailable');const result=await r.json();
 return reply(200,{url:base+'/storage/v1'+result.signedURL});
 }
 const gate=await rpc('reel_worker_gate',{});
 let worker:string;try{worker=await verifyWorker(auth.slice(7),gate?.workflow_sha,fetcher);}catch{return reply(403,{error:'Verified worker required'});}
 if(req.headers.get('content-type')?.split(';')[0]==='video/mp4'){
 const id=req.headers.get('x-job-id')||'',claim=req.headers.get('x-claim-token')||'';
 if(!uuid.test(id)||!uuid.test(claim)||!await rpc('reel_worker_check',{p_id:id,p_claim:claim,p_worker:worker}))return reply(409,{error:'Claim expired or vacancy changed'});
 const length=Number(req.headers.get('content-length'));if(!Number.isInteger(length)||length<100||length>25000000)return reply(413,{error:'Video size outside limits'});
 const bytes=await req.arrayBuffer();if(bytes.byteLength!==length||new TextDecoder().decode(bytes.slice(4,8))!=='ftyp')return reply(400,{error:'MP4 required'});
 const path=id+'/'+claim+'.mp4';
 const r=await fetcher(base+'/storage/v1/object/recruitment-reels/'+path,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'video/mp4'},body:bytes,redirect:'error',signal:AbortSignal.timeout(60000)});
 // A replay may encounter an existing immutable object; completion still requires the current claim.
 if(!r.ok&&r.status!==409)throw Error('Upload failed');
 if(!await rpc('reel_worker_finish',{p_id:id,p_claim:claim,p_worker:worker,p_success:true}))return reply(409,{error:'Vacancy changed before completion'});
 return reply(200,{ready:true});
 }
 const raw=await req.text();if(raw.length>500)return reply(413,{error:'Request too large'});const body=JSON.parse(raw);
 if(body.action==='claim')return reply(200,{job:await rpc('reel_worker_claim',{p_worker:worker})});
 if(body.action==='fail'&&uuid.test(body.id)&&uuid.test(body.claim))return reply(200,{recorded:await rpc('reel_worker_finish',{p_id:body.id,p_claim:body.claim,p_worker:worker,p_success:false})});
 return reply(400,{error:'Unsupported action'});
 }catch{return reply(502,{error:'Reel service temporarily unavailable'});}
}
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve((req:Request)=>handleReels(req,(k:string)=>deno.env.get(k)||''));
