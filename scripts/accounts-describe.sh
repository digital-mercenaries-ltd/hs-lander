#!/usr/bin/env bash
# accounts-describe.sh — Surface the key fields of an account profile so the
# skill can render a confirmation prompt ("Using account dml, portal ...").
#
# Usage:   bash scripts/accounts-describe.sh <account>
# Output (when profile exists):
#   ACCOUNT_PORTAL_ID=<value>
#   ACCOUNT_REGION=<value>
#   ACCOUNT_DOMAIN_PATTERN=<value>
#   ACCOUNT_TOKEN_KEYCHAIN_SERVICE=<value>
#   ACCOUNT_SUBSCRIPTION_ID=<value>           (empty when account pre-dates v1.5.0)
#   ACCOUNT_OFFICE_LOCATION_ID=<value>        (empty when account pre-dates v1.5.0)
# Output (when profile missing):
#   ACCOUNT_STATUS=missing <path>
# Exit:    0 on ok, 1 on missing profile or missing args.
#
# Credential safety: never reads the Keychain; only prints the service name.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "ACCOUNT_STATUS=error account name required (usage: accounts-describe.sh <account>)" >&2
  exit 1
fi
account="$1"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/validate-name.sh"
if ! is_valid_name "$account"; then
  echo "ACCOUNT_STATUS=error invalid-account-name '$account' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
config_path="$accounts_dir/$account/config.sh"

if [[ ! -f "$config_path" ]]; then
  echo "ACCOUNT_STATUS=missing $config_path"
  exit 1
fi

# Source in an isolated subshell so the caller's shell is unaffected and any
# `set -u` inside the account file can't crash us. Print only the four
# documented fields as key=value pairs.
values=$(
  set +eu
  # shellcheck source=/dev/null
  source "$config_path" 2>/dev/null || true
  set +u
  printf 'ACCOUNT_PORTAL_ID=%s\n'              "${HUBSPOT_PORTAL_ID:-}"
  printf 'ACCOUNT_REGION=%s\n'                 "${HUBSPOT_REGION:-}"
  printf 'ACCOUNT_DOMAIN_PATTERN=%s\n'         "${DOMAIN_PATTERN:-}"
  printf 'ACCOUNT_TOKEN_KEYCHAIN_SERVICE=%s\n' "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:-}"
  printf 'ACCOUNT_SUBSCRIPTION_ID=%s\n'        "${HUBSPOT_SUBSCRIPTION_ID:-}"
  printf 'ACCOUNT_OFFICE_LOCATION_ID=%s\n'     "${HUBSPOT_OFFICE_LOCATION_ID:-}"
)
printf '%s\n' "$values"
