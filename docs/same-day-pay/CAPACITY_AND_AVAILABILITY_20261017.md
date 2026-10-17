# Remaining places and dated Candidate availability

Prepared under the user's 17 October instruction to implement options 2 and 3. Not deployed. Production database/site approval remains outstanding under root AGENTS.md.

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
