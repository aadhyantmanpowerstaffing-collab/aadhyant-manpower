import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
const origin='https://aadhyantmanpower.in';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export async function handleMedia(req:Request,get:(k:string)=>string,fetcher:typeof fetch=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(s:number,d:any)=>Response.json(d,{status:s,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST'||req.headers.get('origin')!==origin)return reply(403,{error:'Admin action required'});
 const authorization=req.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});
 try{
  const base=get('SUPABASE_URL'),service=serverDatabaseHeaders(runtimeServerKey(get));
  const admin=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!admin.ok||await admin.json()!==true)return reply(403,{error:'Admin access required'});
  const rpc=async(name:string,args:any)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...service,'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Database unavailable');return r.json();};
  if(req.headers.get('content-type')?.startsWith('application/json')){
   const raw=await req.text();if(raw.length>150)return reply(400,{error:'Invalid preview request'});
   const body=JSON.parse(raw);if(!body||Object.keys(body).length!==1||!uuid.test(body.media_id))return reply(400,{error:'Choose an uploaded video'});
   const path=await rpc('console_promotion_media_object',{p_id:body.media_id});if(typeof path!=='string'||path!==body.media_id+'/'+body.media_id+'.mp4')return reply(404,{error:'Video unavailable'});
   const signed=await fetcher(base+'/storage/v1/object/sign/whatsapp-campaign-media/'+path,{method:'POST',headers:{...service,'content-type':'application/json'},body:JSON.stringify({expiresIn:300}),redirect:'error',signal:AbortSignal.timeout(10000)});
   if(!signed.ok)throw Error('Preview unavailable');const s=await signed.json();
   if(typeof s.signedURL!=='string'||!s.signedURL.startsWith('/object/sign/whatsapp-campaign-media/'+path+'?'))throw Error('Invalid preview');
   return reply(200,{url:base+'/storage/v1'+s.signedURL});
  }
  if(req.headers.get('content-type')!=='video/mp4')return reply(400,{error:'Choose an MP4 video (maximum 16 MB)'});
  const length=Number(req.headers.get('content-length'));if(length>16000000)return reply(413,{error:'Video exceeds 16 MB'});
  // Read a bounded stream before any storage mutation, including chunked requests.
  const reader=req.body?.getReader();if(!reader)return reply(400,{error:'Video required'});
  const chunks:Uint8Array[]=[];let size=0;
  while(true){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;if(size>16000000){await reader.cancel();return reply(413,{error:'Video exceeds 16 MB'});}chunks.push(value);}
  const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.byteLength;}
  if(size<100||new TextDecoder().decode(bytes.slice(4,8))!=='ftyp')return reply(400,{error:'A valid MP4 video is required'});
  const user=await fetcher(base+'/auth/v1/user',{headers:{authorization,apikey:get('SUPABASE_ANON_KEY')},redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!user.ok)return reply(401,{error:'Sign in again'});const identity=await user.json();if(!uuid.test(identity.id))return reply(401,{error:'Sign in again'});
  const id=crypto.randomUUID(),path=id+'/'+id+'.mp4';
  const uploaded=await fetcher(base+'/storage/v1/object/whatsapp-campaign-media/'+path,{method:'POST',headers:{...service,'content-type':'video/mp4','x-upsert':'false'},body:bytes,redirect:'error',signal:AbortSignal.timeout(30000)});
  if(!uploaded.ok)return reply(502,{error:'Video upload not confirmed. Refresh the video list before retrying.'});
  await rpc('console_register_promotion_media',{p_id:id,p_created_by:identity.id,p_size:size});
  return reply(200,{id,byte_size:size});
 }catch{return reply(502,{error:'Video action not confirmed. Refresh before retrying. No message was sent.'});}
}
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve((req:Request)=>handleMedia(req,(key:string)=>deno.env.get(key)||''));
