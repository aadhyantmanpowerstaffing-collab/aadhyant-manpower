import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
export async function handleSetup(req:Request,get:(k:string)=>string,fetcher:typeof fetch=fetch):Promise<Response>{
 const origin='https://aadhyantmanpower.in',headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};const reply=(status:number,data:any)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST'||req.headers.get('origin')!==origin)return reply(403,{error:'Admin action required'});
 const auth=req.headers.get('authorization');if(!auth?.startsWith('Bearer '))return reply(401,{error:'Sign in required'});
 try{
 const base=get('SUPABASE_URL'),access=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization:auth,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});if(!access.ok||await access.json()!==true)return reply(403,{error:'Admin access required'});
 const raw=await req.text();if(raw.length>100)return reply(400,{error:'Invalid sender setup request'});
 let body:any;try{body=JSON.parse(raw||'{}');}catch{return reply(400,{error:'Invalid sender setup request'});}
 if(!body||Array.isArray(body)||Object.keys(body).some(k=>k!=='connect_webhook')||(body.connect_webhook!==undefined&&body.connect_webhook!==true))return reply(400,{error:'Invalid sender setup request'});
 const account=get('WHATSAPP_BUSINESS_ACCOUNT_ID'),token=get('WHATSAPP_ACCESS_TOKEN');if(!/^\d{8,40}$/.test(account)||!token||!get('WHATSAPP_APP_SECRET')||!get('WHATSAPP_WEBHOOK_VERIFY_TOKEN'))return reply(503,{error:'Configure Meta access token, account ID, App Secret and webhook verify token in Supabase Secrets'});
 const r=await fetcher('https://graph.facebook.com/v25.0/'+account+'/phone_numbers?fields=id,display_phone_number,verified_name&limit=100',{headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});if(!r.ok)return reply(502,{error:'Meta phone lookup failed; check account permissions'});const data=await r.json();if(!Array.isArray(data.data)||data.paging?.next)return reply(502,{error:'Incomplete Meta phone list'});
 const configured=get('WHATSAPP_PHONE_NUMBER_ID'),phones=data.data.filter((p:any)=>/^\d{8,40}$/.test(p.id)),phone=configured?phones.find((p:any)=>p.id===configured):phones.length===1?phones[0]:null;
 if(!phone)return reply(503,{error:'Set WHATSAPP_PHONE_NUMBER_ID to the intended phone from this Meta account'});
 // An app-level callback alone does not subscribe this business account.
 const subscriptions=await fetcher('https://graph.facebook.com/v25.0/'+account+'/subscribed_apps',{headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});
 if(!subscriptions.ok)return reply(502,{error:'Sender ownership verified, but Meta webhook subscription lookup failed'});
 let subscribed=await subscriptions.json();const appId=get('WHATSAPP_APP_ID')||'2181424935760142';
 if(!Array.isArray(subscribed.data)||subscribed.paging?.next)return reply(502,{error:'Incomplete Meta webhook subscription list'});
 let app=subscribed.data.find((entry:any)=>entry?.whatsapp_business_api_data?.id===appId);
 if(!app&&body.connect_webhook===true){
  // Only this explicit Admin action may connect the configured business account.
  // It does not change callback URLs, fields, partner access, or send messages.
  const connected=await fetcher('https://graph.facebook.com/v25.0/'+account+'/subscribed_apps',{method:'POST',headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});
  if(!connected.ok||(await connected.json())?.success!==true)return reply(502,{error:'Meta webhook connection was not confirmed. Verify connection before retrying.'});
  const verified=await fetcher('https://graph.facebook.com/v25.0/'+account+'/subscribed_apps',{headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});
  if(!verified.ok)return reply(502,{error:'Meta webhook connection needs verification'});
  subscribed=await verified.json();if(!Array.isArray(subscribed.data)||subscribed.paging?.next)return reply(502,{error:'Incomplete Meta webhook subscription list'});
  app=subscribed.data.find((entry:any)=>entry?.whatsapp_business_api_data?.id===appId);
 }

 if(!app)return reply(409,{error:'Sender ownership verified. Aadhyant Staffing app is not subscribed to this WhatsApp account; incoming messages and delivery receipts are not connected.'});
 const callback=base+'/functions/v1/whatsapp-webhook';
 if(app.override_callback_uri&&app.override_callback_uri!==callback)return reply(409,{error:'Sender ownership verified, but the Meta account webhook override points to a different endpoint'});
 const saved=await fetcher(base+'/rest/v1/rpc/console_sender_connection',{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify({p_phone_id:phone.id,p_account_id:account}),redirect:'error',signal:AbortSignal.timeout(10000)});if(!saved.ok||await saved.json()!==true)return reply(502,{error:'Sender configuration could not be verified'});
 return reply(200,{ready:true,phone_masked:'••••••'+String(phone.display_phone_number||'').replace(/\D/g,'').slice(-4)});
 }catch{return reply(502,{error:'Sender setup unavailable. No message was sent'});}
}
const handler={fetch:(req:Request)=>handleSetup(req,(key:string)=>(globalThis as any).Deno?.env.get(key)||'')};

export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
