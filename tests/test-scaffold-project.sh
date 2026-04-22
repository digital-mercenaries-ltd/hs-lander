#!/usr/bin/env bash
# test-scaffold-project.sh — Validates scripts/scaffold-project.sh copies
# framework scripts + scaffold templates into the project, creates the
# project profile stub, and writes the pointer.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-scaffold-project.sh ==="

SCRIPT="$REPO_DIR/scripts/scaffold-project.sh"
assert_file_exists "$SCRIPT" "scripts/scaffold-project.sh exists"

run() {
  local proj_dir="$1" cfg="$2" account="$3" project="$4" log="$5"
  HS_LANDER_PROJECT_DIR="$proj_dir" HS_LANDER_CONFIG_DIR="$cfg" \
    bash "$SCRIPT" "$account" "$project" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: happy path — account exists, project dir empty ---
echo ""
echo "--- Scenario 1: happy path ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}"' EXIT
mkdir -p "$TMP1/cfg/dml" "$TMP1/proj"
cat > "$TMP1/cfg/dml/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="147959629"
HUBSPOT_REGION="eu1"
DOMAIN_PATTERN="*.dml.example.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="dml-hubspot-access-token"
EOF
exit1=$(run "$TMP1/proj" "$TMP1/cfg" dml heard "$TMP1/log" || true)
assert_equal "$exit1" "0" "exit 0 on happy path"
assert_file_contains "$TMP1/log" "^SCAFFOLD_SCRIPTS=copied" "scripts copied line"
assert_file_contains "$TMP1/log" "^SCAFFOLD_TEMPLATE=copied" "template copied line"
assert_file_contains "$TMP1/log" "^SCAFFOLD_PROJECT_PROFILE=created" "project profile created line"
assert_file_contains "$TMP1/log" "^SCAFFOLD_POINTER=created" "pointer created line"
assert_file_contains "$TMP1/log" "^SCAFFOLD=ok$" "ok terminator"

# Scripts actually copied
assert_file_exists "$TMP1/proj/scripts/preflight.sh" "preflight.sh copied"
assert_file_exists "$TMP1/proj/scripts/build.sh" "build.sh copied"
# Scaffold template copied
assert_file_exists "$TMP1/proj/package.json" "package.json copied from scaffold"
assert_file_exists "$TMP1/proj/brief-template.md" "brief template copied"
# Pointer written with the expected identities
assert_file_exists "$TMP1/proj/project.config.sh" "pointer file exists"
assert_file_contains "$TMP1/proj/project.config.sh" 'HS_LANDER_ACCOUNT="dml"' "pointer identifies account"
assert_file_contains "$TMP1/proj/project.config.sh" 'HS_LANDER_PROJECT="heard"' "pointer identifies project"
# Project profile stub created
assert_file_exists "$TMP1/cfg/dml/heard.sh" "project profile stub created"
assert_file_contains "$TMP1/cfg/dml/heard.sh" 'PROJECT_SLUG="heard"' "stub has project slug"
assert_file_contains "$TMP1/cfg/dml/heard.sh" 'CAPTURE_FORM_ID=""' "stub has empty form id"

# --- Scenario 2: account missing → SCAFFOLD=error account-missing, exit 1 ---
echo ""
echo "--- Scenario 2: account missing ---"
TMP2=$(mktemp -d)
mkdir -p "$TMP2/cfg" "$TMP2/proj"
exit2=$(run "$TMP2/proj" "$TMP2/cfg" nope heard "$TMP2/log" || true)
assert_equal "$exit2" "1" "exit 1 when account missing"
assert_file_contains "$TMP2/log" "^SCAFFOLD=error account-missing" "account-missing reason reported"

# --- Scenario 3: collision — project already has scripts/preflight.sh ---
echo ""
echo "--- Scenario 3: collision refuses to clobber ---"
TMP3=$(mktemp -d)
mkdir -p "$TMP3/cfg/dml" "$TMP3/proj/scripts"
cat > "$TMP3/cfg/dml/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="1"
HUBSPOT_REGION="eu1"
DOMAIN_PATTERN="*.e.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="svc"
EOF
echo 'pre-existing' > "$TMP3/proj/scripts/preflight.sh"
exit3=$(run "$TMP3/proj" "$TMP3/cfg" dml heard "$TMP3/log" || true)
assert_equal "$exit3" "1" "exit 1 on collision"
assert_file_contains "$TMP3/log" "^SCAFFOLD=error collision" "collision reason reported"
# Existing file preserved
assert_equal "$(cat "$TMP3/proj/scripts/preflight.sh")" "pre-existing" "existing script untouched on collision"

test_summary
