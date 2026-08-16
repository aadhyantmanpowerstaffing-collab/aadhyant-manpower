# Reconstruction R4 — Professional Homepage

## Previous homepage problem

The original homepage combined long marketing sections, complete Employer and Candidate forms, jobs, business credentials, and contact information in one uninterrupted flow. Employer, Candidate, and Staffing Partner pathways were not equally clear.

## New homepage architecture

The rendered homepage now follows a concise platform structure:

1. Shared R2 header
2. Workforce-platform hero
3. Employer, Candidate, and Staffing Partner pathways
4. Concise services overview
5. Concise industries overview
6. Three-step Aadhyant coordination process
7. Restrained trust and verified business credential section
8. Candidate opportunity teaser
9. Three-way final call to action
10. Shared R2 footer

Legacy marketing sections remain non-rendered in R4 to minimize deletion risk while the reconstruction is uncommitted. They have no duplicated active anchor identifiers and can be removed after the new homepage is approved.

## User pathways

- Employers use `#employer-form` until the dedicated Hire Manpower form exists.
- Candidates use `#candidate-form` until dedicated Jobs and Candidate pages exist.
- Staffing Partners use the existing `contractor/register.html` route.
- Company and Staffing Partner logins remain in the R2 Portal Login control.
- Admin is not exposed publicly.

## Temporary form compatibility strategy

The Employer and Candidate forms each remain exactly once in the DOM. Their IDs, input names, `data-lead-form` values, review panels, validation, Supabase submission, WhatsApp fallback, and email fallback remain unchanged.

The two compatibility sections are removed from normal homepage layout with public-scoped CSS. An existing hash link makes its matching section the `:target`, which reveals the original form. This keeps old `#employer-form` and `#candidate-form` URLs operational without presenting both full forms during ordinary homepage browsing.

## Preserved anchors

Active compatible anchors:

- `#home`
- `#about`
- `#services`
- `#industries`
- `#employers`
- `#candidates`
- `#employer-form`
- `#candidate-form`
- `#jobs`
- `#contact`
- `#business` remains attached to its retained legacy credential section for backward compatibility

## Mobile behavior

The hero becomes one column, pathways and process steps stack, services and industries collapse to one column, final calls to action remain large links, and the compatibility forms retain their existing responsive form layout. The shared R2 navigation continues to control mobile Menu and Portal Login behavior.

## Accessibility

R4 preserves the skip link, semantic main/section/footer structure, a single H1, logical H2/H3 hierarchy, labelled navigation controls, keyboard-operated Portal Login, visible focus, reduced-motion handling, and real links for all actions. New icon-like arrows are decorative.

## SEO

The canonical homepage remains `https://aadhyantmanpower.in/`. The title and meta description now describe Aadhyant's industrial staffing, workforce network, and job-opportunity pathways without unsupported claims.

## Regression scope

Validation covers required responsive widths, active anchors, compatibility form contracts, local route responses, console/runtime errors, failed assets, public navigation, CNAME/configuration boundaries, portal file preservation, and secret scanning. No form is submitted and no production record is created.

## Known limitations

- Dedicated About, Services, Industries, Hire Manpower, Candidate, Jobs, Contact, Privacy, and Terms pages remain future work.
- The compatibility forms intentionally open inside the homepage until their dedicated pages exist.
- Jobs remain an opportunity call to action; they are not yet sourced from public open requirements.
- R3's official LGD State/District data remains blocked and current form location behavior is unchanged.

## Next phase

Build the dedicated Hire Manpower landing and requirement pages, move the existing Employer form without changing its submission contract, and keep the homepage hash compatible during transition.
