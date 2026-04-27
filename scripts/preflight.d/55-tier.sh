#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 55-tier.sh — emits PREFLIGHT_TIER.
#
# Reads: credential_ok, credential_skip_reason, api_skip_reason,
#        api_curl_exit, api_status, account_info_body_file.
# Writes: tier (one of starter|pro|ent|ent-tx|unknown), consumed by
#         60-scopes.sh.
#
# Classifies portal tier from /account-info/v3/details body. Drives the
# tier-aware required-scope set in 60-scopes.sh. classify_tier_from_account_details
# is sourced by the runner from scripts/lib/tier-classify.sh.

if [[ "$credential_ok" -ne 1 ]]; then
  echo "PREFLIGHT_TIER=skipped (${credential_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ $api_curl_exit -ne 0 ]]; then
  echo "PREFLIGHT_TIER=skipped (API unreachable)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$api_status" == "200" ]] && [[ -n "$account_info_body_file" ]] && [[ -f "$account_info_body_file" ]]; then
  tier=$(classify_tier_from_account_details "$(cat "$account_info_body_file")")
  echo "PREFLIGHT_TIER=$tier"
else
  echo "PREFLIGHT_TIER=skipped (API access failed)"
fi
