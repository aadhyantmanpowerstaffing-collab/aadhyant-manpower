// Admin-only, read-only Meta template sync. Never sends a WhatsApp message.
const allowedOrigin = 'https://aadhyantmanpower.in';
Deno.serve(async (req: Request) => {
 const headers = {'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':allowedOrigin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,error:string)=>new Response(JSON.stringify({error}),{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,'POST required');
 if(req.headers.get('origin')!==allowedOrigin)return reply(403,'Origin not allowed');
 const authorization=req.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return reply(401,'Sign in required');
 const base=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!base||!anon||!service)return reply(503,'Template sync is not configured');
 try{
  const access=await fetch(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:anon,'content-type':'application/json'},body:'{}',signal:AbortSignal.timeout(10000)});
  if(!access.ok||await access.json()!==true)return reply(403,'Admin access required');
  const token=Deno.env.get('WHATSAPP_ACCESS_TOKEN'),account=Deno.env.get('WHATSAPP_BUSINESS_ACCOUNT_ID');
  if(!token||!account||!/^\d{8,40}$/.test(account))return reply(503,'Connect the Meta business account before syncing templates');
  const rows:unknown[]=[];let after:string|undefined;
  for(let page=0;page<10;page++){
   const url=new URL('https://graph.facebook.com/v25.0/'+account+'/message_templates');url.searchParams.set('fields','id,name,status,language,components');url.searchParams.set('limit','100');if(after)url.searchParams.set('after',after);
   const result=await fetch(url,{headers:{authorization:'Bearer '+token},signal:AbortSignal.timeout(15000),redirect:'error'});
   if(!result.ok)return reply(502,'Meta template lookup failed; check account permissions');
   const data=await result.json();if(!Array.isArray(data.data)||rows.length+data.data.length>500)return reply(502,'Template response exceeds the supported limit');rows.push(...data.data);
   if(!data.paging?.next){after=undefined;break;}after=data.paging?.cursors?.after;if(!after)return reply(502,'Incomplete template response');
  }
  if(after)return reply(502,'Incomplete template response; no templates changed');
  const saved=await fetch(base+'/rest/v1/rpc/console_sync_templates',{method:'POST',headers:{authorization:'Bearer '+service,apikey:service,'content-type':'application/json'},body:JSON.stringify({p_rows:rows}),signal:AbortSignal.timeout(15000)});
  if(!saved.ok)return reply(502,'Template metadata could not be saved');
  return new Response(JSON.stringify({synced:await saved.json()}),{headers});
 }catch{return reply(502,'Template sync unavailable. No message was sent');}
});
