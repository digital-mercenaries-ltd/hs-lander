#!/usr/bin/env bash
# preflight.sh — validate config, credentials, and HubSpot account readiness
# before build/deploy. Structured output so the skill (or a human) can parse
# what's done vs missing.
#
# Usage: bash scripts/preflight.sh
# Exit 0: all required checks pass. Exit 1: one or more required checks failed.
#
# Output format: each check prints a single line of the form
#   PREFLIGHT_<NAME>=ok|missing|error|warn|skipped [detail]
#
# Credential safety: tokens are read into a variable, used for API tests, then
# unset. Token values NEVER appear on stdout, stderr, or any file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

required_failed=0

# --- Config discovery ---

if [[ ! -f "$PROJECT_DIR/project.config.sh" ]]; then
  echo "PREFLIGHT_CONFIG=missing project.config.sh not found in $PROJECT_DIR"
  exit 1
fi

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

missing_vars=()
for var in HUBSPOT_PORTAL_ID HUBSPOT_REGION DOMAIN PROJECT_SLUG DM_UPLOAD_PATH HUBSPOT_TOKEN_KEYCHAIN_SERVICE; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done

if [[ ${#missing_vars[@]} -eq 0 ]]; then
  echo "PREFLIGHT_CONFIG=ok"
else
  echo "PREFLIGHT_CONFIG=missing ${missing_vars[*]}"
  required_failed=1
fi

# --- Credential + API checks ---

if [[ -z "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:-}" ]]; then
  echo "PREFLIGHT_CREDENTIAL=missing HUBSPOT_TOKEN_KEYCHAIN_SERVICE not set in account config"
  echo "PREFLIGHT_API_ACCESS=skipped (no credential)"
  echo "PREFLIGHT_PROJECT_SOURCE=skipped (no credential)"
  required_failed=1
else
  token=""
  if token=$(security find-generic-password \
               -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" \
               -a "$USER" -w 2>/dev/null); then
    echo "PREFLIGHT_CREDENTIAL=ok"

    api_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $token" \
      "https://api.hubapi.com/account-info/v3/details")
    if [[ "$api_status" == "200" ]]; then
      echo "PREFLIGHT_API_ACCESS=ok"
    else
      echo "PREFLIGHT_API_ACCESS=error HubSpot API returned HTTP $api_status"
      required_failed=1
    fi

    ps_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $token" \
      "https://api.hubapi.com/crm/v3/properties/contacts/project_source")
    case "$ps_status" in
      200) echo "PREFLIGHT_PROJECT_SOURCE=ok" ;;
      404)
        echo "PREFLIGHT_PROJECT_SOURCE=missing (first project on this account — account-setup module needed)"
        required_failed=1
        ;;
      *)
        echo "PREFLIGHT_PROJECT_SOURCE=error HubSpot API returned HTTP $ps_status"
        required_failed=1
        ;;
    esac

    unset token
  else
    echo "PREFLIGHT_CREDENTIAL=missing Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' not found"
    echo "  Add it with: security add-generic-password -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'"
    echo "PREFLIGHT_API_ACCESS=skipped (no credential)"
    echo "PREFLIGHT_PROJECT_SOURCE=skipped (no credential)"
    required_failed=1
  fi
fi

# --- DNS ---

if [[ -n "${DOMAIN:-}" ]]; then
  dns_result=$(dig +short "$DOMAIN" 2>/dev/null || true)
  if [[ -n "$dns_result" ]]; then
    echo "PREFLIGHT_DNS=ok $DOMAIN resolves"
  else
    echo "PREFLIGHT_DNS=missing $DOMAIN does not resolve"
    required_failed=1
  fi
else
  echo "PREFLIGHT_DNS=skipped (DOMAIN not set)"
fi

# --- Warnings (non-blocking) ---

if [[ -z "${GA4_MEASUREMENT_ID:-}" ]]; then
  echo "PREFLIGHT_GA4=warn GA4_MEASUREMENT_ID is empty"
else
  echo "PREFLIGHT_GA4=ok"
fi

if [[ -z "${CAPTURE_FORM_ID:-}" ]]; then
  echo "PREFLIGHT_FORM_IDS=warn CAPTURE_FORM_ID is empty (expected before first deploy)"
else
  echo "PREFLIGHT_FORM_IDS=ok"
fi

[[ $required_failed -eq 0 ]] || exit 1
exit 0
