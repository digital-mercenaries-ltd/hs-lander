#!/usr/bin/env bash
# test-projects-list.sh — Validates scripts/projects-list.sh enumerates
# project profiles under a given account.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-projects-list.sh ==="

SCRIPT="$REPO_DIR/scripts/projects-list.sh"
assert_file_exists "$SCRIPT" "scripts/projects-list.sh exists"

run() {
  local cfg="$1" account="$2" log="$3"
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" "$account" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: account missing → ACCOUNT_STATUS=missing, exit 1 ---
echo ""
echo "--- Scenario 1: account missing ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}"' EXIT
exit1=$(run "$TMP1" nope "$TMP1/log" || true)
assert_equal "$exit1" "1" "exit 1 when account missing"
assert_file_contains "$TMP1/log" "^ACCOUNT_STATUS=missing" "missing reported"

# --- Scenario 2: account present, zero projects → PROJECTS= (exit 0) ---
echo ""
echo "--- Scenario 2: account with zero projects ---"
TMP2=$(mktemp -d)
mkdir -p "$TMP2/dml"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP2/dml/config.sh"
exit2=$(run "$TMP2" dml "$TMP2/log" || true)
assert_equal "$exit2" "0" "exit 0 on account with no projects"
assert_equal "$(cat "$TMP2/log")" "PROJECTS=" "empty project list"

# --- Scenario 3: single project ---
echo ""
echo "--- Scenario 3: single project ---"
TMP3=$(mktemp -d)
mkdir -p "$TMP3/dml"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP3/dml/config.sh"
echo 'PROJECT_SLUG="heard"' > "$TMP3/dml/heard.sh"
exit3=$(run "$TMP3" dml "$TMP3/log" || true)
assert_equal "$exit3" "0" "exit 0 with single project"
assert_equal "$(cat "$TMP3/log")" "PROJECTS=heard" "single project reported; config.sh not counted"

# --- Scenario 4: multiple projects (alphabetical) ---
echo ""
echo "--- Scenario 4: multiple projects ---"
TMP4=$(mktemp -d)
mkdir -p "$TMP4/dml"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP4/dml/config.sh"
echo 'PROJECT_SLUG="heard"' > "$TMP4/dml/heard.sh"
echo 'PROJECT_SLUG="tsc"'   > "$TMP4/dml/tsc.sh"
exit4=$(run "$TMP4" dml "$TMP4/log" || true)
assert_equal "$exit4" "0" "exit 0 with multiple projects"
assert_equal "$(cat "$TMP4/log")" "PROJECTS=heard,tsc" "projects reported as csv (shell glob order)"

# --- Scenario 5: invalid account name rejected (v1.9.0 validate-name lib) ---
echo ""
echo "--- Scenario 5: invalid-name rejected ---"
TMP5=$(mktemp -d)
exit5=$(run "$TMP5" '..' "$TMP5/log" || true)
assert_equal "$exit5" "1" "exit 1 on '..' account name (path-traversal defeated)"
assert_file_contains "$TMP5/log" "ACCOUNT_STATUS=error invalid-account-name" "invalid-account-name error"

exit6=$(run "$TMP5" 'a/b' "$TMP5/log6" || true)
assert_equal "$exit6" "1" "exit 1 on 'a/b' account name (slash rejected)"
assert_file_contains "$TMP5/log6" "ACCOUNT_STATUS=error invalid-account-name" "invalid-account-name error for slash"
rm -rf "$TMP5"

# --- Scenario 6: .profile-backups/ ignored (v1.9.0 regression) ---
echo ""
echo "--- Scenario 6: .profile-backups/ excluded from project list ---"
TMP6=$(mktemp -d)
mkdir -p "$TMP6/dml/.profile-backups"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP6/dml/config.sh"
echo 'PROJECT_SLUG="heard"' > "$TMP6/dml/heard.sh"
# Plant a backup file that would match *.sh if the glob were broader
echo 'old' > "$TMP6/dml/.profile-backups/heard.sh.2026-04-22T14-30-22Z"
exit6b=$(run "$TMP6" dml "$TMP6/log" || true)
assert_equal "$exit6b" "0" "exit 0 with .profile-backups present"
assert_equal "$(cat "$TMP6/log")" "PROJECTS=heard" ".profile-backups not listed as a project"
rm -rf "$TMP6"

test_summary
