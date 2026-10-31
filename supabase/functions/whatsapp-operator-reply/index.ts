import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
import {wanotifierSessionTransport} from '../_shared/whatsapp/wanotifier.ts';
import {sendSessionOutbox} from '../_shared/whatsapp/registration-reply.ts';
const origin='https://aadhyantmanpower.in';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function operatorReplyPayload(row:any){
 if(row.purpose!=='operator_reply'||row.consent_class!=='transactional'||row.message_type!=='session_text'
 ||!/^\+91[6-9]\d{9}$/.test(row.destination)||JSON.stringify(row.template_variables)!==JSON.stringify({entry_point:'operator_reply_v1'})
 ||typeof row.operator_reply_body!=='string'||!row.operator_reply_body.trim()||Array.from(row.operator_reply_body).length>2000||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(row.operator_reply_body))throw Error('Invalid reply payload');
 return {messaging_product:'whatsapp',to:row.destination.slice(1),type:'text',text:{preview_url:false,body:row.operator_reply_body}};
}
export async function handleOperatorReply(req:Request,get:(name:string)=>string,fetcher:typeof fetch=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,data:any)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST'||req.headers.get('origin')!==origin)return reply(403,{error:'Admin action required'});
 const authorization=req.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return reply(401,{error:'Sign in required'});
 try{
  const raw=await req.text();if(raw.length>200)return reply(400,{error:'Invalid reply request'});const body=JSON.parse(raw);
  if(!body||Array.isArray(body)||Object.keys(body).length!==1||typeof body.message_id!=='string'||!uuid.test(body.message_id))return reply(400,{error:'Choose a prepared reply'});
  const base=get('SUPABASE_URL');
  const userRpc=async(name:string,args:any)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{authorization,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Admin reply access denied');return r.json();};
  // Real user JWT establishes both Admin authority and ownership, before any privileged claim.
  let status;try{status=await userRpc('admin_console_reply_status',{p_message_id:body.message_id});}catch{return reply(403,{error:'Admin reply access required'});}
  if(status?.id!==body.message_id||!['queued','sending','sent','delivered','read','failed'].includes(status?.state))return reply(403,{error:'Reply unavailable'});
  if(['sent','delivered','read','failed'].includes(status?.state))return reply(200,status);
  const useWANotifier=get('WANOTIFIER_OPERATOR_REPLIES_ENABLED')==='true';
  if(useWANotifier&&(get('WANOTIFIER_SENDER_NUMBER')!=='+919624453543'||!get('WANOTIFIER_API_KEY')||get('WANOTIFIER_PHONE_NUMBER_ID')!==get('WHATSAPP_PHONE_NUMBER_ID')||get('WANOTIFIER_BUSINESS_ACCOUNT_ID')!==get('WHATSAPP_BUSINESS_ACCOUNT_ID')))return reply(503,{error:'Verify WANotifier sender binding before sending'});
  const key=runtimeServerKey(get),token=useWANotifier?get('WANOTIFIER_API_KEY'):get('WHATSAPP_ACCESS_TOKEN');
  const rpc=async(name:string,args:any)=>{
   if(name==='admin_console_operator_reply_boundary')return userRpc(name,args);
   const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Reply operation not confirmed');return r.json();
  };
  const config=await rpc('console_sender_configuration',{});
  if(!config?.ready||!token||config.phone_id!==get('WHATSAPP_PHONE_NUMBER_ID')||config.account_id!==get('WHATSAPP_BUSINESS_ACCOUNT_ID'))return reply(503,{error:'Verify the configured sender before sending'});
  const transport=useWANotifier?wanotifierSessionTransport(token,config.phone_id,fetcher):fetcher;
  const providerFetch:typeof fetch=async(input,init)=>{const r=await transport(input,init);if(r.status>=500)throw Error('Ambiguous provider outcome');return r;};
  await sendSessionOutbox(body.message_id,rpc,config,token,providerFetch,'console_claim_operator_reply','p_message_id','admin_console_operator_reply_boundary',operatorReplyPayload);
  status=await userRpc('admin_console_reply_status',{p_message_id:body.message_id});return reply(200,status);
 }catch{return reply(502,{error:'Reply outcome not confirmed. Check this same reply before sending another.'});}
}
const handler={fetch:(req:Request)=>handleOperatorReply(req,(key:string)=>(globalThis as any).Deno?.env.get(key)||'')};
export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
