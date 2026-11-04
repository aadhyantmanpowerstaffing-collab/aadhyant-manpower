type Get=(name:string)=>string;
type Rpc=(name:string,args:Record<string,unknown>)=>Promise<any>;
// Standard Webhooks HMAC: only Supabase Auth may supply an OTP to this handler.
export async function verifyAuthHook(raw:string,headers:Headers,secret:string,now=Date.now()){
 const id=headers.get('webhook-id')||'',stamp=headers.get('webhook-timestamp')||'',signatures=headers.get('webhook-signature')||'';
 if(!/^[A-Za-z0-9_-]{1,200}$/.test(id)||!/^\d{10}$/.test(stamp)||Math.abs(now/1000-Number(stamp))>300||signatures.length>2048)throw Error('Invalid hook');
 const encoded=secret.replace(/^v1,whsec_/,'').replace(/^whsec_/,'');
 let bytes:Uint8Array;try{bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));}catch{throw Error('Invalid hook');}
 if(bytes.length<32)throw Error('Invalid hook');
 const key=await crypto.subtle.importKey('raw',bytes,{name:'HMAC',hash:'SHA-256'},false,['verify']);
 for(const item of signatures.split(' ')){const [version,value]=item.split(',');if(version!=='v1'||!value)continue;try{
  const sig=Uint8Array.from(atob(value),c=>c.charCodeAt(0));
  if(await crypto.subtle.verify('HMAC',key,sig,new TextEncoder().encode(`${id}.${stamp}.${raw}`)))return id;
 }catch{}}
 throw Error('Invalid hook');
}
export async function handleAuthHook(req:Request,get:Get,rpc:Rpc,fetcher:typeof fetch=fetch){
 const reply=(status:number)=>Response.json(status===200?{}:{error:{http_code:status,message:'WhatsApp authentication unavailable'}},{status,headers:{'cache-control':'no-store'}});
 if(req.method!=='POST')return reply(405);
 if(get('WHATSAPP_AUTH_ENABLED')!=='true'||get('WHATSAPP_AUTH_TEMPLATE_VERIFIED')!=='true')return reply(503);
 let raw='',size=0;try{
  const reader=req.body?.getReader();if(!reader)return reply(400);const decoder=new TextDecoder();
  for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>16384){await reader.cancel();return reply(413);}raw+=decoder.decode(value,{stream:true});}raw+=decoder.decode();
 }catch{return reply(400);}
 let id:string;try{id=await verifyAuthHook(raw,req.headers,get('SEND_SMS_HOOK_SECRET'));}catch{return reply(401);}
 let event:any;try{event=JSON.parse(raw);}catch{return reply(400);}
 const user=event?.user,otp=event?.sms?.otp,phone='+'+String(user?.phone||'').replace(/^\+/,'');
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user?.id||'')||!/^\+91[6-9]\d{9}$/.test(phone)||typeof otp!=='string'||!/^\d{6}$/.test(otp))return reply(400);
 const token=get('WHATSAPP_ACCESS_TOKEN'),phoneId=get('WHATSAPP_PHONE_NUMBER_ID'),accountId=get('WHATSAPP_BUSINESS_ACCOUNT_ID');
 if(!token||!/^\d{8,40}$/.test(phoneId)||!/^\d{8,40}$/.test(accountId))return reply(503);
 // The client and hook payload cannot choose a sender, template or language.
 const payload={messaging_product:'whatsapp',to:phone.slice(1),type:'template',template:{
  name:'aadhyant_candidate_login_otp_en_v1',language:{code:'en'},components:[
   {type:'body',parameters:[{type:'text',text:otp}]},
   {type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:otp}]}
  ]}};
 let claimed=false;
 try{
  const state=await rpc('claim_candidate_phone_auth_delivery',{p_hook_id:id,p_user_id:user.id,p_phone:phone});
  if(state==='accepted')return reply(200);
  if(state!=='send')return reply(503);claimed=true;
  // Never fall back to a marketing template or a second provider for an OTP.
  const response=await fetcher('https://graph.facebook.com/v25.0/'+phoneId+'/messages',{
   method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},
   body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(2000)
  });
  const result=await response.json(),receipt=result?.messages?.[0]?.id;
  if(!response.ok||result?.error||!Array.isArray(result?.messages)||result.messages.length!==1
   ||typeof receipt!=='string'||!/^wamid\.[A-Za-z0-9_=-]{1,234}$/.test(receipt))throw Error('Provider acceptance unconfirmed');
  if(await rpc('finish_candidate_phone_auth_delivery',{p_hook_id:id,p_user_id:user.id,p_accepted:true})!==true)throw Error('Acceptance persistence unconfirmed');
  return reply(200);
 }catch{
  if(claimed)try{await rpc('finish_candidate_phone_auth_delivery',{p_hook_id:id,p_user_id:user.id,p_accepted:false});}catch{}
  // No automatic fallback or retry of an uncertain provider call. Never log OTPs.
  return reply(503);
 }
}
