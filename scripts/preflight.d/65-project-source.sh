# 65-project-source.sh — emits PREFLIGHT_PROJECT_SOURCE.
#
# Reads: credential_ok, credential_skip_reason, api_curl_exit, api_status,
#        ps_status, ps_curl_exit.
#
# Probes /crm/v3/properties/contacts/project_source. 200 → ok. 404 → missing
# (recoverable: first project on the account; the skill should run the
# account-setup module). Anything else → error and required_failed=1.

if [[ "$credential_ok" -ne 1 ]]; then
  echo "PREFLIGHT_PROJECT_SOURCE=skipped (${credential_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ $api_curl_exit -ne 0 ]]; then
  echo "PREFLIGHT_PROJECT_SOURCE=skipped (API unreachable)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$api_status" != "200" ]]; then
  echo "PREFLIGHT_PROJECT_SOURCE=skipped (API access failed)"
  return 0 2>/dev/null || exit 0
fi

if [[ $ps_curl_exit -ne 0 ]]; then
  echo "PREFLIGHT_PROJECT_SOURCE=error curl exited with code $ps_curl_exit on project_source probe"
  required_failed=1
else
  case "$ps_status" in
    200)
      echo "PREFLIGHT_PROJECT_SOURCE=ok"
      ;;
    404)
      # Recoverable, non-blocking: first project on the account.
      echo "PREFLIGHT_PROJECT_SOURCE=missing (first project on this account — run account-setup module)"
      ;;
    *)
      echo "PREFLIGHT_PROJECT_SOURCE=error HubSpot API returned HTTP $ps_status"
      required_failed=1
      ;;
  esac
fi
