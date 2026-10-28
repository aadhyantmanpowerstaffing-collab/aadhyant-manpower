import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
export const reviewedTemplate={"name":"aadhyant_registration_video_hi_v1","language":"hi","category":"MARKETING","components":[{"type":"HEADER","format":"VIDEO"},{"type":"BODY","text":"*Aadhyant Manpower & Staffing*\n\nसाणंद GIDC और आसपास नौकरी ढूंढ रहे हैं?\nउपलब्ध नौकरियों के WhatsApp Job Alerts पाने के लिए आज ही रजिस्टर करें।\n\nरजिस्ट्रेशन निःशुल्क है। नौकरी के लिए उम्मीदवारों से कोई फीस नहीं ली जाती।\n\nनीचे Register Now बटन दबाएँ या https://aadhyantmanpower.in/ खोलें।\nजानकारी के लिए कॉल करें: 9586785800\n\nअलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।"},{"type":"BUTTONS","buttons":[{"type":"URL","text":"Register Now","url":"https://aadhyantmanpower.in/"},{"type":"QUICK_REPLY","text":"Stop alerts"}]}]};
const origin='https://aadhyantmanpower.in',uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export async function handleRegistrationTemplate(req:Request,get:(k:string)=>string,fetcher:typeof fetch=fetch):Promise<Response>{
 const headers={'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':origin,'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS','vary':'Origin'};
 const reply=(status:number,data:any)=>Response.json(data,{status,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST'||req.headers.get('origin')!==origin)return reply(403,{error:'Admin action required'});
 const authorization=req.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return reply(401,{error:'Admin sign in required'});
 try{
  const base=get('SUPABASE_URL'),raw=await req.text();if(raw.length>150)return reply(400,{error:'Choose a review video'});
  const body=JSON.parse(raw);if(!body||Object.keys(body).length!==1||!uuid.test(body.media_id))return reply(400,{error:'Choose a review video'});
  const access=await fetcher(base+'/rest/v1/rpc/admin_console_access',{method:'POST',headers:{authorization,apikey:get('SUPABASE_ANON_KEY'),'content-type':'application/json'},body:'{}',redirect:'error',signal:AbortSignal.timeout(10000)});
  if(!access.ok||await access.json()!==true)return reply(403,{error:'Admin access required'});
  const service=serverDatabaseHeaders(runtimeServerKey(get)),token=get('WHATSAPP_ACCESS_TOKEN'),account=get('WHATSAPP_BUSINESS_ACCOUNT_ID');
  if(!token||!/^\d{8,40}$/.test(account))return reply(503,{error:'Meta configuration required'});
  const rpc=async(name:string,args:any)=>{const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{...service,'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Unavailable');return r.json();};
  const config=await rpc('console_sender_configuration',{});if(config?.account_id!==account)return reply(503,{error:'Verified sender account binding required'});
  const meta=async(path:string,init:any={})=>{const r=await fetcher('https://graph.facebook.com/v25.0/'+path,{...init,headers:{authorization:'Bearer '+token,...init.headers},redirect:'error',signal:AbortSignal.timeout(30000)});const result=await r.json();if(!r.ok)throw Error('Meta request unconfirmed');return result;};
  const list=await meta(account+'/message_templates?name='+reviewedTemplate.name+'&fields=id,name,language,status,components&limit=100');
  if(!Array.isArray(list.data)||list.paging?.next)throw Error('Incomplete lookup');
  const matches=list.data.filter((t:any)=>t.name===reviewedTemplate.name&&t.language==='hi');if(matches.length>1)throw Error('Ambiguous identity');
  if(matches.length){
   const t=matches[0],normalized=(t.components||[]).map((c:any)=>{const {example,...v}=c;if(v.type==='BUTTONS')v.buttons=v.buttons.map((b:any)=>{const {example,...binding}=b;return binding;});return v;});
   const stable=(v:any):any=>Array.isArray(v)?v.map(stable):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])])):v;
   if(JSON.stringify(stable(normalized))!==JSON.stringify(stable(reviewedTemplate.components)))return reply(409,{error:'Existing Meta template differs from the reviewed request. Nothing changed.'});
   return reply(200,{status:t.status,created:false});
  }
  const path=await rpc('console_promotion_media_object',{p_id:body.media_id});if(path!==body.media_id+'/'+body.media_id+'.mp4')return reply(404,{error:'Upload a review video first'});
  const file=await fetcher(base+'/storage/v1/object/authenticated/whatsapp-campaign-media/'+path,{headers:service,redirect:'error',signal:AbortSignal.timeout(15000)});
  const size=Number(file.headers.get('content-length'));if(!file.ok||file.headers.get('content-type')?.split(';')[0]!=='video/mp4'||!Number.isInteger(size)||size<100||size>16000000)throw Error('Invalid review video');
  const bytes=await file.arrayBuffer();if(bytes.byteLength!==size)throw Error('Incomplete video');
  // Meta's app alias binds the upload to the configured token, never to a browser-supplied app.
  const session=await meta('app/uploads/?file_length='+size+'&file_type=video%2Fmp4&file_name=registration.mp4',{method:'POST'});
  if(typeof session.id!=='string'||!/^upload:[A-Za-z0-9_?=.:&-]{1,2000}$/.test(session.id))throw Error('Invalid upload session');
  const sample=await meta(session.id,{method:'POST',headers:{authorization:'OAuth '+token,file_offset:'0','content-type':'application/octet-stream'},body:bytes});
  if(typeof sample.h!=='string'||sample.h.length<5||sample.h.length>10000)throw Error('Invalid sample receipt');
  const request=structuredClone(reviewedTemplate);(request.components[0] as any).example={header_handle:[sample.h]};
  // Exactly one create attempt. A later invocation looks up the fixed name before creating.
  const created=await meta(account+'/message_templates',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(request)});
  if(!/^\d{1,40}$/.test(String(created.id)))throw Error('Unconfirmed template');
  return reply(200,{status:created.status||'PENDING',created:true});
 }catch{return reply(502,{error:'Meta submission could not be confirmed. Check aadhyant_registration_video_hi_v1 in Meta before retrying. No message was sent.'});}
}
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve((req:Request)=>handleRegistrationTemplate(req,(key:string)=>deno.env.get(key)||''));
