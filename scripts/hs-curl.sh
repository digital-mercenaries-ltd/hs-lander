#!/usr/bin/env bash
# hs-curl.sh — Read HubSpot token from Keychain, run curl against HubSpot API.
# Usage: scripts/hs-curl.sh GET /crm/v3/properties/contacts
#        scripts/hs-curl.sh POST /marketing/v3/forms -d '{"name":"test"}'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: hs-curl.sh METHOD /api/path [curl-args...]" >&2
  exit 1
fi

METHOD="$1"
API_PATH="$2"
shift 2

# Read token from Keychain
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-access-token" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-access-token from Keychain." >&2
  exit 1
}

exec curl -s -X "$METHOD" \
  "https://api.hubapi.com${API_PATH}" \
  -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "$@"
