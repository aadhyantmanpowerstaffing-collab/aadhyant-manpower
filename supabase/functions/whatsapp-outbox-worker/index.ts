import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
import {constantTimeEqual} from '../_shared/whatsapp/signature.ts';
type Env={get:(key:string)=>string};
type Fetcher=typeof fetch;
const origin='https://aadhyantmanpower.in';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const summaryJobBody="Hello,\n\n*Aadhyant Manpower & Staffing* has a new job opening. Review the summary below and share this opportunity with someone looking for work.\n\n*Job details*\n\u2022 Vacancy: {{1}}\n\u2022 Company: {{2}}\n\u2022 Role: {{3}}\n\u2022 Location: {{4}}\n\n*Qualification*\n{{5}}\n\n*Salary & duty*\n\u2022 CTC / Salary: {{6}}\n\u2022 Approx. take home: {{7}}\n\u2022 Overtime: {{8}}\n\u2022 Duty: {{9}}\n\n*Benefits*\n{{10}}\n\nTap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.\nTo stop WhatsApp job alerts, tap Stop alerts or reply STOP.";
export const sameDayHindiBody="*रोकड़ी काम — उसी शाम भुगतान*\n*Aadhyant Manpower & Staffing*\n\n📍 *स्थान:* {{1}}\n🛠️ *काम:* {{2}}\n📅 *तारीख:* {{3}}\n🕗 *समय:* {{4}}\n👥 *ज़रूरत:* {{5}} लोग\n💵 *मेहनताना:* {{6}} प्रति व्यक्ति, पूरी शिफ्ट का\n✅ *भुगतान:* उसी दिन {{7}}\n\nकाम के लिए उपलब्ध हैं? नीचे बटन दबाकर आवेदन करें। कंपनी/ठेकेदार आपकी जगह की पुष्टि करेगा।\n\nअलर्ट बंद करने के लिए *Stop alerts* दबाएँ या *STOP* लिखें।";
export const hindiSummaryJobBody="नमस्ते,\n*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। नीचे विवरण देखें और काम ढूँढ रहे लोगों के साथ साझा करें।\n\n*नौकरी का विवरण*\n• भर्ती संदर्भ: {{1}}\n• कंपनी: {{2}}\n• पद: {{3}}\n• स्थान: {{4}}\n\n*योग्यता*\n{{5}}\n\n*वेतन और ड्यूटी*\n• CTC / वेतन: {{6}}\n• अनुमानित हाथ में वेतन: {{7}}\n• ओवरटाइम: {{8}}\n• ड्यूटी: {{9}}\n\n*सुविधाएँ*\n{{10}}\n\nपूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे नौकरी देखें बटन दबाएँ।\n\nWhatsApp नौकरी अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।";
export const videoJobBody="Hello,\n\n*Aadhyant Manpower & Staffing* has a new job opening. Watch the video and review the details below.\n\n*Job details*\n• Vacancy: {{1}}\n• Company: {{2}}\n• Role: {{3}}\n• Location: {{4}}\n\n*Qualification*\n{{5}}\n\n*Salary & duty*\n• CTC / Salary: {{6}}\n• Approx. take home: {{7}}\n• Overtime: {{8}}\n• Duty: {{9}}\n\n*Benefits*\n{{10}}\n\nTap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.\nFor more information or to apply, call 9586785800.\nTo stop WhatsApp job alerts, tap Stop alerts or reply STOP.";
export const hindiVideoJobBody="नमस्ते,\n*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। हिंदी वीडियो देखें और नीचे जानकारी पढ़ें।\n\n*नौकरी का विवरण*\n• भर्ती संदर्भ: {{1}}\n• कंपनी: {{2}}\n• पद: {{3}}\n• स्थान: {{4}}\n\n*योग्यता*\n{{5}}\n\n*वेतन और ड्यूटी*\n• CTC / वेतन: {{6}}\n• अनुमानित हाथ में वेतन: {{7}}\n• ओवरटाइम: {{8}}\n• ड्यूटी: {{9}}\n\n*सुविधाएँ*\n{{10}}\n\nपूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे बटन दबाएँ।\nअधिक जानकारी या आवेदन के लिए 9586785800 पर कॉल करें।\nअलर्ट बंद करने के लिए अलर्ट बंद करें दबाएँ या STOP लिखें।";
export const hindiContactJobBody="नमस्ते,\n*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। नीचे विवरण देखें और काम ढूँढ रहे लोगों के साथ साझा करें।\n\n*नौकरी का विवरण*\n• भर्ती संदर्भ: {{1}}\n• कंपनी: {{2}}\n• पद: {{3}}\n• स्थान: {{4}}\n\n*योग्यता*\n{{5}}\n\n*वेतन और ड्यूटी*\n• CTC / वेतन: {{6}}\n• अनुमानित हाथ में वेतन: {{7}}\n• ओवरटाइम: {{8}}\n• ड्यूटी: {{9}}\n\n*सुविधाएँ*\n{{10}}\n\nपूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे नौकरी देखें बटन दबाएँ।\n\nअधिक जानकारी या नौकरी के लिए आवेदन करने हेतु 9586785800 पर कॉल करें।\n\nWhatsApp नौकरी अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।";
export function templatePayload(row:any,videoLink?:string){
 if(row.template_name==='aadhyant_registered_job_alert_hi_v2'){
  const p=templatePayload({...row,template_name:'aadhyant_registered_job_alert_hi_v1'});
  const names=['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'];
  if(Array.from(hindiContactJobBody.replace(/\{\{(\d+)\}\}/g,(_,n)=>row.template_variables[names[Number(n)-1]])).length>1024)throw Error('Hindi contact summary exceeds supported body size');
  p.template.name=row.template_name;return p;
 }
 if(['aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1'].includes(row.template_name)){
  if(!videoLink||!/^https:\/\//.test(videoLink))throw Error('Verified private Reel required');
  const hindi=row.template_name==='aadhyant_registered_job_video_hi_v1';
  const p=templatePayload({...row,template_name:hindi?'aadhyant_registered_job_alert_hi_v1':'aadhyant_registered_job_alert_v4'});
  const names=['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'];
  if(Array.from((hindi?hindiVideoJobBody:videoJobBody).replace(/\{\{(\d+)\}\}/g,(_,n)=>row.template_variables[names[Number(n)-1]])).length>1024)throw Error('Video job body exceeds supported size');
  p.template.name=row.template_name;
  p.template.components.unshift({type:'header',parameters:[{type:'video',video:{link:videoLink}}]} as any);return p;
 }
 const v=row.template_variables;
 if(row.template_name==='aadhyant_same_day_pay_hi_v1'){
  const names=['job_location','job_role','work_date','shift','headcount','pay','payment'];
  if(row.template_language!=='hi'||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!uuid.test(row.correlation_id)||v?.template_contract!=='same_day_hi_v1'||Object.keys(v).some(k=>!names.includes(k)&&!['requirement_code','template_contract','campaign_id','recipient_id','job_fingerprint'].includes(k))||new TextEncoder().encode(JSON.stringify(v)).length>16384||names.some(k=>typeof v[k]!=='string'||!v[k].trim()||Array.from(v[k]).length>300||/[\n\r\t]| {5}/.test(v[k]))||!/^[A-Za-z0-9_-]{1,160}$/.test(v.requirement_code)||!/^[a-f0-9]{64}$/.test(v.job_fingerprint||'')||Array.from(sameDayHindiBody.replace(/\{\{(\d+)\}\}/g,(_,n)=>v[names[Number(n)-1]])).length>1024)throw Error('Unsupported canonical Same-Day Pay payload');
  return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:'hi'},components:[{type:'body',parameters:names.map(k=>({type:'text',text:v[k]}))},{type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:v.requirement_code}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
 }

 if(['aadhyant_registered_job_alert_v4','aadhyant_registered_job_alert_hi_v1'].includes(row.template_name)){
  const hindi=row.template_name==='aadhyant_registered_job_alert_hi_v1';const language=hindi?'hi':'en';const summaryBody=hindi?hindiSummaryJobBody:summaryJobBody;
  const names=["requirement_code", "company", "job_role", "job_location", "qualification", "salary", "take_home", "overtime", "duty", "benefits"];
  if(row.template_language!==language||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!uuid.test(row.correlation_id)||v?.template_contract!=='registered_summary_v4'||Object.keys(v).some(k=>!names.includes(k)&&!['template_contract','campaign_id','recipient_id','job_fingerprint'].includes(k))||new TextEncoder().encode(JSON.stringify(v)).length>16384||names.some(k=>typeof v[k]!=='string'||!v[k].trim()||Array.from(v[k]).length>300||/[\n\r\t]| {5}/.test(v[k]))||!/^[A-Za-z0-9_-]{1,160}$/.test(v.requirement_code))throw Error('Unsupported canonical full-job payload');
  if(!/^[a-f0-9]{64}$/.test(v.job_fingerprint||'')||Array.from(summaryBody.replace(/\{\{(\d+)\}\}/g,(_,n)=>v[names[Number(n)-1]])).length>1024)throw Error('Job summary exceeds supported body size');
  return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:language},components:[{type:'body',parameters:names.map(k=>({type:'text',text:v[k]}))},{type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:v.requirement_code}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
 }
 if(row.template_name==='aadhyant_registered_job_alert_v3'){
  const names=["requirement_code", "line_2", "line_3", "line_4", "line_5", "line_6", "line_7", "line_8", "line_9", "line_10", "line_11", "line_12", "line_13", "line_14", "line_15", "line_16", "line_17", "line_18", "line_19", "line_20", "line_21", "line_22", "line_23", "line_24", "line_25", "line_26", "line_27", "line_28", "line_29", "line_30", "line_31", "line_32", "line_33", "line_34", "line_35", "line_36", "line_37", "line_38", "line_39", "line_40", "line_41", "line_42", "line_43", "line_44", "line_45", "line_46", "line_47", "line_48", "line_49", "line_50", "line_51", "line_52", "line_53", "line_54", "line_55", "line_56", "line_57", "line_58", "line_59", "line_60", "line_61", "line_62", "line_63", "line_64", "line_65", "line_66", "line_67", "line_68", "line_69", "candidate_benefits", "description_1", "description_2"];
  if(row.template_language!=='en'||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!uuid.test(row.correlation_id)||v?.template_contract!=='registered_lines_v3'||Object.keys(v).some(k=>!names.includes(k)&&!['template_contract','campaign_id','recipient_id'].includes(k))||new TextEncoder().encode(JSON.stringify(v)).length>16384||names.some(k=>typeof v[k]!=='string'||!v[k].trim()||Array.from(v[k]).length>1000||/[\n\r\t]| {5}/.test(v[k]))||!/^[A-Za-z0-9_-]{1,160}$/.test(v.requirement_code))throw Error('Unsupported canonical full-job payload');
  return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:'en'},components:[{type:'body',parameters:names.map(k=>({type:'text',text:v[k]}))},{type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:v.requirement_code}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
 }
 if(row.template_name==='aadhyant_registered_job_alert_v2'){
  const names=["requirement_code", "job_identity", "job_location", "eligibility", "earnings", "deductions", "employer_cost", "duty", "facilities", "leave_terms", "employment_terms", "interview_joining", "candidate_benefits", "description_1", "description_2"];
  if(row.template_language!=='en'||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!uuid.test(row.correlation_id)||v?.template_contract!=='registered_full_v2'||names.some(k=>typeof v[k]!=='string'||!v[k].trim()||Array.from(v[k]).length>1000||/[\n\r\t]/.test(v[k]))||!/^[A-Za-z0-9_-]{1,160}$/.test(v.requirement_code))throw Error('Unsupported canonical full-job payload');
  return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:'en'},components:[{type:'body',parameters:names.map(k=>({type:'text',text:v[k]}))},{type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:v.requirement_code}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
 }
 if(row.template_name==='aadhyant_registered_job_alert_v1'){
  const names=['requirement_code','job_role','job_location','qualification','salary_details','benefits_details'];
  if(row.template_language!=='en'||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!uuid.test(row.correlation_id)||!v||names.some(k=>typeof v[k]!=='string'||!v[k].trim()||v[k].length>500)||!/^[A-Za-z0-9_-]{1,160}$/.test(v.requirement_code))throw Error('Unsupported canonical payload');
  return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:'en'},components:[{type:'body',parameters:names.map(k=>({type:'text',text:v[k]}))},{type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:v.requirement_code}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
 }
 if(row.template_name!=='aadhyant_vacancy_alert_v1'||row.template_language!=='en'||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||!/^\+?91[6-9]\d{9}$/.test(row.destination)||!v||typeof v.requirement_code!=='string'||typeof v.job_role!=='string'||!v.requirement_code.trim()||!v.job_role.trim()||v.requirement_code.length>160||v.job_role.length>160||!uuid.test(row.correlation_id))throw Error('Unsupported canonical payload');
 return {messaging_product:'whatsapp',to:row.destination.replace(/^\+/,''),type:'template',template:{name:row.template_name,language:{code:row.template_language},components:[{type:'body',parameters:[{type:'text',text:v.requirement_code},{type:'text',text:v.job_role}]},{type:'button',sub_type:'quick_reply',index:'0',parameters:[{type:'payload',payload:'INTERESTED'}]},{type:'button',sub_type:'quick_reply',index:'1',parameters:[{type:'payload',payload:'STOP'}]}]}};
}
export async function handleWorker(req:Request,env:Env,fetcher:Fetcher=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,value:any)=>Response.json(value,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply(405,{error:'POST required'});
 const base=env.get('SUPABASE_URL'),key=runtimeServerKey(env.get),token=env.get('WHATSAPP_ACCESS_TOKEN');
 const rpc=async(name:string,data:any)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'application/json'},body:JSON.stringify(data),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Database operation not confirmed');return r.json();};
 let campaign:null|string=null,automatic=false;
 try{
  const authorization=req.headers.get('authorization');const schedulerKey=env.get('WHATSAPP_WORKER_SECRET');const scheduler=Boolean(schedulerKey&&schedulerKey.length>=32&&constantTimeEqual(req.headers.get('x-whatsapp-worker-key')||'',schedulerKey));
  let databaseWake=false;
  const wakeKey=req.headers.get('x-whatsapp-wake-key');
  if(wakeKey){
   if(!/^[a-f0-9]{64}$/.test(wakeKey))return reply(401,{error:'Invalid automatic wake'});
   databaseWake=await rpc('console_verify_automatic_wake',{p_key:wakeKey})===true;
   if(!databaseWake)return reply(401,{error:'Invalid automatic wake'});
  }
  if(!scheduler&&!databaseWake){if(req.headers.get('origin')!==origin||!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});const r=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:env.get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok||await r.json()!==true)return reply(403,{error:'Admin access required'});}
  const raw=await req.text();if(raw.length>1000)return reply(400,{error:'Invalid request'});const body=JSON.parse(raw||'{}');if(!body||Array.isArray(body)||Object.keys(body).some(k=>!['campaign_id','automatic'].includes(k)))return reply(400,{error:'Invalid request'});if(body.campaign_id!==undefined){if(databaseWake||!uuid.test(body.campaign_id))return reply(400,{error:'Invalid campaign'});campaign=body.campaign_id;}if(body.automatic!==undefined){if(body.automatic!==true||(!scheduler&&!databaseWake)||campaign)return reply(400,{error:'Automatic scheduler request required'});automatic=true;}if(databaseWake&&!automatic)return reply(400,{error:'Automatic wake only'});if(!scheduler&&!databaseWake&&!campaign)return reply(400,{error:'Choose a campaign'});
  if(automatic){
   if(env.get('WHATSAPP_AUTOMATIC_ALERTS_ENABLED')!=='true')return reply(503,{error:'Automatic worker is not enabled'});
   // Refresh ownership and approval from Meta on every automatic run; never trust stale approval.
   const account=env.get('WHATSAPP_BUSINESS_ACCOUNT_ID'),phone=env.get('WHATSAPP_PHONE_NUMBER_ID');
   if(!token||!/^\d{8,40}$/.test(account)||!/^\d{8,40}$/.test(phone))throw Error('Configured sender required');
   const meta=async(url:URL)=>{const r=await fetcher(url,{headers:{authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Meta verification failed');return r.json();};
   const phones=await meta(new URL('https://graph.facebook.com/v25.0/'+account+'/phone_numbers?fields=id&limit=100'));
   if(!Array.isArray(phones.data)||phones.paging?.next||!phones.data.some((p:any)=>p.id===phone))throw Error('Sender ownership not confirmed');
   const templates:any[]=[];let after:string|undefined;
   for(let page=0;page<10;page++){
    const url=new URL('https://graph.facebook.com/v25.0/'+account+'/message_templates');url.searchParams.set('fields','id,name,status,language,components');url.searchParams.set('limit','100');if(after)url.searchParams.set('after',after);
    const data=await meta(url);if(!Array.isArray(data.data)||templates.length+data.data.length>500)throw Error('Invalid template list');templates.push(...data.data);
    if(!data.paging?.next){after=undefined;break;}after=data.paging?.cursors?.after;if(!after)throw Error('Incomplete template list');
   }
   if(after)throw Error('Incomplete template list');
   await rpc('console_sync_templates',{p_rows:templates});await rpc('console_sender_connection',{p_phone_id:phone,p_account_id:account});await rpc('console_automatic_worker_heartbeat',{});
  }
  const config=await rpc('console_sender_configuration',{});if(!config?.ready||!token||config.account_id!==env.get('WHATSAPP_BUSINESS_ACCOUNT_ID')||!/^\d{8,40}$/.test(config.phone_id))return reply(503,{error:'Verify sender connection before sending'});
  const worker='console:'+crypto.randomUUID();const rows=automatic?await rpc('console_claim_registered_alerts',{p_worker_id:worker}):await rpc('console_claim_campaign',{p_campaign_id:campaign,p_worker_id:worker});if(!Array.isArray(rows)||rows.length>10)throw Error('Invalid claim result');
  const outcomes=await Promise.all(rows.map(async(row:any)=>{
   let payload;try{
    let videoLink:string|undefined;
    if(['aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1'].includes(row.template_name)){
     const path=await rpc('console_claimed_reel_object',{p_message_id:row.message_id,p_worker_id:worker});
     if(typeof path!=='string'||!/^[a-f0-9-]{36}\/[a-f0-9-]{36}\.mp4$/.test(path))throw Error('Current Reel required');
     const media=await fetcher(base+'/storage/v1/object/authenticated/recruitment-reels/'+path,{method:'HEAD',headers:serverDatabaseHeaders(key),redirect:'error',signal:AbortSignal.timeout(10000)});
     const size=Number(media.headers.get('content-length'));
     if(!media.ok||!Number.isInteger(size)||size<100||size>16000000||media.headers.get('content-type')?.split(';')[0]!=='video/mp4')throw Error('Unsupported video size or type');
     const signed=await fetcher(base+'/storage/v1/object/sign/recruitment-reels/'+path,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'application/json'},body:JSON.stringify({expiresIn:3600}),redirect:'error',signal:AbortSignal.timeout(10000)});
     if(!signed.ok)throw Error('Reel unavailable');const data=await signed.json();
     if(typeof data.signedURL!=='string'||!data.signedURL.startsWith('/object/sign/recruitment-reels/'+path+'?'))throw Error('Unexpected media URL');
     videoLink=base+'/storage/v1'+data.signedURL;
    }
    payload=templatePayload(row,videoLink);
   }catch{await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'unsupported_template',p_error_code:'payload_rejected',p_failure_kind:'permanent',p_retry_at:null});return 'failed';}
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
