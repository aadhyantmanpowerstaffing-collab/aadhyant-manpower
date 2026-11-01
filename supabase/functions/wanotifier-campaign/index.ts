import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
import {wanotifierNotificationTransport} from '../_shared/whatsapp/wanotifier-notification.ts';
import {wanotifierMessageId} from '../_shared/whatsapp/job-message.ts';
import {wanotifierRegisteredNotificationPayload} from '../_shared/whatsapp/wanotifier-notification.ts';
export const selectedVacancyRoutes:Record<string,{language:string;secret:string}>={
 aadhyant_registered_job_alert_v4:{language:'en',secret:'WANOTIFIER_SELECTED_VACANCY_EN_V4_URL'},
 aadhyant_registered_job_alert_hi_v1:{language:'hi',secret:'WANOTIFIER_SELECTED_VACANCY_HI_V1_URL'},
 aadhyant_registered_job_alert_v5:{language:'en',secret:'WANOTIFIER_SELECTED_VACANCY_EN_V5_URL'},
 aadhyant_registered_job_alert_hi_v2:{language:'hi',secret:'WANOTIFIER_SELECTED_VACANCY_HI_V2_URL'}
};
export function selectedVacancyPayload(row:any){
 const route=Object.hasOwn(selectedVacancyRoutes,row.template_name)?selectedVacancyRoutes[row.template_name]:null;if(!route||route.language!==row.template_language)throw Error('Unsupported selected vacancy');
 return wanotifierRegisteredNotificationPayload({...row,template_name:row.template_name==='aadhyant_registered_job_alert_hi_v1'?'aadhyant_registered_job_alert_hi_v2':row.template_name});
}
type Get=(name:string)=>string;
const origin='https://aadhyantmanpower.in';
export async function handleSelectedVacancy(req:Request,get:Get,fetcher:typeof fetch=fetch){
 const headers={'cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,data:unknown)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 const authorization=req.headers.get('authorization');
 if(req.headers.get('origin')!==origin||!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});
 if(req.headers.get('content-type')?.split(';')[0].trim()!=='application/json')return reply(415,{error:'JSON required'});
 let claimStarted=false;
 try{
  const base=get('SUPABASE_URL');
  const access=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!access.ok||await access.json()!==true)return reply(403,{error:'Admin access required'});
  // Bound streamed data, including requests without a trustworthy Content-Length.
  const reader=req.body?.getReader();if(!reader)return reply(400,{error:'Campaign required'});
  let raw='',size=0;const decoder=new TextDecoder();for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>256){await reader.cancel();return reply(413,{error:'Request too large'});}raw+=decoder.decode(value,{stream:true});}raw+=decoder.decode();
  let body:any;try{body=JSON.parse(raw);}catch{return reply(400,{error:'Campaign required'});}
  if(!body||Array.isArray(body)||Object.keys(body).length!==1||typeof body.campaign_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.campaign_id))return reply(400,{error:'Campaign required'});
  if(get('WANOTIFIER_SELECTED_VACANCIES_ENABLED')!=='true'||get('WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED')!=='true'
   ||get('WANOTIFIER_SENDER_NUMBER')!=='+919624453543'||get('WANOTIFIER_PHONE_NUMBER_ID')!=='1415347881659158'||get('WANOTIFIER_BUSINESS_ACCOUNT_ID')!=='1386833723249335')return reply(503,{error:'WANotifier vacancy sending is not activated yet. Your campaign remains saved.'});
  const routeResponse=await fetcher(base+'/rest/v1/whatsapp_campaigns?id=eq.'+body.campaign_id+'&select=id,template_name,template_language',{headers:serverDatabaseHeaders(runtimeServerKey(get)),redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!routeResponse.ok)return reply(409,{error:'Saved vacancy campaign required'});
  const campaigns=await routeResponse.json();
  if(!Array.isArray(campaigns)||campaigns.length!==1||campaigns[0].id!==body.campaign_id)return reply(409,{error:'Saved vacancy campaign required'});
  const campaign=campaigns[0],route=Object.hasOwn(selectedVacancyRoutes,campaign.template_name)?selectedVacancyRoutes[campaign.template_name]:null;
  if(!route||campaign.template_language!==route.language)return reply(409,{error:'This template has no verified WANotifier vacancy route'});
  // Resolve the exact template endpoint before taking a canonical lease.
  const send=wanotifierNotificationTransport(get(route.secret),fetcher);
  const rpc=async(name:string,args:Record<string,unknown>)=>{
   const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});
   if(!r.ok)throw Error('Canonical operation unconfirmed');return r.json();
  };
  const config=await rpc('console_sender_configuration',{});
  if(config?.ready!==true||config.phone_id!==get('WANOTIFIER_PHONE_NUMBER_ID')||config.account_id!==get('WANOTIFIER_BUSINESS_ACCOUNT_ID'))return reply(503,{error:'Verified WANotifier sender required'});
  const worker='wanotifier-vacancy:'+crypto.randomUUID();claimStarted=true;
  const rows=await rpc('console_claim_campaign',{p_campaign_id:body.campaign_id,p_worker_id:worker});
  if(!Array.isArray(rows)||rows.length>10)throw Error('Claim result unconfirmed');
  let sent=0,failed=0,reconciliation=0;
  for(const row of rows){
   const failure=(category:string,code:string,kind:string)=>rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:category,p_error_code:code,p_failure_kind:kind,p_retry_at:null});
   let payload;
   try{
    if(row.template_name!==campaign.template_name||row.template_language!==route.language||row.template_variables?.campaign_id!==body.campaign_id)throw Error('Campaign route mismatch');
    payload=selectedVacancyPayload(row);
    if(await rpc('console_provider_boundary',{p_message_id:row.message_id,p_worker_id:worker,p_phone_id:config.phone_id,p_account_id:config.account_id})!==true)throw Error('Boundary denied');
   }catch{await failure('eligibility_changed','final_check_failed','permanent');failed++;continue;}
   try{
    const id=wanotifierMessageId(await send(payload));
    if(await rpc('mark_whatsapp_outbound_sent',{p_message_id:row.message_id,p_worker_id:worker,p_provider_message_id:id,p_provider_timestamp:null})!==true)throw Error('Receipt persistence unconfirmed');sent++;
   }catch{await failure('ambiguous_provider_outcome','reconcile_before_retry','ambiguous');reconciliation++;}
  }
  return reply(200,{processed:rows.length,sent,failed,reconciliation_required:reconciliation});
 }catch{return reply(503,{error:claimStarted?'Outcome unconfirmed. Review WANotifier before any retry.':'vacancy configuration unavailable. No campaign was sent.'});}
}
const get=(name:string)=>(globalThis as any).Deno?.env.get(name)||'';
const handler={fetch:(req:Request)=>handleSelectedVacancy(req,get)};
export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
