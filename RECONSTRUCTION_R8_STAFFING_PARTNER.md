# Reconstruction R8 — Staffing Partner Public Journey

## Branch and scope

R8 is implemented on `v2-development` from the committed R7 checkpoint. It adds a public discovery layer only. No database, Supabase, Auth, RLS, RPC, migration, portal logic or production environment is changed.

## Public route

The canonical route is `/staffing-partner/`. It uses the shared public header, navigation, design system and footer. Public language consistently uses “Staffing Partner”; the existing `/contractor/` technical route names remain unchanged.

## Registration and login routing

The public page does not duplicate authentication or onboarding. Its actions route to the established technical pages:

- Become a Staffing Partner → `/contractor/register.html`
- Staffing Partner Login → `/contractor/login.html`

## Partnership process

The page documents five controlled steps: Register, Review, Approval, Requirement Assignment and Workforce Coordination. Approval and assignment are described as reviewed and conditional; neither is promised.

## Benefits and business-model boundary

Benefits are limited to structured assignments, clear assigned-requirement details, a centralised assignment view and coordination through Aadhyant. The page does not claim guaranteed business, revenue, payment, requirements, Candidate volume, automatic matching or direct Employer access.

Aadhyant remains the coordination layer. Staffing Partners do not receive unrestricted access to Employer, Company, Candidate or administrative databases. Operational access remains account- and assignment-based under existing permissions.

## Homepage, navigation and footer changes

Homepage Staffing Partner discovery links now lead to `/staffing-partner/`. Public footers consistently link “Become a Staffing Partner” to the landing page and “Staffing Partner Login” to the existing technical login. The primary header remains unchanged to avoid overloading navigation. Portal Login still contains only Company Login and Staffing Partner Login.

## Contractor portal preservation

The following technical routes and their source files are unchanged:

- `/contractor/register.html`
- `/contractor/login.html`
- `/contractor/`
- `/contractor/assignments.html`

Authentication, approval, assignment handling, JavaScript, Supabase integration, RLS and RPC behavior remain intact.

## SEO and accessibility

The page has a unique title, factual description, canonical URL, one H1 and no structured-data claims. It reuses the shared skip link, semantic landmarks, keyboard navigation, visible focus, touch targets and reduced-motion handling.

## Validation results

All eleven public routes and all ten portal routes returned HTTP 200 over local HTTP. Every public page passed at 360, 390, 768, 1024 and 1440 pixels with zero page-level horizontal overflow. Shared mobile navigation, Portal Login expansion and layered Escape handling passed.

The internal-link scan found zero broken links. Every public page has one H1 and no duplicate IDs. Browser capture found zero severe console errors and zero failed network responses. JavaScript syntax and `git diff --check` passed. No account, form submission, database record or Supabase write was created.

## Known limitations

- Partner registration remains subject to the existing approval workflow.
- Registration does not guarantee assignments, payment, revenue or Candidate volume.
- Candidate supply and later operational workflows remain outside R8.
- Live public Jobs, LGD data and Candidate Auth remain deferred.

## Recommended next phase

Complete the authoritative reference-data milestone when official LGD exports are available, or plan legal Privacy and Terms pages before broader public deployment. Any live Jobs feed should remain a separate reviewed database-security milestone.
