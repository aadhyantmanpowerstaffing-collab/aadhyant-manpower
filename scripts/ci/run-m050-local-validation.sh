#!/usr/bin/env bash
# Runs only against the disposable Supabase CLI local stack. It never links to
# a hosted project, reads hosted credentials, or invokes hosted migration APIs.
set -euo pipefail
umask 077
# Local validation neither needs nor emits Supabase CLI telemetry.
export SUPABASE_TELEMETRY_DISABLED=1

readonly EXPECTED_M050_SHA256="c7defc9fdef2e36e6753994f70942de476495f66f1e5aa29ce8a92e51f4a9596"
readonly EXPECTED_CHECKPOINT_SHA256="78881deb7e7d528052e216555e2ba779892d131bca1bffe9df96527569aef645"
readonly EXPECTED_SUPABASE_CLI_VERSION="2.111.0"
readonly CHECKPOINT_FILENAME="050_vacancy_candidate_terms_snapshot_test.sql"
readonly LOCAL_PROJECT_ID="aadhyant-m050-local-validation"
readonly PARENT_NONPROD_REF="zrluniaccvcdrvfwgrmj"
readonly PRODUCTION_PROJECT_REF="wsuctjhbqiedttfnwjvf"

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly RAW_OUTPUT="$(mktemp)"
readonly STATUS_ENV="$(mktemp)"
readonly LOCAL_WORKDIR="$(mktemp -d)"
LOCAL_DB_URL=""
STACK_STARTED=0

log() {
  printf '%s\n' "$*"
}

fail() {
  log "M050_LOCAL_RUNTIME_RESULT=FAIL"
  log "M050_LOCAL_RUNTIME_ERROR=$1"
  exit 1
}

cleanup() {
  local status=$?
  trap - EXIT
  rm -f "$RAW_OUTPUT" "$STATUS_ENV"
  if [[ "$STACK_STARTED" -eq 1 ]]; then
    # Scope cleanup to this harness project only; never use --all.
    if ! supabase --workdir "$LOCAL_WORKDIR" stop --no-backup > /dev/null 2>&1; then
      if [[ "$status" -eq 0 ]]; then
        log "M050_LOCAL_RUNTIME_RESULT=FAIL"
        log "M050_LOCAL_RUNTIME_ERROR=LOCAL_SUPABASE_CLEANUP_FAILED"
      fi
      status=1
    fi
  fi
  rm -rf "$LOCAL_WORKDIR"
  if [[ "$status" -eq 0 ]]; then
    log "LOCAL_SUPABASE_CLEANUP=COMPLETE"
  else
    log "LOCAL_SUPABASE_CLEANUP=ATTEMPTED"
  fi
  exit "$status"
}
trap cleanup EXIT

require_command() {
  command -v "$1" > /dev/null 2>&1 || fail "REQUIRED_COMMAND_MISSING:$1"
}

assert_empty_environment() {
  local variable
  for variable in \
    SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD SUPABASE_SERVICE_ROLE_KEY \
    SUPABASE_URL SUPABASE_PROJECT_REF DATABASE_URL \
    STAGING_SUPABASE_PUBLISHABLE_KEY STAGING_SUPABASE_PROJECT_REF STAGING_SUPABASE_URL \
    CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
    if [[ -n "${!variable:-}" ]]; then
      # Never print the value, even for a local-looking value.
      fail "HOSTED_OR_DEPLOYMENT_ENVIRONMENT_PRESENT:$variable"
    fi
  done
}

assert_local_config() {
  local config="$REPOSITORY_ROOT/supabase/config.toml"
  [[ -f "$config" ]] || fail "LOCAL_CONFIG_MISSING"
  grep -Fqx "project_id = \"$LOCAL_PROJECT_ID\"" "$config" || fail "LOCAL_PROJECT_ID_MISMATCH"
  if grep -Eqi "${PARENT_NONPROD_REF}|${PRODUCTION_PROJECT_REF}|\.supabase\.co|\.pooler\.supabase\.com|postgres(ql)?://" "$config"; then
    fail "HOSTED_TARGET_LITERAL_IN_LOCAL_CONFIG"
  fi
}

prepare_local_workdir() {
  # Start from config only: Supabase CLI must not discover repository migrations
  # before this harness explicitly applies schema.sql and 007 through 049.
  mkdir -p "$LOCAL_WORKDIR/supabase"
  cp "$REPOSITORY_ROOT/supabase/config.toml" "$LOCAL_WORKDIR/supabase/config.toml"
}

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

psql_file() {
  local file="$1" filename
  filename="$(basename "$file")"
  if [[ "$filename" == "$CHECKPOINT_FILENAME" ]]; then
    if ! psql "$LOCAL_DB_URL" -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -v SHOW_CONTEXT=errors -f "$file" > "$RAW_OUTPUT" 2>&1; then
      fail_checkpoint_sql "$filename"
    fi
  elif ! psql "$LOCAL_DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$file" > "$RAW_OUTPUT" 2>&1; then
    fail "SQL_FILE_FAILED:$filename"
  fi
}

is_allowed_checkpoint_phase() {
  case "${1:-}" in
    COMPENSATION_CADENCE|LEAVE_HOLIDAY|WORKING_WEEK|OVERTIME|CANTEEN|TRANSPORT|BENEFITS_SECURITY|EMPLOYMENT_TERMS|ACCOMMODATION_REGRESSION|COMPANY_OWNER_RPC|CONTRACTOR_OWNER_RPC|REPLAY_IDENTICAL|REPLAY_CHANGED_BASE|REPLAY_CHANGED_SCALAR|REPLAY_CHANGED_BENEFITS|REPLAY_CHANGED_BASE_AND_TERMS|MATERIAL_REVIEW_INITIAL_APPROVAL|MATERIAL_REVIEW_SCALAR_EDIT|MATERIAL_REVIEW_SCALAR_REAPPROVAL|MATERIAL_REVIEW_BENEFIT_EDIT|MATERIAL_REVIEW_BENEFIT_REAPPROVAL|CANDIDATE_PROJECTION|PENDING_REVIEW_EXCLUSION|LEGACY_COMPATIBILITY|FINAL_RESIDUE_PRE_ROLLBACK) return 0 ;;
    *) return 1 ;;
  esac
}

latest_checkpoint_phase() {
  local line phase latest="UNKNOWN"
  while IFS= read -r line; do
    if [[ "$line" =~ CHECKPOINT_050_PHASE=([A-Z0-9_]+) ]]; then
      phase="${BASH_REMATCH[1]}"
      if is_allowed_checkpoint_phase "$phase"; then
        latest="$phase"
      fi
    fi
  done < "$RAW_OUTPUT"
  printf '%s\n' "$latest"
}

checkpoint_sqlstate() {
  local sqlstate
  sqlstate="$(sed -nE 's/.*ERROR:[[:space:]]+([0-9A-Z]{5}):.*/\1/p' "$RAW_OUTPUT" | tail -n 1 || true)"
  if [[ "$sqlstate" =~ ^[0-9A-Z]{5}$ ]]; then
    printf '%s\n' "$sqlstate"
  else
    printf '%s\n' "UNAVAILABLE"
  fi
}

checkpoint_sql_error() {
  local marker
  marker="$(grep -oE 'CHECKPOINT_050_[A-Z0-9_]+' "$RAW_OUTPUT" | grep -v '^CHECKPOINT_050_PHASE' | tail -n 1 || true)"
  if [[ "$marker" =~ ^CHECKPOINT_050_[A-Z0-9_]+$ ]]; then
    printf 'CHECKPOINT_ASSERTION:%s\n' "$marker"
  else
    printf '%s\n' "REDACTED"
  fi
}

checkpoint_sql_context() {
  if grep -Eq 'CONTEXT:.*PL/pgSQL function inline_code_block line [0-9]+ at RAISE' "$RAW_OUTPUT"; then
    printf '%s\n' "PLPGSQL_INLINE_BLOCK"
  else
    printf '%s\n' "REDACTED"
  fi
}

fail_checkpoint_sql() {
  local filename="$1"
  log "M050_LOCAL_RUNTIME_RESULT=FAIL"
  log "M050_LOCAL_RUNTIME_ERROR=SQL_FILE_FAILED:$filename"
  log "M050_LOCAL_RUNTIME_CHECKPOINT_PHASE=$(latest_checkpoint_phase)"
  log "M050_LOCAL_RUNTIME_SQLSTATE=$(checkpoint_sqlstate)"
  log "M050_LOCAL_RUNTIME_SQL_ERROR=$(checkpoint_sql_error)"
  log "M050_LOCAL_RUNTIME_SQL_CONTEXT=$(checkpoint_sql_context)"
  exit 1
}

psql_scalar() {
  local label="$1"
  local statement="$2"
  local result
  psql "$LOCAL_DB_URL" -X -q -v ON_ERROR_STOP=1 -Atc "$statement" > "$RAW_OUTPUT" 2>&1 \
    || fail "SQL_ASSERTION_FAILED:$label"
  result="$(tr -d '[:space:]' < "$RAW_OUTPUT")"
  [[ "$result" == "t" ]] || fail "SQL_ASSERTION_FAILED:$label"
}

assert_local_db_url() {
  local endpoint host_port host
  endpoint="${LOCAL_DB_URL#*://}"
  endpoint="${endpoint#*@}"
  host_port="${endpoint%%/*}"
  host="${host_port%%:*}"
  if [[ "$host_port" == \[* ]]; then
    host="${host_port#\[}"
    host="${host%%\]*}"
  fi
  case "$host" in
    127.0.0.1|localhost|::1|'[::1') ;;
    *) fail "LOCAL_DB_HOST_REFUSED" ;;
  esac
  if [[ "$LOCAL_DB_URL" =~ $PARENT_NONPROD_REF|$PRODUCTION_PROJECT_REF|\.supabase\.co|\.pooler\.supabase\.com ]]; then
    fail "HOSTED_DB_TARGET_REFUSED"
  fi
}

discover_local_db_url() {
  local db_url_assignment
  supabase --workdir "$LOCAL_WORKDIR" status -o env > "$STATUS_ENV" 2> "$RAW_OUTPUT" || fail "LOCAL_SUPABASE_STATUS_FAILED"
  db_url_assignment="$(grep -m 1 '^DB_URL=' "$STATUS_ENV")" || fail "LOCAL_DB_URL_MISSING"
  LOCAL_DB_URL="${db_url_assignment#DB_URL=}"
  if [[ "$LOCAL_DB_URL" == \"*\" ]]; then
    LOCAL_DB_URL="${LOCAL_DB_URL#\"}"
    LOCAL_DB_URL="${LOCAL_DB_URL%\"}"
  elif [[ "$LOCAL_DB_URL" == \'*\' ]]; then
    LOCAL_DB_URL="${LOCAL_DB_URL#\'}"
    LOCAL_DB_URL="${LOCAL_DB_URL%\'}"
  fi
  [[ -n "$LOCAL_DB_URL" ]] || fail "LOCAL_DB_URL_MISSING"
  assert_local_db_url
}

main() {
  cd "$REPOSITORY_ROOT"
  assert_empty_environment
  assert_local_config
  prepare_local_workdir
  require_command docker
  require_command psql
  require_command sha256sum
  require_command supabase

  [[ "$(supabase --version)" == "$EXPECTED_SUPABASE_CLI_VERSION" ]] || fail "SUPABASE_CLI_VERSION_MISMATCH"
  docker info > /dev/null 2>&1 || fail "DOCKER_DAEMON_UNAVAILABLE"

  # The harness owns only this deterministic disposable local project.
  supabase --workdir "$LOCAL_WORKDIR" stop --no-backup > /dev/null 2>&1 || true
  # Enable the EXIT trap before start because a partial CLI startup can create
  # local containers or volumes that must still be removed.
  STACK_STARTED=1
  supabase --workdir "$LOCAL_WORKDIR" start > "$RAW_OUTPUT" 2>&1 || fail "LOCAL_SUPABASE_START_FAILED"
  discover_local_db_url

  psql_scalar "CLEAN_APPLICATION_BASELINE" "select to_regclass('public.employer_requirements') is null and to_regclass('public.platform_users') is null and to_regclass('private.contractor_vacancy_submission_requests') is null and to_regclass('private.vacancy_candidate_benefits') is null;"

  psql_file "supabase/schema.sql"
  psql_scalar "SCHEMA_BASE_OBJECTS" "select to_regclass('public.employer_requirements') is not null and to_regclass('public.candidates') is not null and to_regclass('public.admin_users') is not null and to_regprocedure('private.is_admin()') is not null;"

  local number prefix matches file
  shopt -s nullglob
  for number in $(seq 7 49); do
    printf -v prefix '%03d' "$number"
    matches=("supabase/migrations/${prefix}_"*.sql)
    [[ "${#matches[@]}" -eq 1 ]] || fail "MIGRATION_SEQUENCE_AMBIGUOUS_OR_MISSING:$prefix"
    file="${matches[0]}"
    log "LOCAL_MIGRATION_APPLY=$(basename "$file")"
    psql_file "$file"
  done
  shopt -u nullglob

  psql_scalar "M049_BASELINE" "select to_regclass('private.contractor_vacancy_submission_requests') is not null and to_regprocedure('private.assert_contractor_expected_joining_date(date)') is not null and exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='manage_contractor_portal_vacancy' and 'p_submission_idempotency_key'=any(p.proargnames)) and exists(select 1 from pg_attribute where attrelid='public.employer_requirements'::regclass and attname='basic_da' and not attisdropped) and to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is not null and to_regclass('private.vacancy_candidate_benefits') is null and not exists(select 1 from pg_attribute where attrelid='public.employer_requirements'::regclass and attname='compensation_cadence' and not attisdropped);"

  local migration checkpoint
  migration="supabase/migrations/050_vacancy_candidate_terms_snapshot.sql"
  checkpoint="supabase/tests/050_vacancy_candidate_terms_snapshot_test.sql"
  [[ "$(sha256_file "$migration")" == "$EXPECTED_M050_SHA256" ]] || fail "M050_SHA256_MISMATCH"
  [[ "$(sha256_file "$checkpoint")" == "$EXPECTED_CHECKPOINT_SHA256" ]] || fail "CHECKPOINT_SHA256_MISMATCH"

  psql_file "$migration"
  psql_scalar "M050_POST_APPLY" "select exists(select 1 from pg_attribute where attrelid='public.employer_requirements'::regclass and attname='compensation_cadence' and not attisdropped) and to_regclass('private.vacancy_candidate_benefits') is not null and to_regprocedure('private.apply_vacancy_candidate_terms(uuid,jsonb)') is not null and exists(select 1 from pg_class where oid='private.vacancy_candidate_benefits'::regclass and relrowsecurity) and not has_table_privilege('anon','private.vacancy_candidate_benefits','select') and not has_table_privilege('authenticated','private.vacancy_candidate_benefits','select') and to_regclass('private.contractor_vacancy_submission_requests') is not null;"

  psql_file "$checkpoint"
  psql_scalar "CHECKPOINT_SYNTHETIC_RESIDUE_ZERO" "select not exists(select 1 from auth.users where email like 'm50-%@test.invalid') and not exists(select 1 from public.platform_users where display_name like 'M50 %') and not exists(select 1 from public.companies where legal_name like 'M50 %') and not exists(select 1 from public.contractors where agency_name like 'M50 %') and not exists(select 1 from public.candidates where full_name like 'M50 %') and not exists(select 1 from public.employer_requirements where requirement_code like 'M50-%' or job_role like 'M50 %') and not exists(select 1 from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id where r.requirement_code like 'M50-%' or r.job_role like 'M50 %') and not exists(select 1 from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id where r.requirement_code like 'M50-%' or r.job_role like 'M50 %') and not exists(select 1 from public.application_stage_history h join public.candidate_applications a on a.id=h.application_id join public.employer_requirements r on r.id=a.requirement_id where r.requirement_code like 'M50-%' or r.job_role like 'M50 %') and not exists(select 1 from public.audit_logs l where l.actor_user_id::text like '50000000-0000-0000-%' or l.entity_id in (select id from public.employer_requirements where requirement_code like 'M50-%' or job_role like 'M50 %')) and not exists(select 1 from private.vacancy_candidate_benefits b join public.employer_requirements r on r.id=b.requirement_id where r.requirement_code like 'M50-%' or r.job_role like 'M50 %') and not exists(select 1 from private.contractor_vacancy_submission_requests where actor_user_id::text like '50000000-0000-0000-%') and not exists(select 1 from private.contractor_vacancy_submission_term_requests where actor_user_id::text like '50000000-0000-0000-%');"

  local postgres_version
  postgres_version="$(psql "$LOCAL_DB_URL" -X -q -Atc 'show server_version;' 2> "$RAW_OUTPUT")" || fail "POSTGRES_VERSION_QUERY_FAILED"
  log "M050_LOCAL_RUNTIME_RESULT=PASS"
  log "RUNNER_OS=$(uname -s)"
  log "SUPABASE_CLI_VERSION=$EXPECTED_SUPABASE_CLI_VERSION"
  log "POSTGRES_VERSION=$postgres_version"
  log "SCHEMA_BOOTSTRAP=PASS"
  log "M049_BASELINE=PASS"
  log "M050_SHA256=VERIFIED"
  log "CHECKPOINT_SHA256=VERIFIED"
  log "EXACT_M050_APPLY=PASS"
  log "CHECKPOINT=PASS"
  log "M050_LOCAL_RUNTIME_CHECKPOINT=PASS"
  log "SYNTHETIC_RESIDUE=ZERO"
}

main "$@"
