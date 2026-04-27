#!/usr/bin/env bash
# 60-scopes.sh — emits PREFLIGHT_SCOPES.
#
# Reads: credential_ok, credential_skip_reason, api_curl_exit, api_status,
#        scopes_status, scopes_curl_exit, scopes_body_file, tier.
#
# Introspection endpoint returns JSON: {"userId":...,"hubId":...,"appId":...,"scopes":[...]}
# We compute: required - granted. Empty → ok; non-empty → missing <list>.
# Required-scope set is tier-aware (required_scopes_for_tier from
# scripts/lib/tier-classify.sh).

if [[ "$credential_ok" -ne 1 ]]; then
  echo "PREFLIGHT_SCOPES=skipped (${credential_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ $api_curl_exit -ne 0 ]]; then
  echo "PREFLIGHT_SCOPES=skipped (API unreachable)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$api_status" != "200" ]]; then
  echo "PREFLIGHT_SCOPES=skipped (API access failed)"
  return 0 2>/dev/null || exit 0
fi

required_scopes=()
while IFS= read -r _scope; do
  [[ -n "$_scope" ]] && required_scopes+=("$_scope")
done < <(required_scopes_for_tier "$tier")

if [[ $scopes_curl_exit -ne 0 ]]; then
  echo "PREFLIGHT_SCOPES=error curl exited with code $scopes_curl_exit on scopes introspection"
  required_failed=1
elif [[ "$scopes_status" != "200" ]]; then
  echo "PREFLIGHT_SCOPES=error introspection endpoint returned HTTP $scopes_status"
  required_failed=1
else
  # Parse the body via python3 (reliable JSON) with a grep/sed fallback
  # for hosts without python3.
  granted=""
  if command -v python3 >/dev/null 2>&1; then
    granted=$(python3 -c '
import json, sys
try:
    print(" ".join(json.load(open(sys.argv[1])).get("scopes", [])))
except Exception:
    pass
' "$scopes_body_file" 2>/dev/null || true)
  else
    # Fallback: extract "scopes":[...] and clean up quotes/commas.
    granted=$(tr -d '\n' <"$scopes_body_file" \
      | sed -nE 's/.*"scopes"[[:space:]]*:[[:space:]]*\[([^]]*)\].*/\1/p' \
      | tr -d '"' | tr ',' ' ')
  fi

  missing_scopes=()
  for scope in "${required_scopes[@]}"; do
    if [[ " $granted " != *" $scope "* ]]; then
      missing_scopes+=("$scope")
    fi
  done

  if [[ ${#missing_scopes[@]} -eq 0 ]]; then
    # Distinguish starter (no marketing-email/transactional-email is *expected*,
    # not just a passing baseline) so the skill can coach manual UI publish
    # without re-checking tier.
    if [[ "$tier" == "starter" ]]; then
      echo "PREFLIGHT_SCOPES=ok-starter"
    else
      echo "PREFLIGHT_SCOPES=ok"
    fi
  else
    missing_csv=$(IFS=,; echo "${missing_scopes[*]}")
    echo "PREFLIGHT_SCOPES=missing $missing_csv"
    required_failed=1
  fi
fi
