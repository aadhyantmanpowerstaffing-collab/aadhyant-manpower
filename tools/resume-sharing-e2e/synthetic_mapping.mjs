// Pure source-faithful SQL seed generator; Auth IDs must come from genuine signup in the runner.
const uid=n=>'e1000000-0000-0000-0000-'+String(n).padStart(12,'0');
export function buildSyntheticMapping(actors) {
 const q=v=>"'"+String(v).replaceAll("'","''")+"'";
 const sql=["BEGIN; DO $$ BEGIN IF current_setting('aadhyant.resume_fixture',true) IS DISTINCT FROM 'local-only' THEN RAISE EXCEPTION 'Local fixture only'; END IF; END $$;"];
 for(const [name,a] of Object.entries(actors)){
  if(name==='admin'){sql.push(`INSERT INTO public.staff_profiles(user_id,display_name) VALUES(${q(a.id)},'Synthetic Admin'); INSERT INTO public.staff_roles(user_id,role) VALUES(${q(a.id)},'admin');`);continue;}
  const type=name.includes('Candidate')||name==='candidate'?'candidate':name==='contractor'?'contractor':'company';
  sql.push(`INSERT INTO public.platform_users(user_id,account_type,display_name,email,account_status) VALUES(${q(a.id)},${q(type)},'Synthetic actor',${q(a.email)},'active');`);
 }
 for(const [id,u,mobile] of [[uid(31),actors.candidate.id,'9876549711'],[uid(32),actors.otherCandidate.id,'9876549712']])sql.push(`INSERT INTO public.candidates(id,user_id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,interview_available,consent,profile_status,profile_completion_status) VALUES(${q(id)},${q(u)},'Synthetic Candidate',25,'Male',${q(mobile)},'Sanand','Ahmedabad','Gujarat','ITI','Fresher','Yes',true,'active','complete');`);
 for(const [n,id,title] of [['company',uid(21),'Synthetic Company A'],['otherCompany',uid(22),'Synthetic Company B']])sql.push(`INSERT INTO public.companies(id,legal_name,account_status) VALUES(${q(id)},${q(title)},'active'); INSERT INTO public.company_users(company_id,user_id,role,status) VALUES(${q(id)},${q(actors[n].id)},'owner','active');`);
 sql.push(`INSERT INTO public.contractors(id,agency_name,account_status) VALUES(${q(uid(23))},'Synthetic Contractor','active'); INSERT INTO public.contractor_users(contractor_id,user_id,role,status) VALUES(${q(uid(23))},${q(actors.contractor.id)},'owner','active');`);
 for(const [req,company,code,app] of [[uid(51),uid(21),'E2E-SHARE-1',uid(61)],[uid(52),null,'E2E-SHARE-2',uid(62)]]){sql.push(`INSERT INTO public.employer_requirements(id,company_id,company_name,contact_person,mobile,company_location,job_role,required_headcount,consent,requirement_code) VALUES(${q(req)},${company?q(company):'NULL'},'Synthetic','Synthetic','9876549713','Sanand','Operator',2,true,${q(code)}); INSERT INTO public.candidate_applications(id,candidate_id,requirement_id) VALUES(${q(app)},${q(uid(31))},${q(req)});`);}
 sql.push(`INSERT INTO public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,origin_type,submission_status,assignment_status) VALUES(${q(uid(52))},${q(uid(23))},2,'contractor_submission','approved','active'); COMMIT; NOTIFY pgrst,'reload schema'; SELECT 'RESUME_AUTH_MAPPING=PASS';`);
 return sql.join('\n')+'\n';
}
