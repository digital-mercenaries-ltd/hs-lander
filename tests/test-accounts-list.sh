#!/usr/bin/env bash
# test-accounts-list.sh — Validates scripts/accounts-list.sh discovers
# account profiles correctly under a sandboxed HS_LANDER_CONFIG_DIR.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-accounts-list.sh ==="

SCRIPT="$REPO_DIR/scripts/accounts-list.sh"
assert_file_exists "$SCRIPT" "scripts/accounts-list.sh exists"

run() {
  local cfg="$1" log="$2"
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: config dir missing entirely → ACCOUNTS= (exit 0) ---
echo ""
echo "--- Scenario 1: no config dir ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}"' EXIT
exit1=$(run "$TMP1/does-not-exist" "$TMP1/log" || true)
assert_equal "$exit1" "0" "exit 0 when config dir missing"
assert_equal "$(cat "$TMP1/log")" "ACCOUNTS=" "empty csv when config dir missing"

# --- Scenario 2: empty config dir → ACCOUNTS= ---
echo ""
echo "--- Scenario 2: empty config dir ---"
TMP2=$(mktemp -d)
exit2=$(run "$TMP2" "$TMP2/log" || true)
assert_equal "$exit2" "0" "exit 0 when config dir empty"
assert_equal "$(cat "$TMP2/log")" "ACCOUNTS=" "empty csv when config dir empty"

# --- Scenario 3: single account with config.sh ---
echo ""
echo "--- Scenario 3: single account ---"
TMP3=$(mktemp -d)
mkdir -p "$TMP3/dml"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP3/dml/config.sh"
exit3=$(run "$TMP3" "$TMP3/log" || true)
assert_equal "$exit3" "0" "exit 0 on single account"
assert_equal "$(cat "$TMP3/log")" "ACCOUNTS=dml" "single account reported"

# --- Scenario 4: multiple accounts + orphan dir without config.sh ignored ---
echo ""
echo "--- Scenario 4: multiple accounts + orphan ignored ---"
TMP4=$(mktemp -d)
mkdir -p "$TMP4/dml" "$TMP4/alpha" "$TMP4/orphan"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP4/dml/config.sh"
echo 'HUBSPOT_PORTAL_ID="2"' > "$TMP4/alpha/config.sh"
# orphan/ has no config.sh — should be skipped
exit4=$(run "$TMP4" "$TMP4/log" || true)
assert_equal "$exit4" "0" "exit 0 on multiple accounts"
# Order is alphabetical (shell glob). Accept either ordering explicitly.
content=$(cat "$TMP4/log")
if [[ "$content" == "ACCOUNTS=alpha,dml" || "$content" == "ACCOUNTS=dml,alpha" ]]; then
  assert_equal "1" "1" "two accounts reported; orphan (no config.sh) ignored"
else
  assert_equal "$content" "ACCOUNTS=alpha,dml" "two accounts reported; orphan (no config.sh) ignored"
fi

test_summary
