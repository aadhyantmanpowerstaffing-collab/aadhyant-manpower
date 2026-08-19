# Staging Safety Guard Specification

## Purpose

Every future database reset, migration, seed, or remote SQL test must positively identify the dedicated Aadhyant staging project before it can run. Unknown identity is a hard failure. This document contains no real project references, hosts, or credentials and does not implement a destructive command.

## Required private inputs

The future guard must receive these values from an approved local secret store or CI secret manager, never from committed files:

- `AADHYANT_STAGING_EXPECTED_PROJECT_REF`
- `AADHYANT_STAGING_EXPECTED_DB_HOST`
- `AADHYANT_STAGING_DB_URL`
- `AADHYANT_PRODUCTION_DENYLIST_PROJECT_REFS`
- `AADHYANT_PRODUCTION_DENYLIST_DB_HOSTS`

The allowlist must contain exactly one approved staging project reference and one canonical staging database host. The production denylists must contain every known production project reference and database host. Empty values, wildcard values, URLs with embedded ambiguity, and multiple staging targets are invalid.

## Mandatory checks

Before any mutating database operation, the guard must perform all checks in this order:

1. Confirm the current Git worktree branch is exactly `web-platform-development`.
2. Confirm the expected staging project reference and database host are non-empty and syntactically valid.
3. Parse the actual target host from the supplied connection information; never compare an unparsed connection string.
4. Obtain the actual project/database identity using a read-only connection and a reviewed identity query or Supabase API response.
5. Require exact equality between actual and expected staging project reference.
6. Require canonical, case-insensitive exact equality between actual and expected staging database host.
7. Require that neither actual nor expected project reference appears in the production project-reference denylist.
8. Require that neither actual nor expected host appears in the production database-host denylist.
9. Confirm the target project name/environment metadata visibly identifies `aadhyant-web-platform-staging-nonprod` or an explicitly approved successor.
10. Confirm the reviewed Git commit and migration checksums before reset or migration execution.

Only after every check succeeds may the guard emit a short-lived positive authorization result for the single requested operation. It must display only non-secret identity information.

## Mandatory refusal conditions

The guard must stop without running the requested mutation when:

- the branch is not `web-platform-development`;
- any expected identity, actual identity, allowlist, or denylist is missing;
- the project reference or host is unknown, malformed, redirected, or does not match exactly;
- more than one staging identity is configured;
- a production project reference or host is detected;
- the identity query cannot run or returns ambiguous results;
- the target contains production or unsanitized real data;
- migration checksums or the reviewed Git commit differ;
- a caller attempts to bypass, disable, or answer the guard interactively after failure.

Failure is closed: lack of proof that the target is staging is treated as proof that mutation is unsafe.

## Logging and secret safety

The guard may log the Git branch/commit, non-secret project name, masked project reference, canonical host, migration checksums, operation type, and pass/fail reason. It must never log database passwords, complete database URLs, access tokens, JWTs, secret/service-role keys, or production denylist contents.

Browser-visible staging URL and publishable key are not sufficient proof of database identity. Server-only credentials must never be accepted through chat, command history, committed files, or ordinary application logs.

## Scope

This specification applies to resets, migration application, seed/fixture loading, role-context tests that create data, and cleanup. Project creation/deletion, credential rotation, deployment, DNS, Meta configuration, and production access require separate authorization and are outside this guard.
