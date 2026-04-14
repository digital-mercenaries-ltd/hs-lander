#!/usr/bin/env bash
# tf.sh — Read HubSpot token from Keychain, export TF_VAR_*, run terraform.
# Usage: scripts/tf.sh init|plan|apply|destroy [extra-args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

# Read token from Keychain
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-access-token" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-access-token from Keychain." >&2
  echo "Add it with: security add-generic-password -s '${KEYCHAIN_PREFIX}-hubspot-access-token' -a \"\$USER\" -w 'TOKEN'" >&2
  exit 1
}

# Export Terraform variables
export TF_VAR_hubspot_token="$HUBSPOT_TOKEN"
export TF_VAR_hubspot_portal_id="$HUBSPOT_PORTAL_ID"
export TF_VAR_domain="$DOMAIN"
export TF_VAR_hubspot_region="$HUBSPOT_REGION"

# Run terraform
exec terraform -chdir="$PROJECT_DIR/terraform" "$@"
