(() => {
 'use strict';
 const fields=['qualification','group_1','ctc_1','take_home_1','ot_1','group_2','ctc_2','take_home_2','ot_2','benefits'];
 const bodies={
 en:'Hello,\n\nAadhyant Manpower & Staffing has new job openings.\n\n*Qualification:*\n{{1}}\n\n*Salary Details*\n\n*{{2}}*\n• CTC: {{3}}\n• Take Home: {{4}}\n• OT: {{5}}\n\n*{{6}}*\n• CTC: {{7}}\n• Take Home: {{8}}\n• OT: {{9}}\n\n*Benefits*\n{{10}}\n\nInterested? Tap the Interested button below.\nCall us: 96244 53543\n\nReply STOP to stop job alerts.',
 hi:'नमस्ते,\n\nAadhyant Manpower & Staffing में नौकरी के नए अवसर उपलब्ध हैं।\n\n*योग्यता:*\n{{1}}\n\n*वेतन विवरण*\n\n*{{2}}*\n• CTC: {{3}}\n• हाथ में वेतन: {{4}}\n• ओवरटाइम: {{5}}\n\n*{{6}}*\n• CTC: {{7}}\n• हाथ में वेतन: {{8}}\n• ओवरटाइम: {{9}}\n\n*सुविधाएँ*\n{{10}}\n\nइच्छुक हैं? नीचे Interested बटन दबाएँ।\nहमें कॉल करें: 96244 53543\n\nनौकरी के अलर्ट बंद करने के लिए STOP लिखें।'
 };
 const name=language=>{if(!Object.hasOwn(bodies,language))throw Error('Choose Hindi or English.');return 'aadhyant_job_salary_details_'+language+'_v2';};
 const isTemplate=t=>['en','hi'].some(l=>t?.name===name(l)&&t.language===l);
 function validate(values){
  if(!values||Array.isArray(values)||Object.keys(values).length!==fields.length||fields.some(k=>typeof values[k]!=='string'||!values[k].trim()||Array.from(values[k]).length>300||/[\u0000-\u001f\u007f]| {5}|\{\{|\}\}/.test(values[k])))throw Error('Complete all message fields. Use one line per field, up to 300 characters.');
  return Object.fromEntries(fields.map(k=>[k,values[k].trim()]));
 }
 const render=(language,values)=>{name(language);const v=validate(values);const text=bodies[language].replace(/\{\{(\d+)\}\}/g,(_,n)=>v[fields[Number(n)-1]]);if(Array.from(text).length>1024)throw Error('Shorten the message to 1,024 characters.');return text;};
 const api=Object.freeze({fields,bodies,name,isTemplate,validate,render});
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
 if(typeof window!=='undefined')window.AadhyantJobMessage=api;
})();
