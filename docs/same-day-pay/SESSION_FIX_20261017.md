# Same-Day Pay authenticated session correction

User screenshots show an authenticated Admin dashboard followed by a logged-out Same-Day Pay Admin page. The shared Supabase client only persisted/loaded sessions on Admin, Company, Contractor and Candidate portal paths; `/same-day-pay/` was omitted. This caused the separate workspace to ignore the existing login.

Added the exact Same-Day Pay path prefix to the existing authenticated client settings, preserving the same SDK storage and server-side role authorization. Public jobs and private registration forms retain nonpersistent sessions. No token is read/copied manually and no RPC grants or database schema change is required.

The previously unstyled sidebar anchor is now a consistent menu link under Local Shifts. It still opens `/same-day-pay/?role=admin` and relies on actual authenticated vacancy-review permission.

Focused Candidate/Admin/artifact checks pass 60/60, including a VM execution of the actual shared client that verifies persisted sessions for Same-Day Pay/Admin and nonpersistent sessions for public Jobs and private form routes. Deterministic production build/verify and git diff checks pass. Not deployed; explicit production approval remains outstanding. Full regression passes 600/600 with zero failures/skips. Prepared payload SHA-256: `2733290090e2e61002849ef2e71516a6fc2e9fbac65f8a3ecd6580e7b0cc3623`.

An authenticated live role walkthrough remains to be verified after approved deployment; the screenshots establish the pre-fix failure, not post-fix success.
