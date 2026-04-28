#!/usr/bin/env bash
# test-scaffold-terraform-plan.sh — Validates that scaffold/terraform/main.tf
# itself produces a valid terraform plan. Distinct from test-terraform-plan.sh
# which uses tests/fixtures/terraform/main.tf and bypasses the scaffold root.
#
# v1.8.1's scaffold-pin defect (?ref= stuck at v1.6.0 across multiple
# releases) and Component 2's four-root-variable wiring miss were both
# invisible to CI because the existing plan test bypasses scaffold/. This
# test exercises the actual file consumers copy into their projects and
# catches scaffold-root drift at CI time.
#
# Strategy: copy scaffold/terraform/main.tf to a temp dir, sed-substitute
# the remote git module sources to local relative paths so terraform init
# resolves without network, provide minimal terraform.tfvars + a stub
# welcome-body.html, then init + plan + assert.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-scaffold-terraform-plan.sh ==="

SCAFFOLD_TF="$REPO_DIR/scaffold/terraform/main.tf"
assert_file_exists "$SCAFFOLD_TF" "scaffold/terraform/main.tf exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Setup: create a project structure that mirrors scaffold-project.sh ---
mkdir -p "$TMPDIR/terraform" "$TMPDIR/dist/emails"

# Copy scaffold/terraform/main.tf into the test project.
cp "$SCAFFOLD_TF" "$TMPDIR/terraform/main.tf"

# Rewrite the remote git module sources to local relative paths so
# terraform init resolves without network. Use the same `|` delimiter
# convention as build.sh (DM_UPLOAD_PATH-friendly) and target both
# module blocks.
ACCOUNT_SETUP_PATH="$REPO_DIR/terraform/modules/account-setup"
LANDING_PAGE_PATH="$REPO_DIR/terraform/modules/landing-page"

sed -i.bak \
  -e "s|git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v[^\"]*|$ACCOUNT_SETUP_PATH|" \
  -e "s|git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v[^\"]*|$LANDING_PAGE_PATH|" \
  "$TMPDIR/terraform/main.tf"
rm -f "$TMPDIR/terraform/main.tf.bak"

# Minimal welcome-body.html so the file() call resolves.
cat > "$TMPDIR/dist/emails/welcome-body.html" <<'HTML'
<p>Welcome (test).</p>
HTML

# terraform.tfvars covering the required root variables.
cat > "$TMPDIR/terraform/terraform.tfvars" <<'TFVARS'
hubspot_token              = "test-token-not-used-for-plan"
hubspot_portal_id          = "12345678"
domain                     = "scaffold-test.example.com"
hubspot_region             = "eu1"
hubspot_subscription_id    = "2269639338"
hubspot_office_location_id = "375327044798"
email_reply_to             = "hello@scaffold-test.example.com"
TFVARS

# --- Init ---
echo "Running terraform init..."
PLAN_FILE="$TMPDIR/terraform/test.tfplan"
PLAN_TXT="$TMPDIR/plan.txt"
PLAN_JSON="$TMPDIR/plan.json"

terraform -chdir="$TMPDIR/terraform" init -backend=false -input=false >"$TMPDIR/init.log" 2>&1 || {
  echo "terraform init failed:"
  cat "$TMPDIR/init.log"
  exit 1
}

# --- Plan ---
echo "Running terraform plan..."
terraform -chdir="$TMPDIR/terraform" plan \
  -out="$PLAN_FILE" \
  -input=false \
  -no-color >"$PLAN_TXT" 2>&1 || {
  echo "terraform plan failed:"
  cat "$PLAN_TXT"
  exit 1
}

terraform -chdir="$TMPDIR/terraform" show -json "$PLAN_FILE" > "$PLAN_JSON"

# --- Assertions ---

echo ""
echo "--- Scaffold pins ?ref= to current VERSION ---"
# Read the original (un-rewritten) scaffold to inspect the pinned ?ref=.
# This is the key assertion that would have caught v1.8.1's stuck
# ?ref=v1.6.0 defect. We grep the source file directly, not the temp
# copy where we rewrote the path.
expected_version=$(tr -d '[:space:]' < "$REPO_DIR/VERSION")
expected_ref="v$expected_version"

scaffold_refs=$(grep -oE '\?ref=v[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.-]*' "$SCAFFOLD_TF" | sort -u)
ref_count=$(printf '%s\n' "$scaffold_refs" | wc -l | tr -d ' ')
assert_equal "$ref_count" "1" "scaffold's two module sources pin the same ?ref= (got: $scaffold_refs)"

actual_ref=$(echo "$scaffold_refs" | sed -E 's/^\?ref=//')
assert_equal "$actual_ref" "$expected_ref" "scaffold's ?ref= matches the framework's current VERSION ($expected_ref)"

echo ""
echo "--- Scaffold root declares all four post-v1.6.0 variables ---"
# Every variable consumed via var.<name> by the module block must be
# declared at the scaffold root. v1.8.1's miss was three of these four
# being unwired despite tf.sh exporting them.
for var_name in email_reply_to email_preview_text auto_publish_welcome_email capture_post_submit_action_override; do
  if grep -qE "^variable \"${var_name}\" \{" "$SCAFFOLD_TF"; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    echo "  PASS: scaffold root declares variable \"$var_name\""
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "  FAIL: scaffold root missing variable \"$var_name\""
  fi
done

echo ""
echo "--- Scaffold module block wires all four post-v1.6.0 variables ---"
# A variable can be declared but unwired (the v1.6.0 → v1.7.0 oversight
# pattern). Verify each is passed to module.landing_page in the actual
# module block.
for var_name in email_reply_to email_preview_text auto_publish_welcome_email capture_post_submit_action_override; do
  if grep -qE "${var_name}\s*=\s*var\.${var_name}" "$SCAFFOLD_TF"; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    echo "  PASS: module.landing_page wires $var_name = var.$var_name"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "  FAIL: module.landing_page does not wire $var_name"
  fi
done

echo ""
echo "--- Plan resources match the fixture-rooted plan ---"
# The same module instantiations should appear regardless of which root
# main.tf drives the plan. We don't compare full byte-equality with the
# fixture's plan (different domain, different project_slug) — just check
# that the same restapi_object resources are present.
for resource in capture_form welcome_email contact_list landing_page thankyou_page project_source_property; do
  if grep -q "$resource" "$PLAN_TXT"; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    echo "  PASS: scaffold-rooted plan includes restapi_object.$resource"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "  FAIL: scaffold-rooted plan missing restapi_object.$resource"
  fi
done

echo ""
echo "--- Scaffold root passes through the four new vars ---"
# Confirm via the JSON plan that landing_page receives the four values.
# Easier than parsing the text plan; consistent with how
# test-terraform-plan.sh validates contact_list dependencies.
for var_name in email_reply_to email_preview_text auto_publish_welcome_email capture_post_submit_action_override; do
  expr=$(jq -r --arg v "$var_name" '
    .configuration.root_module.module_calls.landing_page.expressions[$v]
    | if . == null then "MISSING"
      elif .references != null then "var-ref"
      else "literal"
      end
  ' "$PLAN_JSON")
  if [[ "$expr" == "var-ref" ]]; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    echo "  PASS: landing_page.$var_name plumbed through var.$var_name"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "  FAIL: landing_page.$var_name expression was '$expr' (expected var-ref)"
  fi
done

test_summary
