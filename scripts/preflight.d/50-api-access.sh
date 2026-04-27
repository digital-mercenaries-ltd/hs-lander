#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 50-api-access.sh — emits PREFLIGHT_API_ACCESS.
#
# Reads: credential_ok, credential_skip_reason, api_status, api_curl_exit.
# Writes: api_access_ok, api_skip_reason.
#
# Inspects the /account-info/v3/details probe captured by 40-credential.sh.
# Maps curl exit + HTTP status into one of: ok, unauthorized, forbidden,
# unreachable, error. Sets api_skip_reason for downstream files (TIER,
# SCOPES, PROJECT_SOURCE) when API access is not healthy.

if [[ "$credential_ok" -ne 1 ]]; then
  echo "PREFLIGHT_API_ACCESS=skipped (${credential_skip_reason})"
  api_access_ok=0
  api_skip_reason="$credential_skip_reason"
  return 0 2>/dev/null || exit 0
fi

if [[ $api_curl_exit -ne 0 ]]; then
  echo "PREFLIGHT_API_ACCESS=unreachable curl exited with code $api_curl_exit (network, DNS, or TLS failure reaching api.hubapi.com)"
  api_access_ok=0
  api_skip_reason="API unreachable"
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

case "$api_status" in
  200)
    echo "PREFLIGHT_API_ACCESS=ok"
    api_access_ok=1
    api_skip_reason=""
    ;;
  401)
    echo "PREFLIGHT_API_ACCESS=unauthorized HubSpot returned 401 — token invalid or expired"
    api_access_ok=0
    api_skip_reason="API access failed"
    required_failed=1
    ;;
  403)
    echo "PREFLIGHT_API_ACCESS=forbidden HubSpot returned 403 — token lacks required permissions"
    api_access_ok=0
    api_skip_reason="API access failed"
    required_failed=1
    ;;
  *)
    echo "PREFLIGHT_API_ACCESS=error HubSpot returned HTTP $api_status"
    api_access_ok=0
    api_skip_reason="API access failed"
    required_failed=1
    ;;
esac
