#!/usr/bin/env bash
# test-migrate-project.sh — Validates scripts/migrate-project.sh moves
# a project's terraform/main.tf from one framework version to another,
# applying the migration rules in scripts/lib/migration-rules.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-migrate-project.sh ==="

SCRIPT="$REPO_DIR/scripts/migrate-project.sh"
assert_file_exists "$SCRIPT" "scripts/migrate-project.sh exists"

# Synthetic v1.6.0-era main.tf — minimal content matching the shape of
# scaffolds from that era (single ?ref= pin per module block, no
# email_reply_to / email_preview_text / auto_publish_welcome_email /
# capture_post_submit_action_override root variables yet).
make_v1_6_0_main_tf() {
  cat <<'TF'
terraform {
  required_providers {
    restapi = { source = "Mastercard/restapi", version = "~> 2.0" }
  }
}

variable "hubspot_token" { type = string, sensitive = true }
variable "hubspot_portal_id" { type = string }
variable "domain" { type = string }
variable "hubspot_region" { type = string }

module "account_setup" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v1.6.0"
}

module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.6.0"

  hubspot_portal_id = var.hubspot_portal_id
  domain            = var.domain
}
TF
}

# --- Scenario 1: noop when pinned matches target ---
echo ""
echo "--- Scenario 1: noop when pinned matches target ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}"' EXIT
mkdir -p "$TMP1/terraform"
make_v1_6_0_main_tf > "$TMP1/terraform/main.tf"
exit1=0
out1=$(bash "$SCRIPT" "$TMP1" "1.6.0" 2>&1) || exit1=$?
assert_equal "$exit1" "0" "noop exits 0"
if [[ "$out1" == *"MIGRATE=noop pinned=1.6.0"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "noop output emitted (got: $out1)"

# --- Scenario 2: error when terraform/main.tf missing ---
echo ""
echo "--- Scenario 2: error when terraform/main.tf missing ---"
TMP2=$(mktemp -d)
exit2=0
out2=$(bash "$SCRIPT" "$TMP2" "1.9.0" 2>&1) || exit2=$?
assert_equal "$exit2" "1" "exit 1 when main.tf missing"
if [[ "$out2" == *"MIGRATE=error main-tf-missing"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "main-tf-missing error emitted (got: $out2)"

# --- Scenario 3: plan-only by default ---
echo ""
echo "--- Scenario 3: plan-only by default (no --apply) ---"
TMP3=$(mktemp -d)
mkdir -p "$TMP3/terraform"
make_v1_6_0_main_tf > "$TMP3/terraform/main.tf"
before_content=$(cat "$TMP3/terraform/main.tf")
exit3=0
out3=$(bash "$SCRIPT" "$TMP3" "1.7.0" 2>&1) || exit3=$?
assert_equal "$exit3" "0" "plan-only exits 0"
if [[ "$out3" == *"MIGRATE=plan-only"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "plan-only terminator emitted"
# Step lines were emitted
step_count_log=$(echo "$out3" | grep -c '^MIGRATE_STEP=' || true)
if [[ "$step_count_log" -gt 0 ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "MIGRATE_STEP= lines emitted in plan-only"
# File unchanged in plan-only mode
after_content=$(cat "$TMP3/terraform/main.tf")
assert_equal "$after_content" "$before_content" "main.tf unchanged in plan-only mode"

# --- Scenario 4: --apply applies the migration ---
echo ""
echo "--- Scenario 4: --apply rewrites main.tf ---"
TMP4=$(mktemp -d)
mkdir -p "$TMP4/terraform"
make_v1_6_0_main_tf > "$TMP4/terraform/main.tf"
exit4=0
out4=$(bash "$SCRIPT" "$TMP4" "1.7.0" --apply 2>&1) || exit4=$?
assert_equal "$exit4" "0" "--apply exits 0 on success"
if [[ "$out4" == *"MIGRATE=ok pinned=1.6.0 → 1.7.0"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "ok terminator names from/to versions"

# Assertions about the actual file edits:
assert_file_contains "$TMP4/terraform/main.tf" '\?ref=v1\.7\.0' \
  "?ref= bumped to v1.7.0"
if grep -q '?ref=v1\.6\.0' "$TMP4/terraform/main.tf"; then
  result="false"
else
  result="true"
fi
assert_equal "$result" "true" "no ?ref=v1.6.0 references remain"

assert_file_contains "$TMP4/terraform/main.tf" '^variable "email_preview_text" {' \
  "email_preview_text root variable declared"
assert_file_contains "$TMP4/terraform/main.tf" '^variable "auto_publish_welcome_email" {' \
  "auto_publish_welcome_email root variable declared"
assert_file_contains "$TMP4/terraform/main.tf" '^variable "capture_post_submit_action_override" {' \
  "capture_post_submit_action_override root variable declared"

assert_file_contains "$TMP4/terraform/main.tf" 'email_preview_text = var\.email_preview_text' \
  "email_preview_text wired into module.landing_page"
assert_file_contains "$TMP4/terraform/main.tf" 'auto_publish_welcome_email = var\.auto_publish_welcome_email' \
  "auto_publish_welcome_email wired into module.landing_page"
assert_file_contains "$TMP4/terraform/main.tf" 'capture_post_submit_action_override = var\.capture_post_submit_action_override' \
  "capture_post_submit_action_override wired into module.landing_page"

# --- Scenario 5: idempotent — re-running --apply yields noop or no further changes ---
echo ""
echo "--- Scenario 5: idempotent re-apply ---"
content_after_first_apply=$(cat "$TMP4/terraform/main.tf")
exit5=0
out5=$(bash "$SCRIPT" "$TMP4" "1.7.0" --apply 2>&1) || exit5=$?
assert_equal "$exit5" "0" "second run exits 0"
if [[ "$out5" == *"MIGRATE=noop pinned=1.7.0"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "second run is noop"
content_after_second_apply=$(cat "$TMP4/terraform/main.tf")
assert_equal "$content_after_second_apply" "$content_after_first_apply" \
  "second run leaves file unchanged"

# --- Scenario 6: chained migration v1.6.0 → v1.9.0 ---
echo ""
echo "--- Scenario 6: chained migration v1.6.0 → v1.9.0 ---"
TMP5=$(mktemp -d)
mkdir -p "$TMP5/terraform"
make_v1_6_0_main_tf > "$TMP5/terraform/main.tf"
exit6=0
out6=$(bash "$SCRIPT" "$TMP5" "1.9.0" --apply 2>&1) || exit6=$?
assert_equal "$exit6" "0" "chained migration exits 0"
if [[ "$out6" == *"MIGRATE=ok pinned=1.6.0 → 1.9.0"* ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "chained migration ok terminator"
# All four root variables present (the v1.6.0 → v1.7.0 three plus
# v1.8.0 → v1.8.1's email_reply_to)
assert_file_contains "$TMP5/terraform/main.tf" '^variable "email_reply_to" {' \
  "email_reply_to declared after v1.6.0 → v1.9.0 chain"
assert_file_contains "$TMP5/terraform/main.tf" 'email_reply_to = var\.email_reply_to' \
  "email_reply_to wired after chain"
# Final ?ref= pinned to v1.9.0
assert_file_contains "$TMP5/terraform/main.tf" '\?ref=v1\.9\.0' \
  "chained migration ends with ?ref=v1.9.0"

test_summary
