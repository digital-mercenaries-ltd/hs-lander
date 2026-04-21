#!/usr/bin/env bash
# preflight.sh — validate config, credentials, and HubSpot account readiness
# before build/deploy. Structured output so the skill (or a human) can parse
# what's done vs missing.
#
# Usage: bash scripts/preflight.sh
# Exit 0: all required checks pass (warnings and recoverable "missing" signals
#         like a first-project-on-account state still allow exit 0).
# Exit 1: one or more required checks failed (config incomplete, bad token,
#         API unreachable, DNS unresolved).
#
# Output format: each check prints a single line of the form
#   PREFLIGHT_<NAME>=ok|missing|error|warn|skipped [detail]
#
# Credential safety:
# - The HubSpot token is read from Keychain into a local shell variable, used
#   for the API tests, and unset via EXIT trap. It never appears on stdout,
#   stderr, or in any file.
# - xtrace is suppressed around the two curl calls that carry the bearer
#   header, so running `bash -x scripts/preflight.sh` does NOT leak the token.
# - Do not add an ERR trap that prints $BASH_COMMAND — that would leak the
#   curl line including the Authorization header.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

required_failed=0
token=""
trap 'unset token' EXIT

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
  # Disable xtrace for the entire block that handles the token — both the
  # `token=$(security ...)` assignment (bash -x would print the assigned
  # value after expansion) and the `curl -H "...Bearer $token"` invocations
  # (bash -x would print the header after expansion). Re-enable afterward
  # if the caller originally had it on.
  _xtrace_was_on=0
  case "$-" in *x*) _xtrace_was_on=1; set +x ;; esac

  credential_ok=0
  api_status="000"
  ps_status="000"
  if token=$(security find-generic-password \
               -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" \
               -a "$USER" -w 2>/dev/null); then
    credential_ok=1
    api_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $token" \
      "https://api.hubapi.com/account-info/v3/details")
    ps_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $token" \
      "https://api.hubapi.com/crm/v3/properties/contacts/project_source")
  fi

  unset token
  [[ $_xtrace_was_on -eq 1 ]] && set -x
  unset _xtrace_was_on

  if [[ $credential_ok -eq 1 ]]; then
    echo "PREFLIGHT_CREDENTIAL=ok"

    if [[ "$api_status" == "200" ]]; then
      echo "PREFLIGHT_API_ACCESS=ok"
    else
      echo "PREFLIGHT_API_ACCESS=error HubSpot API returned HTTP $api_status"
      required_failed=1
    fi

    case "$ps_status" in
      200)
        echo "PREFLIGHT_PROJECT_SOURCE=ok"
        ;;
      404)
        # Recoverable, non-blocking: this is the first project on the account.
        # The skill should see this and run the account-setup module, then
        # re-preflight. Exit code stays 0 so the skill can act on the signal.
        echo "PREFLIGHT_PROJECT_SOURCE=missing (first project on this account — run account-setup module)"
        ;;
      *)
        echo "PREFLIGHT_PROJECT_SOURCE=error HubSpot API returned HTTP $ps_status"
        required_failed=1
        ;;
    esac
  else
    echo "PREFLIGHT_CREDENTIAL=missing Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' not found"
    echo "  Add it with: security add-generic-password -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'"
    echo "PREFLIGHT_API_ACCESS=skipped (no credential)"
    echo "PREFLIGHT_PROJECT_SOURCE=skipped (no credential)"
    required_failed=1
  fi
fi

# --- DNS ---
# Prefer dig (most precise). Fall back to host, then getent. If none is
# installed, report skipped rather than falsely claiming the domain doesn't
# resolve — an adopter on a stripped-down Linux image shouldn't be blocked.

dns_result=""
dns_tool=""
if command -v dig >/dev/null 2>&1; then
  dns_tool="dig"
  dns_result=$(dig +short "$DOMAIN" 2>/dev/null || true)
elif command -v host >/dev/null 2>&1; then
  dns_tool="host"
  dns_result=$(host -W 2 "$DOMAIN" 2>/dev/null | awk '/has address/ {print $4; exit}' || true)
elif command -v getent >/dev/null 2>&1; then
  dns_tool="getent"
  dns_result=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
fi

if [[ -z "$dns_tool" ]]; then
  echo "PREFLIGHT_DNS=skipped (no DNS tool available — install dig or host)"
elif [[ -n "$dns_result" ]]; then
  echo "PREFLIGHT_DNS=ok $DOMAIN resolves"
else
  echo "PREFLIGHT_DNS=missing $DOMAIN does not resolve"
  required_failed=1
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
