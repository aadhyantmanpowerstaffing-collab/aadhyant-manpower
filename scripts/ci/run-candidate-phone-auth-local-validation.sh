#!/usr/bin/env bash
# Rehearses the production migration chain on a disposable, unlinked local Supabase
# stack. This script never connects to a hosted Supabase project.
set -euo pipefail
umask 077
export SUPABASE_TELEMETRY_DISABLED=1

readonly EXPECTED_SUPABASE_CLI_VERSION="2.111.0"
readonly TARGET_MIGRATION="supabase/migrations/20261104190000_candidate_whatsapp_otp_account.sql"
readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly RAW_OUTPUT="$(mktemp)"
readonly STATUS_ENV="$(mktemp)"
readonly LOCAL_WORKDIR="$(mktemp -d)"
LOCAL_DB_URL=""
STACK_STARTED=0

log(){ printf '%s\n' "$*"; }
fail(){ log "CANDIDATE_OTP_LOCAL_RESULT=FAIL"; log "CANDIDATE_OTP_LOCAL_ERROR=$1"; exit 1; }

cleanup(){
  local status=$?
  trap - EXIT
  rm -f "$RAW_OUTPUT" "$STATUS_ENV"
  if [[ "$STACK_STARTED" -eq 1 ]]; then
    if ! supabase --workdir "$LOCAL_WORKDIR" stop --no-backup > /dev/null 2>&1; then
      [[ "$status" -ne 0 ]] || { log "CANDIDATE_OTP_LOCAL_RESULT=FAIL"; log "CANDIDATE_OTP_LOCAL_ERROR=LOCAL_SUPABASE_CLEANUP_FAILED"; }
      status=1
    fi
  fi
  rm -rf "$LOCAL_WORKDIR"
  [[ "$status" -eq 0 ]] && log "LOCAL_SUPABASE_CLEANUP=COMPLETE" || log "LOCAL_SUPABASE_CLEANUP=ATTEMPTED"
  exit "$status"
}
trap cleanup EXIT

require_command(){ command -v "$1" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_MISSING:$1"; }

assert_no_hosted_environment(){
  local variable
  for variable in SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD SUPABASE_SERVICE_ROLE_KEY SUPABASE_URL SUPABASE_PROJECT_REF DATABASE_URL STAGING_SUPABASE_PUBLISHABLE_KEY STAGING_SUPABASE_PROJECT_REF STAGING_SUPABASE_URL CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
    [[ -z "${!variable:-}" ]] || fail "HOSTED_OR_DEPLOYMENT_ENVIRONMENT_PRESENT:$variable"
  done
}

assert_local_url(){
  local endpoint host_port host
  endpoint="${LOCAL_DB_URL#*://}"
  endpoint="${endpoint#*@}"
  host_port="${endpoint%%/*}"
  host="${host_port%%:*}"
  if [[ "$host_port" == \\[* ]]; then host="${host#\\[}"; host="${host%%\\]*}"; fi
  case "$host" in 127.0.0.1|localhost|::1|'[::1') ;; *) fail "LOCAL_DB_HOST_REFUSED";; esac
  [[ ! "$LOCAL_DB_URL" =~ \.supabase\.co|\.pooler\.supabase\.com|wsuctjhbqiedttfnwjvf ]] || fail "HOSTED_DB_TARGET_REFUSED"
}

psql_file(){
  local file="$1"
  if ! psql "$LOCAL_DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$file" >"$RAW_OUTPUT" 2>&1; then
    # Never echo SQL, row contents, credentials, or arbitrary database error text.
    fail "SQL_FILE_FAILED:$(basename "$file")"
  fi
}

psql_assert(){
  local label="$1" sql="$2" result
  if ! psql "$LOCAL_DB_URL" -X -q -At -v ON_ERROR_STOP=1 -c "$sql" >"$RAW_OUTPUT" 2>&1; then fail "SQL_ASSERTION_QUERY_FAILED:$label"; fi
  result="$(tr -d '[:space:]' <"$RAW_OUTPUT")"
  [[ "$result" == "t" ]] || fail "SQL_ASSERTION_FAILED:$label"
}

main(){
  cd "$REPOSITORY_ROOT"
  assert_no_hosted_environment
  require_command docker
  require_command psql
  require_command supabase
  [[ "$(supabase --version)" == "$EXPECTED_SUPABASE_CLI_VERSION" ]] || fail "SUPABASE_CLI_VERSION_MISMATCH"
  docker info >/dev/null 2>&1 || fail "DOCKER_DAEMON_UNAVAILABLE"
  [[ -f "supabase/config.toml" && -f "$TARGET_MIGRATION" ]] || fail "LOCAL_CONFIG_OR_TARGET_MIGRATION_MISSING"

  mkdir -p "$LOCAL_WORKDIR/supabase"
  cp supabase/config.toml "$LOCAL_WORKDIR/supabase/config.toml"
  # The local harness project ID is deliberately unique and contains no hosted ref.
  sed -i 's/^project_id = .*/project_id = "aadhyant-candidate-otp-local-validation"/' "$LOCAL_WORKDIR/supabase/config.toml"
  grep -Fqx 'project_id = "aadhyant-candidate-otp-local-validation"' "$LOCAL_WORKDIR/supabase/config.toml" || fail "LOCAL_PROJECT_ID_MISMATCH"
  if grep -Eqi 'wsuctjhbqiedttfnwjvf|zrluniaccvcdrvfwgrmj|\.supabase\.co|\.pooler\.supabase\.com|postgres(ql)?://' "$LOCAL_WORKDIR/supabase/config.toml"; then fail "HOSTED_TARGET_LITERAL_IN_LOCAL_CONFIG"; fi

  STACK_STARTED=1
  supabase --workdir "$LOCAL_WORKDIR" start >"$RAW_OUTPUT" 2>&1 || fail "LOCAL_SUPABASE_START_FAILED"
  supabase --workdir "$LOCAL_WORKDIR" status -o env >"$STATUS_ENV" 2>"$RAW_OUTPUT" || fail "LOCAL_SUPABASE_STATUS_FAILED"
  local assignment
  assignment="$(grep -m1 '^DB_URL=' "$STATUS_ENV")" || fail "LOCAL_DB_URL_MISSING"
  LOCAL_DB_URL="${assignment#DB_URL=}"
  LOCAL_DB_URL="${LOCAL_DB_URL%\"}"
  LOCAL_DB_URL="${LOCAL_DB_URL#\"}"
  assert_local_url

  log "LOCAL_BASELINE=apply schema.sql"
  psql_file "supabase/schema.sql"

  local number prefix matches file
  shopt -s nullglob
  for number in $(seq 7 50); do
    printf -v prefix '%03d' "$number"
    matches=("supabase/migrations/${prefix}_"*.sql)
    [[ "${#matches[@]}" -eq 1 ]] || fail "NUMBERED_MIGRATION_SEQUENCE_MISSING_OR_AMBIGUOUS:$prefix"
    file="${matches[0]}"
    log "LOCAL_MIGRATION_APPLY=$(basename "$file")"
    psql_file "$file"
  done
  shopt -u nullglob

  # The historical WhatsApp baseline is a test-only fixture already used by
  # the PGlite regression suite. It restores the exact expected send-guard body;
  # the following production migration's hash assertion remains unchanged.
  psql_file "tests/fixtures/sharing-send-guard-baseline.sql"
  psql_assert "HISTORICAL_SEND_GUARD_BASELINE" "select md5(pg_get_functiondef('private.whatsapp_vacancy_send_eligible(uuid)'::regprocedure))='aa855103a4239ea9c453a343fd2e7175';"

  # Reconstruct the current application schema in filename order, without hosted history. in filename order, without hosted history.
  local applied_date_count=0
  while IFS= read -r file; do
    [[ "$file" == "$TARGET_MIGRATION" ]] && break
    log "LOCAL_MIGRATION_APPLY=$(basename "$file")"
    psql_file "$file"
    applied_date_count=$((applied_date_count+1))
  done < <(find supabase/migrations -maxdepth 1 -type f -name '202*.sql' -print | sort)
  [[ "$applied_date_count" -gt 0 ]] || fail "DATE_MIGRATION_CHAIN_EMPTY"

  log "LOCAL_MIGRATION_APPLY=$(basename "$TARGET_MIGRATION")"
  psql_file "$TARGET_MIGRATION"

  psql_assert "FEATURE_GATE_DEFAULT_OFF" "select count(*)=1 and bool_and(enabled is false) from private.candidate_phone_auth_config;"
  psql_assert "PRIVATE_LEDGER_RLS_AND_NO_CLIENT_ACCESS" "select c.relrowsecurity and not has_table_privilege('anon','private.candidate_phone_auth_deliveries','select') and not has_table_privilege('authenticated','private.candidate_phone_auth_deliveries','select') and not has_table_privilege('service_role','private.candidate_phone_auth_deliveries','select') from pg_class c where c.oid='private.candidate_phone_auth_deliveries'::regclass;"
  psql_assert "PUBLIC_STATUS_REPORTS_DISABLED" "select public.get_candidate_phone_auth_status() is false;"
  psql_assert "DELIVERY_CLAIM_SERVICE_ROLE_ONLY" "select has_function_privilege('service_role','public.claim_candidate_phone_auth_delivery(text,uuid,text)','execute') and not has_function_privilege('anon','public.claim_candidate_phone_auth_delivery(text,uuid,text)','execute') and not has_function_privilege('authenticated','public.claim_candidate_phone_auth_delivery(text,uuid,text)','execute');"
  psql_assert "DELIVERY_FINISH_SERVICE_ROLE_ONLY" "select has_function_privilege('service_role','public.finish_candidate_phone_auth_delivery(text,uuid,boolean)','execute') and not has_function_privilege('anon','public.finish_candidate_phone_auth_delivery(text,uuid,boolean)','execute') and not has_function_privilege('authenticated','public.finish_candidate_phone_auth_delivery(text,uuid,boolean)','execute');"
  psql_assert "REGISTRATION_WRAPPER_GRANTS_PRESERVED" "select has_function_privilege('anon','public.submit_whatsapp_registration_form(text,jsonb,jsonb)','execute') and has_function_privilege('authenticated','public.submit_whatsapp_registration_form(text,jsonb,jsonb)','execute');"
  psql_assert "ALL_NEW_SECURITY_DEFINER_FUNCTIONS_PIN_SEARCH_PATH" "select count(*)=5 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('get_candidate_phone_auth_status','claim_candidate_phone_auth_delivery','finish_candidate_phone_auth_delivery','submit_whatsapp_registration_form') or n.nspname='private' and p.proname='bind_whatsapp_candidate_phone_account') and p.prosecdef and p.proconfig @> array['search_path=""'];"
  psql_assert "PRIVATE_BIND_FUNCTION_NOT_CLIENT_EXECUTABLE" "select not has_function_privilege('anon','private.bind_whatsapp_candidate_phone_account(text)','execute') and not has_function_privilege('authenticated','private.bind_whatsapp_candidate_phone_account(text)','execute');"
  psql_assert "OTP_LEDGER_EMPTY" "select count(*)=0 from private.candidate_phone_auth_deliveries;"

  local postgres_version
  postgres_version="$(psql "$LOCAL_DB_URL" -X -q -At -c 'show server_version;' 2>"$RAW_OUTPUT")" || fail "POSTGRES_VERSION_QUERY_FAILED"
  log "CANDIDATE_OTP_LOCAL_RESULT=PASS"
  log "SUPABASE_CLI_VERSION=$EXPECTED_SUPABASE_CLI_VERSION"
  log "POSTGRES_VERSION=$postgres_version"
  log "DATE_MIGRATIONS_APPLIED=$applied_date_count"
  log "EXACT_CANDIDATE_OTP_MIGRATION=PASS"
  log "FEATURE_GATE=OFF"
  log "PRIVATE_LEDGER_AND_GRANTS=PASS"
  log "SECURITY_DEFINER_SEARCH_PATH=PASS"
  log "OTP_LEDGER=EMPTY"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
