'use strict';
const endpoint='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/wanotifier-outbox-worker';
async function run(env=process.env,fetcher=fetch){
 if(env.WANOTIFIER_SCHEDULER_ENABLED!=='true'||env.GITHUB_REPOSITORY!=='aadhyantmanpowerstaffing-collab/aadhyant-manpower'
 ||env.GITHUB_REF!=='refs/heads/main'||env.GITHUB_EVENT_NAME!=='schedule')throw Error('WANotifier scheduler is not authorized');
 if(!/^[a-f0-9]{40}$/.test(env.WANOTIFIER_SCHEDULER_APPROVED_SHA||'')||env.CHECKED_OUT_SHA!==env.WANOTIFIER_SCHEDULER_APPROVED_SHA)throw Error('Reviewed scheduler source required');
 if(!/^[a-f0-9]{64}$/.test(env.WHATSAPP_WORKER_SECRET||''))throw Error('Worker credential is missing');
 const kinds=['interviews','registered_alerts'].filter(kind=>env[kind==='interviews'?'WANOTIFIER_INTERVIEWS_ENABLED':'WANOTIFIER_REGISTERED_ALERTS_ENABLED']==='true');
 if(!kinds.length)throw Error('No WANotifier notification kind enabled');
 const results={};
 for(const kind of kinds){
  let response;
  try{response=await fetcher(endpoint,{method:'POST',headers:{'x-whatsapp-worker-key':env.WHATSAPP_WORKER_SECRET,'content-type':'application/json'},body:JSON.stringify({kind}),redirect:'error',signal:AbortSignal.timeout(90000)});}
  catch{throw Error('WANotifier worker completion unconfirmed; review before retrying');}
  if(!response.ok)throw Error('WANotifier worker completion unconfirmed (HTTP '+response.status+'); review before retrying');
  let result;try{result=await response.json();}catch{throw Error('WANotifier worker result unconfirmed');}
  const fields=['processed','sent','blocked','reconciliation_required'];
  if(!result||fields.some(k=>!Number.isInteger(result[k])||result[k]<0||result[k]>10)||result.processed!==result.sent+result.blocked+result.reconciliation_required)throw Error('WANotifier worker result unconfirmed');
  results[kind]=Object.fromEntries(fields.map(k=>[k,result[k]]));
  // Stop this run on an uncertain result; never issue an automatic retry here.
  if(result.reconciliation_required>0)throw Error('Review message results in WANotifier before continuing');
 }
 return results;
}
module.exports={run};
if(require.main===module)run().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error.message);process.exitCode=1;});
