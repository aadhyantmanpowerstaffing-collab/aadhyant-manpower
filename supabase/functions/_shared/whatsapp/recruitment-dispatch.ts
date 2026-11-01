import {wanotifierNotificationTransport} from './wanotifier-notification.ts';
import {wanotifierMessageId} from './job-message.ts';
export const recruitmentRoutes:Record<string,string>={};
for(const kind of ['interview_confirmation','interview_reminder','joining_details'])for(const language of ['en','hi'])
 recruitmentRoutes[`aadhyant_${kind}_${language}_v1`]=`WANOTIFIER_${kind.toUpperCase()}_${language.toUpperCase()}_URL`;
export function recruitmentPayload(row:any){
 if(!Object.hasOwn(recruitmentRoutes,row.template_name)||!['en','hi'].includes(row.template_language)
 ||!row.template_name.endsWith(`_${row.template_language}_v1`)||!/^\+91[6-9]\d{9}$/.test(row.destination))throw Error('Unsupported recruitment route');
 const fields=['requirement_code','job_role','event_date','event_time','venue','instructions'];
 if(!row.template_variables||Object.keys(row.template_variables).length!==fields.length)throw Error('Invalid recruitment variables');
 const values=fields.map(k=>row.template_variables[k]);
 if(values.some(v=>typeof v!=='string'||!v.trim()||Array.from(v).length>300||/[\u0000-\u001f\u007f]/.test(v)))throw Error('Invalid recruitment variables');
 return {data:{body_variables:values},recipients:[{whatsapp_number:row.destination}]};
}
export async function dispatchRecruitmentNotifications(worker:string,phoneId:string,accountId:string,get:(k:string)=>string,rpc:(n:string,a:Record<string,unknown>)=>Promise<any>,fetcher:typeof fetch){
 // Validate every configured route before preparing or claiming any candidate message.
 const transports=Object.fromEntries(Object.entries(recruitmentRoutes).map(([name,key])=>[name,wanotifierNotificationTransport(get(key),fetcher)]));
 await rpc('prepare_recruitment_notifications',{});
 const rows=await rpc('console_claim_recruitment_notifications',{p_worker_id:worker});
 if(!Array.isArray(rows)||rows.length>10)throw Error('Recruitment claim unconfirmed');
 // Claims share a 60-second lease. Run this bounded batch concurrently so a
 // slow provider response cannot consume the leases of later recipients.
 const results=await Promise.allSettled(rows.map(async row=>{
  let payload;
  try{payload=recruitmentPayload(row);if(await rpc('console_recruitment_provider_boundary',{p_message_id:row.message_id,p_worker_id:worker,p_phone_id:phoneId,p_account_id:accountId})!==true)throw Error('Boundary denied');}
  catch{await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'eligibility_changed',p_error_code:'recruitment_final_check',p_failure_kind:'permanent'});return 'blocked';}
  try{const receipt=await transports[row.template_name](payload);const id=wanotifierMessageId(receipt);
   if(await rpc('mark_whatsapp_outbound_sent',{p_message_id:row.message_id,p_worker_id:worker,p_provider_message_id:id})!==true)throw Error('Receipt not persisted');return 'sent';
  }catch{await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'ambiguous_provider_outcome',p_error_code:'reconcile_before_retry',p_failure_kind:'ambiguous'});return 'reconciliation_required';}
 }));
 if(results.some(r=>r.status==='rejected'))throw Error('Recruitment result persistence unconfirmed');
 const outcomes=results.map(r=>(r as PromiseFulfilledResult<string>).value);
 return {processed:outcomes.length,sent:outcomes.filter(x=>x==='sent').length,blocked:outcomes.filter(x=>x==='blocked').length,reconciliation_required:outcomes.filter(x=>x==='reconciliation_required').length};
}
