import { readFile, writeFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
const [directory,id,baseText]=process.argv.slice(2),base=Number(baseText);
if(!/^resume-e2e-[a-f0-9]{12}$/.test(id)||!Number.isInteger(base)||base<20000||base>64000)throw new Error('EXPLICIT_LOCAL_CONFIG_REQUIRED');
const path=resolve(directory,'supabase/config.toml');let text=await readFile(path,'utf8');
function setting(section,key,value){const sectionPattern=section.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');const re=new RegExp('(^\\['+sectionPattern+'\\]\\r?\\n)([\\s\\S]*?)(?=^\\[|$(?![\\s\\S]))','m');
 const match=text.match(re);if(!match)throw new Error('CONFIG_SECTION_MISSING:'+section);
 const k=new RegExp('^'+key+'\\s*=.*$','m');if(!k.test(match[2]))throw new Error('CONFIG_KEY_MISSING:'+section+'.'+key);
 text=text.replace(re,()=>match[1]+match[2].replace(k,key+' = '+value));}
if(!/^project_id\s*=/m.test(text))throw new Error('PROJECT_ID_MISSING');
text=text.replace(/^project_id\s*=.*$/m,'project_id = "'+id+'"');
for(const [section,key,offset] of [['api','port',0],['db','port',1],['db','shadow_port',-1],['studio','port',2],['local_smtp','port',3],['analytics','port',6],['db.pooler','port',8],['edge_runtime','inspector_port',7]])setting(section,key,String(base+offset));
setting('db','major_version','17');setting('db.migrations','enabled','false');setting('db.seed','enabled','false');setting('db.seed','sql_paths','[]');
setting('analytics','enabled','false');setting('edge_runtime','enabled','false');
setting('auth','site_url','"http://127.0.0.1:'+(base+10)+'"');
setting('auth','additional_redirect_urls','["http://127.0.0.1:'+(base+10)+'/**"]');
setting('auth.email','enable_confirmations','false');
if(/^\s*\[storage\.buckets\./m.test(text))throw new Error('DISPOSABLE_BUCKET_INITIALIZATION_FORBIDDEN');
try{if((await readdir(resolve(directory,'supabase/migrations'))).length)throw new Error('MIGRATIONS_MUST_BE_EMPTY');}catch(e){if(e.code!=='ENOENT')throw e;}
await writeFile(path,text);console.log('DISPOSABLE_LOCAL_CONFIG=PASS');
