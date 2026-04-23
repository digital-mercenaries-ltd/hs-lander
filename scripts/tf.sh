#!/usr/bin/env bash
# tf.sh — Read HubSpot token from Keychain, export TF_VAR_*, run terraform.
# Usage: scripts/tf.sh init|plan|apply|destroy [extra-args...]
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
# Export so terraform local-exec provisioners (e.g.
# landing-page/emails.tf → terraform_data.publish_welcome_email) inherit
# the resolved value. Without this, a naked `npm run tf:plan` where the
# caller never set HS_LANDER_PROJECT_DIR would leave the variable empty
# in terraform's environment and any provisioner referencing it would
# point at /scripts/... instead of $PROJECT_DIR/scripts/...
export HS_LANDER_PROJECT_DIR="$PROJECT_DIR"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

# Read token from Keychain using the service name from the account config.
: "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:?HUBSPOT_TOKEN_KEYCHAIN_SERVICE must be set in the account config}"
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE'." >&2
  echo "Add it with: security add-generic-password -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'" >&2
  exit 1
}

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

# Run terraform
exec terraform -chdir="$PROJECT_DIR/terraform" "$@"
