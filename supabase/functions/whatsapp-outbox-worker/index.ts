import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
import {constantTimeEqual} from '../_shared/whatsapp/signature.ts';
type Env={get:(key:string)=>string};
type Fetcher=typeof fetch;
const origin='https://aadhyantmanpower.in';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function templatePayload(row:any){
 const v=row.template_variables;if(row.template_name!=='aadhyant_vacancy_alert_v1'||row.template_language!=='en'||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!v||typeof v.requirement_code!=='string'||typeof v.job_role!=='string'||!v.requirement_code.trim()||!v.job_role.trim()||v.requirement_code.length>160||v.job_role.length>160||!uuid.test(row.correlation_id))throw Error('Unsupported canonical payload');
 return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:row.template_language},components:[{type:'body',parameters:[{type:'text',text:v.requirement_code},{type:'text',text:v.job_role}]},{type:'button',sub_type:'quick_reply',index:'0',parameters:[{type:'payload',payload:'INTERESTED'}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
}
export async function handleWorker(req:Request,env:Env,fetcher:Fetcher=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,value:any)=>Response.json(value,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply(405,{error:'POST required'});
 const base=env.get('SUPABASE_URL'),key=runtimeServerKey(env.get),token=env.get('WHATSAPP_ACCESS_TOKEN');
 const rpc=async(name:string,data:any)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'application/json'},body:JSON.stringify(data),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Database operation not confirmed');return r.json();};
 let campaign:null|string=null;
 try{
  const authorization=req.headers.get('authorization');const schedulerKey=env.get('WHATSAPP_WORKER_SECRET');const scheduler=Boolean(schedulerKey&&schedulerKey.length>=32&&constantTimeEqual(req.headers.get('x-whatsapp-worker-key')||'',schedulerKey));
  if(!scheduler){if(req.headers.get('origin')!==origin||!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});const r=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:env.get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok||await r.json()!==true)return reply(403,{error:'Admin access required'});}
  const raw=await req.text();if(raw.length>1000)return reply(400,{error:'Invalid request'});const body=JSON.parse(raw||'{}');if(!body||Array.isArray(body)||Object.keys(body).some(k=>k!=='campaign_id'))return reply(400,{error:'Invalid request'});if(body.campaign_id!==undefined){if(!uuid.test(body.campaign_id))return reply(400,{error:'Invalid campaign'});campaign=body.campaign_id;}if(!scheduler&&!campaign)return reply(400,{error:'Choose a campaign'});
  const config=await rpc('console_sender_configuration',{});if(!config?.ready||!token||config.account_id!==env.get('WHATSAPP_BUSINESS_ACCOUNT_ID')||!/^\d{8,40}$/.test(config.phone_id))return reply(503,{error:'Verify sender connection before sending'});
  const worker='console:'+crypto.randomUUID();const rows=await rpc('console_claim_campaign',{p_campaign_id:campaign,p_worker_id:worker});if(!Array.isArray(rows)||rows.length>10)throw Error('Invalid claim result');
  const outcomes=await Promise.all(rows.map(async(row:any)=>{
   let payload;try{payload=templatePayload(row);}catch{await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'unsupported_template',p_error_code:'payload_rejected',p_failure_kind:'permanent',p_retry_at:null});return 'failed';}
   try{if(await rpc('console_provider_boundary',{p_message_id:row.message_id,p_worker_id:worker,p_phone_id:config.phone_id,p_account_id:config.account_id})!==true)throw Error('Boundary rejected');}catch{await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'eligibility_changed',p_error_code:'boundary_rejected',p_failure_kind:'permanent',p_retry_at:null});return 'failed';}
   // Once the provider boundary is committed, ambiguous outcomes are never retried automatically.
   try{const sent=await fetcher('https://graph.facebook.com/v25.0/'+config.phone_id+'/messages',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(15000)});const result=await sent.json();
    if(!sent.ok){const code=String(result?.error?.code||'provider_rejected').replace(/[^0-9a-z_]/gi,'').slice(0,80);await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'provider_rejected',p_error_code:code,p_failure_kind:'permanent',p_retry_at:null});return 'failed';}
    const id=result?.messages?.[0]?.id;if(typeof id!=='string'||!id.startsWith('wamid.')||id.length>240)throw Error('Ambiguous provider result');
    if(await rpc('mark_whatsapp_outbound_sent',{p_message_id:row.message_id,p_worker_id:worker,p_provider_message_id:id,p_provider_timestamp:null})!==true)throw Error('Receipt not confirmed');return 'sent';
   }catch{try{await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'ambiguous_provider_outcome',p_error_code:'reconcile_before_retry',p_failure_kind:'ambiguous',p_retry_at:null});}catch{}return 'reconciliation_required';}
  }));
  return reply(200,{processed:outcomes.length,sent:outcomes.filter(x=>x==='sent').length,failed:outcomes.filter(x=>x==='failed').length,reconciliation_required:outcomes.filter(x=>x==='reconciliation_required').length});
 }catch{return reply(502,{error:'Worker result not confirmed. Check reports before retrying.'});}
}
const handler={fetch:(req:Request)=>handleWorker(req,{get:(key:string)=>(globalThis as any).Deno?.env.get(key)||''})};

export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
