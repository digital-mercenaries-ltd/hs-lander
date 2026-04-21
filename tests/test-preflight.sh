#!/usr/bin/env bash
# test-preflight.sh — Validates scripts/preflight.sh reports config, credential,
# and HubSpot API readiness correctly without leaking tokens.
# Local only. Mocks `security`, `curl`, `dig` via a PATH-prefixed bin directory.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-preflight.sh ==="

assert_file_exists "$REPO_DIR/scripts/preflight.sh" "scripts/preflight.sh exists"

# Contract: preflight always emits these 10 PREFLIGHT_<KEY>= lines regardless
# of state, so the skill can parse a complete output. Partial output (e.g.
# from a script crash mid-stream) would make the skill see an incomplete
# picture and coach the user wrongly — this assertion catches that regression
# class.
PREFLIGHT_CONTRACT_KEYS=(
  PREFLIGHT_PROJECT_POINTER
  PREFLIGHT_ACCOUNT_PROFILE
  PREFLIGHT_PROJECT_PROFILE
  PREFLIGHT_CREDENTIAL
  PREFLIGHT_API_ACCESS
  PREFLIGHT_SCOPES
  PREFLIGHT_PROJECT_SOURCE
  PREFLIGHT_DNS
  PREFLIGHT_GA4
  PREFLIGHT_FORM_IDS
)
assert_full_contract() {
  local log="$1" scenario="$2"
  local key
  for key in "${PREFLIGHT_CONTRACT_KEYS[@]}"; do
    assert_file_contains "$log" "^${key}=" "[$scenario] ${key}= line present"
  done
}

# --- Shared setup helpers ---

# Distinctive high-entropy token so partial-leak patterns (truncation,
# encoding) are more likely to trip the grep-based assertion. Built from
# $RANDOM rather than /dev/urandom to avoid SIGPIPE against `pipefail`.
MOCK_TOKEN="hslt_$(printf '%04x%04x%04x%04x%04x%04x%04x%04x%04x%04x' \
  $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM \
  $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM)"

# Create a self-contained test environment: fake HOME with account+project config,
# a project dir containing preflight.sh, and a mock bin dir.
setup_env() {
  local dir
  dir=$(mktemp -d)
  mkdir -p \
    "$dir/project/scripts" \
    "$dir/home/.config/hs-lander/testacct" \
    "$dir/mock-bin"
  cp "$REPO_DIR/scripts/preflight.sh" "$dir/project/scripts/preflight.sh"
  chmod +x "$dir/project/scripts/preflight.sh"
  printf '%s' "$dir"
}

# Writes account config. Callers can override via `CFG_*="" write_account_config dir`
# to test empty values — use `${VAR-default}` (no colon) so an explicitly-empty
# caller override passes through rather than being reset to the default.
write_account_config() {
  local dir="$1"
  local portal_id="${CFG_HUBSPOT_PORTAL_ID-12345678}"
  local region="${CFG_HUBSPOT_REGION-eu1}"
  local domain_pattern="${CFG_DOMAIN_PATTERN-*.example.com}"
  local service="${CFG_HUBSPOT_TOKEN_KEYCHAIN_SERVICE-test-hubspot-access-token}"
  cat > "$dir/home/.config/hs-lander/testacct/config.sh" <<EOF
HUBSPOT_PORTAL_ID="$portal_id"
HUBSPOT_REGION="$region"
DOMAIN_PATTERN="$domain_pattern"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="$service"
EOF
}

write_project_config() {
  local dir="$1"
  local slug="${CFG_PROJECT_SLUG-testproj}"
  local domain="${CFG_DOMAIN-testproj.example.com}"
  local dm_path="${CFG_DM_UPLOAD_PATH-/testproj}"
  local ga4="${CFG_GA4_MEASUREMENT_ID-G-TESTMEAS}"
  local capture="${CFG_CAPTURE_FORM_ID-form-abc123}"
  local survey="${CFG_SURVEY_FORM_ID-}"
  local list="${CFG_LIST_ID-list-def456}"
  cat > "$dir/home/.config/hs-lander/testacct/testproj.sh" <<EOF
PROJECT_SLUG="$slug"
DOMAIN="$domain"
DM_UPLOAD_PATH="$dm_path"
GA4_MEASUREMENT_ID="$ga4"
CAPTURE_FORM_ID="$capture"
SURVEY_FORM_ID="$survey"
LIST_ID="$list"
EOF
}

write_project_sourcing_chain() {
  local dir="$1"
  cat > "$dir/project/project.config.sh" <<'EOF'
HS_LANDER_ACCOUNT="testacct"
HS_LANDER_PROJECT="testproj"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
EOF
}

write_mock_bin() {
  local dir="$1"
  # Use ${2-default} (no colon) so callers passing "" get an empty token,
  # not the default — matches the pattern used by write_account_config.
  local token="${2-$MOCK_TOKEN}"
  # Mock `security`: echo the token iff -s matches the expected service.
  cat > "$dir/mock-bin/security" <<MOCK
#!/usr/bin/env bash
service=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -s) service="\$2"; shift 2 ;;
    *)  shift ;;
  esac
done
if [[ "\$service" == "test-hubspot-access-token" ]]; then
  echo "$token"
  exit 0
fi
exit 1
MOCK
  chmod +x "$dir/mock-bin/security"

  # Mock `curl`: parse URL, -o output-file, and -X method out of the arg
  # list. Return a per-endpoint HTTP code (env var) and optionally write
  # a JSON body to the -o file (for the scopes-introspection endpoint).
  # Supports exit-code simulation for the "unreachable" scenario.
  #
  # Env vars (all optional):
  #   MOCK_CURL_ACCOUNT_INFO_CODE   default 200 — /account-info/v3/details
  #   MOCK_CURL_PROJECT_SOURCE_CODE default 200 — /crm/v3/properties/contacts/project_source
  #   MOCK_CURL_SCOPES_CODE         default 200 — /oauth/v2/private-apps/get/access-token-info
  #   MOCK_CURL_SCOPES_LIST         comma-list of granted scopes (default: all 7 required)
  #   MOCK_CURL_SCOPES_BODY         raw JSON body (overrides SCOPES_LIST)
  #   MOCK_CURL_FAIL                non-zero exit code to simulate curl failure (e.g. 6 for DNS fail)
  cat > "$dir/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
url=""
output_file=""
prev=""
for arg in "$@"; do
  case "$prev" in
    -o) output_file="$arg" ;;
  esac
  case "$arg" in
    https://*) url="$arg" ;;
  esac
  prev="$arg"
done

# Simulate curl exit failure (e.g. DNS or TLS failure). Still emit 000
# as real curl does with -w "%{http_code}" when no HTTP response came back.
if [[ -n "${MOCK_CURL_FAIL:-}" ]]; then
  echo "000"
  exit "$MOCK_CURL_FAIL"
fi

endpoint=""
case "$url" in
  *"/account-info/v3/details"*)                         endpoint="account_info" ;;
  *"/crm/v3/properties/contacts/project_source"*)       endpoint="project_source" ;;
  *"/oauth/v2/private-apps/get/access-token-info"*)     endpoint="scopes" ;;
esac

code="200"
case "$endpoint" in
  account_info)    code="${MOCK_CURL_ACCOUNT_INFO_CODE:-200}" ;;
  project_source)  code="${MOCK_CURL_PROJECT_SOURCE_CODE:-200}" ;;
  scopes)          code="${MOCK_CURL_SCOPES_CODE:-200}" ;;
esac

# Write body to -o file for endpoints that carry meaningful bodies.
if [[ -n "$output_file" && "$output_file" != "/dev/null" && "$endpoint" == "scopes" ]]; then
  if [[ -n "${MOCK_CURL_SCOPES_BODY:-}" ]]; then
    printf '%s' "$MOCK_CURL_SCOPES_BODY" > "$output_file"
  else
    default_list="crm.objects.contacts.read,crm.objects.contacts.write,crm.schemas.contacts.write,crm.lists.read,crm.lists.write,forms,content"
    list="${MOCK_CURL_SCOPES_LIST:-$default_list}"
    # Convert comma-list to JSON array body.
    json_list=$(printf '"%s"' "$list" | sed 's/,/","/g')
    printf '{"scopes":[%s]}' "$json_list" > "$output_file"
  fi
fi

echo "$code"
exit 0
MOCK
  chmod +x "$dir/mock-bin/curl"

  # Mock `dig`: echo a fake IP by default; empty if MOCK_DIG_EMPTY is set.
  cat > "$dir/mock-bin/dig" <<'MOCK'
#!/usr/bin/env bash
if [[ -n "${MOCK_DIG_EMPTY:-}" ]]; then
  exit 0
fi
echo "93.184.216.34"
exit 0
MOCK
  chmod +x "$dir/mock-bin/dig"
}

run_preflight_capture() {
  # $1: env dir, $2: output log path. Returns preflight's exit code via echo-trick.
  # Caller can set any MOCK_CURL_* env var before calling to control the
  # mock curl's per-endpoint response, scopes body, or simulated exit failure.
  local dir="$1" log="$2"
  HOME="$dir/home" PATH="$dir/mock-bin:$PATH" \
    MOCK_CURL_ACCOUNT_INFO_CODE="${MOCK_CURL_ACCOUNT_INFO_CODE:-200}" \
    MOCK_CURL_PROJECT_SOURCE_CODE="${MOCK_CURL_PROJECT_SOURCE_CODE:-200}" \
    MOCK_CURL_SCOPES_CODE="${MOCK_CURL_SCOPES_CODE:-200}" \
    MOCK_CURL_SCOPES_LIST="${MOCK_CURL_SCOPES_LIST-}" \
    MOCK_CURL_SCOPES_BODY="${MOCK_CURL_SCOPES_BODY-}" \
    MOCK_CURL_FAIL="${MOCK_CURL_FAIL-}" \
    MOCK_DIG_EMPTY="${MOCK_DIG_EMPTY-}" \
    bash "$dir/project/scripts/preflight.sh" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: complete config → all ok, exit 0 ---

echo ""
echo "--- Scenario 1: complete config ---"
TMP1=$(setup_env)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}"' EXIT
write_account_config "$TMP1"
write_project_config "$TMP1"
write_project_sourcing_chain "$TMP1"
write_mock_bin "$TMP1"
LOG1="$TMP1/preflight.log"
# shellcheck disable=SC2155
exit1=$(run_preflight_capture "$TMP1" "$LOG1" || true)
assert_equal "$exit1" "0" "exit code 0 when all checks pass"
assert_file_contains "$LOG1" "PREFLIGHT_CREDENTIAL=found" "credential found"
assert_file_contains "$LOG1" "PREFLIGHT_API_ACCESS=ok" "API access ok"
assert_file_contains "$LOG1" "PREFLIGHT_DNS=ok" "DNS check ok"
assert_full_contract "$LOG1" "Scenario 1"

# --- Scenario 2: HUBSPOT_TOKEN_KEYCHAIN_SERVICE empty in account config →
#     ACCOUNT_PROFILE=incomplete → CREDENTIAL=skipped (account is root cause).
#     We reserve CREDENTIAL=missing for the case where the account profile
#     is OK but the Keychain entry doesn't exist — see Scenario M.

echo ""
echo "--- Scenario 2: HUBSPOT_TOKEN_KEYCHAIN_SERVICE empty in account config ---"
TMP2=$(setup_env)
CFG_HUBSPOT_TOKEN_KEYCHAIN_SERVICE="" write_account_config "$TMP2"
write_project_config "$TMP2"
write_project_sourcing_chain "$TMP2"
write_mock_bin "$TMP2"
LOG2="$TMP2/preflight.log"
exit2=$(run_preflight_capture "$TMP2" "$LOG2" || true)
assert_equal "$exit2" "1" "exit 1 when account config has empty HUBSPOT_TOKEN_KEYCHAIN_SERVICE"
assert_file_contains "$LOG2" "PREFLIGHT_ACCOUNT_PROFILE=incomplete" "account profile reported incomplete"
assert_file_contains "$LOG2" "PREFLIGHT_CREDENTIAL=skipped" "credential reported skipped (not missing) when root cause is account profile"

# --- Scenario 3: empty GA4_MEASUREMENT_ID → warn, exit 0 ---

echo ""
echo "--- Scenario 3: empty GA4_MEASUREMENT_ID ---"
TMP3=$(setup_env)
write_account_config "$TMP3"
CFG_GA4_MEASUREMENT_ID="" write_project_config "$TMP3"
write_project_sourcing_chain "$TMP3"
write_mock_bin "$TMP3"
LOG3="$TMP3/preflight.log"
exit3=$(run_preflight_capture "$TMP3" "$LOG3" || true)
assert_equal "$exit3" "0" "exit code 0 when only warnings present"
assert_file_contains "$LOG3" "PREFLIGHT_GA4=warn" "GA4 reported warn when empty"

# --- Scenario 4: empty CAPTURE_FORM_ID → warn, exit 0 ---

echo ""
echo "--- Scenario 4: empty CAPTURE_FORM_ID ---"
TMP4=$(setup_env)
write_account_config "$TMP4"
CFG_CAPTURE_FORM_ID="" write_project_config "$TMP4"
write_project_sourcing_chain "$TMP4"
write_mock_bin "$TMP4"
LOG4="$TMP4/preflight.log"
exit4=$(run_preflight_capture "$TMP4" "$LOG4" || true)
assert_equal "$exit4" "0" "exit code 0 with form-IDs warning"
assert_file_contains "$LOG4" "PREFLIGHT_FORM_IDS=warn" "form IDs reported warn when CAPTURE_FORM_ID empty"

# --- Scenario 5: token must never appear in output ---

echo ""
echo "--- Scenario 5: credential safety (token does not leak) ---"
TMP5=$(setup_env)
write_account_config "$TMP5"
write_project_config "$TMP5"
write_project_sourcing_chain "$TMP5"
write_mock_bin "$TMP5"
LOG5="$TMP5/preflight.log"
run_preflight_capture "$TMP5" "$LOG5" >/dev/null || true
assert_file_not_contains "$LOG5" "$MOCK_TOKEN" "mock token does not appear in preflight output"

# Also check that bash -x xtrace output doesn't leak the token — preflight
# should wrap the curl calls in a set +x guard.
LOG5X="$TMP5/preflight-xtrace.log"
HOME="$TMP5/home" PATH="$TMP5/mock-bin:$PATH" \
  MOCK_CURL_ACCOUNT_INFO_CODE=200 MOCK_CURL_PROJECT_SOURCE_CODE=200 \
  bash -x "$TMP5/project/scripts/preflight.sh" >"$LOG5X" 2>&1 || true
assert_file_not_contains "$LOG5X" "$MOCK_TOKEN" "mock token does not leak in bash -x xtrace output"

# --- Scenario 6: project_source 404 (first project on account) → non-blocking ---
# The plan treats this as an expected, recoverable state: the skill should
# detect it and run the account-setup module, then re-preflight. Therefore
# preflight must report it but NOT set exit 1.

echo ""
echo "--- Scenario 6: project_source 404 (first project on account) ---"
TMP6=$(setup_env)
write_account_config "$TMP6"
write_project_config "$TMP6"
write_project_sourcing_chain "$TMP6"
write_mock_bin "$TMP6"
LOG6="$TMP6/preflight.log"
exit6=$(MOCK_CURL_PROJECT_SOURCE_CODE=404 run_preflight_capture "$TMP6" "$LOG6" || true)
assert_equal "$exit6" "0" "exit code 0 when project_source is 404 (recoverable — skill re-runs account-setup)"
assert_file_contains "$LOG6" "PREFLIGHT_PROJECT_SOURCE=missing" "project_source reported missing on 404"
assert_file_contains "$LOG6" "PREFLIGHT_API_ACCESS=ok" "API access still ok alongside the recoverable 404"

# --- Scenario F: account-info 401 (bad token) → PREFLIGHT_API_ACCESS=unauthorized ---

echo ""
echo "--- Scenario F: API returns 401 (bad or expired token) ---"
TMPF=$(setup_env)
write_account_config "$TMPF"
write_project_config "$TMPF"
write_project_sourcing_chain "$TMPF"
write_mock_bin "$TMPF"
LOGF="$TMPF/preflight.log"
exitF=$(MOCK_CURL_ACCOUNT_INFO_CODE=401 run_preflight_capture "$TMPF" "$LOGF" || true)
assert_equal "$exitF" "1" "exit 1 when API returns 401"
assert_file_contains "$LOGF" "PREFLIGHT_API_ACCESS=unauthorized" "API access reported unauthorized on 401"

# --- Scenario G: account-info 403 → PREFLIGHT_API_ACCESS=forbidden ---
# 403 means auth worked but the token lacks a required permission/scope at
# the account level (distinct from missing-scope on a specific endpoint).

echo ""
echo "--- Scenario G: API returns 403 (forbidden) ---"
TMPG=$(setup_env)
write_account_config "$TMPG"
write_project_config "$TMPG"
write_project_sourcing_chain "$TMPG"
write_mock_bin "$TMPG"
LOGG="$TMPG/preflight.log"
exitG=$(MOCK_CURL_ACCOUNT_INFO_CODE=403 run_preflight_capture "$TMPG" "$LOGG" || true)
assert_equal "$exitG" "1" "exit 1 when API returns 403"
assert_file_contains "$LOGG" "PREFLIGHT_API_ACCESS=forbidden" "API access reported forbidden on 403"

# --- Scenario H: curl fails outright → PREFLIGHT_API_ACCESS=unreachable ---
# DNS failure, connection refused, TLS failure — preflight should distinguish
# this from a real HTTP response so the skill can coach differently
# (e.g., "check your internet" rather than "check your token").

echo ""
echo "--- Scenario H: curl fails (network unreachable) ---"
TMPH=$(setup_env)
write_account_config "$TMPH"
write_project_config "$TMPH"
write_project_sourcing_chain "$TMPH"
write_mock_bin "$TMPH"
LOGH="$TMPH/preflight.log"
# curl exit 6 = "couldn't resolve host" — a realistic failure mode
exitH=$(MOCK_CURL_FAIL=6 run_preflight_capture "$TMPH" "$LOGH" || true)
assert_equal "$exitH" "1" "exit 1 when curl cannot reach HubSpot"
assert_file_contains "$LOGH" "PREFLIGHT_API_ACCESS=unreachable" "API access reported unreachable on curl failure"

# --- Scenario E: Keychain entry exists but returns empty → CREDENTIAL=empty ---
# Regression guard: distinguishes "no Keychain entry" from "entry exists but blank"
# so the skill can tell the user to fix the entry's value rather than create one.

echo ""
echo "--- Scenario E: Keychain entry exists but empty ---"
TMPE=$(setup_env)
write_account_config "$TMPE"
write_project_config "$TMPE"
write_project_sourcing_chain "$TMPE"
# Mock security echoes empty (instead of MOCK_TOKEN) for matching service name.
write_mock_bin "$TMPE" ""
LOGE="$TMPE/preflight.log"
exitE=$(run_preflight_capture "$TMPE" "$LOGE" || true)
assert_equal "$exitE" "1" "exit code 1 when Keychain entry is empty"
assert_file_contains "$LOGE" "PREFLIGHT_CREDENTIAL=empty" "credential reported empty"

# --- Scenario K: DNS missing — detail includes expected CNAME target ---
# The skill can then tell the user exactly which DNS record to create.

echo ""
echo "--- Scenario K: DNS missing, expected CNAME target in detail ---"
TMPK=$(setup_env)
write_account_config "$TMPK"
write_project_config "$TMPK"
write_project_sourcing_chain "$TMPK"
write_mock_bin "$TMPK"
LOGK="$TMPK/preflight.log"
exitK=$(MOCK_DIG_EMPTY=1 run_preflight_capture "$TMPK" "$LOGK" || true)
assert_equal "$exitK" "1" "exit code 1 when DNS does not resolve"
# Portal ID 12345678, region eu1 → 12345678.group0.sites.hscoscdn-eu1.net
assert_file_contains "$LOGK" "12345678.group0.sites.hscoscdn-eu1.net" "expected CNAME target included in DNS missing detail"

# --- Scenario M: account profile OK, but the Keychain entry named by
#     HUBSPOT_TOKEN_KEYCHAIN_SERVICE doesn't exist → CREDENTIAL=missing.
#     This is the case where the skill should coach the user to add a
#     Keychain entry — distinct from Scenario 2 (account config broken).

echo ""
echo "--- Scenario M: Keychain entry absent (account profile ok) ---"
TMPM=$(setup_env)
CFG_HUBSPOT_TOKEN_KEYCHAIN_SERVICE="nonexistent-keychain-entry" write_account_config "$TMPM"
write_project_config "$TMPM"
write_project_sourcing_chain "$TMPM"
write_mock_bin "$TMPM"
LOGM="$TMPM/preflight.log"
exitM=$(run_preflight_capture "$TMPM" "$LOGM" || true)
assert_equal "$exitM" "1" "exit 1 when Keychain entry absent"
assert_file_contains "$LOGM" "PREFLIGHT_ACCOUNT_PROFILE=ok" "account profile ok when service name is set but entry doesn't exist"
assert_file_contains "$LOGM" "PREFLIGHT_CREDENTIAL=missing" "credential reported missing — skill should coach adding a Keychain entry"

# --- Scenario I: SCOPES=ok (introspection endpoint lists all 7 required) ---
# Default mock body returns all 7 required scopes.

echo ""
echo "--- Scenario I: all required scopes present ---"
TMPI=$(setup_env)
write_account_config "$TMPI"
write_project_config "$TMPI"
write_project_sourcing_chain "$TMPI"
write_mock_bin "$TMPI"
LOGI="$TMPI/preflight.log"
exitI=$(run_preflight_capture "$TMPI" "$LOGI" || true)
assert_equal "$exitI" "0" "exit 0 when all required scopes are granted"
assert_file_contains "$LOGI" "PREFLIGHT_SCOPES=ok" "scopes reported ok when all 7 present"

# --- Scenario J: SCOPES=missing — token lacks a subset of required scopes ---
# The skill must be able to name exactly which scopes are missing so the
# user can add them without guesswork.

echo ""
echo "--- Scenario J: two required scopes absent ---"
TMPJ=$(setup_env)
write_account_config "$TMPJ"
write_project_config "$TMPJ"
write_project_sourcing_chain "$TMPJ"
write_mock_bin "$TMPJ"
LOGJ="$TMPJ/preflight.log"
# Mock returns 5 of the 7 required scopes (omitting crm.lists.write and forms).
exitJ=$(MOCK_CURL_SCOPES_LIST="crm.objects.contacts.read,crm.objects.contacts.write,crm.schemas.contacts.write,crm.lists.read,content" \
        run_preflight_capture "$TMPJ" "$LOGJ" || true)
assert_equal "$exitJ" "1" "exit 1 when required scopes missing"
assert_file_contains "$LOGJ" "PREFLIGHT_SCOPES=missing" "scopes reported missing"
assert_file_contains "$LOGJ" "crm.lists.write" "missing scope list names crm.lists.write"
assert_file_contains "$LOGJ" "forms" "missing scope list names forms"

# --- Scenario L: SCOPES=error — introspection endpoint returns unexpected HTTP ---

echo ""
echo "--- Scenario L: introspection endpoint error ---"
TMPL=$(setup_env)
write_account_config "$TMPL"
write_project_config "$TMPL"
write_project_sourcing_chain "$TMPL"
write_mock_bin "$TMPL"
LOGL="$TMPL/preflight.log"
exitL=$(MOCK_CURL_SCOPES_CODE=500 run_preflight_capture "$TMPL" "$LOGL" || true)
assert_equal "$exitL" "1" "exit 1 when scopes endpoint returns 500"
assert_file_contains "$LOGL" "PREFLIGHT_SCOPES=error" "scopes reported error on non-200"
assert_file_contains "$LOGL" "500" "scopes error detail includes the HTTP code"

# --- Scenario A: PROJECT_POINTER missing (no project.config.sh in project dir) ---

echo ""
echo "--- Scenario A: no project.config.sh ---"
TMPA=$(setup_env)
# Skip write_project_sourcing_chain — leaves $TMPA/project/project.config.sh absent
write_account_config "$TMPA"
write_project_config "$TMPA"
write_mock_bin "$TMPA"
LOGA="$TMPA/preflight.log"
exitA=$(run_preflight_capture "$TMPA" "$LOGA" || true)
assert_equal "$exitA" "1" "exit 1 when project.config.sh is missing"
assert_file_contains "$LOGA" "PREFLIGHT_PROJECT_POINTER=missing" "project pointer reported missing"
assert_full_contract "$LOGA" "Scenario A"

# --- Scenario B: ACCOUNT_PROFILE missing — account config file absent ---

echo ""
echo "--- Scenario B: account config file missing ---"
TMPB=$(setup_env)
# Write project pointer but skip account config. Pointer sets HS_LANDER_ACCOUNT
# and HS_LANDER_PROJECT; downstream check should discover the account file is absent.
write_project_config "$TMPB"
write_project_sourcing_chain "$TMPB"
write_mock_bin "$TMPB"
LOGB="$TMPB/preflight.log"
exitB=$(run_preflight_capture "$TMPB" "$LOGB" || true)
assert_equal "$exitB" "1" "exit 1 when account config is missing"
assert_file_contains "$LOGB" "PREFLIGHT_ACCOUNT_PROFILE=missing" "account profile reported missing"
assert_full_contract "$LOGB" "Scenario B"

# --- Scenario C: ACCOUNT_PROFILE incomplete — account config missing a required field ---

echo ""
echo "--- Scenario C: account config incomplete ---"
TMPC=$(setup_env)
CFG_HUBSPOT_PORTAL_ID="" write_account_config "$TMPC"
write_project_config "$TMPC"
write_project_sourcing_chain "$TMPC"
write_mock_bin "$TMPC"
LOGC="$TMPC/preflight.log"
exitC=$(run_preflight_capture "$TMPC" "$LOGC" || true)
assert_equal "$exitC" "1" "exit 1 when account config is incomplete"
assert_file_contains "$LOGC" "PREFLIGHT_ACCOUNT_PROFILE=incomplete" "account profile reported incomplete"
assert_file_contains "$LOGC" "HUBSPOT_PORTAL_ID" "incomplete detail lists the missing field"
assert_full_contract "$LOGC" "Scenario C"

# --- Scenario D: PROJECT_PROFILE missing — project config file absent ---

echo ""
echo "--- Scenario D: project config file missing ---"
TMPD=$(setup_env)
write_account_config "$TMPD"
# Skip write_project_config — project file absent
write_project_sourcing_chain "$TMPD"
write_mock_bin "$TMPD"
LOGD="$TMPD/preflight.log"
exitD=$(run_preflight_capture "$TMPD" "$LOGD" || true)
assert_equal "$exitD" "1" "exit 1 when project config is missing"
assert_file_contains "$LOGD" "PREFLIGHT_PROJECT_PROFILE=missing" "project profile reported missing"
assert_full_contract "$LOGD" "Scenario D"

# --- Scenario N: pointer file with single-quoted values ---
# Locks down the awk extractor's \x27 branch — macOS BWK awk isn't
# documented to support \xNN hex escapes, so this is a portability
# regression guard. Also exercises the "unquoted" branch via the same
# kind of real-file round-trip.

echo ""
echo "--- Scenario N: pointer with single-quoted values ---"
TMPN=$(setup_env)
write_account_config "$TMPN"
write_project_config "$TMPN"
cat > "$TMPN/project/project.config.sh" <<'POINTER'
HS_LANDER_ACCOUNT='testacct'
HS_LANDER_PROJECT='testproj'
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
POINTER
write_mock_bin "$TMPN"
LOGN="$TMPN/preflight.log"
exitN=$(run_preflight_capture "$TMPN" "$LOGN" || true)
assert_equal "$exitN" "0" "single-quoted pointer parses successfully (exit 0)"
assert_file_contains "$LOGN" "PREFLIGHT_PROJECT_POINTER=ok" "pointer reported ok with single-quoted values"
assert_file_contains "$LOGN" "PREFLIGHT_ACCOUNT_PROFILE=ok" "downstream ACCOUNT_PROFILE=ok proves the single-quoted account name resolved to a real file"

# --- Scenario N2: pointer file with unquoted and `export`-prefixed values ---

echo ""
echo "--- Scenario N2: pointer with unquoted + export-prefixed values ---"
TMPN2=$(setup_env)
write_account_config "$TMPN2"
write_project_config "$TMPN2"
cat > "$TMPN2/project/project.config.sh" <<'POINTER'
export HS_LANDER_ACCOUNT=testacct
HS_LANDER_PROJECT=testproj  # trailing comment on unquoted value
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
POINTER
write_mock_bin "$TMPN2"
LOGN2="$TMPN2/preflight.log"
exitN2=$(run_preflight_capture "$TMPN2" "$LOGN2" || true)
assert_equal "$exitN2" "0" "unquoted+export pointer parses successfully (exit 0)"
assert_file_contains "$LOGN2" "PREFLIGHT_PROJECT_POINTER=ok" "pointer reported ok with unquoted+export values"
assert_file_contains "$LOGN2" "PREFLIGHT_ACCOUNT_PROFILE=ok" "downstream ACCOUNT_PROFILE=ok proves unquoted+export resolved"

# Extend EXIT trap to include all temp dirs created above.
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMPF:-}" "${TMPG:-}" "${TMPH:-}" "${TMPE:-}" "${TMPK:-}" "${TMPA:-}" "${TMPB:-}" "${TMPC:-}" "${TMPD:-}" "${TMPI:-}" "${TMPJ:-}" "${TMPL:-}" "${TMPM:-}" "${TMPN:-}" "${TMPN2:-}"' EXIT

test_summary
