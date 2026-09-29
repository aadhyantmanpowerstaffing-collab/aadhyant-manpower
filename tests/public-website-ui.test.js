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

test('runtime-injected shared footer uses the published email as its visible mailto label', () => {
  const footerTemplate = navigation.match(/footer\.innerHTML = '([\s\S]*?)';/)[1];
  assert.equal((footerTemplate.match(/href="mailto:aadhyantmanpowerstaffing@gmail\.com">aadhyantmanpowerstaffing@gmail\.com<\/a>/g) || []).length, 1);
  assert.doesNotMatch(footerTemplate, />Email Aadhyant<\/a>/);
  assert.match(footerTemplate, /href="tel:\+919586785800">\+91 95867 85800<\/a>/);
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

// Execute the actual public-page handlers with presentation-only projected rows.
// This does not simulate authentication or establish a backend E2E result.
async function publicJobHistoryFixture(initialSearch = '') {
  const all = (node) => node.children.flatMap((child) => [child, ...all(child)]);
  const matches = (node, selector) => {
    const last = selector.split(' ').at(-1);
    if (last.startsWith('.')) return node.className.split(' ').includes(last.slice(1));
    if (last.startsWith('[data-')) {
      const key = last.slice(6, -1).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      return key in node.dataset;
    }
    return node.tagName === last;
  };
  class Element {
    constructor(tag = 'div') { this.tagName = tag; this.children = []; this.dataset = {}; this.className = ''; this.textContent = ''; this.hidden = false; this.handlers = {}; }
    append(...nodes) { this.children.push(...nodes); }
    replaceChildren(...nodes) { this.children = nodes; }
    querySelectorAll(selector) { return all(this).filter((node) => matches(node, selector)); }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    setAttribute() {}
    addEventListener(name, handler) { this.handlers[name] = handler; }
    scrollIntoView() {}
    click() { return this.handlers.click?.({ preventDefault() {} }); }
  }
  const selectors = ['job-filters', 'jobs-list', 'jobs-loading', 'jobs-empty', 'jobs-error', 'jobs-count', 'jobs-load-more', 'jobs-view', 'job-detail'];
  const nodes = Object.fromEntries(selectors.map((name) => [`[data-${name}]`, new Element()]));
  const form = nodes['[data-job-filters]'];
  form.values = { keyword: '', location: '', qualification: '', experience: '' };
  const detail = nodes['[data-job-detail]']; detail.hidden = true;
  ['code', 'title', 'department', 'posted', 'location', 'openings', 'list', 'apply'].forEach((name) => {
    const node = new Element(); node.dataset[`detail${name[0].toUpperCase()}${name.slice(1)}`] = ''; detail.append(node);
  });
  nodes['[data-jobs-error]'].append(new Element('h3'), new Element('p'));
  const document = { readyState: 'complete', title: 'Browse jobs', createElement: (tag) => new Element(tag), querySelector: (selector) => nodes[selector] || null };
  const calls = [], handlers = {}, location = { search: initialSearch, reloads: 0, reload() { this.reloads += 1; } };
  const records = [{ requirement_code: 'TEST-A', job_role: 'Associate', job_location: 'Sanand' }, { requirement_code: 'TEST-B', job_role: 'Helper', job_location: 'Ahmedabad' }];
  const window = { location, addEventListener(name, handler) { handlers[name] = handler; }, history: { pushState(_state, _title, url) { location.search = url; } },
    aadhyantSupabase: { isConfigured: true, client: { async rpc(name, args) { calls.push({ name, args }); return { data: records }; } } } };
  vm.runInNewContext(jobs, { window, document, Intl, URLSearchParams, console, requestAnimationFrame: (fn) => fn(), FormData: class { constructor(element) { return Object.entries(element.values); } } });
  await new Promise(setImmediate);
  return { nodes, document, calls, location, form, detail,
    cards: () => nodes['[data-jobs-list]'].children,
    pop(search) { location.search = search; handlers.popstate?.(); },
    open(index) { nodes['[data-jobs-list]'].children[index].querySelector('.public-button--primary').click(); } };
}

test('public job Back restores the filtered listing and Forward restores the selected Apply target', async () => {
  const x = await publicJobHistoryFixture();
  x.form.values.keyword = 'Associate'; x.form.handlers.input();
  assert.deepEqual(x.cards().map((card) => card.hidden), [false, true]);
  x.open(0);
  assert.equal(x.nodes['[data-jobs-view]'].hidden, true);
  x.pop('');
  assert.equal(x.nodes['[data-jobs-view]'].hidden, false);
  assert.equal(x.detail.hidden, true);
  assert.equal(x.document.title, 'Browse jobs');
  assert.equal(x.form.values.keyword, 'Associate');
  assert.equal(x.nodes['[data-jobs-count]'].textContent, '1 opportunity shown');
  assert.deepEqual(x.cards().map((card) => card.hidden), [false, true]);
  x.pop('?requirement=TEST-A');
  assert.equal(x.detail.hidden, false);
  assert.equal(x.document.title, 'Associate | Aadhyant Jobs');
  assert.equal(x.detail.querySelector('[data-detail-apply]').href, '../candidate/portal/login.html?requirement=TEST-A');
  assert.equal(x.calls.length, 1);
  assert.equal(x.calls[0].name, 'get_public_job_requirements');
});

test('history selects each cached job without leaving a stale title or Apply link', async () => {
  const x = await publicJobHistoryFixture('?requirement=TEST-A');
  x.pop('?requirement=test-b');
  assert.equal(x.detail.querySelector('[data-detail-code]').textContent, 'TEST-B');
  assert.equal(x.document.title, 'Helper | Aadhyant Jobs');
  assert.equal(x.detail.querySelector('[data-detail-apply]').href, '../candidate/portal/login.html?requirement=TEST-B');
  x.pop('');
  assert.equal(x.detail.hidden, true);
  assert.equal(x.nodes['[data-jobs-count]'].textContent, '2 opportunities shown');
  assert.equal(x.calls.length, 1);
});

test('an uncached history target reloads through the existing bounded lookup', async () => {
  const x = await publicJobHistoryFixture();
  x.open(0); x.pop('?requirement=NOT-CACHED');
  assert.equal(x.location.reloads, 1);
  assert.equal(x.location.search, '?requirement=NOT-CACHED');
  assert.equal(x.calls.length, 1);
});
