import {serverDatabaseHeaders} from './server-headers.ts';
export const campaignVideoTemplates=new Set(['aadhyant_registered_job_video_en_v1','aadhyant_registered_job_video_hi_v1','aadhyant_registration_video_hi_v1']);
export async function campaignMediaUrl(row:any,worker:string,base:string,key:string,rpc:(name:string,args:Record<string,unknown>)=>Promise<any>,fetcher:typeof fetch){
 const image=row.template_name==='aadhyant_registered_job_image_hi_v1';
 if(!image&&!campaignVideoTemplates.has(row.template_name))return undefined;
 const bucket=(image||row.template_name==='aadhyant_registration_video_hi_v1')?'whatsapp-campaign-media':'recruitment-reels';
 const object=await rpc(image?'console_claimed_image_object':'console_claimed_reel_object',{p_message_id:row.message_id,p_worker_id:worker});
 const path=image?object?.path:object;
 const format=image?object?.format:'VIDEO',mime=format==='JPEG'?'image/jpeg':format==='PNG'?'image/png':format==='VIDEO'?'video/mp4':null;
 if(typeof path!=='string'||!mime||image&&!['JPEG','PNG'].includes(format)||!image&&format!=='VIDEO'||!new RegExp('^[a-f0-9-]{36}/[a-f0-9-]{36}'+(format==='JPEG'?'\\.jpg':format==='PNG'?'\\.png':'\\.mp4')+'$').test(path))throw Error('Current canonical media required');
 const media=await fetcher(base+'/storage/v1/object/authenticated/'+bucket+'/'+path,{method:'HEAD',headers:serverDatabaseHeaders(key),redirect:'error',signal:AbortSignal.timeout(10000)});
 const size=Number(media.headers.get('content-length'));
 if(!media.ok||!Number.isInteger(size)||size<100||size>(image?5000000:16000000)||media.headers.get('content-type')?.split(';')[0]!==mime)throw Error('Unsupported canonical video');
 const signed=await fetcher(base+'/storage/v1/object/sign/'+bucket+'/'+path,{method:'POST',headers:{...serverDatabaseHeaders(key),'content-type':'application/json'},body:JSON.stringify({expiresIn:3600}),redirect:'error',signal:AbortSignal.timeout(10000)});
 if(!signed.ok)throw Error('Video unavailable');const data=await signed.json();
 if(typeof data.signedURL!=='string'||!data.signedURL.startsWith('/object/sign/'+bucket+'/'+path+'?'))throw Error('Unexpected video URL');
 return base+'/storage/v1'+data.signedURL;
}
