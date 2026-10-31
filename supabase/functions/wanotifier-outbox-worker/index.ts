import {dispatchWANotifierNotifications} from '../_shared/whatsapp/interview-dispatch.ts';
import {wanotifierNotificationTransport} from '../_shared/whatsapp/wanotifier-notification.ts';
import {constantTimeEqual} from '../_shared/whatsapp/signature.ts';
import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';

type Get=(key:string)=>string;
export async function handleWANotifierWorker(req:Request,get:Get,fetcher:typeof fetch=fetch){
 const reply=(status:number,value:unknown)=>Response.json(value,{status,headers:{'cache-control':'no-store'}});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 const secret=get('WHATSAPP_WORKER_SECRET');
 if(secret.length<32||!constantTimeEqual(req.headers.get('x-whatsapp-worker-key')||'',secret))return reply(401,{error:'Worker authentication required'});
 if(get('WANOTIFIER_AUTOMATION_ENABLED')!=='true'||get('WANOTIFIER_SENDER_NUMBER')!=='+919624453543'
 ||get('WANOTIFIER_PHONE_NUMBER_ID')!=='1415347881659158'||get('WANOTIFIER_BUSINESS_ACCOUNT_ID')!=='1386833723249335')return reply(503,{error:'WANotifier automation is not enabled'});
 if(req.headers.get('content-type')?.split(';')[0].trim()!=='application/json')return reply(415,{error:'JSON required'});
 // Bound body bytes even if a caller omits or falsifies Content-Length.
 const reader=req.body?.getReader();if(!reader)return reply(400,{error:'Notification kind required'});
 let bytes=new Uint8Array();for(;;){const {done,value}=await reader.read();if(done)break;if(bytes.length+value.length>256){await reader.cancel();return reply(413,{error:'Request too large'});}const next=new Uint8Array(bytes.length+value.length);next.set(bytes);next.set(value,bytes.length);bytes=next;}
 let kind:'interviews'|'registered_alerts';
 try{const body=JSON.parse(new TextDecoder().decode(bytes));if(!body||Array.isArray(body)||Object.keys(body).length!==1||!['interviews','registered_alerts'].includes(body.kind))throw Error();kind=body.kind;}catch{return reply(400,{error:'Notification kind required'});}
 if(get(kind==='interviews'?'WANOTIFIER_INTERVIEWS_ENABLED':'WANOTIFIER_REGISTERED_ALERTS_ENABLED')!=='true')return reply(503,{error:'Notification kind is not enabled'});
 let claimStarted=false;
 try{
  const interviewEn=kind==='interviews'?wanotifierNotificationTransport(get('WANOTIFIER_INTERVIEW_EN_URL'),fetcher):null;
  const interviewHi=kind==='interviews'?wanotifierNotificationTransport(get('WANOTIFIER_INTERVIEW_HI_URL'),fetcher):null;
  const registered=kind==='registered_alerts'?wanotifierNotificationTransport(get('WANOTIFIER_REGISTERED_JOB_EN_URL'),fetcher):null;
  const rpc=async(name:string,args:Record<string,unknown>)=>{
   const r=await fetcher(get('SUPABASE_URL')+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});
   if(!r.ok)throw Error('Canonical operation unconfirmed');return r.json();
  };
  const config=await rpc('console_sender_configuration',{});
  if(config?.ready!==true||config.phone_id!==get('WANOTIFIER_PHONE_NUMBER_ID')||config.account_id!==get('WANOTIFIER_BUSINESS_ACCOUNT_ID'))return reply(503,{error:'Verified sender required'});
  claimStarted=true;
  const result=await dispatchWANotifierNotifications(kind,'wanotifier:'+crypto.randomUUID(),config.phone_id,config.account_id,{rpc,send:async(language,payload)=>{
   const transport=kind==='registered_alerts'?registered:language==='en'?interviewEn:language==='hi'?interviewHi:null;
   if(!transport)throw Error('Unsupported notification route');return transport(payload);
  }});
  return reply(200,{processed:result.length,sent:result.filter(r=>r.outcome==='sent').length,blocked:result.filter(r=>r.outcome==='blocked').length,reconciliation_required:result.filter(r=>r.outcome==='reconciliation_required').length});
 }catch{return reply(503,{error:claimStarted?'Worker result unconfirmed; review WANotifier before any retry.':'Notification configuration unavailable.'});}
}
const get=(key:string)=>(globalThis as any).Deno?.env.get(key)||'';
const handler={fetch:(req:Request)=>handleWANotifierWorker(req,get)};
export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
