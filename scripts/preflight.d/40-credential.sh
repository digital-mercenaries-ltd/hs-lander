#!/usr/bin/env bash
# 40-credential.sh — emits PREFLIGHT_CREDENTIAL.
#
# Reads: account_profile_ok, project_pointer_ok, pointer_skip_reason,
#        HUBSPOT_TOKEN_KEYCHAIN_SERVICE.
# Writes: credential_ok, credential_skip_reason, token, plus all of the API
#         probe results that 50/55/60/65/75 check files consume:
#         api_status, api_curl_exit, account_info_body_file,
#         ps_status, ps_curl_exit,
#         scopes_status, scopes_curl_exit, scopes_body_file,
#         domains_status, domains_curl_exit, domains_body_file.
#
# Why this file batches the API probes:
# - Each probe needs the bearer token, which only exists inside the xtrace-
#   suppressed window in this file. Splitting the curls into separate files
#   would require either holding the token open across files (defeating the
#   xtrace guard) or reading from Keychain four times. Keeping the four
#   probes together preserves the v1.8.0 single-token-window design.
# - The downstream files (50/55/60/65/75) only inspect the captured probe
#   results — they never see the token.
#
# Cascade contract:
# - If account_profile_ok=0, emit CREDENTIAL=skipped pointing at the upstream
#   ACCOUNT_PROFILE line and set credential_skip_reason for downstream files.

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_CREDENTIAL=skipped (${pointer_skip_reason})"
  credential_ok=0
  credential_skip_reason="$pointer_skip_reason"
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

if [[ "$account_profile_ok" -ne 1 ]]; then
  # Account profile is missing or incomplete; the ACCOUNT_PROFILE line above
  # has already told the skill the root cause. Don't attempt a Keychain
  # lookup (HUBSPOT_TOKEN_KEYCHAIN_SERVICE is absent or empty anyway) and
  # don't conflate this with CREDENTIAL=missing, which the skill treats as
  # "add a Keychain entry for the service name from your account config".
  echo "PREFLIGHT_CREDENTIAL=skipped (account profile missing or incomplete)"
  credential_ok=0
  credential_skip_reason="no credential"
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

# Disable xtrace for the entire block that handles the token — both the
# `token=$(security ...)` assignment (bash -x would print the assigned
# value after expansion) and the `curl -H "...Bearer $token"` invocations
# (bash -x would print the header after expansion). Re-enable afterward
# if the caller originally had it on.
_xtrace_was_on=0
case "$-" in *x*) _xtrace_was_on=1; set +x ;; esac

credential_state="missing"   # missing | empty | found

# keychain_read's three-state contract (rc 0 / 1 / 3 — see lib/keychain.sh)
# maps directly to credential_state's three-state output.
keychain_rc=0
token=$(keychain_read "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" 2>/dev/null) || keychain_rc=$?
case "$keychain_rc" in
  0) credential_state="found" ;;
  3) credential_state="empty" ;;
  *) credential_state="missing" ;;
esac
unset keychain_rc

if [[ "$credential_state" == "found" ]]; then
  # Capture curl's exit code separately so a non-zero exit doesn't trip
  # set -e — we need to distinguish "curl couldn't connect" (unreachable)
  # from "HTTP error response". Capture body so the tier-classifier can
  # read accountType / subscriptions without a second round-trip.
  account_info_body_file=$(mktemp)
  api_status=$(curl -s -o "$account_info_body_file" -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    "https://api.hubapi.com/account-info/v3/details") || api_curl_exit=$?
  # Skip subsequent calls if the first failed to reach the server.
  if [[ $api_curl_exit -eq 0 ]]; then
    ps_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $token" \
      "https://api.hubapi.com/crm/v3/properties/contacts/project_source") || ps_curl_exit=$?
    # Scope introspection — only run when API access looks healthy.
    if [[ "$api_status" == "200" ]]; then
      scopes_body_file=$(mktemp)
      scopes_status=$(curl -s -o "$scopes_body_file" -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"tokenKey\":\"$token\"}" \
        "https://api.hubapi.com/oauth/v2/private-apps/get/access-token-info") || scopes_curl_exit=$?

      # Domain-connection probe — surfaces the "DOMAIN not connected to
      # HubSpot" failure mode before terraform apply rather than after a
      # confusing temp-slug deploy. Only meaningful for projects in
      # custom-domain hosting modes; system-domain and iframe consumers
      # still get a result but the skill ignores it (it knows the mode).
      domains_body_file=$(mktemp)
      domains_status=$(curl -s -o "$domains_body_file" -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "https://api.hubapi.com/cms/v3/domains") || domains_curl_exit=$?
    fi
  fi
fi

unset token
[[ $_xtrace_was_on -eq 1 ]] && set -x
unset _xtrace_was_on

case "$credential_state" in
  found)
    echo "PREFLIGHT_CREDENTIAL=found"
    credential_ok=1
    credential_skip_reason=""
    ;;
  empty)
    echo "PREFLIGHT_CREDENTIAL=empty Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' exists but its value is blank"
    echo "  Re-add it with: security add-generic-password -U -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'"
    credential_ok=0
    credential_skip_reason="credential empty"
    required_failed=1
    ;;
  missing)
    echo "PREFLIGHT_CREDENTIAL=missing Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' not found"
    echo "  Add it with: security add-generic-password -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'"
    credential_ok=0
    credential_skip_reason="no credential"
    required_failed=1
    ;;
esac
