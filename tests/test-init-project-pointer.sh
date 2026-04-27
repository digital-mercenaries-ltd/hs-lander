#!/usr/bin/env bash
# test-init-project-pointer.sh — Validates scripts/init-project-pointer.sh
# idempotently creates the sourcing-chain pointer and detects conflicts.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-init-project-pointer.sh ==="

SCRIPT="$REPO_DIR/scripts/init-project-pointer.sh"
assert_file_exists "$SCRIPT" "scripts/init-project-pointer.sh exists"

run() {
  local proj_dir="$1" account="$2" project="$3" log="$4"
  HS_LANDER_PROJECT_DIR="$proj_dir" bash "$SCRIPT" "$account" "$project" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: empty dir → creates pointer ---
echo ""
echo "--- Scenario 1: pointer created ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}"' EXIT
exit1=$(run "$TMP1" dml heard "$TMP1/log" || true)
assert_equal "$exit1" "0" "exit 0 on creation"
assert_file_contains "$TMP1/log" "^INIT_POINTER=created" "created reported"
assert_file_exists "$TMP1/project.config.sh" "pointer file written"
assert_file_contains "$TMP1/project.config.sh" 'HS_LANDER_ACCOUNT="dml"' "account name written"
assert_file_contains "$TMP1/project.config.sh" 'HS_LANDER_PROJECT="heard"' "project name written"
# shellcheck disable=SC2016 # literal pattern for grep — we want the `${HOME}` text itself, not expansion
assert_file_contains "$TMP1/project.config.sh" 'source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"' "sources account config"
# shellcheck disable=SC2016
assert_file_contains "$TMP1/project.config.sh" 'source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"' "sources project config"

# --- Scenario 2: re-run with same values → INIT_POINTER=present (idempotent) ---
echo ""
echo "--- Scenario 2: re-run matching values → present ---"
TMP2="$TMP1"
before=$(cat "$TMP2/project.config.sh")
exit2=$(run "$TMP2" dml heard "$TMP2/log2" || true)
assert_equal "$exit2" "0" "exit 0 on idempotent re-run"
assert_file_contains "$TMP2/log2" "^INIT_POINTER=present" "present reported"
after=$(cat "$TMP2/project.config.sh")
assert_equal "$after" "$before" "pointer file unchanged on idempotent re-run"

# --- Scenario 3: existing pointer has different values → conflict, exit 1 ---
echo ""
echo "--- Scenario 3: differing values → conflict ---"
TMP3=$(mktemp -d)
cat > "$TMP3/project.config.sh" <<'EOF'
HS_LANDER_ACCOUNT="other"
HS_LANDER_PROJECT="different"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
EOF
before=$(cat "$TMP3/project.config.sh")
exit3=$(run "$TMP3" dml heard "$TMP3/log" || true)
assert_equal "$exit3" "1" "exit 1 on conflict"
assert_file_contains "$TMP3/log" "^INIT_POINTER=conflict" "conflict reported"
after=$(cat "$TMP3/project.config.sh")
assert_equal "$after" "$before" "conflict does not overwrite existing pointer"

# --- Scenario 4: missing args → exit 1 ---
echo ""
echo "--- Scenario 4: missing args → exit 1 ---"
TMP4=$(mktemp -d)
HS_LANDER_PROJECT_DIR="$TMP4" bash "$SCRIPT" >"$TMP4/log" 2>&1 && exit4=0 || exit4=$?
assert_equal "$exit4" "1" "exit 1 when args missing"

# --- Scenario 5: project dir missing → refuse to create it silently ---
# A typo or wrong CWD for HS_LANDER_PROJECT_DIR used to result in a silently
# created directory holding a stray pointer. The script must now error.

echo ""
echo "--- Scenario 5: project dir does not exist → error ---"
TMP5=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}"' EXIT
nonexistent="$TMP5/does-not-exist"
HS_LANDER_PROJECT_DIR="$nonexistent" bash "$SCRIPT" dml heard >"$TMP5/log" 2>&1 && exit5=0 || exit5=$?
assert_equal "$exit5" "1" "exit 1 when project dir missing"
assert_file_contains "$TMP5/log" "^INIT_POINTER=error project-dir-missing" "missing-dir error reported"
if [[ -d "$nonexistent" ]]; then
  assert_equal "created" "must-NOT-have-been-created" "init must not silently create the project dir"
else
  assert_equal "1" "1" "project dir not silently created"
fi

# --- Scenario 6: invalid-name validation (v1.9.0 validate-name lib) ---
echo ""
echo "--- Scenario 6: invalid-name rejected ---"
TMP6=$(mktemp -d)
exit6=0
HS_LANDER_PROJECT_DIR="$TMP6" bash "$REPO_DIR/scripts/init-project-pointer.sh" '..' someproject >"$TMP6/log" 2>&1 || exit6=$?
assert_equal "$exit6" "1" "exit 1 on '..' account name"
assert_file_contains "$TMP6/log" "INIT_POINTER=error invalid-account-name" "invalid-account-name error"
if [[ -f "$TMP6/project.config.sh" ]]; then
  assert_equal "pointer-was-written" "must-not-have-been" "pointer file should not exist when validation rejected"
else
  assert_equal "1" "1" "no pointer file written on validation rejection"
fi

exit7=0
HS_LANDER_PROJECT_DIR="$TMP6" bash "$REPO_DIR/scripts/init-project-pointer.sh" dml 'Up_Case' >"$TMP6/log7" 2>&1 || exit7=$?
assert_equal "$exit7" "1" "exit 1 on uppercase/underscore project name"
assert_file_contains "$TMP6/log7" "INIT_POINTER=error invalid-project-name" "invalid-project-name error"

rm -rf "$TMP6"

test_summary
