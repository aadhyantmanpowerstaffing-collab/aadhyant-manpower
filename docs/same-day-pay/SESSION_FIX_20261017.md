# Same-Day Pay authenticated session correction

User screenshots show an authenticated Admin dashboard followed by a logged-out Same-Day Pay Admin page. The shared Supabase client only persisted/loaded sessions on Admin, Company, Contractor and Candidate portal paths; `/same-day-pay/` was omitted. This caused the separate workspace to ignore the existing login.

Added the exact Same-Day Pay path prefix to the existing authenticated client settings, preserving the same SDK storage and server-side role authorization. Public jobs and private registration forms retain nonpersistent sessions. No token is read/copied manually and no RPC grants or database schema change is required.

The previously unstyled sidebar anchor is now a consistent menu link under Local Shifts. It still opens `/same-day-pay/?role=admin` and relies on actual authenticated vacancy-review permission.

Focused Candidate/Admin/artifact checks pass 60/60, including a VM execution of the actual shared client that verifies persisted sessions for Same-Day Pay/Admin and nonpersistent sessions for public Jobs and private form routes. Deterministic production build/verify and git diff checks pass. User approved production deployment at 13:06:45 IST. Full regression passes 600/600 with zero failures/skips. Prepared payload SHA-256: `2733290090e2e61002849ef2e71516a6fc2e9fbac65f8a3ecd6580e7b0cc3623`.

An authenticated live role walkthrough remains to be verified after approved deployment; the screenshots establish the pre-fix failure, not post-fix success.

## Authorized release

Exact native source `550cfa2ebcbe33f6d86e5dbc54f4b8a087b56d68`, tree `7d8591beb32d61697cd011e065e31d930e35fcb0`, was promoted from `806e864cb142cfccb74d6f0583c20c5c3b42cbcf` using an expected-head non-force update. Only the reviewed five files changed; retained scheduler source was preserved. Production run `39014400686` (#24) dispatched with deploy_production=true on the reviewed branch. No database/Meta change or send is part of this release.

## Live closure

Run `39014400686` (#24) completed build and deployment successfully. CI reports 600 tests, zero failures/skips, and both initial/final payload verification show the exact reviewed SHA above. Public deployed `supabase-client.js` and `admin/admin.css` match source bytes; live Admin HTML contains the new Local Shifts menu/link. The Admin Same-Day Pay URL loads correctly. This cloud browser has no current Aadhyant authenticated session (Admin redirects to its login), so the full signed-in navigation walkthrough was not claimed; the actual SDK configuration regression proves the session-setting correction. No credentials were extracted and no dummy user created. The user can hard-refresh their existing signed-in Admin page and reopen the link. Proof: `same-day-session-deployed-20261017.jpg`. No database mutation, Meta change or WhatsApp send occurred.
