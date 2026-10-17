'use strict';
// No recipients, credentials or template overrides come from scheduler input.
const endpoint='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/whatsapp-outbox-worker';
async function run(env=process.env,fetcher=fetch){
 if(env.WHATSAPP_REGISTERED_ALERTS_ENABLED!=='true'||env.GITHUB_REPOSITORY!=='aadhyantmanpowerstaffing-collab/aadhyant-manpower'||env.GITHUB_REF!=='refs/heads/main'||env.GITHUB_EVENT_NAME!=='schedule')throw Error('Automatic scheduler is not authorized');
 if(!/^[a-f0-9]{40}$/.test(env.WHATSAPP_REGISTERED_ALERTS_APPROVED_SHA||'')||env.CHECKED_OUT_SHA!==env.WHATSAPP_REGISTERED_ALERTS_APPROVED_SHA)throw Error('Reviewed scheduler source required');
 if(!/^[a-f0-9]{64}$/.test(env.WHATSAPP_WORKER_SECRET||''))throw Error('Worker credential is missing');
 const r=await fetcher(endpoint,{method:'POST',headers:{'x-whatsapp-worker-key':env.WHATSAPP_WORKER_SECRET,'content-type':'application/json'},body:'{"automatic":true}',redirect:'error',signal:AbortSignal.timeout(150000)});
 // Only expose the HTTP status, never a response body, header or credential.
 if(!r.ok)throw Error(`Automatic worker did not confirm completion (HTTP ${r.status}); inspect Reports`);
 const d=await r.json(),keys=['processed','sent','failed','reconciliation_required'];
 if(!d||keys.some(k=>!Number.isInteger(d[k])||d[k]<0||d[k]>10)||d.processed!==d.sent+d.failed+d.reconciliation_required)throw Error('Unexpected worker result; inspect Reports');
 // Provider delivery failures are terminal per recipient; no scheduler resend loop.
 return Object.fromEntries(keys.map(k=>[k,d[k]]));
}
module.exports={run};
if(require.main===module)run().then(d=>console.log(JSON.stringify(d))).catch(e=>{console.error(e.message);process.exitCode=1;});
