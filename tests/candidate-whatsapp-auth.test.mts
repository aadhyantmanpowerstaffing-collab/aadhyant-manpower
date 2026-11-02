import test from 'node:test';import assert from 'node:assert/strict';
import {handleAuthHook,verifyAuthHook} from '../supabase/functions/candidate-whatsapp-auth/handler.ts';
const secret='v1,whsec_'+btoa('synthetic-secret-32-bytes-minimum!!');
const body={user:{id:'00000000-0000-0000-0000-000000000099',phone:'919876543210'},sms:{otp:'112233'}};
const settings:Record<string,string>={WANOTIFIER_AUTH_ENABLED:'true',WANOTIFIER_AUTH_TEMPLATE_VERIFIED:'true',SEND_SMS_HOOK_SECRET:secret,WANOTIFIER_AUTH_NOTIFICATION_URL:'https://app.wanotifier.com/api/v1/notifications/synthetic123?key=synthetic-private-key'};
async function request(value:any=body,stamp=Math.floor(Date.now()/1000),id='hook_synthetic'){
 const raw=JSON.stringify(value),key=await crypto.subtle.importKey('raw',new TextEncoder().encode('synthetic-secret-32-bytes-minimum!!'),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const signature=await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(`${id}.${stamp}.${raw}`));
 return new Request('https://synthetic.invalid',{method:'POST',headers:{'webhook-id':id,'webhook-timestamp':String(stamp),'webhook-signature':'v1,'+btoa(String.fromCharCode(...new Uint8Array(signature)))},body:raw});
}
function fixture({claim='send',provider={error:false},throws=false,persist=true}={}){
 const calls:any[]=[],sends:any[]=[];
 const rpc=async(name:string,args:any)=>{calls.push({name,args});return name==='claim_candidate_phone_auth_delivery'?claim:persist;};
 const fetcher:typeof fetch=async(_input,init)=>{sends.push(JSON.parse(String(init?.body)));if(throws)throw Error('secret-error-112233');return Response.json(provider);};
 return {calls,sends,rpc,fetcher};
}
test('signed hook sends the exact single-recipient authentication payload and never persists OTP',async()=>{const f=fixture();const result=await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher);assert.equal(result.status,200);assert.deepEqual(f.sends,[{data:{body_variables:['112233'],button_variables:['112233']},recipients:[{whatsapp_number:'+919876543210'}]}]);assert.doesNotMatch(JSON.stringify(f.calls),/112233|private-key/);});
test('signature rejects tampering, expired timestamp and unsigned payload before any database/provider call',async()=>{
 const req=await request(),raw=await req.text();await assert.rejects(()=>verifyAuthHook(raw+' ',req.headers,secret));await assert.rejects(()=>verifyAuthHook(raw,req.headers,secret,Date.now()+600000));const f=fixture();assert.equal((await handleAuthHook(new Request('https://synthetic.invalid',{method:'POST',body:raw}),k=>settings[k],f.rpc,f.fetcher)).status,401);assert.equal(f.calls.length,0);assert.equal(f.sends.length,0);
});
for(const key of ['WANOTIFIER_AUTH_ENABLED','WANOTIFIER_AUTH_TEMPLATE_VERIFIED','WANOTIFIER_AUTH_NOTIFICATION_URL'])test('missing '+key+' prevents any OTP claim/send',async()=>{const f=fixture();assert.equal((await handleAuthHook(await request(),k=>k===key?'':settings[k],f.rpc,f.fetcher)).status,503);assert.equal(f.calls.length,0);assert.equal(f.sends.length,0);});
for(const claim of ['accepted','review'])test('hook replay '+claim+' never resends',async()=>{const f=fixture({claim});assert.equal((await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher)).status,claim==='accepted'?200:503);assert.equal(f.sends.length,0);});
for(const options of [{provider:{error:true}},{provider:{}},{throws:true},{persist:false}])test('uncertain provider acceptance never retries or leaks code: '+JSON.stringify(options),async()=>{const f=fixture(options as any),result=await handleAuthHook(await request(),k=>settings[k],f.rpc,f.fetcher);assert.equal(result.status,503);assert.equal(f.sends.length,1);assert.doesNotMatch(await result.text(),/112233|secret-error|private-key/);});
test('unsupported phone and malformed OTP are rejected after signature verification without claim',async()=>{for(const value of [{...body,sms:{otp:'12'}},{...body,user:{...body.user,phone:'+12025550100'}}]){const f=fixture();assert.equal((await handleAuthHook(await request(value),k=>settings[k],f.rpc,f.fetcher)).status,400);assert.equal(f.calls.length,0);}});
