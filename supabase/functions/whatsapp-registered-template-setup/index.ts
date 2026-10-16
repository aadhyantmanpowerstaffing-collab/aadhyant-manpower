import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
export const reviewedTemplate={"name":"aadhyant_registered_job_alert_v4","language":"en","category":"MARKETING","components":[{"type":"BODY","text":"Hello,\n\n*Aadhyant Manpower & Staffing* has a new job opening. Review the summary below and share this opportunity with someone looking for work.\n\n*Job details*\n\u2022 Vacancy: {{1}}\n\u2022 Company: {{2}}\n\u2022 Role: {{3}}\n\u2022 Location: {{4}}\n\n*Qualification*\n{{5}}\n\n*Salary & duty*\n\u2022 CTC / Salary: {{6}}\n\u2022 Approx. take home: {{7}}\n\u2022 Overtime: {{8}}\n\u2022 Duty: {{9}}\n\n*Benefits*\n{{10}}\n\nTap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.\nTo stop WhatsApp job alerts, tap Stop alerts or reply STOP.","example":{"body_text":[["EXAMPLE-ONLY","Example Manufacturing","Associate","Sanand","10th / 12th / ITI","INR 17000 monthly","INR 15000 monthly","INR 121 per hour","8 hours; rotational shift","PF / ESIC listed; Free transport; Canteen charges apply"]]}},{"type":"BUTTONS","buttons":[{"type":"URL","text":"View Job & Apply","url":"https://aadhyantmanpower.in/jobs/?requirement={{1}}","example":["https://aadhyantmanpower.in/jobs/?requirement=AAD-2026-000003"]},{"type":"QUICK_REPLY","text":"Stop alerts"}]}]};
const origin='https://aadhyantmanpower.in';
export async function handleTemplateSetup(req:Request,get:(k:string)=>string,fetcher:typeof fetch=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,data:any)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST'||req.headers.get('origin')!==origin)return reply(403,{error:'Admin action required'});
 const authorization=req.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});
 try{
  const raw=await req.text();if(raw.length>100||raw.trim()!=='{}')return reply(400,{error:'Only the reviewed template can be submitted'});
  const base=get('SUPABASE_URL');
  const access=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!access.ok||await access.json()!==true)return reply(403,{error:'Admin access required'});
  const account=get('WHATSAPP_BUSINESS_ACCOUNT_ID'),token=get('WHATSAPP_ACCESS_TOKEN');
  if(!/^\d{8,40}$/.test(account)||!token)return reply(503,{error:'Meta account configuration required'});
  const configResponse=await fetcher(base+'/rest/v1/rpc/console_sender_configuration',{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!configResponse.ok||(await configResponse.json())?.account_id!==account)return reply(503,{error:'Verified sender account binding required'});
  const url=new URL('https://graph.facebook.com/v25.0/'+account+'/message_templates');url.searchParams.set('name',reviewedTemplate.name);url.searchParams.set('fields','id,name,language,status,components');url.searchParams.set('limit','100');
  const lookup=await fetcher(url,{headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});
  if(!lookup.ok)return reply(502,{error:'Meta template lookup failed; no template submitted'});
  const list=await lookup.json();if(!Array.isArray(list.data)||list.paging?.next)return reply(502,{error:'Incomplete template lookup; no template submitted'});
  const existing=list.data.filter((t:any)=>t.name===reviewedTemplate.name&&t.language==='en');
  if(existing.length>1)return reply(409,{error:'Template identity requires review'});
  if(existing.length){
   const t=existing[0],body=t.components?.filter((x:any)=>x.type==='BODY'),buttons=t.components?.filter((x:any)=>x.type==='BUTTONS');
   const normalized=(buttons?.[0]?.buttons||[]).map((b:any)=>{const {example,...binding}=b;return binding;});
   const expected=(reviewedTemplate.components[1] as any).buttons.map((b:any)=>{const {example,...binding}=b;return binding;});
   if(body?.length!==1||buttons?.length!==1||t.components.length!==2||body[0].text!==reviewedTemplate.components[0].text||JSON.stringify(normalized)!==JSON.stringify(expected))return reply(409,{error:'Existing template differs from the reviewed request; nothing changed'});
   return reply(200,{template_id:t.id,name:reviewedTemplate.name,status:t.status,created:false});
  }
  // One create attempt only. An ambiguous response must be checked by name on the next invocation.
  const created=await fetcher('https://graph.facebook.com/v25.0/'+account+'/message_templates',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(reviewedTemplate),redirect:'error',signal:AbortSignal.timeout(15000)});
  const result=await created.json();
  if(!created.ok){
   const number=(v:any)=>/^\d{1,12}$/.test(String(v))?String(v):'unknown';
   const code=number(result?.error?.code),subcode=number(result?.error?.error_subcode);
   // Only user-facing provider diagnostics; never return raw Graph bodies, traces or credentials.
   const detail=[result?.error?.error_user_title,result?.error?.error_user_msg].filter(v=>typeof v==='string').join(' — ')
    .replaceAll(token,'[redacted]').replace(/https?:\/\/\S+/gi,'[link removed]').replace(/[<>\x00-\x1f\x7f]/g,' ').replace(/\s+/g,' ').trim().slice(0,400);
   return reply(502,{error:'Meta template submission rejected (code '+code+', subcode '+subcode+').'+(detail?' '+detail:''),code,subcode});
  }
  if(!/^\d{1,40}$/.test(String(result.id||'')))throw Error('Unconfirmed receipt');
  return reply(200,{template_id:String(result.id),name:reviewedTemplate.name,status:result.status||'PENDING',created:true});
 }catch{return reply(502,{error:'Template submission could not be confirmed. Check Meta by template name before retrying.'});}
}
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve((req:Request)=>handleTemplateSetup(req,(key:string)=>deno.env.get(key)||''));
