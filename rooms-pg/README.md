# Rooms & PG — first release

Adds an accommodation workspace to the existing Aadhyant platform. It reuses Supabase Auth, canonical Candidate identities, and the existing Admin authorization function. No recruitment or messaging system is replaced.

## Routes

- `/rooms-pg/`: public approved properties, area/type/budget filters, Candidate enquiries.
- `/rooms-pg/owner/register.html`: owner account creation and email confirmation.
- `/rooms-pg/owner/login.html`: isolated Owner session, including password recovery.
- `/rooms-pg/owner/`: submit Owner details for review, then manage own properties and enquiries.
- `/rooms-pg/admin.html`: Admin-only Owner approval/suspension and property review.

Owner approval and property approval are separate. Editing property details returns it to pending review. Updating availability or pausing a listing preserves review status. Only approved, listed properties belonging to active owners with positive availability reported within the last 30 days are publicly visible. Rent is monthly per bed or room. An enquiry does not reserve inventory or collect money.

Enquiries require an active canonical Candidate and explicit sharing of the provided phone number/message with the property's owner. Candidate withdrawal conceals the shared phone and message from the Owner's enquiry view. Existing enquiry records remain for continuity. A new enquiry resubmission requires consent again. Owners see only enquiries for their properties.

## Data and deployment

Apply `supabase/migrations/20261021081946_rooms_pg_owner_portal.sql` before publishing the frontend. This transaction creates three private RLS tables and narrow RPCs. Browser direct table access is revoked. Admin review uses `private.can_review_vacancies()`; Candidate access uses `private.current_candidate_portal_id()`.

Owner sign-in uses `sb-<project>-room-owner-auth-token` to avoid changing Candidate, Contractor or Admin sessions. New owner signups use `onboarding_type: room_owner`, which existing Company/Contractor signup triggers ignore. A confirmed email is required to submit Owner details. The Owner email-confirmation and password-reset redirect paths must be allowed in the existing Supabase Auth redirect settings; verify those settings before activation.

The first release accepts up to three browser-resized JPEG photos per property, each capped at 180,000 characters. They are saved with the property and included in its approved public projection; no Storage bucket or external image tracking is introduced. Listings paginate by 12. Admin Owner review is bounded to the latest 500 accounts, enquiry views to the latest 200 records. These limits should be expanded with pagination if usage grows. No payment gateway, booking guarantee, bulk messages, map-distance matching or automated tenant selection is included.

## Validation

`node --test tests/rooms-pg-runtime.test.js tests/rooms-pg-ui.test.js` exercises actual migration functions in disposable PGlite and executes frontend access gates. Covers confirmed-email onboarding, approval separation, cross-owner denials, re-review, freshness/capacity, explicit consent, withdrawal, replay identity, invalid maps/photos, RLS/grants, session isolation and source packaging. `npm test` includes these tests and all retained regression suites.

Runtime SQL and permission testing is local and synthetic. Hosted mutation and publication require deployment authorization. Authenticated live browser verification remains necessary after deployment; no real Owner/Candidate account was created by the implementation tests.

## Owner workspace navigation

The Owner header contains Dashboard plus My Properties and Enquiries for approved accounts only. Public listings open separately from the workspace footer; they are browsing, not a Candidate login shortcut. An account overview distinguishes profile submission, pending approval, approved and suspended states. Refresh Account Status rechecks the server before revealing management. Signed-out access remains gated. Property submission returns to the first page, and an enquiry-read failure has its own retry message without hiding loaded properties. Sign-out errors preserve the session and report failure.
