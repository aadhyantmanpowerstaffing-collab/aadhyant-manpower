import {wanotifierInterviewNotificationPayload} from './wanotifier-notification.ts';

type Claim={message_id:string;destination:string;template_language:'en'|'hi';template_variables:Record<string,string>};
type Dependencies={
 rpc:(name:string,args:Record<string,unknown>)=>Promise<unknown>;
 // Provider transport is supplied only after its receipt contract is verified.
 send:(language:'en'|'hi',payload:ReturnType<typeof wanotifierInterviewNotificationPayload>)=>Promise<unknown>;
};
export async function dispatchInterviewNotifications(worker:string,phoneId:string,accountId:string,deps:Dependencies){
 if(!worker.trim()||worker.length>160||!/^\d{8,40}$/.test(phoneId)||!/^\d{8,40}$/.test(accountId))throw Error('Invalid interview worker identity');
 const claimed=await deps.rpc('console_claim_interview_notifications',{p_worker_id:worker});
 if(!Array.isArray(claimed)||claimed.length>10)throw Error('Interview claim not confirmed');
 const results:{message_id:string;outcome:'sent'|'blocked'|'reconciliation_required'}[]=[];
 for(const row of claimed as Claim[]){
  let payload:ReturnType<typeof wanotifierInterviewNotificationPayload>;
  try{
   payload=wanotifierInterviewNotificationPayload({destination:row.destination,language:row.template_language,variables:row.template_variables});
   const permitted=await deps.rpc('console_interview_provider_boundary',{p_message_id:row.message_id,p_worker_id:worker,p_phone_id:phoneId,p_account_id:accountId});
   if(permitted!==true)throw Error('Boundary denied');
  }catch{
   await deps.rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'interview_ineligible',p_error_code:'final_check_failed',p_failure_kind:'permanent'});
   results.push({message_id:row.message_id,outcome:'blocked'});continue;
  }
  // Exactly one invocation. Network errors, malformed receipts and successful
  // acknowledgements without a genuine provider ID all require reconciliation.
  try{
   const receipt:any=await deps.send(row.template_language,payload);
   const id=receipt?.messages?.[0]?.id;
   if(typeof id!=='string'||!/^wamid\.[A-Za-z0-9._=+\/-]{1,230}$/.test(id))throw Error('Unconfirmed provider receipt');
   const recorded=await deps.rpc('mark_whatsapp_outbound_sent',{p_message_id:row.message_id,p_worker_id:worker,p_provider_message_id:id});
   if(recorded!==true)throw Error('Receipt persistence unconfirmed');
   results.push({message_id:row.message_id,outcome:'sent'});
  }catch{
   await deps.rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'ambiguous_provider_outcome',p_error_code:'reconcile_before_retry',p_failure_kind:'ambiguous'});
   results.push({message_id:row.message_id,outcome:'reconciliation_required'});
  }
 }
 return results;
}
