#!/usr/bin/env bash
# test-terraform-plan.sh — Validates terraform plan produces expected resources.
# Requires: terraform CLI installed. Downloads restapi provider on first run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=fixtures/test-helper.sh
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-terraform-plan.sh ==="

HARNESS_DIR="$REPO_DIR/tests/fixtures/terraform"

# --- Init ---
echo "Running terraform init..."
terraform -chdir="$HARNESS_DIR" init -backend=false -input=false >/dev/null 2>&1 || {
  echo "terraform init failed — re-running with output:"
  terraform -chdir="$HARNESS_DIR" init -backend=false -input=false
  exit 1
}

# --- Plan ---
echo "Running terraform plan..."
PLAN_FILE="$HARNESS_DIR/test.tfplan"
PLAN_TXT="$HARNESS_DIR/plan.txt"
trap 'rm -f "$PLAN_FILE" "$PLAN_TXT"' EXIT

terraform -chdir="$HARNESS_DIR" plan \
  -out="$PLAN_FILE" \
  -input=false \
  -no-color 2>&1 | tee "$PLAN_TXT"

# --- Parse plan output ---
PLAN_TEXT=$(cat "$PLAN_TXT")

echo ""
echo "--- Expected resources in plan ---"

# Count resources to add
add_count=$(echo "$PLAN_TEXT" | grep -c "will be created" || true)

# Minimum expected: project_source_property + capture_form + landing_page +
# thankyou_page + welcome_email + contact_list = 6
if [[ "$add_count" -ge 6 ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "at least 6 resources to create (got $add_count)"

# Check specific resources by name
assert_file_contains "$PLAN_TXT" "project_source_property" \
  "account-setup: project_source CRM property"

assert_file_contains "$PLAN_TXT" "capture_form" \
  "landing-page: capture form"

assert_file_contains "$PLAN_TXT" "landing_page" \
  "landing-page: landing page"

assert_file_contains "$PLAN_TXT" "thankyou_page" \
  "landing-page: thank-you page"

assert_file_contains "$PLAN_TXT" "welcome_email" \
  "landing-page: welcome email"

assert_file_contains "$PLAN_TXT" "contact_list" \
  "landing-page: contact list"

echo ""
echo "--- No unexpected destroy actions ---"
destroy_count=$(echo "$PLAN_TEXT" | grep -c "will be destroyed" || true)
assert_equal "$destroy_count" "0" "no resources to destroy"

echo ""
echo "--- Resource naming includes project_slug ---"
assert_file_contains "$PLAN_TXT" "test-project" \
  "project slug appears in plan"

echo ""
echo "--- Domain matches config ---"
assert_file_contains "$PLAN_TXT" "test.example.com" \
  "domain appears in plan"

test_summary
