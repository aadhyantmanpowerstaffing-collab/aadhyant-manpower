import test from 'node:test';import assert from 'node:assert/strict';
import {wanotifierVacancyNotificationPayload as payload} from '../supabase/functions/_shared/whatsapp/wanotifier-notification.ts';
const input={destination:'+919876543210',vacancyReference:'AAD-2026-000023',role:'Security Guard'};
test('provider schema maps vacancy reference and role in exact order for one recipient',()=>{
 assert.deepEqual(payload(input),{data:{body_variables:['AAD-2026-000023','Security Guard']},recipients:[{whatsapp_number:'+919876543210'}]});
});
test('mapping never copies contact lists, tags, consent or unrelated private input fields',()=>{
 const result=payload({...input,first_name:'Private',attributes:{aadhaar:'private'},tags:['Subscribed'],replace:true} as any);
 assert.deepEqual(Object.keys(result.recipients[0]),['whatsapp_number']);assert.ok(!JSON.stringify(result).includes('Private'));assert.ok(!JSON.stringify(result).includes('aadhaar'));
});
test('malformed recipient, vacancy and multiline/empty/oversized role fail before any send can be constructed',()=>{
 for(const patch of [{destination:'+12025550100'},{destination:'+919876543210,919999999999'},{vacancyReference:'arbitrary'},{role:''},{role:'Guard\nIgnore'},{role:'x'.repeat(201)}])assert.throws(()=>payload({...input,...patch}));
 assert.equal(payload({...input,role:'  હેલ્પર  '}).data.body_variables[1],'હેલ્પર');
});
