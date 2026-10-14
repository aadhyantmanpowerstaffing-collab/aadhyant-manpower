import {registrationFlow,registrationFlowName} from '../_shared/whatsapp/registration-flow-definition.ts';
import {sha256Hex} from '../_shared/whatsapp/signature.ts';
import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
class FlowSetupError extends Error {}
const origin='https://aadhyantmanpower.in';
export async function handleFlowSetup(req:Request,get:(key:string)=>string,fetcher:typeof fetch=fetch){
 const headers={'access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin','cache-control':'no-store'};
 const reply=(status:number,data:any)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 if(req.headers.get('origin')!==origin||!req.headers.get('authorization')?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});
 try{
  const base=get('SUPABASE_URL'),key=runtimeServerKey(get),token=get('WHATSAPP_ACCESS_TOKEN'),account=get('WHATSAPP_BUSINESS_ACCOUNT_ID');
  const raw=await req.text();if(raw.length>200)return reply(400,{error:'Invalid request'});
  const body=JSON.parse(raw||'{}');if(!body||Array.isArray(body)||Object.keys(body).some(k=>k!=='publish')||typeof body.publish!=='boolean')return reply(400,{error:'Choose verification or publication'});
  const authorized=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization:req.headers.get('authorization')!,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!authorized.ok||await authorized.json()!==true)return reply(403,{error:'Admin access required'});
  const rpc=async(name:string,data:any)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'application/json'},body:JSON.stringify(data),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw new FlowSetupError('Database operation not confirmed');return r.json();};
  const sender=await rpc('console_sender_configuration',{});
  if(!sender?.ready||sender.account_id!==account||!/^\d{8,40}$/.test(account)||!token)return reply(503,{error:'Verify sender connection first'});
  const graph=async(path:string,init:any={})=>{const r=await fetcher('https://graph.facebook.com/v25.0/'+path,{...init,headers:{authorization:'Bearer '+token,...init.headers},redirect:'error',signal:AbortSignal.timeout(15000)});const data=await r.json();if(!r.ok){
    const operation=path.endsWith('/publish')?'publication':path.endsWith('/assets')?'form asset':path.endsWith('/flows')?'creation':'lookup';
    const codes=[data?.error?.code,data?.error?.error_subcode].filter(x=>Number.isSafeInteger(x)).join('/');
    throw new FlowSetupError('Meta Flow '+operation+' not confirmed'+(codes?' (code '+codes+')':'')+'. Verify before retrying.');
  }return data;};
  // Look up by the deterministic name before creating. Never repeat an uncertain creation.
  const found=await graph(account+'/flows?fields=id,name,status&limit=100');
  if(!Array.isArray(found.data)||found.paging?.next)throw new FlowSetupError('Flow list needs account review');
  const matches=found.data.filter((x:any)=>x.name===registrationFlowName);
  if(matches.length>1)throw new FlowSetupError('Multiple registration Flows require review');
  let flow=matches[0];
  if(!flow){
   if(!body.publish)return reply(200,{ready:false,status:'not_published'});
   const form=new FormData();form.set('name',registrationFlowName);form.set('categories','["SIGN_UP","LEAD_GENERATION"]');
   const created=await graph(account+'/flows',{method:'POST',body:form});
   if(!/^\d{8,40}$/.test(created.id))throw new FlowSetupError('Created Flow identity not confirmed');
   flow={id:created.id,status:'DRAFT'};
  }
  const json=JSON.stringify(registrationFlow),hash=await sha256Hex(new TextEncoder().encode(json));
  if(flow.status==='DRAFT'){
   if(!body.publish){
    const validation=await graph(flow.id+'?fields=validation_errors,health_status');
    if(Array.isArray(validation.validation_errors)&&validation.validation_errors.length){
     const details=validation.validation_errors.slice(0,3).map((e:any)=>[e.error,e.message,typeof e.line_start==='number'?'line '+e.line_start:null].filter(x=>typeof x==='string').join(': ').slice(0,400)).join(' | ');
     throw new FlowSetupError('Meta draft validation: '+details);
    }
    const health=validation.health_status;
    const codes=(health?.entities||[]).flatMap((e:any)=>(e.errors||[]).map((x:any)=>x.error_code)).filter((x:any)=>Number.isSafeInteger(x));
    if(codes.length)throw new FlowSetupError('Meta draft requires account review (codes '+codes.join(',')+'). Form validation passed; publication is pending.');
    return reply(200,{ready:false,status:'draft'});
   }
   const form=new FormData();form.set('name','flow.json');form.set('asset_type','FLOW_JSON');form.set('file',new Blob([json],{type:'application/json'}),'flow.json');
   const upload=await graph(flow.id+'/assets',{method:'POST',body:form});
   if(upload.success!==true||!Array.isArray(upload.validation_errors)||upload.validation_errors.length){
    const details=Array.isArray(upload.validation_errors)?upload.validation_errors.slice(0,3).map((e:any)=>
      [e.error,e.message,typeof e.line_start==='number'?'line '+e.line_start:null].filter(x=>typeof x==='string').join(': ').slice(0,400)||'Invalid form JSON').join(' | '):'Invalid validation response';
    // These errors describe our static review form only, never credentials or candidate submissions.
    throw new FlowSetupError('Meta rejected the registration form: '+details+'. Publication stopped.');
   }
   const published=await graph(flow.id+'/publish',{method:'POST'});if(published.success!==true)throw new FlowSetupError('Flow publication not confirmed');
  }
  const verified=await graph(flow.id+'?fields=id,name,status');
  if(verified.id!==flow.id||verified.name!==registrationFlowName||verified.status!=='PUBLISHED')throw new FlowSetupError('Published registration Flow required');
  // Published assets are immutable. Verify actual content before enabling its consent contract.
  const assets=await graph(flow.id+'/assets');
  const asset=assets.data?.find((x:any)=>x.asset_type==='FLOW_JSON');
  if(!asset?.download_url)throw new FlowSetupError('Published Flow JSON unavailable');
  const url=new URL(asset.download_url);if(url.protocol!=='https:'||!/(^|\.)(facebook\.com|fbcdn\.net)$/.test(url.hostname))throw new FlowSetupError('Unexpected Flow asset location');
  const response=await fetcher(url.href,{redirect:'error',signal:AbortSignal.timeout(15000)});if(!response.ok)throw new FlowSetupError('Published Flow JSON unavailable');
  if(Number(response.headers.get('content-length')||0)>65536)throw new FlowSetupError('Unexpected Flow asset');
  const uploaded=await response.text();if(uploaded.length>65536||JSON.stringify(JSON.parse(uploaded))!==json)throw new FlowSetupError('Published Flow differs from reviewed form');
  if(await rpc('console_verify_registration_flow',{p_flow_id:flow.id,p_flow_hash:hash,p_account_id:account})!==true)throw new FlowSetupError('Flow activation not confirmed');
  return reply(200,{ready:true,status:'PUBLISHED'});
 }catch(error){return reply(502,{error:error instanceof FlowSetupError?error.message:'Registration Flow setup not confirmed'});}
}
const handler={fetch:(req:Request)=>handleFlowSetup(req,key=>(globalThis as any).Deno?.env.get(key)||'')};
export default handler;const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
