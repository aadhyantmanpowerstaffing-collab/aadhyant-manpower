# Reconstruction R2 — Shared Public Design Foundation

## Scope

R2 establishes the public-site design and navigation foundation without moving the existing Employer or Candidate forms, changing Supabase behavior, or altering authenticated portal routes.

## Design system

`assets/css/public.css` defines public-scoped tokens for brand colors, semantic colors, typography, a 4/8-derived spacing scale, radii, shadows, content width, control height, and motion. Reusable public primitives cover buttons, cards, headings, links, fields, messages, status badges, and empty states.

The stylesheet is loaded only by public pages and every component rule is scoped beneath `.public-site`. Company, Contractor, and Admin pages do not load it.

## Header and navigation

The shared public header contains Home, About, Services, Industries, Jobs, and Contact links. Until dedicated public pages exist, these resolve to compatible homepage anchors and do not create 404 responses.

CTA order is:

- Secondary: Find Jobs, currently pointing to the existing Candidate form.
- Primary: Hire Manpower, currently pointing to the existing Employer form.

The Portal Login control contains only the existing Company Login and Staffing Partner Login routes. Admin and Candidate Login are intentionally absent.

## Mobile behavior

`assets/js/public-navigation.js` is a dependency-free, isolated module wrapper. It controls the public menu and Portal Login group, synchronizes `aria-expanded`, closes on navigation, closes on Escape with focus restoration, closes on outside clicks where applicable, and locks background scrolling while the mobile menu is open. On mobile the Portal Login dropdown becomes an inline expanded group.

## Footer

The shared footer preserves the verified Aadhyant contact details and GSTIN already present in the website. It groups public exploration, Employer/Candidate/Partner pathways, portal logins, and contact information. Missing Privacy or Terms routes are not linked in R2. Admin is not exposed.

## Portal route preservation

These technical routes are unchanged:

- `/company/register.html`
- `/company/login.html`
- `/company/index.html` and `/company/`
- `/company/requirements.html`
- `/contractor/register.html`
- `/contractor/login.html`
- `/contractor/index.html` and `/contractor/`
- `/contractor/assignments.html`
- `/admin/login.html`
- `/admin/index.html` and `/admin/`

No Company, Contractor, or Admin HTML, CSS, JavaScript, Auth gate, redirect, RLS, RPC, or database behavior was changed.

## Existing form preservation

The Employer and Candidate forms remain on the homepage. Their IDs, names, fields, validation hooks, review panels, submission behavior, Supabase client calls, WhatsApp fallback, and email fallback are unchanged.

## Reference-data foundation

`assets/js/reference-data.js` provides an optional ES-module loader with input validation, same-origin loading, array validation, and in-memory caching. `assets/data/` is reserved for future canonical datasets:

- India states
- India districts
- Education
- ITI trades
- Industries
- Job roles
- Experience levels
- Employment types
- Shift types
- Availability options

No incomplete dataset is fabricated in R2 and the loader is not connected to any production form.

## Accessibility

- Existing skip link and semantic header, navigation, main, and footer are retained.
- Menu and Portal Login buttons have accessible names, controls, and expanded states.
- Menu actions are keyboard-operable and Escape restores focus.
- Visible focus indicators remain enabled.
- Mobile controls meet the 44px target baseline.
- Portal options do not depend on hover.
- Reduced-motion preferences disable nonessential transitions.

## Test record

R2 validation must cover JavaScript syntax, HTML parsing, local HTTP route responses, homepage navigation behavior, responsive widths of 360, 390, 768, 1024, and 1440 pixels, page-level overflow, preserved forms, portal-route responses, console/runtime exceptions, and failed assets. The final task report records the completed results.

## Next phase

R3 should reconstruct the homepage into a shorter pathway-led experience while retaining compatibility links to the existing Employer and Candidate forms until their dedicated R4/R5 routes are deployed and verified.
