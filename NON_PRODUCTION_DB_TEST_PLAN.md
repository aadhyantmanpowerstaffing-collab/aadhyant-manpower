# Non-Production Database Runtime Test Plan

## Decision

Use a **dedicated Supabase staging project** as the first reliable runtime-test environment for migrations 007–016, SQL security tests, role-context tests, and later portal smoke tests.

Local Supabase remains the preferred developer feedback loop after Docker/WSL access is repaired, but it is not currently usable on this machine. Plain PostgreSQL is useful for PostgreSQL syntax and constraint testing, but it does not reproduce Supabase Auth schemas, `auth.uid()`, platform roles, or hosted RLS behavior without substantial scaffolding.

No staging project has been created or contacted as part of this plan.

## Options considered

| Option | Advantages | Current constraint / limitation | Decision |
|---|---|---|---|
| Supabase local through Docker | Full Supabase fidelity, fast destructive resets, no remote risk | Docker engine and WSL enumeration currently return access denied; Supabase CLI is absent | Preferred after local tooling is repaired, not the immediate path |
| Dedicated Supabase staging project | Full Auth/Postgres/RLS/RPC fidelity and supports later browser smoke tests | Requires separately approved project creation, network access, secrets, and cost/governance controls | Recommended immediate runtime environment |
| Plain disposable PostgreSQL | Simple and inexpensive SQL parser/constraint test target | Missing Supabase Auth schemas, roles, JWT helpers, and platform behavior unless recreated | Optional secondary lint/SQL check, not the acceptance environment |
| CI-created local Supabase | Repeatable and isolated from developer-machine Docker problems | Requires CI design, Docker-capable runner, secret configuration, and time limits | Recommended follow-up once the first staging run proves the sequence |

## Setup prerequisites

1. Obtain explicit authorization to create one new Supabase project named with an unmistakable suffix such as `aadhyant-web-platform-staging`.
2. Use a separate organization/project reference from production. Never clone or reuse the production project reference, database password, API keys, or connection string.
3. Install and pin a reviewed Supabase CLI version and PostgreSQL client. Record their versions in the test evidence.
4. Create `supabase/config.toml` only when local/CI Supabase is introduced; do not copy a production project reference into it.
5. Establish a staging-only operator account and a small set of synthetic test identities for admin, Company A/B, Contractor A/B, Candidate, and authenticated non-member roles.
6. Confirm staging e-mail/SMS/WhatsApp integrations are disabled or point only to safe test sinks. No Meta production webhook or sending credential may be configured.

## Isolation boundary

The staging project is disposable and contains synthetic data only. Its project name, project reference, database host, dashboard banner, and environment-variable names must visibly include `STAGING` or `NONPROD`.

Before every mutating command, the operator must verify all of the following:

- the resolved host/project reference equals the approved staging allowlist;
- it does not equal the separately recorded production denylist;
- the current Git branch is `web-platform-development`;
- the migration set and checksums match the reviewed commit;
- no production export or real applicant/contact data is present.

Any failed or ambiguous guard stops the run. Do not use a generic “currently linked project” as authority for destructive commands. Commands must receive or validate the explicit staging target.

## Secret handling

- Store the staging database password, access token, service-role key, and project reference in an approved password manager or CI secret store.
- Use staging-specific environment-variable names such as `AADHYANT_STAGING_DB_URL`; never reuse production variable names.
- Keep `.env` files outside the repository. If a local ignored environment file is later approved, verify `.gitignore` first and scan the index before every commit.
- Never print connection strings, JWTs, passwords, service-role keys, or SQL containing secrets to logs.
- Browser smoke tests may use only the staging publishable key. Service-role credentials remain server/CI-only.
- Rotate staging secrets immediately if they appear in a terminal transcript, artifact, commit, screenshot, or test report.

## Migration application procedure

Use an automation script reviewed in a later authorized task; do not manually paste migrations out of order.

1. Guard and display only the non-secret staging project identity and Git commit.
2. Initialize a clean staging database state.
3. Apply `supabase/schema.sql` as the repository baseline.
4. Apply migrations in strict numeric order from `007_platform_roles_architecture.sql` through `016_web_platform_schema_foundation.sql` with stop-on-first-error behavior.
5. Record filename, SHA-256 checksum, start/end time, and success/failure without recording credentials or row data.
6. Query catalog state to verify tables, constraints, indexes, triggers, grants, RLS flags, policies, function owners, `SECURITY DEFINER`, and `search_path` settings.
7. Do not mark a migration as applied if its transaction rolled back or its postflight failed.

Because repository migrations begin at 007, `supabase/schema.sql` is a mandatory prerequisite. Do not infer that a blank hosted project already matches it.

## SQL test procedure

Run tests with stop-on-first-error and preserve sanitized output.

Historical tests should be executed at their intended migration checkpoint:

1. Reset to the repository baseline plus migrations through 009; run test 009.
2. Repeat for migrations/tests 010, 011, 012, 013, and 014.
3. Reset and apply through 015; run the migration 015 tenant-boundary test.
4. Reset and apply through 016; run `016_web_platform_schema_foundation_test.sql` and the still-compatible security suites.

This checkpoint approach avoids treating intentionally superseded historical-policy assertions as current behavior. Every test fixture must be synthetic and transactional where the suite supports it.

For the final 016 state, explicitly test:

- anon, authenticated non-member, admin, Company A/B, and Contractor A/B contexts;
- migration 015 Company and Staffing Partner projections and legacy-RPC revocations;
- RLS and grants on all W1 tables;
- inability of browser roles to insert/update/delete history or audit rows;
- automatic application history on insert and real status change, but not unchanged status;
- staff/profile/preference access restricted to the existing admin bootstrap;
- absence of cross-tenant Candidate, application, internal-note, staff-role, history, and audit exposure.

## Portal smoke tests

After database suites pass, point an explicitly non-production browser configuration at the staging URL and publishable key. Test public Jobs and Candidate registration plus admin, Company, and Contractor workflows with synthetic accounts. Never replace the production configuration file or deploy the staging configuration to the public site.

Portal smoke tests must confirm that existing RPC signatures and returned fields remain compatible after migrations 015/016. W1 adds no required frontend rewrite.

## Reset and cleanup

- Destructive reset is permitted only after the staging-target guard passes and only within the dedicated staging project.
- Reset by dropping/recreating application-owned objects or using the pinned CLI's reviewed staging reset workflow, then replay the baseline and migrations.
- Do not delete or alter managed Auth/platform schemas except as required by the documented Supabase reset mechanism.
- Remove synthetic Auth users and Storage objects during reset.
- Retain sanitized test evidence and migration checksums; do not retain secrets or raw JWTs.
- Project deletion requires separate approval. Never broaden a cleanup command from the explicit staging project.

## Targets that must never be used

The runtime test tooling, CLI link, environment, browser build, CI job, and reset script must never point to:

- the production Supabase project reference or database host;
- production database/API/service-role credentials;
- the production site or deployment environment;
- production DNS, Meta application, WhatsApp phone-number ID, webhook, verify token, or access token;
- copied production applicant, Company, Contractor, message, or audit data.

## Exit criteria before W2

W2 may begin only after a reviewed non-production run demonstrates:

- clean replay of schema plus migrations 007–016 at the recorded W1 commit;
- migration 015 and 016 SQL security tests pass at their correct checkpoints;
- final-state RLS tests pass for anon, non-member, admin, Company, Contractor, and Candidate contexts;
- browser roles cannot forge application history or audit events;
- migration 015 tenant isolation remains intact;
- existing public/admin/Company/Contractor portal smoke tests pass against staging;
- reset and replay are repeatable with no manual drift;
- test evidence contains no secrets or production data;
- W1 runtime findings are fixed, reviewed, committed, and pushed before W2 schema/auth work begins.

If staging creation is not approved, the next action is to repair Docker/WSL access and install a pinned Supabase CLI; plain PostgreSQL alone is not sufficient to approve W1 RLS behavior.
