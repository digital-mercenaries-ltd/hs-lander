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
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}"' EXIT
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
assert_file_contains "$TMP1/log" "^SCAFFOLD_VERSION=copied" "VERSION copied line"
assert_file_contains "$TMP1/log" "^SCAFFOLD=ok$" "ok terminator"
# VERSION is copied from framework into the project root so the project's
# preflight.sh reports the framework version it was scaffolded against.
assert_file_exists "$TMP1/proj/VERSION" "VERSION file copied"

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
# v1.5.0 hosting-modes fields — stub seeds sensible defaults per custom-domain-primary mode
assert_file_contains "$TMP1/cfg/dml/heard.sh" 'LANDING_SLUG=""' "stub has LANDING_SLUG default"
assert_file_contains "$TMP1/cfg/dml/heard.sh" 'THANKYOU_SLUG="thank-you"' "stub has THANKYOU_SLUG default"
# HOSTING_MODE_HINT was removed from the stub in v1.7.0 — skill stores hosting
# state in <project>.skillstate.sh now, outside the framework's project profile.
assert_file_not_contains() {
  local file="$1" pattern="$2" name="$3"
  if grep -qE "$pattern" "$file"; then
    echo "  FAIL: $name — pattern '$pattern' present in $file"
    return 1
  fi
  echo "  PASS: $name"
}
assert_file_not_contains "$TMP1/cfg/dml/heard.sh" 'HOSTING_MODE_HINT=""' "stub does NOT seed HOSTING_MODE_HINT (removed in v1.7.0)"
# v1.7.0 module flags — commented placeholders only (skill activates per project)
assert_file_contains "$TMP1/cfg/dml/heard.sh" '# AUTO_PUBLISH_WELCOME_EMAIL' "stub mentions AUTO_PUBLISH_WELCOME_EMAIL placeholder"
assert_file_contains "$TMP1/cfg/dml/heard.sh" '# EMAIL_PREVIEW_TEXT' "stub mentions EMAIL_PREVIEW_TEXT placeholder"
# INCLUDE_BOTTOM_CTA removed in v1.7.1 — variable was advisory-only and
# consumers were misled into setting false expecting effect.
assert_file_not_contains "$TMP1/cfg/dml/heard.sh" 'INCLUDE_BOTTOM_CTA' "stub does NOT seed INCLUDE_BOTTOM_CTA (removed in v1.7.1)"

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

# --- Scenario 4: LATE collision (template-phase) — no partial copy leaks ---
# Regression guard for the two-pass validation: put the collision on a
# scaffold-template entry so the naive single-pass implementation would
# have already copied scripts/ before hitting the error. With two-pass
# validation, NO file should be copied and NO SCAFFOLD_* lines emitted.

echo ""
echo "--- Scenario 4: late collision → no partial copy ---"
TMP4=$(mktemp -d)
mkdir -p "$TMP4/cfg/dml" "$TMP4/proj"
cat > "$TMP4/cfg/dml/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="1"
HUBSPOT_REGION="eu1"
DOMAIN_PATTERN="*.e.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="svc"
EOF
# Pre-create a scaffold-template target (package.json) to force a collision
# AFTER the scripts/ phase has been validated. Do NOT pre-create anything
# under scripts/ — we want the would-be script targets clear so a naive
# single-pass impl would have copied them before erroring here.
echo 'pre-existing-package-json' > "$TMP4/proj/package.json"
exit4=$(run "$TMP4/proj" "$TMP4/cfg" dml heard "$TMP4/log" || true)
assert_equal "$exit4" "1" "exit 1 on late collision"
assert_file_contains "$TMP4/log" "^SCAFFOLD=error collision .*/package.json" "collision on template phase reported"
# No scripts copied — the two-pass check must catch the template collision
# BEFORE any copy happens, so scripts/ stays absent or empty.
if [[ -f "$TMP4/proj/scripts/preflight.sh" ]]; then
  assert_equal "copied" "must-NOT-have-been-copied" "no scripts should be copied before collision detected"
else
  assert_equal "1" "1" "two-pass validation prevented partial copy (scripts/ untouched)"
fi
# Existing package.json preserved
assert_equal "$(cat "$TMP4/proj/package.json")" "pre-existing-package-json" "existing template file untouched on late collision"

# --- Scenario 5: invalid account name rejected (v1.9.0 validate-name lib) ---
echo ""
echo "--- Scenario 5: invalid-name rejected ---"
TMP5=$(mktemp -d)
mkdir -p "$TMP5/cfg/dml"
echo 'HUBSPOT_PORTAL_ID="1"' > "$TMP5/cfg/dml/config.sh"
mkdir -p "$TMP5/proj"
exit5=0
HS_LANDER_CONFIG_DIR="$TMP5/cfg" HS_LANDER_PROJECT_DIR="$TMP5/proj" \
  bash "$REPO_DIR/scripts/scaffold-project.sh" '..' someproject >"$TMP5/log" 2>&1 || exit5=$?
assert_equal "$exit5" "1" "exit 1 on '..' account name"
assert_file_contains "$TMP5/log" "SCAFFOLD=error invalid-account-name" "invalid-account-name error"
# Project dir should not have scripts/ etc. populated by a rejected scaffold.
if [[ -d "$TMP5/proj/scripts" ]]; then
  assert_equal "files-copied" "must-not-have-been-copied" "scripts/ must not be created when validation rejected"
else
  assert_equal "1" "1" "no scripts/ written on validation rejection"
fi

exit6=0
HS_LANDER_CONFIG_DIR="$TMP5/cfg" HS_LANDER_PROJECT_DIR="$TMP5/proj" \
  bash "$REPO_DIR/scripts/scaffold-project.sh" dml 'Bad/Name' >"$TMP5/log6" 2>&1 || exit6=$?
assert_equal "$exit6" "1" "exit 1 on slash in project name"
assert_file_contains "$TMP5/log6" "SCAFFOLD=error invalid-project-name" "invalid-project-name error"
rm -rf "$TMP5"

test_summary
