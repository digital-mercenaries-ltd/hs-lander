#!/usr/bin/env bash
# test-terraform-plan.sh — Validates terraform plan produces expected resources.
# Requires: terraform CLI installed. Downloads restapi provider on first run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
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
PLAN_JSON="$HARNESS_DIR/plan.json"
trap 'rm -f "$PLAN_FILE" "$PLAN_TXT" "$PLAN_JSON"' EXIT

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

# Minimum expected: project_source_property + capture_form + survey_form +
# landing_page + thankyou_page + welcome_email + contact_list +
# project_source_dependency (terraform_data anchor) = 8
if [[ "$add_count" -ge 8 ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "at least 8 resources to create (got $add_count)"

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
echo "--- Forms API v3: formType required ---"
# Both form payloads must carry formType = "hubspot" (Forms API v3 drift —
# the field became required post-v1.0.0 and missing it fails apply with
# "Some required fields were not set: [formType]").
formtype_count=$(grep -c 'formType\s*=\s*"hubspot"' "$PLAN_TXT" || true)
if [[ "$formtype_count" -ge 2 ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "both form payloads include formType=hubspot (got $formtype_count)"

echo ""
echo "--- Property→list dependency anchor ---"
# The contact_list must depend on the project_source property. We route
# that through a terraform_data resource inside the landing-page module
# whose input is var.project_source_property_id.
#
# Two invariants to verify — existence alone is not enough. A future
# refactor could leave the anchor in place but drop the edge; that would
# re-introduce the race condition silently.
#
# 1. The anchor resource exists in the plan.
# 2. contact_list carries `depends_on = [terraform_data.project_source_dependency]`
#    in its parsed configuration.

terraform -chdir="$HARNESS_DIR" show -json "$PLAN_FILE" > "$PLAN_JSON"

assert_file_contains "$PLAN_TXT" "project_source_dependency" \
  "terraform_data dependency anchor for project_source present in plan"

# Pull the contact_list resource's depends_on from the module config and
# confirm it names the anchor. Addresses inside module configuration are
# module-local (no "module.landing_page." prefix).
contact_list_deps=$(jq -r '
  .configuration.root_module.module_calls.landing_page.module.resources[]
  | select(.address == "restapi_object.contact_list")
  | .depends_on // []
  | join(",")
' "$PLAN_JSON")

if [[ ",$contact_list_deps," == *",terraform_data.project_source_dependency,"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" \
  "contact_list depends_on includes the project_source anchor (got: [$contact_list_deps])"

echo ""
echo "--- Marketing email v1.5.0 payload shape ---"
# The v1.5.0 email payload is structurally different from v1.4.0:
# - type is AUTOMATED_EMAIL (was REGULAR, which HubSpot silently coerced
#   to BATCH_EMAIL)
# - `from` is a nested object (was top-level fromName/replyTo, which
#   HubSpot silently dropped to null)
# - subscriptionDetails carries portal-specific IDs (was absent)
# - content uses DnD widget tree (primary_rich_text_module.body.rich_text
#   holds the HTML; content.html is gone — it was silently discarded)

assert_file_contains "$PLAN_TXT" 'type *= *"AUTOMATED_EMAIL"' \
  "welcome_email type is AUTOMATED_EMAIL"
assert_file_contains "$PLAN_TXT" 'subcategory *= *"automated"' \
  "welcome_email subcategory is automated"
assert_file_contains "$PLAN_TXT" 'emailTemplateMode *= *"DRAG_AND_DROP"' \
  "welcome_email uses DnD template mode"
assert_file_contains "$PLAN_TXT" 'fromName *= *"Test Project"' \
  "welcome_email fromName populated (inside nested from block)"
assert_file_contains "$PLAN_TXT" 'subscriptionId *= *"2269639338"' \
  "welcome_email subscriptionDetails.subscriptionId from fixture"
assert_file_contains "$PLAN_TXT" 'officeLocationId *= *"375327044798"' \
  "welcome_email subscriptionDetails.officeLocationId from fixture"
assert_file_contains "$PLAN_TXT" "primary_rich_text_module" \
  "welcome_email content has DnD primary_rich_text_module widget"

# Guard against regression to the broken v1.4.0 payload. The plan should
# never render content.html as an attribute, never mention REGULAR type.
if grep -qE '^\s+html +=' "$PLAN_TXT"; then
  result="false"
else
  result="true"
fi
assert_equal "$result" "true" "no top-level content.html (DnD widgets replaced it)"

if grep -qE 'type *= *"REGULAR"' "$PLAN_TXT"; then
  result="false"
else
  result="true"
fi
assert_equal "$result" "true" "email type is not the broken REGULAR value"

echo ""
echo "--- Hosting-modes plumbing ---"
# Fixture uses landing_slug = "" (default) and thankyou_slug = "thank-you".
# The thankyou_page slug must appear verbatim in the plan — confirms
# var.thankyou_slug flows through. No UUID-mangled slug should appear
# (that was the v1.0.0 symptom on empty-domain, empty-slug paths).
assert_file_contains "$PLAN_TXT" 'slug *= *"thank-you"' \
  "thankyou_page slug honoured from var.thankyou_slug"

if grep -qE 'slug += "-temporary-slug-' "$PLAN_TXT"; then
  result="false"
else
  result="true"
fi
assert_equal "$result" "true" "no placeholder UUID slugs in plan output"

echo ""
echo "--- v1.8.1 B1: dropdown survey field renders correct fieldType ---"
# The fixture declares one survey_field with type="dropdown". The v1.8.0
# renderer informed-guessed `fieldType = "single_line_text"` here; v1.8.1
# Fix 10 corrects it to `fieldType = "dropdown"`. Heard's deploy surfaced
# the original miss. A regression that re-introduces the wrong mapping
# would let HubSpot Forms v3 reject the apply with a fieldType error.
assert_file_contains "$PLAN_TXT" 'fieldType *= *"dropdown"' \
  "survey form renders dropdown fieldType (B1 fix)"

# Belt-and-braces: the dropdown options array must populate from the
# fixture's options=["Designer","Engineer","Other"].
assert_file_contains "$PLAN_TXT" '"Designer"' \
  "dropdown option Designer in plan"
assert_file_contains "$PLAN_TXT" '"Engineer"' \
  "dropdown option Engineer in plan"

echo ""
echo "--- v1.8.1 B2: bool properties carry canonical True/False options ---"
# include_survey=true auto-instantiates the <slug>_survey_completed bool
# property via properties.tf. v1.8.0 emitted no options array; HubSpot CRM
# 400s on bool create without it. v1.8.1 Fix 11 adds the canonical pair.
assert_file_contains "$PLAN_TXT" "test-project_survey_completed" \
  "bool survey_completed property in plan"
assert_file_contains "$PLAN_TXT" 'label *= *"True"' \
  "bool property carries True option (B2 fix)"
assert_file_contains "$PLAN_TXT" 'label *= *"False"' \
  "bool property carries False option (B2 fix)"
assert_file_contains "$PLAN_TXT" 'value *= *"true"' \
  "bool property True option has value=\"true\""
assert_file_contains "$PLAN_TXT" 'value *= *"false"' \
  "bool property False option has value=\"false\""

echo ""
echo "--- v1.8.1 B5: survey_form depends_on custom_property ---"
# v1.8.0 lacked this depends_on; Heard hit a race where HubSpot 400'd the
# form because field names referenced properties not yet on the contact
# schema. Workaround was two-pass apply. v1.8.1 Fix 12 closes the race
# with a graph edge. Verify the edge survives in the parsed config —
# existence in the plan text alone is not enough; the edge could be
# rendered as a comment without affecting the graph.
survey_form_deps=$(jq -r '
  .configuration.root_module.module_calls.landing_page.module.resources[]
  | select(.address == "restapi_object.survey_form")
  | .depends_on // []
  | join(",")
' "$PLAN_JSON")

if [[ ",$survey_form_deps," == *",restapi_object.custom_property,"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" \
  "survey_form depends_on includes restapi_object.custom_property (got: [$survey_form_deps])"

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
