// Deployed to both former WhatsApp endpoints with verify_jwt=true.
// No database access or provider call remains.
Deno.serve(() => new Response(JSON.stringify({error:"WhatsApp service removed"}),{status:410,headers:{"content-type":"application/json","cache-control":"no-store"}}));
