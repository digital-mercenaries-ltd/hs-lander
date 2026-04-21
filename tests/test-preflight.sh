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
  local token="${2:-$MOCK_TOKEN}"
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

  # Mock `curl`: parse the URL out of the arg list and return a code per
  # endpoint. Callers control each endpoint's code via env vars:
  #   MOCK_CURL_ACCOUNT_INFO_CODE   (default 200) — /account-info/v3/details
  #   MOCK_CURL_PROJECT_SOURCE_CODE (default 200) — /crm/v3/properties/contacts/project_source
  cat > "$dir/mock-bin/curl" <<'MOCK'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in https://*) url="$arg" ;; esac
done
case "$url" in
  *"/account-info/v3/details"*)
    echo "${MOCK_CURL_ACCOUNT_INFO_CODE:-200}"
    ;;
  *"/crm/v3/properties/contacts/project_source"*)
    echo "${MOCK_CURL_PROJECT_SOURCE_CODE:-200}"
    ;;
  *)
    echo "200"
    ;;
esac
exit 0
MOCK
  chmod +x "$dir/mock-bin/curl"

  # Mock `dig`: echo a fake IP so the DNS check sees a non-empty result.
  cat > "$dir/mock-bin/dig" <<'MOCK'
#!/usr/bin/env bash
echo "93.184.216.34"
exit 0
MOCK
  chmod +x "$dir/mock-bin/dig"
}

run_preflight_capture() {
  # $1: env dir, $2: output log path. Returns preflight's exit code via echo-trick.
  # Caller can set MOCK_CURL_ACCOUNT_INFO_CODE / MOCK_CURL_PROJECT_SOURCE_CODE
  # before calling to control the mock curl's per-endpoint response.
  local dir="$1" log="$2"
  HOME="$dir/home" PATH="$dir/mock-bin:$PATH" \
    MOCK_CURL_ACCOUNT_INFO_CODE="${MOCK_CURL_ACCOUNT_INFO_CODE:-200}" \
    MOCK_CURL_PROJECT_SOURCE_CODE="${MOCK_CURL_PROJECT_SOURCE_CODE:-200}" \
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
assert_file_contains "$LOG1" "PREFLIGHT_CONFIG=ok" "config check ok"
assert_file_contains "$LOG1" "PREFLIGHT_CREDENTIAL=ok" "credential check ok"
assert_file_contains "$LOG1" "PREFLIGHT_API_ACCESS=ok" "API access ok"
assert_file_contains "$LOG1" "PREFLIGHT_DNS=ok" "DNS check ok"

# --- Scenario 2: missing HUBSPOT_TOKEN_KEYCHAIN_SERVICE → credential=missing, exit 1 ---

echo ""
echo "--- Scenario 2: missing HUBSPOT_TOKEN_KEYCHAIN_SERVICE ---"
TMP2=$(setup_env)
CFG_HUBSPOT_TOKEN_KEYCHAIN_SERVICE="" write_account_config "$TMP2"
write_project_config "$TMP2"
write_project_sourcing_chain "$TMP2"
write_mock_bin "$TMP2"
LOG2="$TMP2/preflight.log"
exit2=$(run_preflight_capture "$TMP2" "$LOG2" || true)
assert_equal "$exit2" "1" "exit code 1 when credential reference missing"
assert_file_contains "$LOG2" "PREFLIGHT_CREDENTIAL=missing" "credential reported missing"

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

# --- Scenario 7: account-info 401 (bad token) → blocking error ---

echo ""
echo "--- Scenario 7: account-info 401 (bad token) ---"
TMP7=$(setup_env)
write_account_config "$TMP7"
write_project_config "$TMP7"
write_project_sourcing_chain "$TMP7"
write_mock_bin "$TMP7"
LOG7="$TMP7/preflight.log"
# Extend trap to cover TMP6, TMP7 and the xtrace log dir (already covered by TMP5)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}"' EXIT
exit7=$(MOCK_CURL_ACCOUNT_INFO_CODE=401 run_preflight_capture "$TMP7" "$LOG7" || true)
assert_equal "$exit7" "1" "exit code 1 when HubSpot API returns 401"
assert_file_contains "$LOG7" "PREFLIGHT_API_ACCESS=error" "API access reported error on 401"

test_summary
