// Pure mapping for the provider-generated aadhyant_vacancy_alert_v1 (en)
// Notification API schema. This helper does not authenticate, select recipients,
// grant consent, send, retry, or infer delivery. Its caller must retain the
// canonical campaign lease and final eligibility/provider boundary.
export function wanotifierVacancyNotificationPayload(input:{destination:string;vacancyReference:string;role:string}){
 if(!/^\+91[6-9]\d{9}$/.test(input.destination))throw Error('Invalid notification destination');
 if(!/^AAD-\d{4}-\d{6}$/.test(input.vacancyReference))throw Error('Invalid vacancy reference');
 if(typeof input.role!=='string'||!input.role.trim()||Array.from(input.role).length>200||/[\u0000-\u001f\u007f]/.test(input.role))throw Error('Invalid vacancy role');
 return {data:{body_variables:[input.vacancyReference,input.role.trim()]},recipients:[{whatsapp_number:input.destination}]};
}
