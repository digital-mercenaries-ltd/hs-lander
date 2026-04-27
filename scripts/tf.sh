#!/usr/bin/env bash
# tf.sh — Read HubSpot token from Keychain, export TF_VAR_*, run terraform.
# Usage: scripts/tf.sh init|plan|apply|destroy [extra-args...]
#
# The `apply` verb (v1.9.0) requires a saved plan file produced by
# plan-review.sh. Without one, apply refuses with APPLY=error plan-file-missing.
# Set HS_LANDER_UNSAFE_APPLY=1 to bypass (recovery / debugging only) — backup
# of state still runs unconditionally before any apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
# Export so terraform local-exec provisioners (e.g.
# landing-page/emails.tf → terraform_data.publish_welcome_email) inherit
# the resolved value. Without this, a naked `npm run tf:plan` where the
# caller never set HS_LANDER_PROJECT_DIR would leave the variable empty
# in terraform's environment and any provisioner referencing it would
# point at /scripts/... instead of $PROJECT_DIR/scripts/...
export HS_LANDER_PROJECT_DIR="$PROJECT_DIR"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/keychain.sh"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

# Read token from Keychain using the service name from the account config.
# Lib helper closes the leak for the security call itself; the caller is
# still responsible for wrapping subsequent token-using expansions
# (`export TF_VAR_hubspot_token=...`) under `bash -x` if they care about
# xtrace hygiene end-to-end. See scripts/lib/keychain.sh for the contract.
: "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:?HUBSPOT_TOKEN_KEYCHAIN_SERVICE must be set in the account config}"
HUBSPOT_TOKEN=$(keychain_read "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE") || exit 1

# Export Terraform variables. Values sourced from the account config
# (via project.config.sh) and the project profile (same source chain).
# LANDING_SLUG / THANKYOU_SLUG default per hosting-mode conventions when
# the project profile doesn't set them; subscription/office-location are
# account-level and must be set somewhere in the sourcing chain.
export TF_VAR_hubspot_token="$HUBSPOT_TOKEN"
export TF_VAR_hubspot_portal_id="$HUBSPOT_PORTAL_ID"
export TF_VAR_domain="$DOMAIN"
export TF_VAR_hubspot_region="$HUBSPOT_REGION"
export TF_VAR_landing_slug="${LANDING_SLUG:-}"
export TF_VAR_thankyou_slug="${THANKYOU_SLUG:-thank-you}"
export TF_VAR_hubspot_subscription_id="${HUBSPOT_SUBSCRIPTION_ID:-}"
export TF_VAR_hubspot_office_location_id="${HUBSPOT_OFFICE_LOCATION_ID:-}"
export TF_VAR_email_preview_text="${EMAIL_PREVIEW_TEXT:-}"
export TF_VAR_auto_publish_welcome_email="${AUTO_PUBLISH_WELCOME_EMAIL:-true}"
export TF_VAR_email_reply_to="${EMAIL_REPLY_TO:-}"

# Verb dispatch. The `apply` verb is the safety-gated path; everything else
# falls through to plain terraform.
verb="${1:-}"
if [[ "$verb" == "apply" ]]; then
  shift || true

  # Resolve plan file: positional arg > $HS_LANDER_PLAN_FILE > default.
  plan_file=""
  if [[ $# -gt 0 && "$1" != -* ]]; then
    plan_file="$1"
    shift
  fi
  plan_file="${plan_file:-${HS_LANDER_PLAN_FILE:-$PROJECT_DIR/.hs-lander-plan.bin}}"

  # Always back up state before apply, even on the unsafe path. Backup is
  # advisory — non-zero exit from backup-file.sh does not block apply.
  state_file="${HS_LANDER_STATE_FILE:-$PROJECT_DIR/terraform/terraform.tfstate}"
  state_backup_dir="${HS_LANDER_STATE_BACKUP_DIR:-$PROJECT_DIR/terraform/state-backups}"
  bash "$SCRIPT_DIR/backup-file.sh" "$state_file" "$state_backup_dir" || \
    echo "WARNING: state backup failed; proceeding with apply" >&2

  if [[ ! -f "$plan_file" ]]; then
    if [[ "${HS_LANDER_UNSAFE_APPLY:-}" == "1" ]]; then
      echo "WARNING: HS_LANDER_UNSAFE_APPLY=1 — running plain 'terraform apply' with no saved plan file." >&2
      echo "WARNING: This bypasses the plan-review gate. Use only for recovery scenarios." >&2
      if terraform -chdir="$PROJECT_DIR/terraform" apply -auto-approve "$@"; then
        echo "APPLY=ok"
        exit 0
      else
        rc=$?
        echo "APPLY=error terraform-apply-failed"
        exit "$rc"
      fi
    fi
    echo "APPLY=error plan-file-missing $plan_file" >&2
    echo "Hint: run 'bash scripts/plan-review.sh' first, or set HS_LANDER_UNSAFE_APPLY=1 to bypass." >&2
    exit 1
  fi

  # Apply the saved plan. Terraform refuses if state has drifted since plan —
  # that's the correct safety behaviour; surface it verbatim.
  if terraform -chdir="$PROJECT_DIR/terraform" apply "$@" "$plan_file"; then
    rm -f "$plan_file"
    echo "APPLY=ok"
    exit 0
  else
    rc=$?
    echo "APPLY=error terraform-apply-failed"
    exit "$rc"
  fi
fi

# Run terraform
exec terraform -chdir="$PROJECT_DIR/terraform" "$@"
