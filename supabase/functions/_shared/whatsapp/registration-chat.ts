import {sendSessionOutbox} from './registration-reply.ts';

// No submitted profile data is echoed. Choice IDs bind the exact session and step.
const questions = [
  'May Aadhyant register you and contact you about this job? This does not subscribe you to future job alerts. Please read our privacy policy: https://aadhyantmanpower.in/privacy/',
  'Please type your full name.',
  'Please type your age in completed years (16–75).',
  'Please select your gender.',
  'Please select your highest qualification.',
  'Please type your course, trade or specialization. Type General if you do not have one.',
  'Please type your state.',
  'Please type your district.',
  'Please type your current village or city.',
  'Are you a fresher or experienced?',
  'Can you attend an interview for this job?',
  'Would you like to receive ALL Aadhyant job alerts on WhatsApp, including jobs outside your qualification, trade, age or preferred location? You may share them with others. This is optional. Select No to finish registration without subscribing. You can stop alerts anytime by sending STOP.',
];
const choices: Record<number,string[]> = {
  0:['Yes','No'],3:['Male','Female','Other'],
  4:['Below 10th','10th','12th','ITI','Diploma','Graduate','Post Graduate','Other'],
  9:['Fresher','Experienced'],10:['Yes','No'],11:['Yes','No'],
};
const compactQuestions = [
  'May Aadhyant register you and contact you about this job? Future job alerts are a separate choice. Privacy: https://aadhyantmanpower.in/privacy/',
  'Personal details — reply in ONE message:\nName | Age | Gender | State | District | City/Village\nExample: Ravi Patel | 25 | Male | Gujarat | Ahmedabad | Sanand\nAge: 16–75. Gender: Male / Female / Other. You may also send one value per line.',
  'Education & availability — reply in ONE message:\nQualification | Trade/Course | Fresher/Experienced | Interview Yes/No\nExample: ITI | Fitter | Fresher | Yes\nQualification: Below 10th / 10th / 12th / ITI / Diploma / Graduate / Post Graduate / Other. Use General if no trade. You may also send one value per line.',
  'Receive ALL Aadhyant job alerts on WhatsApp, even outside your qualification or location? You can share them. Optional: No still completes registration. Send STOP anytime to stop alerts.',
];
export function registrationChatPayload(row:any) {
  const v=row.template_variables;
  if(row.purpose!=='registration_chat'||row.consent_class!=='transactional'||row.message_type!=='session_text'
    ||!/^\+91[6-9]\d{9}$/.test(row.destination)||!v||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v.session_id)
    ||!Number.isInteger(v.step)||v.step<0||v.step>12||!['question','complete','cancelled','review'].includes(v.kind)
    ||typeof v.invalid!=='boolean'||!/^([A-Z0-9_-]){1,64}$/.test(v.requirement_code)) throw Error('Invalid registration chat');
  const base={messaging_product:'whatsapp',to:row.destination.slice(1)};
  if(v.mode!==undefined&&!['legacy','compact'].includes(v.mode))throw Error('Invalid intake mode');
  if(v.kind!=='question') {
    if(v.kind==='complete'&&typeof v.job_alerts_selected!=='boolean')throw Error('Invalid registration receipt');
    const text=v.kind==='complete'
      ? `Registration complete. Your interest in ${v.requirement_code} has been recorded. ${v.job_alerts_selected?'You have subscribed to all Aadhyant job alerts. Send STOP anytime to stop alerts.':'You have not subscribed to new job alerts through this registration.'} Aadhyant will contact you about the next steps for this job.`
      : v.kind==='cancelled'?'Registration cancelled. No registration or new job-alert subscription was created.'
      : 'Your registration needs an Aadhyant staff review. No new job-alert subscription was created. Please contact Aadhyant for help.';
    return {...base,type:'text',text:{preview_url:false,body:text}};
  }
  const compact=v.mode==='compact';
  if(v.step===12||(compact&&v.step>3))throw Error('Question step invalid');
  const body=`Aadhyant • ${v.requirement_code}${compact?' • '+(v.step+1)+'/4':''}\n${v.invalid?'Please use the options or send all values in the format below.\n':''}${compact?compactQuestions[v.step]:questions[v.step]}\n\nCANCEL = cancel • RESUME = repeat`;
  const options=compact?(v.step===0||v.step===3?['Yes','No']:undefined):choices[v.step];
  if(!options)return {...base,type:'text',text:{preview_url:false,body}};
  const rows=options.map((title,i)=>({id:`REGCHAT|${v.session_id}|${v.step}|${i+1}`,title}));
  if(options.length<=3)return {...base,type:'interactive',interactive:{type:'button',body:{text:body},action:{buttons:rows.map(reply=>({type:'reply',reply}))}}};
  return {...base,type:'interactive',interactive:{type:'list',body:{text:body},action:{button:'Select qualification',sections:[{title:'Highest qualification',rows}]}}};
}
export async function sendRegistrationChat(messageId:string,rpc:(name:string,body:Record<string,unknown>)=>Promise<any>,
  config:{ready:boolean;phone_id:string;account_id:string},token:string,fetcher:typeof fetch=fetch) {
  return sendSessionOutbox(messageId,rpc,config,token,fetcher,'console_claim_registration_chat','p_message_id','console_registration_chat_boundary',registrationChatPayload);
}
