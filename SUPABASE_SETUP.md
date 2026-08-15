# Supabase setup for Aadhyant Manpower & Staffing

This project remains a static GitHub Pages site. Supabase provides the PostgreSQL database, authentication, and Row Level Security (RLS). Complete these steps manually before testing online submission or admin access.

Never place a service-role key, database password, JWT signing secret, or administrator password in this repository. The browser configuration accepts only the public project URL and anon/publishable key. Security depends on applying `supabase/schema.sql` completely and verifying its RLS policies.

## 1. Create the Supabase project

1. Sign in to Supabase and create a project for this website.
2. Choose and securely store the database password outside this repository.
3. Wait for project provisioning to finish.

## 2. Apply the database schema

1. In the Supabase dashboard, open **SQL Editor**.
2. Open `supabase/schema.sql` from this project.
3. Copy the complete SQL file into a new SQL query.
4. Review it, then run it once as the project owner.
5. Confirm these tables exist:
   - `public.admin_users`
   - `public.employer_requirements`
   - `public.candidates`
6. Confirm RLS is enabled on all three tables.

The schema deliberately provides:

- anonymous, column-limited INSERT access to the two public submission tables;
- no anonymous SELECT, UPDATE, or DELETE access;
- no browser access to insert or modify `admin_users`;
- allowlisted administrator SELECT access;
- allowlisted administrator UPDATE access limited to `status` and `internal_notes`;
- no DELETE grants or policies.

Supabase recommends enabling RLS on exposed tables and using `TO anon` / `TO authenticated` policies explicitly. See [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).

## 3. Configure authentication

1. Open **Authentication → Providers**.
2. Keep Email/Password sign-in enabled.
3. Disable public new-user sign-up for this admin-only application.
4. Do not add a public sign-up page to this website.
5. Configure the Site URL and permitted redirect URLs for the final domain if Supabase requires them for your Auth settings.

## 4. Create the first admin Auth user

1. Open **Authentication → Users**.
2. Use the dashboard's administrative user-creation control to create the first trusted administrator.
3. Use a real administrator email and a strong unique password.
4. Do not write that password into a source file or this guide.
5. Copy the new user's UUID from the Auth user record.

## 5. Add the user to the admin allowlist

Open **SQL Editor** and run this statement after replacing the example value with the copied Auth UUID:

```sql
insert into public.admin_users (user_id)
values ('REPLACE-WITH-AUTH-USER-UUID');
```

Do not create a public insert policy for `admin_users`. Future administrators must be created in Supabase Auth and manually allowlisted by a trusted project owner.

To remove dashboard authorization without deleting submission data:

```sql
delete from public.admin_users
where user_id = 'REPLACE-WITH-AUTH-USER-UUID';
```

This manual owner action is intentionally not available in the website dashboard.

## 6. Obtain the public browser configuration

1. Open the Supabase project's API settings.
2. Copy the **Project URL**.
3. Copy the **anon/public** or **publishable** browser key.
4. Do not copy the service-role key.

Supabase documents browser installation and public client creation in [Installing supabase-js](https://supabase.com/docs/reference/javascript/installing).

## 7. Configure the static website

Edit only the placeholder values in `config.js`:

```js
window.AADHYANT_CONFIG = Object.freeze({
  supabaseUrl: 'https://wsuctjhbqiedttfnwjvf.supabase.co',
  supabasePublishableKey: 'YOUR_SUPABASE_PUBLISHABLE_KEY'
});
```

Replace `YOUR_SUPABASE_PUBLISHABLE_KEY` with the project's `sb_publishable_...` value. The publishable key is expected to be visible in browser source. RLS and least-privilege grants protect the data. Never substitute a secret or service-role key.

## 8. Start a local static preview

From the project directory:

```powershell
python -m http.server 8000
```

Open:

- Public site: `http://localhost:8000/`
- Admin login: `http://localhost:8000/admin/login.html`
- Admin dashboard: `http://localhost:8000/admin/`

## 9. Test public employer submission

1. Open the public homepage in a private/incognito browser window.
2. Select **Hire Manpower**.
3. Complete the employer form with authorized test information.
4. Review the details and select **Submit Requirement**.
5. Confirm the success message appears.
6. In Supabase Table Editor, confirm one row appears in `employer_requirements` with status `new`.
7. Confirm WhatsApp and email remain optional after submission.

## 10. Test candidate registration

1. Select **Find a Job**.
2. Complete the candidate form with authorized test information and consent.
3. Review and select **Submit Registration**.
4. Confirm the success message appears.
5. Confirm one row appears in `candidates` with status `new`.

Do not use real candidate personal data until the business has reviewed its privacy and data-handling responsibilities.

## 11. Test admin login and authorization

1. Open `/admin/login.html`.
2. Sign in with the allowlisted administrator account.
3. Confirm the dashboard loads actual counts and records.
4. Confirm logout returns to the login page.
5. Create a second Auth user without adding it to `admin_users`.
6. Confirm login may authenticate but shows: “Your account is not authorized for Aadhyant administration.”
7. Confirm that account is signed out and denied dashboard access.
8. Confirm that account cannot SELECT or UPDATE either submission table through the Data API.

Supabase Auth and RLS are designed to work together; authentication alone does not grant administrator access in this project. See [Supabase Auth](https://supabase.com/docs/guides/auth).

## 12. Verify RLS before production use

Using an incognito session or the Supabase API testing tools, confirm:

1. An unauthenticated visitor can INSERT a valid consented employer requirement.
2. An unauthenticated visitor can INSERT a valid consented candidate registration.
3. An unauthenticated visitor cannot SELECT either table.
4. An unauthenticated visitor cannot UPDATE or DELETE either table.
5. An unauthenticated visitor cannot read or insert `admin_users`.
6. An authenticated but non-allowlisted user cannot SELECT or UPDATE submissions.
7. An allowlisted administrator can SELECT submissions.
8. An allowlisted administrator can update only `status` and `internal_notes` through the API role.
9. No browser role can DELETE submissions.
10. A non-allowlisted authenticated user cannot SELECT or UPDATE submissions.

Do not proceed to production if any forbidden operation succeeds.

## 13. Test dashboard functions

Verify both tabs:

- actual total/new counts;
- newest-first ordering;
- status and text filters;
- 25-row pagination;
- detail view;
- WhatsApp, call, and employer email actions;
- controlled status changes;
- internal notes;
- no delete action.

## 14. Production checklist

Before any deployment:

1. Complete the RLS tests above.
2. Review Supabase Auth security settings and password requirements.
3. Review privacy and consent obligations for employer and candidate information.
4. Confirm only trusted users exist in `admin_users`.
5. Confirm `config.js` contains only the public URL and anon/publishable key.
6. Confirm `CNAME` remains unchanged.
7. Manually review the public and admin interfaces on mobile and desktop.
8. Commit, merge, or deploy only after explicit approval.

For eventual production Auth configuration, use `https://aadhyantmanpower.in` as the production Site URL. Add the exact localhost URLs used for testing, including `http://localhost:8000/admin/` and `http://localhost:8000/admin/login.html`, to the permitted redirect URL list where required. Also permit the corresponding production admin URLs under `https://aadhyantmanpower.in/admin/`. These settings must be changed manually in the Supabase dashboard; this repository does not modify them.

With placeholder configuration, the public forms intentionally show that online submission is unavailable while keeping WhatsApp and email usable. The admin pages remain locked until valid public Supabase configuration is supplied.
