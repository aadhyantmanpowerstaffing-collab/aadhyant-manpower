const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const read=(file)=>fs.readFileSync(file,'utf8');
const companyHtml=read('company/requirements.html'),company=read('company/batch2-vacancies.js'),contractorHtml=read('contractor/vacancies.html'),contractor=read('contractor/batch2-vacancies.js'),candidateHtml=read('candidate/portal/jobs.html'),candidate=read('candidate/portal/batch2-jobs.js'),admin=read('admin/vacancy-review.js'),operations=read('admin/recruitment-operations.js'),options=read('assets/js/registration-options.js');
test('Company vacancy creation uses the M043 extended RPC contract and a one-step submit UX',()=>{['p_iti_trade','p_expected_joining_date','create_and_submit','resubmit','Submit Vacancy','Save Draft','Vacancy submitted successfully. It is pending Admin approval and is not visible to candidates yet.'].forEach(token=>assert.match(`${companyHtml}\n${company}`,new RegExp(token)));assert.doesNotMatch(company,/\.from\s*\(/);assert.match(company,/list_company_portal_vacancy_reviews/);});
test('Contractor vacancy creation is sectioned, uses shared controls, and keeps Draft secondary',()=>{['A. Job Details','B. Candidate Requirements','C. Salary &amp; Work Conditions','D. Structured Salary / Wage','E. Facilities','F. Interview / Joining','Minimum CTC','Maximum CTC','data-option-set="qualifications"','data-option-set="vacancyFacilities"','Submit Vacancy','Save Draft'].forEach(token=>assert.match(contractorHtml,new RegExp(token)));['create_and_submit','resubmit','correction_required','Vacancy submitted successfully. It is pending Admin approval and is not visible to candidates yet.'].forEach(token=>assert.match(contractor,new RegExp(token)));assert.doesNotMatch(contractor,/\.from\s*\(/);});
test('Company and Contractor vacancy lists map the approved review vocabulary and show detail feedback',()=>{['Draft','Pending Review','Correction Required','Published / Open','Rejected','Closed'].forEach(token=>{assert.match(company,new RegExp(token));assert.match(contractor,new RegExp(token));});assert.match(company,/review_feedback/);assert.match(contractor,/review_feedback/);assert.match(companyHtml,/Applications.*Interviews.*Joined/s);assert.match(contractorHtml,/Applications.*Interviews.*Joined/s);});
test('Admin uses the unified canonical review/detail RPCs and requires a reason for correction or rejection',()=>{['admin_list_vacancy_reviews','admin_get_vacancy_review_detail','admin_approve_and_publish_vacancy','admin_request_vacancy_correction','admin_reject_vacancy','Approve & Publish','Request Correction','Reject','Full Vacancy Details','Salary / Wage Details','Review / Lifecycle','Recruitment Progress'].forEach(token=>assert.match(admin,new RegExp(token)));assert.match(admin,/!reason\.value\.trim\(\)/);assert.doesNotMatch(admin,/\.from\s*\(|set_company_requirement_stage|Start Review/);});
test('Match Candidates mirrors the complete server eligibility predicate rather than raw stage alone',()=>{assert.match(operations,/normalized_review_status === 'approved'/);assert.match(operations,/requirement_stage === 'open'/);assert.match(operations,/requirement_visibility === 'public'/);assert.match(operations,/Number\(requirement\?\.remaining_positions\) > 0/);});
test('Candidate opportunities use only the approved projection and prevent duplicate Apply clicks',()=>{['list_candidate_job_opportunities','apply_candidate_job','already_applied','Apply','Applied','Salary Summary','Salary Breakup','Company / Worksite','Canteen','Transport','Accommodation'].forEach(token=>assert.match(`${candidateHtml}\n${candidate}`,new RegExp(token)));assert.match(candidate,/apply\.disabled = true/);assert.doesNotMatch(candidate,/\.from\s*\(/);});
test('shared controlled vacancy options have one source of truth',()=>{['vacancyExperience','vacancyGender','vacancyShifts','vacancyFacilities'].forEach(token=>assert.match(options,new RegExp(token)));assert.match(companyHtml,/registration-options\.js/);assert.match(contractorHtml,/registration-options\.js/);});

// Presentation-only fixture: execute the real review module and its event handlers.
// Synthetic read responses do not represent an Auth/backend E2E test.
function reviewDialogFixture(reviewStatus){
  const vm=require('node:vm'),calls=[];
  const descendants=node=>node.children.flatMap(child=>[child,...descendants(child)]);
  const matches=(node,selector)=>selector.split(',').some(part=>{
    const s=part.trim();if(s.startsWith('.'))return node.className.split(' ').includes(s.slice(1));
    const a=s.match(/^\[data-([\w-]+)(?:="([^"]*)")?\]$/);
    if(a){const key=a[1].replace(/-([a-z])/g,(_,c)=>c.toUpperCase());return key in node.dataset&&(a[2]===undefined||node.dataset[key]===a[2]);}
    return node.tagName===s.toUpperCase();
  });
  class Element {
    constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.dataset={};this.attributes={};this.listeners={};this.className='';this.value='';this.textContent='';this.classList={add(){}};}
    append(...nodes){nodes.forEach(node=>{node.parent=this;this.children.push(node);});}
    insertBefore(node,reference){node.parent=this;const at=this.children.indexOf(reference);this.children.splice(at<0?this.children.length:at,0,node);}
    replaceChildren(...nodes){this.children=[];this.append(...nodes);}
    setAttribute(name,value){this.attributes[name]=value;}
    querySelectorAll(selector){return descendants(this).filter(node=>matches(node,selector));}
    querySelector(selector){return this.querySelectorAll(selector)[0]||null;}
    addEventListener(name,handler){this.listeners[name]=handler;}
    showModal(){this.open=true;}close(){this.open=false;}
    remove(){if(this.parent)this.parent.children=this.parent.children.filter(node=>node!==this);this.parent=null;}
    focus(){}click(){if(!this.disabled)return this.onclick?.();}
  }
  const body=new Element('body'),group=new Element('nav'),main=new Element('main'),staff=new Element('section');
  group.dataset.navGroup='recruitment';main.className='admin-main';staff.dataset.panel='staff';main.append(staff);body.append(group,main);
  const document={body,createElement:tag=>new Element(tag),querySelector:s=>body.querySelector(s),querySelectorAll:s=>body.querySelectorAll(s)};
  const window={};vm.runInNewContext(admin,{window,document});
  const client={rpc:async(name,args)=>{calls.push({name,args});
    if(name==='admin_list_vacancy_reviews')return {data:[{requirement_id:'synthetic-vacancy',requirement_code:'TEST-CLOSE',job_role:'Synthetic',normalized_review_status:reviewStatus}]};
    if(name==='admin_get_vacancy_review_detail')return {data:{vacancy:{requirement_code:'TEST-CLOSE',job_role:'Synthetic'},review:{normalized_status:reviewStatus},lifecycle:{requirement_stage:'open',requirement_visibility:'public'},progress:{joined:0}}};
    throw Error('Unexpected mutation RPC: '+name);
  }};
  return {body,calls,async initialize(){await window.aadhyantVacancyReview.initialize({client,authorization:{bootstrap_admin:true}});await group.querySelector('button').click();},
    async open(){await body.querySelectorAll('button').find(node=>node.textContent==='View & Review').click();return body.querySelector('dialog');}};
}
for(const control of ['top X','bottom Close','Escape'])test(`Admin review ${control} dismisses the dialog without a review mutation`,async()=>{
  for(const status of ['approved','pending_review']){
    const x=reviewDialogFixture(status);await x.initialize();const dialog=await x.open();assert.equal(dialog.open,true);
    const callsBefore=x.calls.length;
    if(control==='top X')await dialog.querySelectorAll('button').find(node=>node.attributes['aria-label']==='Close vacancy review').click();
    else if(control==='bottom Close')await dialog.querySelectorAll('button').find(node=>node.textContent==='Close').click();
    else {let prevented=false;dialog.listeners.cancel({preventDefault(){prevented=true;}});assert.equal(prevented,true);}
    assert.equal(dialog.open,false);assert.equal(x.body.querySelector('dialog'),null);assert.equal(x.calls.length,callsBefore);
    assert.equal((await x.open()).open,true);assert.equal(x.body.querySelectorAll('dialog').length,1);
    assert.ok(x.calls.every(call=>['admin_list_vacancy_reviews','admin_get_vacancy_review_detail'].includes(call.name)));
  }
});
