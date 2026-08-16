# Reconstruction R6 — Candidate and Jobs Journey

## Candidate journey

The public Candidate journey is now:

`Homepage → /jobs/ or /candidate/ → /candidate/register/ → review and registration confirmation`

Candidate registration remains public and does not create an Auth account, Candidate Login, dashboard, application, interview, or joining workflow.

## Canonical Candidate form

The single canonical Candidate form is `/candidate/register/`. It was moved from the homepage without changing `candidate-registration-form`, `data-lead-form="candidate"`, inputs, names, required attributes, validation hooks, conditional experience behavior, same-as-mobile behavior, review panel, database submission, WhatsApp/email fallbacks, or consent.

The homepage `#candidate-form` destination now contains only a compatibility message linking to the canonical route. Active homepage Candidate links lead to `/jobs/`, `/candidate/`, or `/candidate/register/` as appropriate.

## Script reuse

The registration page reuses root `script.js`, `config.js`, and `supabase-client.js`. The script already treats Employer and Candidate forms independently and guards Candidate-only elements, so no script refactor or duplicated submission code was required.

## Jobs data-source decision

Result: **LIVE FEED BLOCKED BY CURRENT RLS**.

The repository schema grants anonymous users only the narrow Employer and Candidate insert operations. `employer_requirements` SELECT policies are limited to approved Admins, an active owning Company, and an active Contractor with an explicit assignment. There is no anonymous policy for open/public requirements.

R6 does not add SQL or weaken RLS. `/jobs/` therefore provides a professional filter-ready shell and honest empty state without issuing a Supabase request.

## Future public field boundary

A future narrowly scoped public view/RPC/policy should return only open/public records and an explicit safe projection such as requirement code, role/trade, department where appropriate, job location, headcount, salary range, qualification, experience, age range, gender preference where legitimate, shift, approved facilities, and intentionally public interview details.

It must exclude Company contacts, emails, mobile numbers, user/company UUIDs, internal notes, Contractor identities, assignment data, private/draft/on-hold/filled/closed/cancelled requirements, and Admin fields.

## Job filters and cards

`assets/js/jobs.js` is a dependency-free client filter for future DOM-rendered safe job cards. It supports keyword, location, qualification, and experience filtering without network access. State/District controls are intentionally absent. Current empty-state actions lead to Candidate Registration and Contact Aadhyant. “Apply” is not shown because Candidate Applications are not active publicly.

## Candidate success and privacy

The dedicated page preserves existing success/error and fallback behavior and adds guidance that Aadhyant may use submitted details for recruitment/workforce communication. It does not promise contact, an interview, placement, salary, or automated matching. Actions lead to Jobs and Home.

## R3 limitation

Official LGD State/District exports remain unavailable. Existing Candidate location and Education/Trade controls retain their current contract; R6 does not fabricate structured datasets or normalize production records.

## Validation scope

Validation covers exact single-form preservation, required-field blocking, conditional experience controls, review/edit behavior, WhatsApp/email fallbacks, no duplicate handlers, Employer regression, all portal routes, six public routes at 360/390/768/1024/1440, heading/ID integrity, navigation, empty-state filters, console/runtime errors, failed assets, unexpected Supabase reads/writes, secret scanning, and protected-file boundaries. No record is submitted unless an isolated local Supabase stack is explicitly targeted.

## Next phase

Create separately reviewed SQL architecture for a minimal public Jobs projection only if live Jobs are prioritized. Otherwise continue with dedicated public Services/Industries/About/Contact pages while retaining the safe Jobs empty state.
