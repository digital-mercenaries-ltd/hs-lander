#!/usr/bin/env bash
# plan-review.sh — Pre-apply review gate.
#
# Usage:    bash scripts/plan-review.sh [--plan-file PATH]
# Output:   stable-order key=value lines (see contract below)
# Exit:     0 always when the plan succeeds; non-zero only on infrastructure
#           errors (terraform/jq failure, missing config).
#
# Output contract:
#   PLAN_CREATE=<count>
#   PLAN_UPDATE=<count>
#   PLAN_DELETE=<count>
#   PLAN_REPLACE=<count>
#   PLAN_RESOURCES=<json {create:[],update:[],delete:[],replace:[]}>
#   PLAN_FILE=<absolute path to saved plan file>
#   PLAN_REVIEW=ok|confirm
#   PLAN_REVIEW_SEVERITY=info|caution|destructive   (only when PLAN_REVIEW=confirm)
#
# Thresholds (configurable via env):
#   HS_LANDER_MAX_CREATE — default 50 (caution when exceeded)
#   HS_LANDER_MAX_UPDATE — default 100 (info when exceeded)
#   destroy/replace thresholds are fixed at 0 — any destructive change
#   triggers severity=destructive.
#
# The gate is advisory: PLAN_REVIEW=confirm does NOT exit non-zero. The caller
# (skill or chained npm script) inspects the output and decides whether to
# proceed to apply.
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
export HS_LANDER_PROJECT_DIR="$PROJECT_DIR"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/keychain.sh"

# Parse args
plan_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-file)
      plan_file="$2"
      shift 2
      ;;
    *)
      echo "PLAN_REVIEW=error unknown-arg '$1'" >&2
      exit 1
      ;;
  esac
done

plan_file="${plan_file:-${HS_LANDER_PLAN_FILE:-$PROJECT_DIR/.hs-lander-plan.bin}}"

# Ensure jq is present (preflight already requires it but plan-review may run
# in isolation).
if ! command -v jq >/dev/null 2>&1; then
  echo "PLAN_REVIEW=error jq-missing" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "PLAN_REVIEW=error terraform-missing" >&2
  exit 1
fi

# Source config + Keychain → TF_VAR_* (mirrors tf.sh). Skipped when the
# project.config.sh isn't present (test fixtures may invoke plan-review.sh
# directly against a Terraform dir with TF_VAR_* / no provider needs).
if [[ -f "$PROJECT_DIR/project.config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/project.config.sh"

  : "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:?HUBSPOT_TOKEN_KEYCHAIN_SERVICE must be set in the account config}"
  HUBSPOT_TOKEN=$(keychain_read "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE") || exit 1

  export TF_VAR_hubspot_token="$HUBSPOT_TOKEN"
  export TF_VAR_hubspot_portal_id="${HUBSPOT_PORTAL_ID:-}"
  export TF_VAR_domain="${DOMAIN:-}"
  export TF_VAR_hubspot_region="${HUBSPOT_REGION:-}"
  export TF_VAR_landing_slug="${LANDING_SLUG:-}"
  export TF_VAR_thankyou_slug="${THANKYOU_SLUG:-thank-you}"
  export TF_VAR_hubspot_subscription_id="${HUBSPOT_SUBSCRIPTION_ID:-}"
  export TF_VAR_hubspot_office_location_id="${HUBSPOT_OFFICE_LOCATION_ID:-}"
  export TF_VAR_email_preview_text="${EMAIL_PREVIEW_TEXT:-}"
  export TF_VAR_auto_publish_welcome_email="${AUTO_PUBLISH_WELCOME_EMAIL:-true}"
  export TF_VAR_email_reply_to="${EMAIL_REPLY_TO:-}"
fi

TF_DIR="${HS_LANDER_TF_DIR:-$PROJECT_DIR/terraform}"

# Run terraform plan, capturing stderr for diagnostics if it fails.
plan_log="$(mktemp)"
trap 'rm -f "$plan_log"' EXIT

if ! terraform -chdir="$TF_DIR" plan -out="$plan_file" -input=false >"$plan_log" 2>&1; then
  echo "PLAN_REVIEW=error terraform-plan-failed see $plan_log" >&2
  cat "$plan_log" >&2
  exit 1
fi

# Render plan as JSON and tally actions.
plan_json="$(terraform -chdir="$TF_DIR" show -json "$plan_file" 2>/dev/null)" || {
  echo "PLAN_REVIEW=error terraform-show-failed" >&2
  exit 1
}

# Counts. A "replace" plan is encoded as actions ["delete","create"] in
# .resource_changes[].change.actions; surface that separately from plain
# create/delete.
counts=$(jq -r '
  .resource_changes // [] |
  reduce .[] as $rc (
    {create:0, update:0, delete:0, replace:0,
     create_addrs:[], update_addrs:[], delete_addrs:[], replace_addrs:[]};
    ($rc.change.actions // []) as $a |
    if $a == ["create"] then
      .create += 1 | .create_addrs += [$rc.address]
    elif $a == ["update"] then
      .update += 1 | .update_addrs += [$rc.address]
    elif $a == ["delete"] then
      .delete += 1 | .delete_addrs += [$rc.address]
    elif ($a == ["delete","create"] or $a == ["create","delete"]) then
      .replace += 1 | .replace_addrs += [$rc.address]
    else . end
  ) |
  "\(.create)\t\(.update)\t\(.delete)\t\(.replace)\t\(
    {create:.create_addrs, update:.update_addrs, delete:.delete_addrs, replace:.replace_addrs}
    | tojson
  )"
' <<<"$plan_json")

create=$(printf '%s' "$counts" | cut -f1)
update=$(printf '%s' "$counts" | cut -f2)
delete=$(printf '%s' "$counts" | cut -f3)
replace=$(printf '%s' "$counts" | cut -f4)
resources_json=$(printf '%s' "$counts" | cut -f5-)

# Resolve plan file to absolute path for output.
plan_file_abs="$plan_file"
if [[ "$plan_file_abs" != /* ]]; then
  plan_file_abs="$PROJECT_DIR/$plan_file"
fi

# Thresholds.
max_create="${HS_LANDER_MAX_CREATE:-50}"
max_update="${HS_LANDER_MAX_UPDATE:-100}"

# Decide review state and severity. Highest severity wins:
# destructive > caution > info.
review="ok"
severity=""

if (( delete > 0 || replace > 0 )); then
  review="confirm"
  severity="destructive"
elif (( create > max_create )); then
  review="confirm"
  severity="caution"
elif (( update > max_update )); then
  review="confirm"
  severity="info"
fi

# Emit contract (stable order).
echo "PLAN_CREATE=$create"
echo "PLAN_UPDATE=$update"
echo "PLAN_DELETE=$delete"
echo "PLAN_REPLACE=$replace"
echo "PLAN_RESOURCES=$resources_json"
echo "PLAN_FILE=$plan_file_abs"
echo "PLAN_REVIEW=$review"
if [[ "$review" == "confirm" ]]; then
  echo "PLAN_REVIEW_SEVERITY=$severity"
fi

exit 0
