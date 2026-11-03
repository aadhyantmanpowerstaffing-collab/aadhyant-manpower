import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
const origin='https://aadhyantmanpower.in',uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export async function handleCampaignImage(req:Request,get:(k:string)=>string,fetcher:typeof fetch=fetch){
 const headers={'cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,body:unknown)=>Response.json(body,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 const authorization=req.headers.get('authorization');
 if(req.method!=='POST'||req.headers.get('origin')!==origin||!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});
 try{
  const base=get('SUPABASE_URL'),service=serverDatabaseHeaders(runtimeServerKey(get));
  const access=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!access.ok||await access.json()!==true)return reply(403,{error:'Admin access required'});
  const mime=req.headers.get('content-type'),format=mime==='image/jpeg'?'JPEG':mime==='image/png'?'PNG':null;
  if(!format)return reply(415,{error:'Choose a JPEG or PNG image up to 5 MB'});
  if(Number(req.headers.get('content-length'))>5000000)return reply(413,{error:'Image exceeds 5 MB'});
  const reader=req.body?.getReader();if(!reader)return reply(400,{error:'Image required'});
  const parts:Uint8Array[]=[];let size=0;for(;;){const r=await reader.read();if(r.done)break;size+=r.value.length;if(size>5000000){await reader.cancel();return reply(413,{error:'Image exceeds 5 MB'});}parts.push(r.value);}
  const bytes=new Uint8Array(size);let at=0;for(const part of parts){bytes.set(part,at);at+=part.length;}
  if(size<100)return reply(400,{error:'A valid JPEG or PNG image is required'});
  const valid=format==='JPEG'?bytes[0]===255&&bytes[1]===216&&bytes[2]===255&&bytes.at(-2)===255&&bytes.at(-1)===217:[137,80,78,71,13,10,26,10].every((n,i)=>bytes[i]===n)&&new TextDecoder().decode(bytes.slice(12,16))==='IHDR'&&new DataView(bytes.buffer).getUint32(16)>0&&new DataView(bytes.buffer).getUint32(20)>0;
  if(size<100||!valid)return reply(400,{error:'A valid JPEG or PNG image is required'});
  const user=await fetcher(base+'/auth/v1/user',{headers:{authorization,apikey:get('SUPABASE_ANON_KEY')},redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!user.ok)return reply(401,{error:'Sign in again'});const identity=await user.json();if(!uuid.test(identity.id))return reply(401,{error:'Sign in again'});
  const id=crypto.randomUUID(),path=id+'/'+id+(format==='JPEG'?'.jpg':'.png');
  const upload=await fetcher(base+'/storage/v1/object/whatsapp-campaign-media/'+path,{method:'POST',headers:{...service,'content-type':mime!,'x-upsert':'false'},body:bytes,redirect:'error',signal:AbortSignal.timeout(30000)});
  if(!upload.ok)throw Error('Upload unavailable');
  const register=await fetcher(base+'/rest/v1/rpc/console_register_campaign_image',{method:'POST',headers:{...service,'content-type':'application/json'},body:JSON.stringify({p_id:id,p_created_by:identity.id,p_size:size,p_format:format}),redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!register.ok||await register.json()!==id)throw Error('Image registration unconfirmed');
  const signed=await fetcher(base+'/storage/v1/object/sign/whatsapp-campaign-media/'+path,{method:'POST',headers:{...service,'content-type':'application/json'},body:JSON.stringify({expiresIn:300}),redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!signed.ok)throw Error('Preview unavailable');const data=await signed.json();
  if(typeof data.signedURL!=='string'||!data.signedURL.startsWith('/object/sign/whatsapp-campaign-media/'+path+'?'))throw Error('Invalid preview');
  return reply(200,{id,byte_size:size,url:base+'/storage/v1'+data.signedURL});
 }catch{return reply(502,{error:'Image upload not confirmed. Refresh before retrying. No message was sent.'});}
}
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve((r:Request)=>handleCampaignImage(r,(k:string)=>deno.env.get(k)||''));
