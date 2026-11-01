export const jobMessageFields=['qualification','group_1','ctc_1','take_home_1','ot_1','group_2','ctc_2','take_home_2','ot_2','benefits'];
export const jobMessageLanguages:Record<string,'en'|'hi'>={aadhyant_job_salary_details_en_v2:'en',aadhyant_job_salary_details_hi_v2:'hi'};
export const jobMessageBodies:Record<string,string>={"en":"Hello,\n\nAadhyant Manpower & Staffing has new job openings.\n\n*Qualification:*\n{{1}}\n\n*Salary Details*\n\n*{{2}}*\n• CTC: {{3}}\n• Take Home: {{4}}\n• OT: {{5}}\n\n*{{6}}*\n• CTC: {{7}}\n• Take Home: {{8}}\n• OT: {{9}}\n\n*Benefits*\n{{10}}\n\nInterested? Tap the Interested button below.\nCall us: 96244 53543\n\nReply STOP to stop job alerts.","hi":"नमस्ते,\n\nAadhyant Manpower & Staffing में नौकरी के नए अवसर उपलब्ध हैं।\n\n*योग्यता:*\n{{1}}\n\n*वेतन विवरण*\n\n*{{2}}*\n• CTC: {{3}}\n• हाथ में वेतन: {{4}}\n• ओवरटाइम: {{5}}\n\n*{{6}}*\n• CTC: {{7}}\n• हाथ में वेतन: {{8}}\n• ओवरटाइम: {{9}}\n\n*सुविधाएँ*\n{{10}}\n\nइच्छुक हैं? नीचे Interested बटन दबाएँ।\nहमें कॉल करें: 96244 53543\n\nनौकरी के अलर्ट बंद करने के लिए STOP लिखें।"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function jobMessageNotificationPayload(row:any){
 const v=row.template_variables,language=jobMessageLanguages[row.template_name];
 if(!language||row.template_language!==language||row.template_version!=='1'||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'
 ||!/^\+91[6-9]\d{9}$/.test(row.destination)||!uuid.test(row.correlation_id)||v?.template_contract!=='salary_details_v2'
 ||!uuid.test(v.campaign_id)||v.recipient_id!==row.correlation_id||!/^[A-Za-z0-9_-]{1,160}$/.test(v.requirement_code||'')||!/^[a-f0-9]{64}$/.test(v.job_fingerprint||'')
 ||Object.keys(v).length!==15||jobMessageFields.some(k=>typeof v[k]!=='string'||!v[k].trim()||Array.from(v[k]).length>300||/[\u0000-\u001f\u007f]| {5}|\{\{|\}\}/.test(v[k])))throw Error('Invalid Job Message contract');
 const rendered=jobMessageBodies[language].replace(/\{\{(\d+)\}\}/g,(_,n)=>v[jobMessageFields[Number(n)-1]]);
 if(Array.from(rendered).length>1024)throw Error('Job Message exceeds supported size');
 // A fixed Interested quick reply has no runtime URL/button variable.
 return {data:{body_variables:jobMessageFields.map(k=>v[k])},recipients:[{whatsapp_number:row.destination}]};
}
export function wanotifierMessageId(receipt:any):string{
 const nested=receipt?.messages?.[0]?.id,top=receipt?.wamid;
 if(nested!==undefined&&top!==undefined&&nested!==top)throw Error('Conflicting provider receipts');
 const id=top??nested;
 if(typeof id!=='string'||!/^wamid\.[A-Za-z0-9._=+\/-]{1,230}$/.test(id))throw Error('Provider receipt requires reconciliation');
 return id;
}
