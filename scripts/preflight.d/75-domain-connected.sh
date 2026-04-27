#!/usr/bin/env bash
# 75-domain-connected.sh — emits PREFLIGHT_DOMAIN_CONNECTED.
#
# Reads: tools_required_ok, project_pointer_ok, pointer_skip_reason, DOMAIN,
#        domains_status, domains_curl_exit, domains_body_file.
#
# Result of the /cms/v3/domains probe captured during 40-credential.sh.
# Tells the skill whether the project's DOMAIN is actually connected in the
# portal as a primary landing-page domain — the temp-slug failure mode
# v1.6.5 documented happens when DOMAIN isn't connected and HubSpot falls
# back to a system subdomain without warning.
#
# Emits one of:
#   ok          — DOMAIN present and isUsedForLandingPage:true
#   not-primary — DOMAIN present but not primary for landing pages
#   missing     — DOMAIN not in /cms/v3/domains at all
#   skipped     — credential/api unavailable, or DOMAIN unset
#   error       — API call hit a transport or unexpected-status problem
# The result is informational: skills consuming it know the project's hosting
# mode (custom-domain-primary vs system-domain vs iframe) from their own
# state and can interpret accordingly.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_DOMAIN_CONNECTED=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_DOMAIN_CONNECTED=skipped (${pointer_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ -z "${DOMAIN:-}" ]]; then
  echo "PREFLIGHT_DOMAIN_CONNECTED=skipped (DOMAIN not set)"
elif [[ "$domains_status" == "000" ]]; then
  echo "PREFLIGHT_DOMAIN_CONNECTED=skipped (no API access)"
elif [[ "$domains_curl_exit" -ne 0 ]]; then
  echo "PREFLIGHT_DOMAIN_CONNECTED=error curl exited with code $domains_curl_exit on /cms/v3/domains"
elif [[ "$domains_status" != "200" ]]; then
  echo "PREFLIGHT_DOMAIN_CONNECTED=error /cms/v3/domains returned HTTP $domains_status"
else
  domain_match=$(jq -r --arg d "$DOMAIN" '
    .results[]? | select(.domain == $d) |
      if (.isUsedForLandingPages // .isUsedForPages // false) then "primary"
      else "secondary"
      end
  ' "$domains_body_file" 2>/dev/null | head -n 1)
  case "$domain_match" in
    primary)
      echo "PREFLIGHT_DOMAIN_CONNECTED=ok"
      ;;
    secondary)
      echo "PREFLIGHT_DOMAIN_CONNECTED=not-primary $DOMAIN connected but not flagged for landing pages"
      ;;
    *)
      echo "PREFLIGHT_DOMAIN_CONNECTED=missing $DOMAIN not present in /cms/v3/domains"
      ;;
  esac
fi
