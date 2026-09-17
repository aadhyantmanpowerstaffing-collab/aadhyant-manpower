# Production pre-M050 reconciliation runbook

This manual artifact reconciles the audited Production drift before applying
the separately reviewed M049 and M050 migrations. It is not an automatic
migration and must never be included in normal migration discovery.

## Scope and order

1. Obtain a fresh, approved backup/restore point and record its immutable
   evidence.
2. Independently run the repository production target guard, TLS identity
   check, source hash/manifest check, and the catalog preflight that produced
   the documented two-row lifecycle mapping.
3. In one controlled `psql -X -v ON_ERROR_STOP=1` session, execute
   `SET app.pre_m050_reconciliation_approved = 'yes';` and then execute
   `supabase/production/pre_m050_production_reconciliation.sql`. The file
   owns its own `BEGIN`/`COMMIT`; do not wrap it in another transaction and do
   not stream it through an interactive password prompt.
4. If any preflight, collision, constraint, security, or postflight assertion
   fails, stop. The transaction rolls back; do not repair objects manually or
   replay historical migrations.
5. After a successful commit, run the read-only postflight inventory and the
   disposable/static checkpoint. Confirm M049 and M050 artifacts are absent.
6. Obtain a separate approval to apply M049 unchanged, verify it, then a
   separate approval to apply M050 unchanged.

## Historical lifecycle mapping encoded by the artifact

The artifact permits exactly two existing requirements, matched only by their
audited lifecycle predicates. It intentionally contains no requirement code,
record ID, person, or organization name.

- One `in_progress/open/public` row with `published_at` is mapped to
  `review_status = approved`. Its publication timestamp and source attribution
  remain unchanged; no reviewer identity or historical review time is made up.
- One `new/draft/private` row without `published_at` is mapped to
  `review_status = draft`. It remains non-public and no submission/review/
  publication metadata is made up.

Any deviation is a fail-closed stop condition requiring a new operator mapping
decision and source review.

## Security invariants

- The reconciler never grants direct browser writes to applications or
  joinings. It preserves authenticated read access and removes only the
  audited M7 create/update policies and table grants.
- New privileged functions use `SECURITY DEFINER SET search_path = ''`, revoke
  `PUBLIC`/`anon` access, and grant only the documented `authenticated` owner
  RPCs.
- Private helpers and later M049/M050 ledgers are not browser executable.
- The existing Contractor management/listing and anonymous interest contracts
  are not replaced. The Contractor list must match the exact reviewed M046
  result-column contract, SECURITY DEFINER/empty-search-path posture, and
  authenticated-only execution boundary; any mismatch stops the transaction.
- The reconciliation installs the reviewed M039 Admin review list/detail and
  Company review queue, plus the reviewed M046 Company/Contractor owner detail
  projections. These are owner/reviewer RPCs only; they do not grant table
  access or change Candidate visibility.
- M045 lifecycle transitions write canonical `audit_logs` events in the same
  transaction as the lifecycle mutation. Audit records remain internal and are
  not granted as browser write endpoints.

## Required postflight evidence

Record only catalog/aggregate evidence showing M037 validation, M038 direct
write hardening, M039 eligibility/review list/detail/owner-review surfaces,
M043 Company management RPC, M044 columns/constraints/private helpers, M045
atomic audit behavior, M046 Company and Contractor list/detail projections,
and the exact M048 Contractor shape. Prove M049's ledger, idempotent overload,
and joining-date trigger remain absent, as do all M050 terms/benefit artifacts.

## Rollback and recovery

The reconciler is one explicit transaction. Any error before its final commit
rolls back all changes. After commit, do not attempt ad-hoc reverse DDL: stop,
preserve sanitized evidence, and use the reviewed backup/restore plan and a
separately approved corrective artifact.
