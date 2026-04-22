#!/usr/bin/env bash
# test-accounts-init.sh — Validates scripts/accounts-init.sh creates account
# profiles safely: correct content, refuses overwrite, rejects invalid input.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-accounts-init.sh ==="

SCRIPT="$REPO_DIR/scripts/accounts-init.sh"
assert_file_exists "$SCRIPT" "scripts/accounts-init.sh exists"

run() {
  local cfg="$1"; shift
  local log="$1"; shift
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: fresh create ---
echo ""
echo "--- Scenario 1: fresh create ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}"' EXIT
exit1=$(run "$TMP1" "$TMP1/log" dml 147959629 eu1 "*.example.com" dml-hubspot-access-token || true)
assert_equal "$exit1" "0" "exit 0 on fresh create"
assert_file_contains "$TMP1/log" "^ACCOUNTS_INIT=created" "created line emitted"
assert_file_exists "$TMP1/dml/config.sh" "config.sh written"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_PORTAL_ID="147959629"$' "portal id written"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_REGION="eu1"$' "region written"
assert_file_contains "$TMP1/dml/config.sh" '^DOMAIN_PATTERN="\*\.example\.com"$' "domain pattern written"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_TOKEN_KEYCHAIN_SERVICE="dml-hubspot-access-token"$' "service name written"

# Round-trip: sourcing the written file yields the original values.
(
  # shellcheck source=/dev/null
  source "$TMP1/dml/config.sh"
  [[ "$HUBSPOT_PORTAL_ID" == "147959629" ]] || exit 10
  [[ "$HUBSPOT_REGION" == "eu1" ]] || exit 11
  [[ "$DOMAIN_PATTERN" == "*.example.com" ]] || exit 12
  [[ "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" == "dml-hubspot-access-token" ]] || exit 13
) && rt=ok || rt=fail
assert_equal "$rt" "ok" "sourced values round-trip (including the * in DOMAIN_PATTERN)"

# --- Scenario 2: overwrite refused ---
echo ""
echo "--- Scenario 2: existing profile → conflict ---"
TMP2="$TMP1" # re-use dir to keep the just-created profile
before=$(cat "$TMP2/dml/config.sh")
exit2=$(run "$TMP2" "$TMP2/log2" dml 99999999 na1 "*.other.com" different-service || true)
assert_equal "$exit2" "1" "exit 1 on conflict"
assert_file_contains "$TMP2/log2" "^ACCOUNTS_INIT=conflict" "conflict line emitted"
after=$(cat "$TMP2/dml/config.sh")
assert_equal "$after" "$before" "existing profile untouched on conflict"

# --- Scenario 3: invalid account name (slash) ---
echo ""
echo "--- Scenario 3: invalid account name ---"
TMP3=$(mktemp -d)
exit3=$(run "$TMP3" "$TMP3/log" "bad/name" 1 eu1 "" svc || true)
assert_equal "$exit3" "1" "exit 1 on invalid account name"
assert_file_contains "$TMP3/log" "^ACCOUNTS_INIT=error invalid-account-name" "invalid-account-name reported"

# --- Scenario 4: invalid region ---
echo ""
echo "--- Scenario 4: invalid region ---"
TMP4=$(mktemp -d)
exit4=$(run "$TMP4" "$TMP4/log" dml 1 us1 "" svc || true)
assert_equal "$exit4" "1" "exit 1 on invalid region"
assert_file_contains "$TMP4/log" "^ACCOUNTS_INIT=error invalid-region" "invalid-region reported"

# --- Scenario 5: empty DOMAIN_PATTERN accepted ---
echo ""
echo "--- Scenario 5: empty DOMAIN_PATTERN accepted ---"
TMP5=$(mktemp -d)
exit5=$(run "$TMP5" "$TMP5/log" dml 1 eu1 "" svc || true)
assert_equal "$exit5" "0" "exit 0 when DOMAIN_PATTERN is empty"
assert_file_contains "$TMP5/dml/config.sh" '^DOMAIN_PATTERN=""$' "empty domain pattern written as empty string"

# --- Scenario 6: wrong arg count ---
echo ""
echo "--- Scenario 6: wrong arg count ---"
TMP6=$(mktemp -d)
HS_LANDER_CONFIG_DIR="$TMP6" bash "$SCRIPT" dml 1 eu1 >"$TMP6/log" 2>&1 && exit6=0 || exit6=$?
assert_equal "$exit6" "1" "exit 1 when arg count wrong"

test_summary
