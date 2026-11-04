(function(){
 'use strict';
 function create(client,createUser=false,now=()=>Date.now()){
  let phone='',verified=false,nextRequest=0,busy=false,generation=0;
  const fail=()=>new Error('WhatsApp verification could not be confirmed. Please try again after a minute.');
  return {
   async request(number){
    if(busy||now()<nextRequest)throw new Error('Please wait one minute before requesting another code.');
    const normalized=String(number).replace(/[\s()-]/g,'');
    const candidate=/^[6-9]\d{9}$/.test(normalized)?'+91'+normalized:normalized;
    if(!/^\+91[6-9]\d{9}$/.test(candidate))throw new Error('Enter a valid 10-digit Indian mobile number.');
    const current=generation;busy=true;verified=false;phone='';
    try{
     const ready=await client.rpc('get_candidate_phone_auth_status',{});
     if(ready.error||ready.data!==true)throw new Error('WhatsApp OTP login is not activated yet.');
     nextRequest=now()+60000;
     // Supabase's SMS hook routes this OTP to WhatsApp. Do not use channel:
     // whatsapp here: that option is specific to the Twilio built-in provider.
     const result=await client.auth.signInWithOtp({phone:candidate,options:{shouldCreateUser:createUser}});
     if(result.error||current!==generation)throw fail();phone=candidate;return phone;
    }finally{busy=false;}
   },
   async verify(code){
    if(busy||!phone||!/^\d{6}$/.test(String(code)))throw new Error('Enter the six-digit code from WhatsApp.');
    const current=generation;busy=true;verified=false;
    try{const result=await client.auth.verifyOtp({phone,token:String(code),type:'sms'});
     if(current!==generation||result.error||!result.data?.session||!result.data?.user?.phone_confirmed_at||'+'+String(result.data.user.phone).replace(/^\+/,'')!==phone)throw new Error('The code is invalid or expired. Request a new code if needed.');
     verified=true;return result.data.user;
    }finally{busy=false;}
   },
   async clear(signOut=false){generation++;phone='';verified=false;if(signOut){const result=await client.auth.signOut();if(result.error)throw new Error('Could not clear the previous WhatsApp sign-in. Reload this page before changing numbers.');}},get verified(){return verified;}
  };
 }
 function mount(root,client,onVerified,createUser=false){
  const flow=create(client,createUser),phone=root.querySelector('[data-phone-number]'),code=root.querySelector('[data-phone-code]'),request=root.querySelector('[data-phone-request]'),verify=root.querySelector('[data-phone-verify]'),status=root.querySelector('[data-phone-status]');
  const report=(text)=>{status.textContent=text;};
  const change=root.querySelector('[data-phone-change]');
  change?.addEventListener('click',async()=>{try{await flow.clear(flow.verified);phone.disabled=false;code.value='';code.hidden=true;verify.hidden=true;report('Enter your WhatsApp mobile number.');phone.focus();}catch(_){report('Could not safely clear the previous sign-in. Reload this page before changing numbers.');}});
  request.addEventListener('click',async()=>{request.disabled=true;verify.disabled=true;code.value='';try{await flow.request(phone.value);phone.disabled=true;code.hidden=false;verify.hidden=false;verify.disabled=false;report('Enter the code sent to your WhatsApp number.');code.focus();}catch(error){report(error.message);}finally{request.disabled=false;}});
  verify.addEventListener('click',async()=>{verify.disabled=true;try{await flow.verify(code.value.trim());code.value='';code.hidden=true;verify.hidden=true;report('WhatsApp number verified.');await onVerified();}catch(error){report(error.message);verify.disabled=false;}});
  client.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){flow.clear();code.value='';phone.disabled=false;report('Sign-in ended. Verify your WhatsApp number again.');}});
  addEventListener('pagehide',()=>{flow.clear();code.value='';});
  return flow;
 }
 window.AadhyantCandidatePhoneAuth={create,mount};
 const login=document.querySelector('[data-phone-login]'),client=window.aadhyantSupabase?.client;
 if(login&&client)client.rpc('get_candidate_phone_auth_status',{}).then(result=>{
  if(result.error||result.data!==true)return;
  login.hidden=false;
  const emailLogin=document.querySelector('[data-email-login]');if(emailLogin)emailLogin.open=false;
  mount(login,client,async()=>{
   const context=await client.rpc('get_candidate_portal_context',{});
   if(context.error||!Array.isArray(context.data)||context.data.length!==1)throw new Error('Your number is verified, but your Candidate account needs review. Contact Aadhyant.');
   location.replace('index.html');
  },false);
 }).catch(()=>{});
})();
