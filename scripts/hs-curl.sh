#!/usr/bin/env bash
# hs-curl.sh — Read HubSpot token from Keychain, run curl against HubSpot API.
# Usage: scripts/hs-curl.sh GET /crm/v3/properties/contacts
#        scripts/hs-curl.sh POST /marketing/v3/forms -d '{"name":"test"}'
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/keychain.sh"

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: hs-curl.sh METHOD /api/path [curl-args...]" >&2
  exit 1
fi

METHOD="$1"
API_PATH="$2"
shift 2

# Read token from Keychain using the service name from the account config.
# v1.9.0 (Component 2.4): xtrace-safe lib helper.
: "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:?HUBSPOT_TOKEN_KEYCHAIN_SERVICE must be set in the account config}"
HUBSPOT_TOKEN=$(keychain_read "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE") || exit 1

exec curl -s -X "$METHOD" \
  "https://api.hubapi.com${API_PATH}" \
  -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "$@"
