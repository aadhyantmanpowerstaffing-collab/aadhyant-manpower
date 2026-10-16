import {sendSessionOutbox} from './registration-reply.ts';
export const isEmployerPostJob=(text:unknown)=>typeof text==='string'&&['POST JOB','POSTJOB','POST_JOB','POST VACANCY','NEW VACANCY'].includes(text.trim().replace(/\s+/g,' ').toUpperCase());
export function employerPostJobPayload(row:any){
 if(row.purpose!=='employer_post_job'||row.consent_class!=='transactional'||row.message_type!=='session_text'
 ||!/^\+91[6-9]\d{9}$/.test(row.destination)||JSON.stringify(row.template_variables)!==JSON.stringify({entry_point:'post_job_v1'}))throw Error('Invalid employer posting reply');
 return {messaging_product:'whatsapp',to:row.destination.slice(1),type:'text',text:{preview_url:false,body:'Aadhyant Manpower & Staffing\n\nPost a vacancy as a Company or Contractor:\nhttps://aadhyantmanpower.in/post-job/\n\nChoose your account type and complete the vacancy form. Sign in with your own approved portal account if asked.\n\nSubmit for Aadhyant review. Candidate alerts follow Admin approval and publication when job alerts are active. This does not subscribe you to job alerts.'}};
}
export async function sendEmployerPostJob(id:string,rpc:(name:string,body:Record<string,unknown>)=>Promise<any>,config:{ready:boolean;phone_id:string;account_id:string},token:string,fetcher:typeof fetch=fetch){
 return sendSessionOutbox(id,rpc,config,token,fetcher,'console_claim_employer_post_job','p_message_id','console_employer_post_job_boundary',employerPostJobPayload);
}
