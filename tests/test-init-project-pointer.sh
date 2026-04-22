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

test_summary
