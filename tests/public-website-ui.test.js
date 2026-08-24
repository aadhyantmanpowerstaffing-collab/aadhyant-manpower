const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');
const pages = {
  home: read('index.html'),
  jobs: read('jobs', 'index.html'),
  candidate: read('candidate', 'index.html'),
  employer: read('hire-manpower', 'index.html'),
  partner: read('staffing-partner', 'index.html')
};
const supportingPages = {
  candidateAssisted: read('candidate', 'register', 'index.html'),
  employerEnquiry: read('hire-manpower', 'requirement', 'index.html'),
  services: read('services', 'index.html'),
  industries: read('industries', 'index.html'),
  contact: read('contact', 'index.html'),
  companyLogin: read('company', 'login.html'),
  companyRegister: read('company', 'register.html'),
  contractorLogin: read('contractor', 'login.html'),
  contractorRegister: read('contractor', 'register.html')
};
const navigation = read('assets', 'js', 'public-navigation.js');
const jobs = read('assets', 'js', 'jobs.js');
const css = read('assets', 'css', 'public.css');
const publicProjection = read('supabase', 'migrations', '011_public_jobs_projection.sql');
const interestMigration = read('supabase', 'migrations', '012_candidate_requirement_interest.sql');

test('final primary navigation is audience-led on core public pages', () => {
  Object.values(pages).forEach((page) => {
    ['Jobs', 'For Employers', 'For Contractors', 'About', 'Contact', 'Portal Login'].forEach((label) => assert.match(page, new RegExp(`>${label}<|>${label} `)));
  });
});

test('portal selection names all three supported role workspaces', () => {
  ['Candidate Portal', 'Employer Portal', 'Contractor Portal'].forEach((label) => {
    assert.match(pages.home, new RegExp(label));
    assert.match(navigation, new RegExp(label));
  });
  assert.match(pages.home, /candidate\/portal\/login\.html/);
  assert.match(pages.home, /company\/login\.html/);
  assert.match(pages.home, /contractor\/login\.html/);
  const menuTemplate = navigation.match(/portal\.innerHTML = '([\s\S]*?)';/)[1];
  ['Candidate Portal', 'Employer Portal', 'Contractor Portal'].forEach((label) => {
    assert.equal((menuTemplate.match(new RegExp(`<strong>${label}<`, 'g')) || []).length, 1);
  });
  assert.equal((menuTemplate.match(/<a href=/g) || []).length, 3);
  assert.doesNotMatch(navigation, /portalMenu\.prepend|candidateLink/);
  assert.match(navigation, /if \(navigation\) \{/);
});

test('homepage preserves one primary candidate CTA and distinct employer and partner routes', () => {
  const hero = pages.home.match(/<section class="public-home-hero">([\s\S]*?)<\/section>/)[1];
  assert.match(hero, /href="jobs\/">Find Jobs/);
  assert.match(hero, /href="hire-manpower\/">Hire Manpower/);
  assert.match(hero, /href="staffing-partner\/">For Contractors \/ Staffing Partners/);
  assert.match(hero, /Structured from opportunity to progress/);
  assert.doesNotMatch(hero, /Three clear ways to begin|Find work|Build a workforce/);
});

test('homepage explains the three roles once and ends with one compact conversion band', () => {
  assert.equal((pages.home.match(/One platform\. Three distinct journeys\./g) || []).length, 1);
  assert.equal((pages.home.match(/class="public-journey-grid"/g) || []).length, 1);
  assert.doesNotMatch(pages.home, /public-audience-cta|Move forward through the right pathway/);
  assert.match(pages.home, /class="public-conversion-band"/);
  assert.match(pages.home, /Ready to move forward\?/);
  ['Find Jobs', 'For Employers', 'For Contractors'].forEach((label) => assert.match(pages.home, new RegExp(`public-conversion-actions[\\s\\S]*?>${label}<`)));
});

test('homepage job discovery uses the existing safe public projection', () => {
  assert.match(pages.home, /data-home-jobs-list/);
  assert.match(jobs, /rpc\('get_public_job_requirements'/);
  assert.doesNotMatch(jobs, /\.from\(['"]employer_requirements/);
  assert.match(publicProjection, /requirement_stage = 'open'/);
  assert.match(publicProjection, /requirement_visibility = 'public'/);
});

test('job browsing has meaningful filters and bounded paging', () => {
  ['keyword', 'location', 'qualification', 'experience'].forEach((name) => assert.match(pages.jobs, new RegExp(`name="${name}"`)));
  assert.match(pages.jobs, /data-jobs-load-more/);
  assert.match(jobs, /const PAGE_SIZE = 20/);
  assert.match(jobs, /p_limit: limit, p_offset: offset/);
});

test('job detail is a safe view over the same projected record', () => {
  assert.match(pages.jobs, /data-job-detail/);
  assert.match(pages.jobs, /data-detail-list/);
  assert.match(jobs, /new URLSearchParams\(window\.location\.search\)\.get\('requirement'\)/);
  assert.match(jobs, /details\.replaceChildren\(\)/);
  assert.doesNotMatch(jobs, /innerHTML|insertAdjacentHTML|document\.write/);
  assert.doesNotMatch(jobs, /company_name|contact_person|mobile|whatsapp|internal_notes/);
});

test('job cards route only to detail before the canonical account application', () => {
  ['job_role', 'job_location', 'open_positions', 'salary_min', 'salary_text', 'qualification', 'iti_trade', 'experience_requirement', 'shift_details', 'published_at'].forEach((field) => assert.match(jobs, new RegExp(field)));
  assert.match(jobs, /View Job/);
  assert.doesNotMatch(jobs, /Register Interest|candidate\/register\/\?requirement=/);
  assert.match(pages.jobs, /data-detail-apply>Apply for this Job/);
  assert.match(css, /\.public-job-detail\[hidden\] \{ display: none; \}/);
  assert.match(jobs, /candidate\/portal\/login\.html\?requirement=/);
});

test('job UI has loading, empty, error and unavailable states', () => {
  assert.match(pages.jobs, /data-jobs-loading/);
  assert.match(pages.jobs, /data-jobs-empty hidden/);
  assert.match(pages.jobs, /data-jobs-error[^>]*hidden/);
  assert.match(jobs, /This opportunity is no longer available/);
});

test('candidate journey is account based and keeps assisted registration secondary', () => {
  assert.match(pages.candidate, /one secure Candidate account/);
  assert.match(pages.candidate, /Browse Jobs/);
  assert.match(pages.candidate, /Candidate Login \/ Register/);
  assert.match(pages.candidate, /Sign in or register/);
  assert.match(pages.candidate, /Apply and follow progress/);
  assert.match(pages.candidate, /assisted registration form/);
  assert.doesNotMatch(pages.candidate, /Two supported application paths|Quick Job Interest|Express interest or apply/);
  assert.match(supportingPages.candidateAssisted, /secondary enquiry/);
  assert.match(supportingPages.candidateAssisted, /not a Candidate Portal application/);
  assert.match(interestMigration, /register_candidate_requirement_interest/);
  assert.match(interestMigration, /insert into public\.candidate_applications/);
});

test('candidate copy does not claim guaranteed hiring outcomes', () => {
  assert.match(pages.candidate, /does not guarantee contact, interview, selection, salary or placement/);
  assert.doesNotMatch(pages.candidate, /guaranteed placement|instant hiring|100% placement/i);
});

test('employer journey makes reviewed account access primary and public enquiry secondary', () => {
  assert.match(pages.employer, /Primary employer journey/);
  assert.match(pages.employer, /Create Employer Account/);
  assert.match(pages.employer, /Employer Login/);
  assert.match(pages.employer, /Employer Portal/);
  assert.match(pages.employer, /Secondary · one-time enquiry/);
  assert.match(pages.employer, /Does not create an Employer account/);
  assert.match(pages.employer, /href="requirement\/"/);
  assert.match(pages.employer, /company\/register\.html/);
  assert.match(supportingPages.employerEnquiry, /Secondary one-time enquiry/);
  assert.match(supportingPages.companyLogin, /Employer Login/);
  assert.match(supportingPages.companyRegister, /Employer Registration/);
  assert.doesNotMatch(supportingPages.companyRegister, /index\.html#employer-form|index\.html#contact/);
  assert.doesNotMatch(supportingPages.companyRegister, /Brief manpower requirement \/ notes|one-time enquiry|public manpower enquiry/);
});

test('contractor journey is distinct and review gated', () => {
  assert.match(pages.partner, /For Contractors \/ Staffing Partners/);
  assert.match(pages.partner, /Registration begins a review—not an automatic activation/);
  assert.match(pages.partner, /Vacancies remain review-gated/);
  assert.match(pages.partner, /does not promise assignments, business, revenue or candidate outcomes/);
  assert.match(pages.partner, /contractor\/register\.html/);
  assert.match(pages.partner, /contractor\/login\.html/);
  assert.match(supportingPages.contractorLogin, /Contractor Portal Login/);
  assert.match(supportingPages.contractorRegister, /Register as a Staffing Partner/);
});

test('homepage uses defensible trust language and real business identity', () => {
  assert.match(pages.home, /Approved public opportunities/);
  assert.match(pages.home, /Reviewed workspace access/);
  assert.match(pages.home, /Clear process\. Clear expectations\./);
  assert.doesNotMatch(pages.home, /Clear process\. Defensible expectations\./);
  assert.match(pages.home, /GSTIN 24ACNFA4445J1Z9/);
  assert.doesNotMatch(pages.home, /verified candidates|guaranteed|AI-powered|instant matching/i);
});

test('footer includes all audiences, contact pathways and complete legal navigation', () => {
  ['Candidates / Jobs', 'Employers', 'Contractors', 'Aadhyant', 'Legal', 'Privacy Policy', 'Terms of Use', 'Data Deletion'].forEach((label) => assert.match(pages.home, new RegExp(label)));
  Object.values(pages).forEach((page) => {
    assert.match(page, /class="public-footer-contact"/);
    assert.match(page, /class="footer-column public-footer-meta"/);
    assert.equal((page.match(/class="public-legal-links"/g) || []).length, 1);
    const footer = page.match(/<footer class="site-footer public-footer"([\s\S]*?)<\/footer>/)[0];
    assert.match(footer, /href="mailto:aadhyantmanpowerstaffing@gmail\.com">aadhyantmanpowerstaffing@gmail\.com<\/a>/);
    assert.doesNotMatch(footer, />Email Aadhyant<\/a>/);
    assert.doesNotMatch(footer, /Candidate Options|Register Interest|Submit Requirement|Join the Network|Partner Registration|Submit Vacancy/);
  });
  assert.match(navigation, /Data Deletion/);
});

test('supporting public pages converge on the canonical role entry points', () => {
  const contactMain = supportingPages.contact.match(/<main[\s\S]*?<\/main>/)[0];
  assert.match(supportingPages.services, /Create Employer Account/);
  assert.doesNotMatch(supportingPages.services, /hire-manpower\/requirement/);
  assert.doesNotMatch(supportingPages.industries, /hire-manpower\/requirement/);
  assert.match(contactMain, /<h3>Candidate<\/h3>[\s\S]*?href="\.\.\/jobs\/">Browse Jobs/);
  assert.match(contactMain, /<h3>Employer<\/h3>[\s\S]*?href="\.\.\/hire-manpower\/">For Employers/);
  assert.match(contactMain, /<h3>Contractor \/ Staffing Partner<\/h3>[\s\S]*?href="\.\.\/staffing-partner\/">For Contractors/);
  assert.doesNotMatch(contactMain, /<h3>Company Account<\/h3>|Candidate Registration|Submit Requirement/);
});

test('homepage polish keeps desktop rhythm compact without changing mobile breakpoints', () => {
  assert.match(css, /public-home-page \.public-home-hero__grid \{ min-height: 30rem;/);
  assert.match(css, /public-home-page \.public-home-section \{ padding-block: clamp\(3\.25rem, 4\.5vw, 4\.25rem\);/);
  assert.match(css, /public-home-page \.public-jobs-empty \{ margin-top: 1\.25rem; padding: 2\.25rem;/);
  assert.match(css, /public-home-conversion \{ padding-block: 3\.25rem;/);
  assert.doesNotMatch(css, /public-audience-cta/);
  assert.match(css, /@media \(min-width: 821px\)/);
  assert.match(css, /@media \(max-width: 820px\)/);
  assert.match(css, /@media \(max-width: 620px\)/);
});

test('core public pages have unique metadata and canonical URLs', () => {
  Object.values(pages).forEach((page) => {
    assert.match(page, /<title>[^<]+<\/title>/);
    assert.match(page, /<meta name="description" content="[^"]+"/);
    assert.match(page, /<link rel="canonical" href="https:\/\/aadhyantmanpower\.in\//);
    assert.equal((page.match(/<h1[ >]/g) || []).length, 1);
  });
});

test('organization structured data uses only published business information', () => {
  assert.match(pages.home, /"@type":"Organization"/);
  assert.match(pages.home, /aadhyantmanpowerstaffing@gmail\.com/);
  assert.match(pages.home, /\+91-95867-85800/);
  assert.doesNotMatch(pages.home, /"@type":"JobPosting"/);
});

test('mobile navigation and touch targets cover tablet and 412px journeys', () => {
  assert.match(css, /@media \(max-width: 1180px\)/);
  assert.match(css, /@media \(max-width: 1080px\)/);
  assert.match(css, /@media \(max-width: 820px\)/);
  assert.match(css, /@media \(max-width: 620px\)/);
  assert.match(css, /min-height: 3rem/);
  assert.match(navigation, /aria-expanded/);
  assert.match(navigation, /event\.key !== 'Escape'/);
});

test('accessibility foundation keeps skip links, live states and reduced motion', () => {
  Object.values(pages).forEach((page) => assert.match(page, /class="skip-link" href="#main-content"/));
  assert.match(pages.jobs, /aria-live="polite"/);
  assert.match(pages.jobs, /role="search"/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(read('style.css'), /:focus-visible/);
});

test('public job formatter handles salary and facilities without fabricated values', () => {
  const context = {
    window: {},
    document: { readyState: 'loading', addEventListener() {} },
    Intl,
    URLSearchParams,
    console
  };
  vm.runInNewContext(jobs, context);
  const api = context.window.aadhyantPublicJobs;
  assert.equal(api.formatSalary({ salary_min: 15000, salary_max: 18000 }), '₹15,000 – ₹18,000');
  assert.equal(api.formatSalary({ salary_text: 'As discussed' }), 'As discussed');
  assert.deepEqual([...api.facilities({ canteen: 'Yes', transport: 'No', accommodation: 'Yes' })], ['Canteen', 'Accommodation']);
});

test('public product layer remains free of backend, Admin and messaging mutations', () => {
  const combined = Object.values(pages).join('\n') + jobs + navigation + css;
  assert.doesNotMatch(combined, /admin_manage_|admin_create_|whatsapp-webhook|graph\.facebook|service_role/i);
  assert.doesNotMatch(jobs, /insert\(|update\(|delete\(/);
});
