// Transport adapter only. Durable claim, Admin authorization, 24-hour window,
// consent/suppression and provider boundary remain in the canonical caller.
export function wanotifierSessionTransport(apiKey:string,phoneId:string,fetcher:typeof fetch=fetch):typeof fetch{
 return async(input,init)=>{
  const source=new URL(String(input));
  if(!apiKey||!/^\d{8,40}$/.test(phoneId)||source.origin!=='https://graph.facebook.com'||source.pathname!=='/v25.0/'+phoneId+'/messages'||init?.method!=='POST')throw Error('Provider route rejected');
  const payload=JSON.parse(String(init.body));
  if(payload?.type!=='text'||!/^91[6-9]\d{9}$/.test(payload.to)||typeof payload.text?.body!=='string'||!payload.text.body.trim()||Array.from(payload.text.body).length>2000)throw Error('Unsupported WANotifier session payload');
  const url=new URL('https://app.wanotifier.com/api/v1/messages');url.searchParams.set('key',apiKey);
  // Never log this URL or propagate provider error bodies/URLs to clients.
  const result=await fetcher(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({recipient:{whatsapp_number:'+'+payload.to},message:{type:'text',text:{preview_url:false,body:payload.text.body}}}),redirect:'error',signal:AbortSignal.timeout(15000)});
  if(result.status>=500)throw Error('Ambiguous provider outcome');
  let data:any;try{data=await result.json();}catch{throw Error('Ambiguous provider outcome');}
  if(!result.ok||data?.error===true)return Response.json({error:{code:'wanotifier_rejected'}},{status:400});
  // The documented error:false acknowledgement has no message ID. It must
  // never become Sent, nor cause fallback to Meta or automatic retransmission.
  const id=data?.messages?.[0]?.id;
  if(typeof id!=='string'||!/^wamid\.[A-Za-z0-9._=+\/-]{1,230}$/.test(id))throw Error('Provider receipt requires reconciliation');
  return Response.json({messages:[{id}]});
 };
}
