import {dispatchRecruitmentNotifications,recruitmentRoutes} from './recruitment-dispatch.ts';
import {constantTimeEqual} from './signature.ts';
import {runtimeServerKey,serverDatabaseHeaders} from './server-headers.ts';
type Get=(key:string)=>string;
export function verifyRecruitmentTemplates(rows:any[]){
 for(const name of Object.keys(recruitmentRoutes)){
  const found=rows.filter(r=>r?.name===name&&r.language===(name.includes('_hi_')?'hi':'en'));
  if(found.length!==1)throw Error('Exact recruitment templates required');
  const t=found[0],parts=t.components;
  if(t.status!=='APPROVED'||t.category!=='UTILITY'||!Array.isArray(parts)||parts.some((p:any)=>!['BODY','BUTTONS'].includes(p.type)))throw Error('Approved Utility templates required');
  const bodies=parts.filter((p:any)=>p.type==='BODY'),buttons=parts.filter((p:any)=>p.type==='BUTTONS');
  if(bodies.length!==1||typeof bodies[0].text!=='string')throw Error('Exact template body required');
  const variables=[...bodies[0].text.matchAll(/\{\{([^}]+)\}\}/g)].map(m=>m[1]);
  if(JSON.stringify(variables)!==JSON.stringify(['1','2','3','4','5','6']))throw Error('Six ordered variables required');
  if(name.startsWith('aadhyant_joining_details_')){if(buttons.length)throw Error('Joining buttons unavailable');}
  else if(buttons.length!==1||JSON.stringify(buttons[0].buttons?.map((b:any)=>[b.type,b.text]))!==JSON.stringify([['QUICK_REPLY','Will attend'],['QUICK_REPLY','Cannot attend']]))throw Error('Exact interview reply buttons required');
 }
}
export async function handleMetaRecruitmentWorker(req:Request,get:Get,fetcher:typeof fetch=fetch){
 const reply=(status:number,body:unknown)=>Response.json(body,{status,headers:{'cache-control':'no-store'}});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 const secret=get('WHATSAPP_WORKER_SECRET');
 let authorized=secret.length>=32&&constantTimeEqual(req.headers.get('x-whatsapp-worker-key')||'',secret);
 const wake=req.headers.get('x-whatsapp-wake-key');
 if(!authorized&&wake&&/^[a-f0-9]{64}$/.test(wake))try{
  const r=await fetcher(get('SUPABASE_URL')+'/rest/v1/rpc/console_verify_automatic_wake',{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify({p_key:wake}),redirect:'error',signal:AbortSignal.timeout(10000)});
  authorized=r.ok&&await r.json()===true;
 }catch{authorized=false;}
 if(!authorized)return reply(401,{error:'Worker authentication required'});
 if(get('WHATSAPP_RECRUITMENT_UPDATES_ENABLED')!=='true'||get('WANOTIFIER_AUTOMATION_ENABLED')==='true')return reply(503,{error:'Direct recruitment sending is not enabled'});
 if(req.headers.get('content-type')?.split(';')[0].trim()!=='application/json')return reply(415,{error:'JSON required'});
 try{
  const reader=req.body?.getReader();if(!reader)return reply(400,{error:'Recruitment request required'});
  let raw='';const decoder=new TextDecoder();let size=0;
  for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>256){await reader.cancel();return reply(413,{error:'Request too large'});}raw+=decoder.decode(value,{stream:true});}raw+=decoder.decode();
  let body:any;try{body=JSON.parse(raw);}catch{return reply(400,{error:'Recruitment request required'});}
  if(!body||Array.isArray(body)||Object.keys(body).length!==1||body.kind!=='recruitment_updates')return reply(400,{error:'Only recruitment updates are supported'});
  const token=get('WHATSAPP_ACCESS_TOKEN'),phone=get('WHATSAPP_PHONE_NUMBER_ID'),account=get('WHATSAPP_BUSINESS_ACCOUNT_ID');
  if(!token||!/^\d{8,40}$/.test(phone)||!/^\d{8,40}$/.test(account))return reply(503,{error:'Configured sender required'});
  const rpc=async(name:string,args:Record<string,unknown>)=>{
   const r=await fetcher(get('SUPABASE_URL')+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});
   if(!r.ok)throw Error('Canonical operation unavailable');return r.json();
  };
  const config=await rpc('console_sender_configuration',{});
  if(config?.phone_id!==phone||config.account_id!==account)return reply(503,{error:'Verify the configured sender'});
  const meta=async(url:URL)=>{const r=await fetcher(url,{headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Meta verification unavailable');return r.json();};
  const phones=await meta(new URL('https://graph.facebook.com/v25.0/'+account+'/phone_numbers?fields=id&limit=100'));
  if(!Array.isArray(phones.data)||phones.paging?.next||!phones.data.some((p:any)=>p.id===phone))throw Error('Sender ownership unavailable');
  const subscriptions=await meta(new URL('https://graph.facebook.com/v25.0/'+account+'/subscribed_apps'));
  if(!Array.isArray(subscriptions.data)||subscriptions.paging?.next)throw Error('Complete subscription required');
  const app=subscriptions.data.find((r:any)=>r?.whatsapp_business_api_data?.id===(get('WHATSAPP_APP_ID')||'2181424935760142'));
  if(!app||(app.override_callback_uri&&app.override_callback_uri!==get('SUPABASE_URL')+'/functions/v1/whatsapp-webhook'))throw Error('Direct receipt webhook required');
  const rows:any[]=[];let after:string|undefined;
  for(let page=0;page<10;page++){
   const url=new URL('https://graph.facebook.com/v25.0/'+account+'/message_templates');url.searchParams.set('fields','id,name,status,category,language,components');url.searchParams.set('limit','100');if(after)url.searchParams.set('after',after);
   const data=await meta(url);if(!Array.isArray(data.data)||rows.length+data.data.length>500)throw Error('Template response unavailable');rows.push(...data.data);
   if(!data.paging?.next){after=undefined;break;}after=data.paging?.cursors?.after;if(!after)throw Error('Incomplete templates');
  }
  if(after)throw Error('Incomplete templates');verifyRecruitmentTemplates(rows);
  if(await rpc('console_sender_connection',{p_phone_id:phone,p_account_id:account})!==true)throw Error('Sender verification not persisted');
  if(await rpc('console_refresh_recruitment_template_verification',{p_phone_id:phone,p_account_id:account})!==true)throw Error('Template verification not persisted');
  return reply(200,await dispatchRecruitmentNotifications('meta-recruitment:'+crypto.randomUUID(),phone,account,get,rpc,fetcher,{accessToken:token}));
 }catch{return reply(503,{error:'Recruitment result not confirmed. Check reports before another run.'});}
}
