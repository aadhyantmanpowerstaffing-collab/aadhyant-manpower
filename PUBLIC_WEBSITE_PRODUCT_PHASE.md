# Public Website Final Structure and Premium Product Design Phase

Status: public product implementation, local regression validation, and isolated browser QA complete on `web-platform-development`. The phase changes the public presentation and public Jobs browser only. It does not change the validated Admin product, portals, schema, Edge functions, WhatsApp architecture, Meta configuration, Auth state, or production runtime.

## Audit

The phase began from clean tracked HEAD `c698bc28feded24f74220cf3a6ab47b38ab650b5`, even with `origin/web-platform-development`; only expected ignored/local runtime material and `supabase/.temp/` were present. The public reconstruction history, current routes, portal and authentication flows, legal pages, business identity, schema, milestones, safe public migrations, and all frontend tests were inspected before source changes.

The existing public foundation was truthful and every local link resolved, but it had material product gaps:

- Primary navigation was organized around legacy About / Services / Industries labels instead of Candidate, Employer, and Contractor intent.
- Candidate login was absent from most portal selectors.
- The Candidate landing page emphasized a no-login registration flow and described it as the current journey even though the W6 Candidate Portal is now supported.
- Quick interest and authenticated Candidate application were not explained as distinct supported paths.
- Jobs provided a safe list but no structured job-detail state, bounded pagination, or homepage discovery.
- The homepage did not expose current safe public opportunities and retained a large hidden duplicate of the original page.
- Footers omitted Data Deletion on most pages and depended on partial JavaScript enhancement for legal navigation.
- Loading, empty, error, and unavailable states existed in Jobs but the broader route and conversion behavior had no dedicated public test suite.
- The two established stylesheets contained a useful design foundation but also overlapping legacy rules that required a clear final public layer.
- Titles, descriptions, canonical URLs, semantic headings, legal content, verified phone/email/location, and GSTIN were already legitimate and reusable.
- The Company, Contractor, and Candidate portals were established role-scoped products and did not require a public-phase rewrite.

The pre-change frontend baseline passed 155/155.

## Final public information architecture

| Audience / area | Public route | Supported destination |
| --- | --- | --- |
| Home | `/` | Audience selection, live safe Jobs discovery, trust and conversion paths |
| Jobs | `/jobs/` | Browse, filter, bounded paging, query-addressable detail, quick interest |
| Candidates | `/candidate/` | Quick interest and Candidate Portal paths explained separately |
| Candidate quick interest | `/candidate/register/?requirement=<code>` | Existing public registration and `register_candidate_requirement_interest` |
| Candidate Portal | `/candidate/portal/login.html` | Existing profile, jobs, applications, interviews, joinings and documents |
| Employers | `/hire-manpower/` | Staffing solutions and quick-versus-portal choice |
| Quick requirement | `/hire-manpower/requirement/` | Existing public Employer requirement workflow |
| Employer Portal | `/company/login.html` | Existing approved Company workspace |
| Contractors | `/staffing-partner/` | Reviewed partner proposition and portal boundaries |
| Partner registration | `/contractor/register.html` | Existing Contractor onboarding flow |
| Contractor Portal / vacancies | `/contractor/login.html`, `/contractor/vacancies.html` | Existing approved partner workspace and review-gated vacancy flow |
| About | `/about/` | Identity, operating model, how it works and why Aadhyant |
| Services / industries | `/services/`, `/industries/` | Secondary crawlable detail linked from journeys and footer |
| Contact | `/contact/` | Existing legitimate business contact and role-specific routes |
| Legal | `/privacy/`, `/terms/`, `/data-deletion/` | Existing privacy, terms and deletion information |

No route was removed, and no duplicate business workflow was introduced. Services and Industries remain useful secondary pages without competing with the five-item primary navigation.

## Homepage

The final homepage contains:

1. A focused industrial manpower and recruitment hero with Find Jobs as primary action, Hire Manpower as secondary action, and a contextual staffing-partner link.
2. A defensible value strip: industrial recruitment, approved public opportunities, reviewed partner access, and structured hiring coordination.
3. Current Jobs discovery through the existing safe projection, including explicit loading, empty, and error states.
4. Three separate step-by-step Candidate, Employer, and Staffing Partner journeys.
5. Manufacturing, automotive, engineering/trades, warehouse/logistics, and industrial-support context.
6. A truthful Why Aadhyant section centered on requirement-led handling, role-specific access, transparent expectations, and registered business identity.
7. Three clear audience conversion panels and a complete audience/legal footer.

The hidden duplicate legacy homepage content and its unnecessary homepage form controller were removed from the page. The design uses CSS geometry and restrained brand motifs rather than stock imagery or heavyweight media.

## Jobs experience

`assets/js/jobs.js` continues to call only `get_public_job_requirements(integer, integer)`. It has no direct table access and performs no mutation. The list now supports:

- keyword/role, location, qualification, and experience filtering;
- 20-row bounded pages and an explicit Load More action;
- current opening count, location, wage/salary when supplied, qualification, trade, experience, shift, facilities, interview context, expected joining date, and posted date when present;
- a query-addressable detail state at `/jobs/?requirement=<public-code>`;
- direct quick-interest routing to the existing Candidate registration contract;
- clear live loading, empty, error, filtered-empty, and no-longer-available states; and
- text-node-only rendering for all projected public data.

The safe projection does not include employer/company identity, contact information, internal notes, UUIDs, age/gender criteria, or the authenticated Candidate Portal's additional safe description. Those values are not fabricated or exposed. A dynamic `JobPosting` schema is intentionally not emitted because the safe public record does not currently provide complete hiring-organization and per-job canonical URL governance.

## Candidate journey

The Candidate page separates two canonical choices:

- **Quick Job Interest:** begins with a current public job, requires no login, requests no Aadhaar in the public form, and uses `register_candidate_requirement_interest` to reuse or create the canonical Candidate/Application relationship safely.
- **Candidate Portal:** uses the existing email/password account, role-scoped context, required authenticated profile setup, private documents, direct application, and Candidate-owned progress views.

The public copy states that registration or application does not guarantee contact, interview, selection, salary, or placement. Sensitive identity and document steps are described as authenticated portal actions rather than public-form requirements.

## Employer journey

The Employer page explains manpower sourcing, industrial staffing, Candidate matching, recruitment coordination, and approved partner coordination without guarantees. It distinguishes:

- a no-account Quick Requirement for a current need; and
- a reviewed Company account for recurring structured requirements and safe hiring-progress views.

The public form, Company registration, Company login, and existing portal RPC boundaries remain unchanged.

## Contractor journey

The Contractor / Staffing Partner page is positioned separately from the Employer journey. It explains agency registration, Aadhyant review, role-scoped portal activation, review-gated vacancy submission, explicit requirement assignment, contact-safe Candidate views, and read-only interview/joining progress. It states that registration does not guarantee activation, assignments, business, revenue, or Candidate outcomes.

## Navigation and footer

The final desktop header is: Jobs, For Employers, For Contractors, About, Contact, and Portal Login. The role selector names Candidate, Employer, and Contractor workspaces with short descriptions. At tablet/mobile widths it becomes a full-viewport drawer with a 48px menu target, Escape handling, body scroll control, and a nested role selector.

Core journey pages contain the final semantic header and footer directly. Existing secondary/legal/form pages are progressively normalized by the shared navigation controller so the complete site presents the same final information architecture without duplicating route-specific business logic.

The footer contains Aadhyant identity, GSTIN/location, Jobs/Candidate links, Employer links, Contractor links, About/Industries/Contact, and static Privacy, Terms, and Data Deletion links. Existing verified phone and email remain available on Contact and legal pages.

## Design system

- Brand core: deep industrial navy, controlled teal action color, warm terracotta accent, white and cool-neutral surfaces.
- Typography: system-first Inter / Segoe UI stack with compact display headings, readable body measures, and restrained uppercase labels.
- Layout: 76rem maximum width, consistent spacing, bordered grids, low-radius cards, purposeful density, and no stock imagery.
- Components: shared header, portal menu, hero, buttons, job cards, filter controls, journey cards, process grids, action panels, footer, empty/error states, and legal links.
- Breakpoints: 1180, 1080, 820, and 620 CSS thresholds cover the required 1440, 1180, 768, and 412 review matrix.
- Motion: subtle hover movement only, disabled through `prefers-reduced-motion`.

## SEO and discoverability

- Core page titles and descriptions are unique and intent-specific.
- Every public route retains its legitimate canonical URL.
- Core pages have one semantic `h1`, ordered section headings, meaningful links, and crawlable static route anchors.
- The homepage includes an Organization JSON-LD record using only the published business name, URL, phone, email, and location.
- No incomplete or fabricated JobPosting schema is emitted.
- Portal pages retain their existing noindex posture where established; the isolated review server adds noindex headers and metadata only at runtime.

## Accessibility

- Skip links, landmark elements, heading order, associated form labels, live status regions, visible focus, keyboard-accessible controls, Escape behavior, and reduced-motion support are retained or strengthened.
- The mobile menu occupies the available viewport and remains scrollable.
- Touch targets are at least 42px; principal public buttons and the mobile menu target are 48px.
- Public data is inserted through `textContent`, and filters remain usable without pointer-only behavior.
- Colors were selected for strong foreground/background contrast; browser QA confirmed no responsive overflow at the required widths.

## Performance

- No new runtime library, font download, image library, animation framework, or build dependency was added.
- The homepage performs one bounded three-row public Jobs RPC; Jobs uses bounded 20-row requests and loads subsequent pages only on demand.
- The production Supabase client architecture and existing CDN library are reused.
- The new favicon is a 247-byte SVG.
- The hidden duplicate homepage content was removed, reducing homepage markup substantially.

## Validation

- Focused public product tests: 20/20 PASS.
- Complete frontend suite: 175/175 PASS, including all pre-existing 155 Admin, Candidate Portal, Company Portal, Contractor Portal, recruitment, staff, and W7B campaign tests.
- Unchanged W7 Edge suite: 21/21 PASS.
- JavaScript syntax checks: PASS.
- `git diff --check`: PASS.
- Local link resolution: 43 HTML pages checked, zero unresolved local targets.
- Static security/leak scan: PASS.

### Browser QA

- Engine: installed Google Chrome 151 in isolated headless DevTools mode; no browser package was installed.
- Environment: loopback-only `127.0.0.1:4174`, with `config.js` replaced in memory by the approved NONPROD project `zrluniaccvcdrvfwgrmj`. The server blocks Admin and Supabase source paths and denies non-loopback Host headers.
- Matrix: 14 public pages at 1440x1000, 1180x820, 768x1024, and 412x915: 56 page/viewport combinations.
- Every page retained one `h1`, the five final navigation labels, all three legal links, zero failed images, and no document-level horizontal overflow.
- The live approved NONPROD Jobs projection returned its valid current empty state. Loading and empty behavior passed without errors.
- Populated cards, filtering, job detail, and interest routing were exercised with an in-memory browser-only projection. It made no database/Auth mutation, created no retained fixture, and exposed no internal identifier.
- Mobile menu: 48x48 target, correct expanded state, 843px available-height drawer at 412x915, scrollable content, and three-role portal selector.
- Console/network: zero exceptions, console errors, failed requests, or HTTP error responses.
- Observed hosts were exactly loopback, `cdn.jsdelivr.net`, and `zrluniaccvcdrvfwgrmj.supabase.co`; there were no unexpected hosts and the production project was not contacted.
- Visual inspection covered desktop and mobile Home/Jobs, populated Job cards and Job detail, Candidate, Employer, Contractor, and the open mobile navigation. The shared-header flex and collapsed mobile-drawer defects found during inspection were corrected and the entire matrix was rerun cleanly.

## Backend contracts reused

- `get_public_job_requirements(integer, integer)` for anonymous safe public Jobs data.
- `register_candidate_requirement_interest(text, jsonb)` for quick job-linked Candidate interest.
- Existing anonymous `employer_leads` and `candidates` public submission contracts through the unchanged form controller.
- Existing Candidate Portal RPC/storage contracts from migration 023–025.
- Existing Company Portal RPC contracts from migration 019/020.
- Existing Contractor Portal RPC contracts from migration 021/022.

No migration, table, policy, grant, trigger, RPC, Auth configuration, Edge function, Admin module, Meta setting, WhatsApp path, or production configuration changed.

## Focused implementation commit

- `64c6b7e25e36b13cb65f4c7778ad6bafcc9d1d10` — `Public: build premium workforce website`

## Known limitations and production posture

- Approved NONPROD currently has no open public Jobs rows, so the final live review shows the designed empty state until an authorized public requirement exists.
- The safe anonymous Jobs contract intentionally omits employer identity, direct contact, private notes, authenticated-only criteria, and long description; the public UI cannot display values the contract does not provide.
- Job detail is client-rendered at a public requirement-code query URL. Server-rendered per-job pages and complete JobPosting structured data would require separately governed publishing/backend work and are not fabricated here.
- Quick public interest and Candidate Portal account onboarding remain distinct established entry points. The public phase explains them but does not change their identity or Auth contracts.
- This is a local validated product phase, not a production launch. A production deployment, production configuration review, domain/DNS change, or new backend capability requires separate explicit approval.

No production deployment or contact occurred. Domain/DNS and Meta were unchanged. No message was sent or queued, no campaign action occurred, and no real Candidate was contacted.
