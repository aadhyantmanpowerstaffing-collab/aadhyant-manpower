# W0 Production Inventory

Captured 2026-08-19. This W0 inspected repository state only. It made no application-source changes, production queries, deployments, DNS/Meta changes, migration runs, or credential changes.

## Current web architecture

The Aadhyant project is a static, multipage HTML/CSS/JavaScript site. Pages load Supabase JS v2 from a CDN, then `config.js`, `supabase-client.js`, and page-specific scripts. There is no repository-hosted application server or permanent webhook runtime in this project.

The public and authenticated surfaces share one domain but are directory-separated. Current route ownership is:

| Capability | Current route/files | Data behavior |
|---|---|---|
| Public home | `/index.html`, `script.js`, `style.css`, `assets/js/public-navigation.js` | Public navigation/forms and jobs teaser. |
| Jobs | `/jobs/index.html`, `assets/js/jobs.js` | Calls `get_public_job_requirements`; public interest links to candidate registration. |
| Candidate landing/registration | `/candidate/index.html`; `/candidate/register/index.html`, `script.js` | No candidate login/account; submits profile or requirement-linked interest through public pathways/RPC. |
| Employer landing/requirement | `/hire-manpower/index.html`; `/hire-manpower/requirement/index.html`, `script.js` | Anonymous employer requirement intake. |
| Admin | `/admin/login.html`, `/admin/index.html`, `admin/admin.js`, `admin/admin.css` | Supabase Auth plus `admin_users` membership check; manages requirements, candidates, companies, contractors, applications, assignments, and interviews. |
| Company | `/company/register.html`, `login.html`, `index.html`, `requirements.html`, `company/company.js` | Auth signup/login, membership/status gate, profile and requirement lifecycle. Current uncommitted JS expects migration 015 wrapper RPCs. |
| Contractor | `/contractor/register.html`, `login.html`, `index.html`, `assignments.html`, `contractor/contractor.js` | Auth signup/login, membership/status gate, profile and assigned requirements. Current uncommitted JS expects migration 015 projection/wrapper RPCs. |
| Applications | Admin application panel/dialog in `admin/index.html`, logic in `admin/admin.js`; public creation via job/candidate flow | Backed by `candidate_applications` and migrations 012–013. No standalone applicant portal. |
| Interviews | Interview section embedded in admin application dialog, `admin/admin.js` | Backed by `interviews` and migration 014; no standalone public/company interview route. |

Other public routes include About, Services, Industries, Contact, Staffing Partner landing, Privacy, Terms, and Data Deletion. `CNAME` names `aadhyantmanpower.in`, but repository files alone do not prove the current hosting provider, deployed commit, DNS state, or live behavior.

## Supabase configuration and authentication

- `config.js` places the Supabase project URL and a **publishable/anon-class browser key** in `window.AADHYANT_CONFIG`. Those values are necessarily public; they are intentionally not reproduced here.
- `supabase-client.js` reads that object and constructs one frozen `window.aadhyantSupabase` facade.
- Session persistence, automatic refresh, and callback-session detection are enabled only under `/admin`, `/company`, and `/contractor`. Public/candidate pages use non-persistent sessions.
- Admin signs in through Supabase Auth and must also match `admin_users`.
- Company and contractor users sign up/sign in through Supabase Auth; server-side signup triggers create platform/membership records, while client gates inspect account and membership status. RLS/RPC authorization remains the actual security boundary.
- Repository search found no service-role key or database password in client code. The configuration comment explicitly prohibits them. This does not replace secret scanning of deployed artifacts/history or production configuration.

Security observations:

1. A browser publishable key is not a secret; safety depends on correct RLS, grants, and RPC authorization.
2. The dirty client code depends on untracked migration 015. Deploying either side alone risks broken portals or excessive tenant exposure.
3. Supabase JS is CDN-loaded without a pinned integrity attribute; consider dependency pinning/CSP in a later hardening milestone, not W0.
4. Repository inspection cannot verify production RLS or function definitions. A migration file is intent, not evidence of application.

## Desktop reference boundary

The desktop V3 reference is a PySide6/SQLite application with repository/service/controller layers, a local signed Meta webhook, Cloud API sender, Candidate/Company/Vacancy masters, Reply Manager, persisted WhatsApp messages/conversations, deterministic multilingual chatbot state, candidate intake/Flow handling, campaigns/templates/queue, delivery status, reports, and keyring-backed secrets. It is a behavioral reference only; its SQLite schemas and Windows-thread/UI architecture should not be copied directly into the Supabase browser client.

For W0, no desktop source or data was changed. The prior architecture documents contain the detailed desktop-to-web mapping.

## Baseline conclusions

- The useful web foundation is real: public site, Supabase Auth/RLS, tenant onboarding, requirements, contractor assignments, public jobs, candidate applications, and interviews.
- There is no repository-proven 24x7 webhook/chatbot/team-inbox backend yet.
- Do not duplicate existing candidate/company/contractor/requirement/application/interview entities in W1.
- Migration 015 plus both portal JS changes must be treated as one unfinished compatibility/security bundle.
- Production schema, applied migrations, deployed revision, RLS effectiveness, secrets, backups, Realtime, and hosting configuration remain unverified until an authorized read-only production audit.

## W0 stop point

W1 must not begin in this dirty worktree. The exact next action is to review and staging-test migration 015 with its client/test/preflight files, confirm the favicon's provenance, commit coherent changes on `v2-development`, fetch/reconcile/push safely, and only then create an isolated `web-platform-development` worktree as specified in `W0_GIT_BASELINE.md`.
