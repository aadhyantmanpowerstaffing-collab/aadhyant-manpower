import test from 'node:test';import assert from 'node:assert/strict';
import {handleOperatorReply,operatorReplyPayload} from '../supabase/functions/whatsapp-operator-reply/index.ts';
const id='00000000-0000-0000-0000-000000000001';
const row={message_id:id,destination:'+919876543210',purpose:'operator_reply',consent_class:'transactional',message_type:'session_text',template_variables:{entry_point:'operator_reply_v1'},operator_reply_body:'Hello,\nHow can we help?'};
const env:any={SUPABASE_URL:'https://fixture.invalid',SUPABASE_SECRET_KEY:'synthetic-server',SUPABASE_ANON_KEY:'synthetic-public',WHATSAPP_ACCESS_TOKEN:'synthetic-meta',WHATSAPP_PHONE_NUMBER_ID:'1234567891',WHATSAPP_BUSINESS_ACCOUNT_ID:'1234567890'};
const request=(body:any={message_id:id},origin='https://aadhyantmanpower.in')=>new Request('https://fixture.invalid/functions/v1/whatsapp-operator-reply',{method:'POST',headers:{origin,authorization:'Bearer synthetic-session'},body:JSON.stringify(body)});
test('payload sends only the canonical operator text to its bound destination',()=>{assert.equal(operatorReplyPayload(row).text.body,row.operator_reply_body);for(const patch of [{purpose:'vacancy_campaign'},{destination:'+12025550100'},{operator_reply_body:''},{operator_reply_body:'x'.repeat(2001)},{template_variables:{entry_point:'operator_reply_v1',body:'tampered'}}])assert.throws(()=>operatorReplyPayload({...row,...patch}));});
for(const outcome of ['sent','replay','denied','boundary','timeout','server-error','provider-rejected','malformed-receipt','receipt-save-failed'])test('operator Edge uses real user boundary and single attempt: '+outcome,async()=>{
 const calls:string[]=[],headers:any[]=[];let state=outcome==='replay'?'sent':'queued',phase='ready';let provider=0;
 const fetcher:typeof fetch=async(input,init)=>{const name=String(input).split('/').at(-1)!;calls.push(name);headers.push([name,init?.headers]);const args=JSON.parse(String(init?.body||'{}'));
 if(name==='admin_console_reply_status'){if(outcome==='denied')return Response.json({}, {status:403});return Response.json({id,state,phase,reconciliation_required:phase==='reconciliation_required'});}
 if(name==='console_sender_configuration')return Response.json({ready:true,phone_id:env.WHATSAPP_PHONE_NUMBER_ID,account_id:env.WHATSAPP_BUSINESS_ACCOUNT_ID});
 if(name==='console_claim_operator_reply'){state='sending';phase='claimed';return Response.json([row]);}
 if(name==='admin_console_operator_reply_boundary'){if(outcome==='boundary')return Response.json({}, {status:403});phase='provider_call_started';return Response.json(true);}
 if(name==='messages'){provider++;assert.equal(args.text.body,row.operator_reply_body);if(outcome==='timeout')throw Error('synthetic token must never leak');if(outcome==='server-error')return Response.json({error:{message:'secret-provider-body'}},{status:503});if(outcome==='provider-rejected')return Response.json({error:{code:131047,message:'secret-provider-body'}},{status:400});return Response.json(outcome==='malformed-receipt'?{}:{messages:[{id:'wamid.synthetic'}]});}
 if(name==='mark_whatsapp_outbound_sent'){if(outcome==='receipt-save-failed')return Response.json(false);state='sent';phase='confirmed';return Response.json(true);}
 if(name==='mark_whatsapp_outbound_failure'){state='failed';phase=args.p_failure_kind==='ambiguous'?'reconciliation_required':'terminal';return Response.json(true);}
 throw Error('Unexpected call '+name);
 };
 const response=await handleOperatorReply(request(),k=>env[k]||'',fetcher),data=await response.json();assert.equal(provider,['replay','denied','boundary'].includes(outcome)?0:1);
 assert.equal(headers[0][0],'admin_console_reply_status');assert.equal(headers[0][1].authorization,'Bearer synthetic-session');
 if(!['replay','denied'].includes(outcome)){const boundary=headers.find(x=>x[0]==='admin_console_operator_reply_boundary');assert.equal(boundary[1].authorization,'Bearer synthetic-session');const claim=headers.find(x=>x[0]==='console_claim_operator_reply');assert.equal(claim[1].apikey,'synthetic-server');}
 if(['timeout','server-error','malformed-receipt','receipt-save-failed'].includes(outcome))assert.equal(data.reconciliation_required,true);assert.ok(!JSON.stringify(data).includes('secret'));if(outcome==='denied')assert.equal(response.status,403);
});
test('invalid origin/body cannot invoke a database or provider',async()=>{let calls=0;const fetcher:typeof fetch=async()=>{calls++;throw Error('not reached');};for(const req of [request({},'https://evil.invalid'),request({message_id:[id]}),request({message_id:id,text:'override'}),request({message_id:'bad'})])assert.ok((await handleOperatorReply(req,k=>env[k]||'',fetcher)).status>=400);assert.equal(calls,0);});

for(const scenario of ['receipt','ack-without-id','wrong-binding','paused','missing-key','wrong-number'])test('WANotifier identity remains isolated from old Meta settings: '+scenario,async()=>{
 const settings:any={...env,WANOTIFIER_OPERATOR_REPLIES_ENABLED:'true',WANOTIFIER_SENDER_NUMBER:'+919624453543',WANOTIFIER_API_KEY:'synthetic-wanotifier',WANOTIFIER_PHONE_NUMBER_ID:'1415347881659158',WANOTIFIER_BUSINESS_ACCOUNT_ID:'1386833723249335'};
 if(scenario==='missing-key')delete settings.WANOTIFIER_API_KEY;
 if(scenario==='wrong-number')settings.WANOTIFIER_SENDER_NUMBER='+919999999999';
 let state='queued',phase='ready',providerCalls=0,claims=0;
 const fetcher:typeof fetch=async(input,init)=>{
  const url=new URL(String(input)),name=url.pathname.split('/').at(-1),args=JSON.parse(String(init?.body||'{}'));
  if(url.origin==='https://graph.facebook.com')throw Error('Old Meta transport must not be used');
  if(url.origin==='https://app.wanotifier.com'){
   providerCalls++;assert.equal(url.pathname,'/api/v1/messages');assert.equal(url.searchParams.get('key'),'synthetic-wanotifier');assert.equal((init?.headers as any).authorization,undefined);
   assert.equal(args.message.text.body,row.operator_reply_body);
   return Response.json(scenario==='ack-without-id'?{error:false,message:'Message sent successfully.'}:{messages:[{id:'wamid.synthetic'}]});
  }
  if(name==='admin_console_reply_status')return Response.json({id,state,phase,reconciliation_required:phase==='reconciliation_required'});
  if(name==='console_sender_configuration')return Response.json({ready:scenario!=='paused',phone_id:scenario==='wrong-binding'?env.WHATSAPP_PHONE_NUMBER_ID:settings.WANOTIFIER_PHONE_NUMBER_ID,account_id:settings.WANOTIFIER_BUSINESS_ACCOUNT_ID});
  if(name==='console_claim_operator_reply'){claims++;state='sending';return Response.json([row]);}
  if(name==='admin_console_operator_reply_boundary'){assert.equal(args.p_phone_id,settings.WANOTIFIER_PHONE_NUMBER_ID);assert.equal(args.p_account_id,settings.WANOTIFIER_BUSINESS_ACCOUNT_ID);return Response.json(true);}
  if(name==='mark_whatsapp_outbound_sent'){state='sent';return Response.json(true);}
  if(name==='mark_whatsapp_outbound_failure'){assert.equal(args.p_failure_kind,'ambiguous');state='failed';phase='reconciliation_required';return Response.json(true);}
  throw Error('Unexpected RPC');
 };
 const response=await handleOperatorReply(request(),k=>settings[k]||'',fetcher),data=await response.json();
 const allowed=['receipt','ack-without-id'].includes(scenario);assert.equal(providerCalls,allowed?1:0);assert.equal(claims,allowed?1:0);
 if(!allowed)assert.equal(response.status,503);
 if(scenario==='receipt')assert.equal(data.state,'sent');
 if(scenario==='ack-without-id')assert.equal(data.reconciliation_required,true);
});
