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
});

test('homepage preserves one primary candidate CTA and distinct employer and partner routes', () => {
  const hero = pages.home.match(/<section class="public-home-hero">([\s\S]*?)<\/section>/)[1];
  assert.match(hero, /href="jobs\/">Find Jobs/);
  assert.match(hero, /href="hire-manpower\/">Hire Manpower/);
  assert.match(hero, /href="staffing-partner\/">Join as a staffing partner/);
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

test('job cards render useful safe fields and route to detail and interest', () => {
  ['job_role', 'job_location', 'open_positions', 'salary_min', 'salary_text', 'qualification', 'iti_trade', 'experience_requirement', 'shift_details', 'published_at'].forEach((field) => assert.match(jobs, new RegExp(field)));
  assert.match(jobs, /Register Interest/);
  assert.match(jobs, /candidate\/register\/\?requirement=/);
  assert.match(jobs, /View Job/);
});

test('job UI has loading, empty, error and unavailable states', () => {
  assert.match(pages.jobs, /data-jobs-loading/);
  assert.match(pages.jobs, /data-jobs-empty hidden/);
  assert.match(pages.jobs, /data-jobs-error[^>]*hidden/);
  assert.match(jobs, /This opportunity is no longer available/);
});

test('candidate journey distinguishes quick interest from Candidate Portal application', () => {
  assert.match(pages.candidate, /Two supported application paths/);
  assert.match(pages.candidate, /Quick Job Interest/);
  assert.match(pages.candidate, /Candidate Portal/);
  assert.match(pages.candidate, /No Aadhaar requested in the public form/);
  assert.match(interestMigration, /register_candidate_requirement_interest/);
  assert.match(interestMigration, /insert into public\.candidate_applications/);
});

test('candidate copy does not claim guaranteed hiring outcomes', () => {
  assert.match(pages.candidate, /does not guarantee contact, interview, selection, salary or placement/);
  assert.doesNotMatch(pages.candidate, /guaranteed placement|instant hiring|100% placement/i);
});

test('employer journey exposes quick requirement and reviewed Employer Portal separately', () => {
  assert.match(pages.employer, /Quick Requirement/);
  assert.match(pages.employer, /No account required/);
  assert.match(pages.employer, /Employer Portal/);
  assert.match(pages.employer, /Registration and Admin approval required/);
  assert.match(pages.employer, /href="requirement\/"/);
  assert.match(pages.employer, /company\/register\.html/);
});

test('contractor journey is distinct and review gated', () => {
  assert.match(pages.partner, /For Contractors &amp; Staffing Partners/);
  assert.match(pages.partner, /Registration begins a review—not an automatic activation/);
  assert.match(pages.partner, /Vacancies remain review-gated/);
  assert.match(pages.partner, /does not promise assignments, business, revenue or candidate outcomes/);
  assert.match(pages.partner, /contractor\/register\.html/);
  assert.match(pages.partner, /contractor\/login\.html/);
});

test('homepage uses defensible trust language and real business identity', () => {
  assert.match(pages.home, /Approved public opportunities/);
  assert.match(pages.home, /Reviewed partner access/);
  assert.match(pages.home, /GSTIN 24ACNFA4445J1Z9/);
  assert.doesNotMatch(pages.home, /verified candidates|guaranteed|AI-powered|instant matching/i);
});

test('footer includes all audiences, contact pathways and complete legal navigation', () => {
  ['Jobs &amp; Candidates', 'Employers', 'Contractors', 'Privacy Policy', 'Terms of Use', 'Data Deletion'].forEach((label) => assert.match(pages.home, new RegExp(label)));
  assert.match(navigation, /Data Deletion/);
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
