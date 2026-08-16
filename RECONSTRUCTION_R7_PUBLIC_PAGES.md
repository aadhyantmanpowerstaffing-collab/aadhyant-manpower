# Reconstruction R7 — Public Professional Pages

## Scope and routes

R7 adds four dedicated public routes: `/about/`, `/services/`, `/industries/`, and `/contact/`. It migrates public header and footer navigation away from temporary homepage anchors while preserving all Company, Staffing Partner, Admin, Employer and Candidate technical routes.

No database, Supabase, Auth, RLS, RPC, migration, portal logic or production environment is changed.

## Navigation migration

Every public header now links to the real Home, About, Services, Industries, Jobs and Contact routes. Portal Login continues to contain only Company Login and Staffing Partner Login. Find Jobs and Hire Manpower continue to use their existing routes. Admin and Candidate Login are not exposed.

Homepage sections keep their IDs as backward-compatible inbound anchors, but primary public navigation and footers use dedicated routes.

## About content strategy

The About page explains Aadhyant as a central workforce coordination point serving Employers, Candidates and approved Staffing Partners. It describes the requirement-led process, controlled account model and operating principles without claiming scale, awards, guaranteed outcomes or unsupported technology.

Only confirmed business identity is shown: Aadhyant Manpower & Staffing, Kadi, Mahesana, Gujarat, GSTIN 24ACNFA4445J1Z9, the verified phone number and verified email address already present in the site.

## Services scope

The Services page is limited to the established platform and business scope: Industrial Manpower Supply, Contract Staffing, Recruitment Support, Workforce Mobilisation, Staffing Partner Coordination and Requirement Management Support. It does not claim payroll outsourcing, statutory compliance management, HRMS, background verification, certified training or overseas recruitment.

## Industries scope

The Industries page covers Manufacturing, Automotive, Engineering, Warehouse & Logistics, FMCG and Industrial Operations. Roles are presented as indicative workforce categories, not current or guaranteed vacancies.

## Contact strategy

The Contact page provides verified phone, WhatsApp, email, location and GSTIN details, plus direct links for Employers, Candidates, Staffing Partners and Company users. No new generic contact form, table, email backend or Supabase write path is introduced. Business hours are omitted because none are confirmed in the repository.

## Footer changes

Public footers now use dedicated About, Services, Industries and Contact routes and group Employer, Candidate and Staffing Partner pathways. Admin remains absent. Privacy and Terms links remain omitted because those routes do not yet exist.

## SEO and accessibility

Each new page has a unique title, description, canonical URL, one H1 and logical heading hierarchy. Pages reuse the shared skip link, semantic landmarks, keyboard navigation, visible focus styles, touch targets and reduced-motion handling.

## Validation results

All ten public routes and all ten existing portal routes returned HTTP 200 over local HTTP. Every public page passed at 360, 390, 768, 1024 and 1440 pixels without page-level horizontal overflow. Shared mobile navigation, Portal Login expansion and layered Escape handling passed.

All ten public pages contain one H1, one title, one canonical URL and no duplicate IDs. The internal-link scan found zero broken local links. Browser capture found zero severe console errors and zero failed network responses. JavaScript syntax and `git diff --check` passed. No form was submitted and no Supabase write occurred.

## Known limitations

- Official LGD State/District data remains pending under R3.
- Jobs remains an honest empty state because anonymous live requirement access is not safely available under current RLS.
- Candidate Auth, Candidate Applications, Interview/Joining workflow and WhatsApp integration remain deferred.
- A dedicated public Staffing Partner landing page and legal pages are not part of R7.

## Recommended next phase

Create a dedicated public Staffing Partner discovery page while preserving `/contractor/` portal routes, then complete the official reference-data integration when reliable LGD exports are available. Live Jobs should be handled only in a separate, reviewed database-security milestone.
