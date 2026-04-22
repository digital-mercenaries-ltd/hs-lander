#!/usr/bin/env bash
# accounts-init.sh — Create a new account profile at
# ~/.config/hs-lander/<account>/config.sh from explicit field arguments.
# Does NOT touch the Keychain; the <token-keychain-service> argument is a
# service-name reference, not the token itself.
#
# Usage:
#   bash scripts/accounts-init.sh <account> <portal-id> <region> \
#                                 <domain-pattern> <token-keychain-service>
#
# Output:
#   ACCOUNTS_INIT=created <path>       — profile written (exit 0)
#   ACCOUNTS_INIT=conflict <path>      — refuse to overwrite (exit 1)
#   ACCOUNTS_INIT=error <reason>       — invalid input (exit 1)
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "ACCOUNTS_INIT=error usage: accounts-init.sh <account> <portal-id> <region> <domain-pattern> <token-keychain-service>" >&2
  exit 1
fi
account="$1"
portal_id="$2"
region="$3"
domain_pattern="$4"
token_service="$5"

# Validate account name: lowercase letters, digits, hyphens only. Rejects
# empty, slashes (path traversal), dots, spaces, uppercase — keeps the
# ~/.config/hs-lander/<account>/ convention clean and defeats `..` tricks.
if [[ ! "$account" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ACCOUNTS_INIT=error invalid-account-name '$account' (expected lowercase letters, digits, hyphens)"
  exit 1
fi

if [[ "$region" != "eu1" && "$region" != "na1" ]]; then
  echo "ACCOUNTS_INIT=error invalid-region '$region' (expected eu1 or na1)"
  exit 1
fi

if [[ -z "$portal_id" ]]; then
  echo "ACCOUNTS_INIT=error invalid-portal-id (empty)"
  exit 1
fi

if [[ -z "$token_service" ]]; then
  echo "ACCOUNTS_INIT=error invalid-token-keychain-service (empty)"
  exit 1
fi

# Reject characters that can't round-trip through canonical `KEY="value"`
# quoting. None of the account-config fields have any legitimate use for
# double-quote, dollar, backtick, backslash, or control chars.
_has_banned_char() {
  [[ "$1" == *'"'* || "$1" == *'$'* || "$1" == *'`'* || "$1" == *"\\"* ]] && return 0
  [[ "$1" != "$(printf '%s' "$1" | tr -d '[:cntrl:]')" ]] && return 0
  return 1
}
for field_name in portal_id domain_pattern token_service; do
  if _has_banned_char "${!field_name}"; then
    echo "ACCOUNTS_INIT=error invalid-value $field_name (contains disallowed character)"
    exit 1
  fi
done

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
account_dir="$accounts_dir/$account"
config_path="$account_dir/config.sh"

if [[ -e "$config_path" ]]; then
  echo "ACCOUNTS_INIT=conflict $config_path"
  exit 1
fi

mkdir -p "$account_dir"
# Write to a temp and mv for atomicity — an interrupted write shouldn't
# leave a partial config.sh that later scripts would source. EXIT trap
# cleans up the temp if we crash before the mv.
tmp_path="$config_path.tmp.$$"
trap 'rm -f "$tmp_path"' EXIT
cat > "$tmp_path" <<EOF
HUBSPOT_PORTAL_ID="$portal_id"
HUBSPOT_REGION="$region"
DOMAIN_PATTERN="$domain_pattern"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="$token_service"
EOF
mv "$tmp_path" "$config_path"
trap - EXIT

echo "ACCOUNTS_INIT=created $config_path"
