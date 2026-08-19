# Staging Runtime Setup and Test Runbook

## Scope and isolation

This runbook prepares runtime validation for the dedicated Supabase project `aadhyant-web-platform-staging-nonprod` in Singapore. It does not authorize production access, deployment, destructive commands, migration execution, or W2.

Only synthetic data may enter staging. Production project references/hosts remain in a private denylist; staging identity remains in a separate allowlist. Server-only secrets must never be committed, printed, passed through chat, placed in browser code, or stored in command-line arguments.

## Current prerequisites

- Windows x64 host.
- Node.js `24.18.0` and npm `11.16.0` are present. PowerShell blocks `npm.ps1`, so use `npm.cmd`/`npx.cmd`.
- Docker CLI `29.7.2` is present, but Docker engine and WSL access are unavailable. They are not required for the hosted staging workflow.
- Supabase CLI, `psql`, and `pg_isready` are not installed.

## Pinned tooling recommendation

Install only after separate approval:

- Supabase CLI `2.111.0`, stable, project-scoped and exact-pinned.
- PostgreSQL client binaries `18.4` for `psql` and `pg_isready`; extract the official Windows x64 binary archive without registering or starting a PostgreSQL server.

Reviewed future commands:

```powershell
if (-not (Test-Path -LiteralPath '.\package.json')) { npm.cmd init --yes }
npm.cmd install --save-dev --save-exact supabase@2.111.0
npm.cmd exec -- supabase --version
```

Download the PostgreSQL 18.4 Windows x64 binary archive from the PostgreSQL-referenced EDB binaries page, verify the downloaded artifact and publisher, and save/rename the reviewed archive to the exact local filename below. Then extract it without installing a server service:

```powershell
$archive = "$env:USERPROFILE\Downloads\postgresql-18.4-windows-x64-binaries.zip"
$destination = "$env:LOCALAPPDATA\AadhyantTools\PostgreSQL-18.4"
Expand-Archive -LiteralPath $archive -DestinationPath $destination
& "$destination\pgsql\bin\psql.exe" --version
& "$destination\pgsql\bin\pg_isready.exe" --version
```

Confirm the downloaded archive's actual filename/layout before running these commands. Do not add the PostgreSQL server binaries to Windows services or start a local database.

## Local environment

The ignored `.env.staging.local` contains placeholders for:

```text
AADHYANT_STAGING_EXPECTED_PROJECT_REF=
AADHYANT_STAGING_EXPECTED_DB_HOST=
AADHYANT_STAGING_URL=
AADHYANT_STAGING_PUBLISHABLE_KEY=
AADHYANT_STAGING_DB_URL=
AADHYANT_STAGING_DB_PASSWORD=
AADHYANT_STAGING_SECRET_KEY=
AADHYANT_PRODUCTION_DENYLIST_PROJECT_REFS=
AADHYANT_PRODUCTION_DENYLIST_DB_HOSTS=
AADHYANT_STAGING_APPROVED_GIT_COMMIT=
AADHYANT_STAGING_APPROVED_MIGRATION_MANIFEST_SHA256=
```

Classification:

| Value | Classification |
|---|---|
| Staging URL, publishable key | Browser-safe, staging only |
| Expected project ref, expected DB host, approved commit/checksum | Operational identity; keep local to reduce targeting mistakes |
| DB URL, DB password, secret key | Server-only |
| Production denylists | Server-only operational safety data |

Prefer password-manager injection. If this local file is used, keep it only on the trusted workstation; Git ignores `.env` and `.env.*`. Never use production variable values.

## Identity verification

Before any remote mutation:

1. Run `scripts/staging/verify-staging-target.ps1`.
2. Require branch `web-platform-development` and the approved exact commit.
3. Require every guard value and non-empty production denylist.
4. Parse rather than substring-match URL, host, port, and pooler username.
5. Require staging URL `<project-ref>.supabase.co` and either:
   - direct endpoint `db.<project-ref>.supabase.co:5432` with user `postgres`; or
   - session pooler on port 5432 with user `postgres.<project-ref>`.
6. Reject any project ref or DB host found in production denylists.
7. Require the aggregate reviewed migration-manifest hash.
8. Using `psql`, perform a separately reviewed read-only identity query and record only non-secret database/user/server identity.
9. Abort on any missing, unknown, redirected, ambiguous, or mismatched result.

The static script is necessary but not sufficient: the read-only remote identity check must immediately precede every reset/migration operation.

## Connection choice

Use the **Supavisor session pooler on port 5432** as the default for this Windows host. It supports IPv4 and preserves session semantics needed by `psql`, explicit transactions, `SET`, and checkpoint tests.

Use the direct endpoint only after confirming IPv6 connectivity (or an approved IPv4 add-on). Direct connection is otherwise ideal for migrations. Do not use the transaction pooler on port 6543 for migrations/tests: transaction pooling does not preserve session state and does not support prepared statements reliably for this workflow.

Always require TLS (`sslmode=require`) and keep the complete connection URL server-only.

## Migration replay and checkpoint tests

No command in this section may run until the guard, remote identity check, and destructive reset wrapper are separately reviewed and authorized.

For each checkpoint, start from a clean staging application schema/Auth fixture state:

1. Apply `supabase/schema.sql` with stop-on-error.
2. Apply migrations 007, 008, and 009 in numeric order.
3. Run `supabase/tests/009_company_requirements_test.sql`.
4. Reset safely, replay baseline through 010, and run test 010.
5. Repeat reset/replay/test for 011, 012, 013, and 014.
6. Reset, replay through 015, and run test 015.
7. Reset, replay through 016, and run test 016.
8. On the final 016 state, run only historical suites whose assertions remain compatible; record superseded assertions rather than weakening current security boundaries.

Each SQL invocation uses `psql` with `ON_ERROR_STOP=1`, TLS, sanitized output, and one explicit staging connection. Record filename, SHA-256, commit, timestamp, and result. Never echo the connection string.

## Synthetic identities and RLS matrix

Use synthetic addresses under a reserved test domain and no deliverable phone numbers.

| Identity | Must be able to | Must not be able to |
|---|---|---|
| Anonymous | Use intentionally public registration/jobs RPCs only | Read tenant/internal tables; execute staging/admin/tenant-private RPCs |
| Authenticated non-member | Hold a valid session | Read staff, tenant, Candidate, history, audit, assignment, or internal-note data |
| Admin | Use existing `admin_users` bootstrap; manage reviewed application/interview/tenant workflows; read W1 internal tables | Bypass controlled values or forge direct audit/history mutations |
| Company A | Read/manage only Company A requirements through migration 015 RPCs | Read Company B, assignments, internal notes, staff, audit/history, or Candidate CRM |
| Company B | Same within Company B | Read Company A or any unrelated/internal data |
| Contractor A | Read/respond only to Contractor A assignments through migration 015 RPCs | Read Contractor B, unassigned requirements, internal notes, staff, audit/history, or Candidate CRM |
| Contractor B | Same within Contractor B | Read Contractor A or any unrelated/internal data |
| Candidate | Use only currently authorized public/self pathways | Read other Candidates, tenant internals, staff, audit/history, or arbitrary applications |

Create users only after schema replay and only through a reviewed synthetic fixture process. Never copy production users or invite real contacts.

## Browser staging configuration

Do not replace `config.js`. Serve a local-only staging copy/build that injects only:

- `AADHYANT_STAGING_URL`
- `AADHYANT_STAGING_PUBLISHABLE_KEY`

The local staging config must be generated outside tracked source, use a localhost-only server, carry an obvious NONPROD banner, and fail if hostname is not localhost. It must never contain DB URL/password, secret/service-role key, or management token. Add a future reviewed generator rather than manually editing the production-facing configuration.

Smoke tests cover public Jobs/registration plus admin, Company, and Contractor existing flows against staging synthetic data. No staging build may be deployed to production hosting.

## Reset and abort rules

The future reset wrapper must:

- call both static and immediate remote read-only identity guards;
- require exact staging allowlist and reject production denylists;
- enumerate the exact staging-owned objects/users to reset;
- never broaden to managed schemas or project deletion;
- stop on first failure without retrying more broadly;
- replay the repository baseline deterministically.

Abort on wrong branch/commit, blank value, malformed URL, unknown identity, production match, checksum drift, TLS failure, unexpected objects/data, test failure, or evidence of real user data.

## Evidence and W2 exit criteria

Save sanitized tool versions, Git commit, migration/test checksums, non-secret masked staging identity, catalog/RLS/grant/function results, test pass/fail output, reset/replay repeatability, and portal smoke results. Never save secrets, full JWTs, connection strings, or real data.

Before W2: migrations 007–016 must replay cleanly; checkpoint and final RLS tests must pass; migration 015 boundaries must remain intact; history/audit forgery must fail; portal smoke tests must pass; reset/replay must be repeatable; all runtime defects must be fixed, reviewed, committed, and pushed.
