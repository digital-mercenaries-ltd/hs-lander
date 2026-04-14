#!/usr/bin/env bash
# hs.sh — Optional HubSpot CLI wrapper for local debugging.
# Reads PAK from Keychain. Not part of the core workflow.
# Requires: npm install -g @hubspot/cli
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

# Read PAK from Keychain (separate from Service Key)
HUBSPOT_PAK=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-pak" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-pak from Keychain." >&2
  echo "The HubSpot CLI requires a Personal Access Key (PAK), not a Service Key." >&2
  echo "This script is optional — use deploy.sh for the core workflow." >&2
  exit 1
}

export HUBSPOT_PERSONAL_ACCESS_KEY="$HUBSPOT_PAK"
exec hs "$@"
