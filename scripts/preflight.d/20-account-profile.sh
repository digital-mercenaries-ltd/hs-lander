#!/usr/bin/env bash
# 20-account-profile.sh — emits PREFLIGHT_ACCOUNT_PROFILE.
#
# Reads: project_pointer_ok, pointer_skip_reason, HS_LANDER_ACCOUNT.
# Writes: account_profile_ok, HUBSPOT_PORTAL_ID, HUBSPOT_REGION,
#         HUBSPOT_TOKEN_KEYCHAIN_SERVICE.
#
# Loads the account config at ~/.config/hs-lander/<account>/config.sh and
# verifies all three required fields are non-empty. account_profile_ok gates
# the credential / API / scopes / project_source checks below — a broken
# account profile surfaces as CREDENTIAL=skipped (pointing the skill at the
# root cause via this line) rather than a misleading CREDENTIAL=missing that
# would have the skill coach the user to add a Keychain entry when the real
# problem is upstream.

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_ACCOUNT_PROFILE=skipped (${pointer_skip_reason})"
  account_profile_ok=0
  return 0 2>/dev/null || exit 0
fi

account_config="${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
if [[ ! -f "$account_config" ]]; then
  echo "PREFLIGHT_ACCOUNT_PROFILE=missing $account_config does not exist"
  account_profile_ok=0
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

eval "$(source_vars "$account_config" HUBSPOT_PORTAL_ID HUBSPOT_REGION HUBSPOT_TOKEN_KEYCHAIN_SERVICE)"
account_missing=()
for v in HUBSPOT_PORTAL_ID HUBSPOT_REGION HUBSPOT_TOKEN_KEYCHAIN_SERVICE; do
  [[ -z "${!v:-}" ]] && account_missing+=("$v")
done
if [[ ${#account_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_ACCOUNT_PROFILE=ok"
  account_profile_ok=1
else
  missing_csv=$(IFS=,; echo "${account_missing[*]}")
  echo "PREFLIGHT_ACCOUNT_PROFILE=incomplete $missing_csv"
  account_profile_ok=0
  required_failed=1
fi
