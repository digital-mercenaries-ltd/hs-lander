#!/usr/bin/env bash
# test-projects-describe.sh — Validates projects-describe.sh emits the
# 14-line PROJECT_<KEY>=<value> contract for an existing profile, the
# `PROJECT_STATUS=missing` shape for a missing profile, and the
# `PROJECT_STATUS=error invalid-...-name` shape for invalid arguments.
#
# Mirrors test-accounts-describe.sh; the two scripts share contract shape.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-projects-describe.sh ==="

SCRIPT="$REPO_DIR/scripts/projects-describe.sh"
assert_file_exists "$SCRIPT" "scripts/projects-describe.sh exists"

run() {
  local cfg="$1" account="$2" project="$3" log="$4"
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" "$account" "$project" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: complete project profile → all 14 fields emitted ---
echo ""
echo "--- Scenario 1: complete project profile ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}"' EXIT
mkdir -p "$TMP1/dml"
cat > "$TMP1/dml/heard.sh" <<'EOF'
PROJECT_SLUG="heard"
DOMAIN="heard.example.com"
DM_UPLOAD_PATH="/heard"
GA4_MEASUREMENT_ID="G-HEARD123"
CAPTURE_FORM_ID="form-cap-1"
SURVEY_FORM_ID="form-sur-2"
LIST_ID="list-3"
LANDING_SLUG=""
THANKYOU_SLUG="thank-you"
HUBSPOT_SUBSCRIPTION_ID="2269639338"
HUBSPOT_OFFICE_LOCATION_ID="375327044798"
EMAIL_PREVIEW_TEXT="Welcome aboard"
AUTO_PUBLISH_WELCOME_EMAIL="true"
EMAIL_REPLY_TO="hello@mail.heard.example.com"
EOF
exit1=$(run "$TMP1" dml heard "$TMP1/log" || true)
assert_equal "$exit1" "0" "exit 0 when profile is complete"
assert_file_contains "$TMP1/log" "^PROJECT_SLUG=heard$" "PROJECT_SLUG reported"
assert_file_contains "$TMP1/log" "^PROJECT_DOMAIN=heard.example.com$" "PROJECT_DOMAIN reported"
assert_file_contains "$TMP1/log" "^PROJECT_DM_UPLOAD_PATH=/heard$" "PROJECT_DM_UPLOAD_PATH reported"
assert_file_contains "$TMP1/log" "^PROJECT_GA4_MEASUREMENT_ID=G-HEARD123$" "PROJECT_GA4_MEASUREMENT_ID reported"
assert_file_contains "$TMP1/log" "^PROJECT_CAPTURE_FORM_ID=form-cap-1$" "PROJECT_CAPTURE_FORM_ID reported"
assert_file_contains "$TMP1/log" "^PROJECT_SURVEY_FORM_ID=form-sur-2$" "PROJECT_SURVEY_FORM_ID reported"
assert_file_contains "$TMP1/log" "^PROJECT_LIST_ID=list-3$" "PROJECT_LIST_ID reported"
assert_file_contains "$TMP1/log" "^PROJECT_LANDING_SLUG=$" "PROJECT_LANDING_SLUG reported (empty)"
assert_file_contains "$TMP1/log" "^PROJECT_THANKYOU_SLUG=thank-you$" "PROJECT_THANKYOU_SLUG reported"
assert_file_contains "$TMP1/log" "^PROJECT_HUBSPOT_SUBSCRIPTION_ID=2269639338$" "PROJECT_HUBSPOT_SUBSCRIPTION_ID reported"
assert_file_contains "$TMP1/log" "^PROJECT_HUBSPOT_OFFICE_LOCATION_ID=375327044798$" "PROJECT_HUBSPOT_OFFICE_LOCATION_ID reported"
assert_file_contains "$TMP1/log" "^PROJECT_EMAIL_PREVIEW_TEXT=Welcome aboard$" "PROJECT_EMAIL_PREVIEW_TEXT reported"
assert_file_contains "$TMP1/log" "^PROJECT_AUTO_PUBLISH_WELCOME_EMAIL=true$" "PROJECT_AUTO_PUBLISH_WELCOME_EMAIL reported"
assert_file_contains "$TMP1/log" "^PROJECT_EMAIL_REPLY_TO=hello@mail.heard.example.com$" "PROJECT_EMAIL_REPLY_TO reported"

# Line count: exactly 14.
line_count=$(grep -c '^PROJECT_' "$TMP1/log")
assert_equal "$line_count" "14" "exactly 14 PROJECT_<KEY>= lines emitted"

# --- Scenario 2: profile missing ---
echo ""
echo "--- Scenario 2: missing project profile ---"
TMP2=$(mktemp -d)
mkdir -p "$TMP2/dml"
exit2=$(run "$TMP2" dml ghost "$TMP2/log" || true)
assert_equal "$exit2" "1" "exit 1 when profile missing"
assert_file_contains "$TMP2/log" "^PROJECT_STATUS=missing $TMP2/dml/ghost.sh$" "missing reported with full path"

# --- Scenario 3: usage error (no args) ---
echo ""
echo "--- Scenario 3: no args ---"
TMP3=$(mktemp -d)
exit3=0
HS_LANDER_CONFIG_DIR="$TMP3" bash "$SCRIPT" >"$TMP3/log" 2>&1 || exit3=$?
assert_equal "$exit3" "1" "exit 1 when no args"
assert_file_contains "$TMP3/log" "PROJECT_STATUS=error account and project names required" "usage error emitted"

# --- Scenario 4: invalid account name ---
echo ""
echo "--- Scenario 4: invalid account name ---"
TMP4=$(mktemp -d)
exit4=$(run "$TMP4" '..' someproj "$TMP4/log" || true)
assert_equal "$exit4" "1" "exit 1 on '..' account name (path-traversal defeated)"
assert_file_contains "$TMP4/log" "PROJECT_STATUS=error invalid-account-name" "invalid-account-name error emitted"

exit5=$(run "$TMP4" 'Foo' someproj "$TMP4/log5" || true)
assert_equal "$exit5" "1" "exit 1 on uppercase account name"
assert_file_contains "$TMP4/log5" "PROJECT_STATUS=error invalid-account-name" "invalid-account-name error for uppercase"

# --- Scenario 5: invalid project name ---
echo ""
echo "--- Scenario 5: invalid project name ---"
TMP5=$(mktemp -d)
mkdir -p "$TMP5/dml"
exit6=$(run "$TMP5" dml '..' "$TMP5/log" || true)
assert_equal "$exit6" "1" "exit 1 on '..' project name"
assert_file_contains "$TMP5/log" "PROJECT_STATUS=error invalid-project-name" "invalid-project-name error emitted"

exit7=$(run "$TMP5" dml 'a/b' "$TMP5/log7" || true)
assert_equal "$exit7" "1" "exit 1 on slash in project name"
assert_file_contains "$TMP5/log7" "PROJECT_STATUS=error invalid-project-name" "invalid-project-name error for slash"

# --- Scenario 6: profile with empty fields ---
# Mirror accounts-describe's pre-v1.5.0-style scenario: a sparse profile
# that only sets a few keys. The omitted ones should report as empty.
echo ""
echo "--- Scenario 6: sparse profile reports unset fields as empty ---"
mkdir -p "$TMP1/sparse-account"
cat > "$TMP1/sparse-account/sparse-project.sh" <<'EOF'
PROJECT_SLUG="sparse"
DOMAIN="sparse.example.com"
EOF
exit_sparse=$(run "$TMP1" sparse-account sparse-project "$TMP1/log_sparse" || true)
assert_equal "$exit_sparse" "0" "exit 0 on sparse profile"
assert_file_contains "$TMP1/log_sparse" "^PROJECT_SLUG=sparse$" "set field reported"
assert_file_contains "$TMP1/log_sparse" "^PROJECT_LANDING_SLUG=$" "unset LANDING_SLUG reports empty"
assert_file_contains "$TMP1/log_sparse" "^PROJECT_EMAIL_REPLY_TO=$" "unset EMAIL_REPLY_TO reports empty"

test_summary
