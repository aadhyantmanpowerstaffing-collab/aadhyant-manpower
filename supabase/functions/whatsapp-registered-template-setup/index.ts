import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
export const reviewedTemplate={"name":"aadhyant_registered_job_alert_v3","language":"en","category":"MARKETING","components":[{"type":"BODY","text":"Hello,\n\n*Aadhyant Manpower & Staffing*\nNew job opening\n\n*Vacancy*\n{{1}}\n\n*Company & Role*\n\u2022 {{2}}\n\u2022 {{3}}\n\u2022 {{4}}\n\n*Location & Openings*\n\u2022 {{5}}\n\u2022 {{6}}\n\u2022 {{7}}\n\n*Eligibility*\n\u2022 {{8}}\n\u2022 {{9}}\n\u2022 {{10}}\n\u2022 {{11}}\n\u2022 {{12}}\n\u2022 {{13}}\n\n*Salary (INR)*\n\u2022 {{14}}\n\u2022 {{15}}\n\u2022 {{16}}\n\u2022 {{17}}\n\u2022 {{18}}\n\u2022 {{19}}\n\u2022 {{20}}\n\u2022 {{21}}\n\u2022 {{22}}\n\u2022 {{23}}\n\u2022 {{24}}\n\u2022 {{25}}\n\u2022 {{26}}\n\n*Deductions (INR)*\n\u2022 {{27}}\n\u2022 {{28}}\n\u2022 {{29}}\n\u2022 {{30}}\n\n*Employer CTC (INR)*\n\u2022 {{31}}\n\u2022 {{32}}\n\u2022 {{33}}\n\u2022 {{34}}\n\u2022 {{35}}\n\u2022 {{36}}\n\n*Duty & OT*\n\u2022 {{37}}\n\u2022 {{38}}\n\u2022 {{39}}\n\u2022 {{40}}\n\u2022 {{41}}\n\u2022 {{42}}\n\u2022 {{43}}\n\n*Facilities*\n\u2022 {{44}}\n\u2022 {{45}}\n\u2022 {{46}}\n\u2022 {{47}}\n\u2022 {{48}}\n\u2022 {{49}}\n\u2022 {{50}}\n\u2022 {{51}}\n\u2022 {{52}}\n\u2022 {{53}}\n\u2022 {{54}}\n\u2022 {{55}}\n\n*Leave / Year*\n\u2022 {{56}}\n\u2022 {{57}}\n\u2022 {{58}}\n\u2022 {{59}}\n\u2022 {{60}}\n\n*Employment*\n\u2022 {{61}}\n\u2022 {{62}}\n\u2022 {{63}}\n\u2022 {{64}}\n\u2022 {{65}}\n\u2022 {{66}}\n\n*Interview & Joining*\n\u2022 {{67}}\n\u2022 {{68}}\n\u2022 {{69}}\n\n*Benefits*\n{{70}}\n\n*Description*\n{{71}}\n\n*Continued*\n{{72}}\n\nView Job & Apply below. Share this job.\nTo stop alerts, tap Stop alerts or reply STOP.","example":{"body_text":[["EXAMPLE-ONLY","Company / worksite: Example Company","Department: Assembly","Role: Associate","Location: Sanand","Open positions: 10","Total openings: 10","Qualification: ITI","Trade / specialization: Fitter","Experience: Both","Gender: Any","Minimum age: 18","Maximum age: 35","Salary period: monthly","Minimum CTC (INR): 15000","Maximum CTC (INR): 18000","Salary information: As per grade","Payable days: 26","Basic + DA (INR): 13000","Attendance bonus (INR): 300","Monthly bonus (INR): 400","Leave amount (INR): 500","Other fixed earnings (INR): 600","Gross wages (INR): 14800","Approx. take home (INR): 13259","CTC (INR): 19544","Employee PF (INR): 1200","Employee ESIC (INR): 111","Canteen deduction (INR): 200","Other deduction (INR): 30","Employer PF (INR): 1300","Employer ESIC (INR): 444","Gratuity provision (INR): 600","Bonus provision (INR): 700","Leave provision (INR): 800","Other CTC component (INR): 900","Duty hours: 8 hours","Shift: Rotational","Working days / week: 6","Weekly offs: 1","OT rate: 125","OT rate basis: per hour","OT information: Optional overtime","Canteen: chargeable","Canteen charge (INR): 30","Canteen charge basis: per meal","Canteen information: Lunch service","Transport: chargeable","Transport charge (INR): 25","Transport charge basis: per day","Transport information: Sanand bus","Accommodation: chargeable","Accommodation charge (INR): 1500","Accommodation charge basis: per month","Accommodation information: Shared room","Paid leave days / year: 12","Casual leave days / year: 7","Sick leave days / year: 6","National holiday days / year: 3","Festival holiday days / year: 5","Employment: contract","Payroll: contractor","Contract months: 12","Probation months: 3","Training days: 7","Notice days: 30","Interview location: Plant gate","Interview date / time: 01 Nov 2026 10:00 IST","Expected joining date: 2026-11-05","Uniform: provided","Assembly work. Quality checks. Safety rules apply.","No further description supplied."]]}},{"type":"BUTTONS","buttons":[{"type":"URL","text":"View Job & Apply","url":"https://aadhyantmanpower.in/jobs/?requirement={{1}}","example":["https://aadhyantmanpower.in/jobs/?requirement=AAD-2026-000003"]},{"type":"QUICK_REPLY","text":"Stop alerts"}]}]};
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
