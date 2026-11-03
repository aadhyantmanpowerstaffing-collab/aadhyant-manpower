import test from 'node:test';import assert from 'node:assert/strict';
import {handleAuthHook,verifyAuthHook} from '../supabase/functions/candidate-whatsapp-auth/handler.ts';
const secret='v1,whsec_'+btoa('synthetic-secret-32-bytes-minimum!!');
const body={user:{id:'00000000-0000-0000-0000-000000000099',phone:'919876543210'},sms:{otp:'112233'}};
const settings:Record<string,string>={WHATSAPP_AUTH_ENABLED:'true',WHATSAPP_AUTH_TEMPLATE_VERIFIED:'true',SEND_SMS_HOOK_SECRET:secret,WHATSAPP_ACCESS_TOKEN:'synthetic-private-key',WHATSAPP_PHONE_NUMBER_ID:'1415347881659158',WHATSAPP_BUSINESS_ACCOUNT_ID:'1386833723249335'};
async function request(value:any=body,stamp=Math.floor(Date.now()/1000),id='hook_synthetic'){
 const raw=JSON.stringify(value),key=await crypto.subtle.importKey('raw',new TextEncoder().encode('synthetic-secret-32-bytes-minimum!!'),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const signature=await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(`${id}.${stamp}.${raw}`));
 return new Request('https://synthetic.invalid',{method:'POST',headers:{'webhook-id':id,'webhook-timestamp':String(stamp),'webhook-signature':'v1,'+btoa(String.fromCharCode(...new Uint8Array(signature)))},body:raw});
}
function fixture({claim='send',provider={messages:[{id:'wamid.synthetic_receipt'}]},throws=false,persist=true,httpStatus=200}={}){
 const calls:any[]=[],sends:any[]=[],requests:any[]=[];
 const rpc=async(name:string,args:any)=>{calls.push({name,args});return name==='claim_candidate_phone_auth_delivery'?claim:persist;};
 const fetcher:typeof fetch=async(_input,init)=>{sends.push(JSON.parse(String(init?.body)));requests.push({url:String(_input),method:init?.method,headers:init?.headers,redirect:init?.redirect});if(throws)throw Error('secret-error-112233');return Response.json(provider,{status:httpStatus});};
 return {calls,sends,requests,rpc,fetcher};
}
test('signed hook sends the exact single-recipient authentication payload and never persists OTP',async()=>{const f=fixture();const result=await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher);assert.equal(result.status,200);assert.deepEqual(f.sends,[{messaging_product:'whatsapp',to:'919876543210',type:'template',template:{name:'aadhyant_candidate_login_otp_en_v1',language:{code:'en'},components:[{type:'body',parameters:[{type:'text',text:'112233'}]},{type:'button',sub_type:'url',index:'0',parameters:[{type:'text',text:'112233'}]}]}}]);assert.doesNotMatch(JSON.stringify(f.calls),/112233|private-key/);});
test('signature rejects tampering, expired timestamp and unsigned payload before any database/provider call',async()=>{
 const req=await request(),raw=await req.text();await assert.rejects(()=>verifyAuthHook(raw+' ',req.headers,secret));await assert.rejects(()=>verifyAuthHook(raw,req.headers,secret,Date.now()+600000));const f=fixture();assert.equal((await handleAuthHook(new Request('https://synthetic.invalid',{method:'POST',body:raw}),k=>settings[k],f.rpc,f.fetcher)).status,401);assert.equal(f.calls.length,0);assert.equal(f.sends.length,0);
});
for(const key of ['WHATSAPP_AUTH_ENABLED','WHATSAPP_AUTH_TEMPLATE_VERIFIED','WHATSAPP_ACCESS_TOKEN','WHATSAPP_PHONE_NUMBER_ID','WHATSAPP_BUSINESS_ACCOUNT_ID'])test('missing '+key+' prevents any OTP claim/send',async()=>{const f=fixture();assert.equal((await handleAuthHook(await request(),k=>k===key?'':settings[k],f.rpc,f.fetcher)).status,503);assert.equal(f.calls.length,0);assert.equal(f.sends.length,0);});
for(const claim of ['accepted','review'])test('hook replay '+claim+' never resends',async()=>{const f=fixture({claim});assert.equal((await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher)).status,claim==='accepted'?200:503);assert.equal(f.sends.length,0);});
for(const options of [{provider:{error:true}},{provider:{}},{provider:{messages:[{id:'invented'}]}},{provider:{messages:[{id:'wamid.a'},{id:'wamid.b'}]}},{httpStatus:400},{httpStatus:500},{throws:true},{persist:false}])test('uncertain provider acceptance never retries or leaks code: '+JSON.stringify(options),async()=>{const f=fixture(options as any),result=await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher);assert.equal(result.status,503);assert.equal(f.sends.length,1);assert.doesNotMatch(await result.text(),/112233|secret-error|private-key/);});
test('unsupported phone and malformed OTP are rejected after signature verification without claim',async()=>{for(const value of [{...body,sms:{otp:'12'}},{...body,user:{...body.user,phone:'+12025550100'}}]){const f=fixture();assert.equal((await handleAuthHook(await request(value),k=>settings[k],f.rpc,f.fetcher)).status,400);assert.equal(f.calls.length,0);}});

test('direct transport uses only the configured Meta sender and bearer header',async()=>{const f=fixture();await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher);assert.equal(f.requests[0].url,'https://graph.facebook.com/v25.0/1415347881659158/messages');assert.equal(f.requests[0].redirect,'error');assert.equal(f.requests[0].headers.authorization,'Bearer synthetic-private-key');assert.equal(f.requests[0].method,'POST');assert.doesNotMatch(f.requests[0].url,/private-key|112233|wanotifier/);});
