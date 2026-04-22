#!/usr/bin/env bash
# test-accounts-describe.sh — Validates scripts/accounts-describe.sh surfaces
# the four documented ACCOUNT_* fields and refuses to touch the Keychain.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-accounts-describe.sh ==="

SCRIPT="$REPO_DIR/scripts/accounts-describe.sh"
assert_file_exists "$SCRIPT" "scripts/accounts-describe.sh exists"

run() {
  local cfg="$1" account="$2" log="$3"
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" "$account" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: complete account profile → all four fields emitted ---
echo ""
echo "--- Scenario 1: complete account profile ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}"' EXIT
mkdir -p "$TMP1/dml"
cat > "$TMP1/dml/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="147959629"
HUBSPOT_REGION="eu1"
DOMAIN_PATTERN="*.dml.example.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="dml-hubspot-access-token"
HUBSPOT_SUBSCRIPTION_ID="2269639338"
HUBSPOT_OFFICE_LOCATION_ID="375327044798"
EOF
exit1=$(run "$TMP1" dml "$TMP1/log" || true)
assert_equal "$exit1" "0" "exit 0 when profile is complete"
assert_file_contains "$TMP1/log" "^ACCOUNT_PORTAL_ID=147959629$" "portal id reported"
assert_file_contains "$TMP1/log" "^ACCOUNT_REGION=eu1$" "region reported"
assert_file_contains "$TMP1/log" "^ACCOUNT_DOMAIN_PATTERN=\*\.dml\.example\.com$" "domain pattern reported"
assert_file_contains "$TMP1/log" "^ACCOUNT_TOKEN_KEYCHAIN_SERVICE=dml-hubspot-access-token$" "Keychain service name reported"
assert_file_contains "$TMP1/log" "^ACCOUNT_SUBSCRIPTION_ID=2269639338$" "subscription id reported"
assert_file_contains "$TMP1/log" "^ACCOUNT_OFFICE_LOCATION_ID=375327044798$" "office location id reported"

# --- Scenario 2: missing account → ACCOUNT_STATUS=missing, exit 1 ---
echo ""
echo "--- Scenario 2: missing account ---"
TMP2=$(mktemp -d)
exit2=$(run "$TMP2" nope "$TMP2/log" || true)
assert_equal "$exit2" "1" "exit 1 when profile is missing"
assert_file_contains "$TMP2/log" "^ACCOUNT_STATUS=missing" "missing reported with path"

# --- Scenario 3: missing account name argument → exit 1 ---
echo ""
echo "--- Scenario 3: no account argument ---"
TMP3=$(mktemp -d)
HS_LANDER_CONFIG_DIR="$TMP3" bash "$SCRIPT" >"$TMP3/log" 2>&1 && exit3=0 || exit3=$?
assert_equal "$exit3" "1" "exit 1 when no account name provided"

# --- Scenario 4: token never leaks — describe doesn't invoke security ---
# Mock `security` that records invocation. The script must not call it.
echo ""
echo "--- Scenario 4: script never invokes security ---"
TMP4=$(mktemp -d)
mkdir -p "$TMP4/dml" "$TMP4/bin"
cat > "$TMP4/dml/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="147959629"
HUBSPOT_REGION="eu1"
DOMAIN_PATTERN="*.dml.example.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="dml-hubspot-access-token"
EOF
cat > "$TMP4/bin/security" <<MOCK
#!/usr/bin/env bash
touch "$TMP4/security-was-called"
echo "leaked-token"
MOCK
chmod +x "$TMP4/bin/security"
HS_LANDER_CONFIG_DIR="$TMP4" PATH="$TMP4/bin:$PATH" bash "$SCRIPT" dml >"$TMP4/log" 2>&1 || true
if [[ -e "$TMP4/security-was-called" ]]; then
  assert_equal "security-was-called" "should-NOT-have-been-called" "accounts-describe must not invoke security"
else
  assert_equal "1" "1" "accounts-describe did not invoke security"
fi
assert_file_not_contains "$TMP4/log" "leaked-token" "no token value appears in output"

# --- Scenario 5: pre-v1.5.0 profile → subscription/office fields are empty ---
# Accounts created before v1.5.0 don't have the new fields. The describe
# output must still include the lines, with empty values, so skill parsing
# never has to branch on field presence.
echo ""
echo "--- Scenario 5: pre-v1.5.0 profile emits empty new fields ---"
TMP5=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}"' EXIT
mkdir -p "$TMP5/legacy"
cat > "$TMP5/legacy/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="99999999"
HUBSPOT_REGION="na1"
DOMAIN_PATTERN=""
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="legacy-svc"
EOF
exit5=$(run "$TMP5" legacy "$TMP5/log" || true)
assert_equal "$exit5" "0" "exit 0 on pre-v1.5.0 profile"
assert_file_contains "$TMP5/log" "^ACCOUNT_SUBSCRIPTION_ID=$" "empty subscription id line emitted"
assert_file_contains "$TMP5/log" "^ACCOUNT_OFFICE_LOCATION_ID=$" "empty office location id line emitted"

test_summary
