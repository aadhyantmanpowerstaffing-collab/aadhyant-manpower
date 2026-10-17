# Remaining places and dated Candidate availability

Prepared under the user's 17 October instruction to implement options 2 and 3. Production database/site approval received at 12:32:53 IST. Deployment verification follows below.

## Behavior

Same-Day Pay cards show required people, confirmed count and remaining places. Only confirmed/attended/completed/paid canonical applications occupy places; pending interest does not. Cancellation releases a place. Upcoming approved full shifts remain visible with Fully booked, while the existing locked server-side application and confirmation guards continue to reject overbooking. Counts refresh every 30 seconds while visible, on return to the page, after actions, and with Refresh Places; this is polling, not a push subscription.

Candidates can separately mark today, tomorrow or both and enter their local work area. The Save Availability action explains that verified Companies, Contractors and Aadhyant can see their name, local area and selected date. The employer/admin panel provides a date selector and paginated available-workers list, without phone numbers, candidate IDs, email or private documents. Neither a canonical application nor WhatsApp consent is created by marking general availability. Unchecking both and saving withdraws availability.

Dates use India time server-side, automatically fall out of projections after midnight and reject stale/past/future submissions outside today/tomorrow. This feature is limited to the existing Sanand GIDC Same-Day Pay workspace. It does not automatically apply candidates or assert attendance. Existing location/alert opt-in rules are unchanged.

## Implementation and access

Migration: `20261017065604_same_day_capacity_and_availability.sql`. Adds one private Candidate extension table with RLS and no browser table grants. Own-identity read/write RPCs resolve the canonical active Candidate server-side. Available-worker listing requires active Company/Contractor management or vacancy-review permission, and excludes inactive profiles, inactive Candidates and inactive/non-Candidate portal accounts. All definer functions use an empty search path, explicit grants and input bounds. No caller-supplied Candidate ID, new outbox, transport, automatic sending or Meta configuration.

`list_same_day_jobs` retains canonical pre-Same-Day review/publication eligibility when projecting full cards, while the final application/confirmation capacity guard is unchanged. Owner/admin scope restrictions remain.

## Validation and release boundary

Three focused isolated PGlite tests pass: confirmation-only count/cancellation/full visibility and application guard; own dated state/expiry/no application or consent side effects; validation/withdrawal/employer authorization/inactive-account exclusion/private fields/RLS/grants/definer search paths. JavaScript syntax, production artifact build/verification and git diff checks pass. Full regression passed 599/599 with zero failures/skips. Final tightened inactive-account and catalog-security checks also passed in the three-test focused rerun.

Prepared artifact payload SHA-256: `71de2c1428801b9cc615458da056fda755796a7c268b50819f8a7c632097d5f1` (93 runtime files). No authenticated browser walkthrough or mobile visual matrix was performed. No real candidate/job/availability row was created and no message sent. Before authorized release, verify live table/function prerequisites and original listing body, install the migration atomically, compare installed definitions/grants/RLS, deploy the exact allowlisted artifact and inspect the live workspace. Keep automatic alerts off.

## Authorized production installation

Installed migration `20261017070346 / same_day_capacity_and_availability` on Aadhyant production `wsuctjhbqiedttfnwjvf`. Existing listing body and prerequisites matched before installation. All four installed function bodies match the reviewed SQL exactly. Private table RLS is enabled; anonymous save and direct authenticated table reads are denied. Public listing succeeds with zero upcoming shifts; availability rows remain zero. Automatic alerts remain OFF. Business counts before installation were zero Candidates, Vacancies, Applications and Outbound messages.

Native source commit `21462aaa4870ba1718262c3bd0e98ace787ba8e1` was promoted with expected-head non-force update from `858adcbb96904d58a2bce92a3187137eccf5dd95`. The existing remote scheduler workflow was preserved. Production Pages run `39012457453` (#23) was dispatched on this exact commit with deploy_production=true. Final outcome follows.

## Live closure

Run `39012457453` (#23) completed build and production deployment successfully. CI confirms 599 tests and the exact payload digest above. Live `https://aadhyantmanpower.in/same-day-pay/` renders the new refresh-count note/button; clicking Refresh Places returns the correct zero-upcoming-shifts state. Read-only live DOM confirms today/tomorrow checkboxes, local_area input and pool-date selector are shipped. Logged-out access correctly retains the existing sign-in entry; Candidate and employer panels remain hidden without their respective roles. No authenticated real-user availability walkthrough or populated full-card visual test was fabricated. Successful deployment screenshot: `availability-deployed-20261017.jpg`. Final Candidate/Vacancy/Application/Outbound/Availability counts all remain zero.

Security advisors retain the documented RPC-only definer categories and Free-plan leaked-password warning. The private availability table is intentionally default-deny with RLS/no policies and no direct browser grants; its INFO notice does not represent browser exposure.
