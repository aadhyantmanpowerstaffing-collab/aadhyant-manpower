import {handleAuthHook} from './handler.ts';
import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
const get=(name:string)=>(globalThis as any).Deno?.env.get(name)||'';
const rpc=async(name:string,args:Record<string,unknown>)=>{
 const result=await fetch(get('SUPABASE_URL')+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(1000)});
 if(!result.ok)throw Error('Auth operation unavailable');return result.json();
};
const handler={fetch:(req:Request)=>handleAuthHook(req,get,rpc)};
export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
