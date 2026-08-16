# Reconstruction R5 — Dedicated Hire Manpower Journey

## Employer journey

The public Employer journey is now:

`Homepage → /hire-manpower/ → Quick Requirement or Company Portal`

The landing page distinguishes the two workflows before requesting data.

## Quick Requirement and Company Portal

Quick Requirement is a public, no-account submission for one current workforce need. It uses the existing anonymous Employer flow and does not create an Auth user, Company, or Company membership.

Company Portal is for recurring structured requirement management. Its unchanged lifecycle remains registration, email verification, pending Admin review, approval, login, and requirement creation/management.

## Canonical form route

The one canonical public Employer form is now:

`/hire-manpower/requirement/`

Its functional markup was moved from the homepage without changing the form ID, `data-lead-form`, fields, input names, required attributes, validation hooks, review panel, database-submit action, WhatsApp link, email fallback, consent, or direct-contact options.

## Homepage compatibility transition

All active homepage Employer CTAs now lead to `/hire-manpower/`. The historical `#employer-form` destination remains as a lightweight compatibility message linking to `/hire-manpower/requirement/`; it contains no duplicate form.

The Candidate compatibility form remains on the homepage and is unchanged.

## Script reuse

The dedicated requirement page loads the existing root `script.js`, `config.js`, and `supabase-client.js` with correct relative paths. No submission logic was copied. `script.js` already binds through `querySelectorAll('[data-lead-form]')` and guards Candidate-only controls, so no script refactor was required.

## Form presentation and success guidance

The existing form remains grouped into Company Information, Manpower Requirement, Work Details, consent, review, and fallback contact areas. The page adds route-level context before the form and a post-submission guidance section after it. Existing success and error statuses remain authoritative. Employers can return Home or create a Company account for recurring needs.

## Accessibility and mobile behavior

Both new pages use the R2 skip link, semantic header/navigation/main/footer, one H1, logical headings, keyboard-operated mobile navigation and Portal Login, visible focus, reduced-motion support, and minimum-size actions. At narrow widths, Employer choices, process steps, form fields, review content, and CTA groups stack to one column.

## SEO

- `/hire-manpower/`: `Hire Industrial Manpower & Staffing Support | Aadhyant`
- `/hire-manpower/requirement/`: `Submit Manpower Requirement | Aadhyant`

Both pages include unique descriptions and production canonical URLs.

## Regression scope

Local validation passed for route responses, exact form-contract preservation, single canonical form occurrence, required validation, review/edit behavior, fallback links, Candidate compatibility, and all existing portal routes. Homepage, Employer landing, and Requirement routes passed at 360, 390, 768, 1024, and 1440 pixels with no page overflow, console errors, runtime exceptions, failed assets, or unexpected Supabase requests. No production record was created; online insertion was intentionally not triggered because no isolated local Supabase stack was running for R5.

## Known limitations

- Location controls remain free text because official LGD exports are still unavailable.
- No production-like Employer record is submitted unless an isolated local Supabase stack is explicitly available and targeted.
- Dedicated Services, Industries, Jobs, Candidate, Contact, Privacy, and Terms pages remain future work.

## Next phase

Create the dedicated Candidate landing and registration journey, move the single Candidate form from homepage compatibility into its canonical route, and preserve its current anonymous submission contract.
