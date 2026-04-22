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
# Project directory resolution:
# - PROJECT_DIR is $PWD by default, or $HS_LANDER_PROJECT_DIR if set. Invoke
#   from the project directory, or export the env var in automation. The script
#   location is NOT used — the framework install and the consuming project are
#   separate directories.
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

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"

# --- FRAMEWORK_VERSION ---
# Always the first line. Emitted unconditionally, before any other check,
# so the skill can read the framework version even when downstream checks
# abort. Sourced from the VERSION file at the framework-install (or
# project-scaffolded) root — resolved from this script's own location so it
# doesn't depend on $PWD.
_preflight_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_preflight_version_file="$(dirname "$_preflight_script_dir")/VERSION"
if [[ -f "$_preflight_version_file" ]]; then
  _framework_version=$(tr -d '[:space:]' < "$_preflight_version_file")
else
  _framework_version="unknown"
fi
echo "PREFLIGHT_FRAMEWORK_VERSION=${_framework_version:-unknown}"
unset _preflight_script_dir _preflight_version_file _framework_version

required_failed=0
token=""
scopes_body_file=""
trap 'unset token; [[ -n "$scopes_body_file" ]] && rm -f "$scopes_body_file"' EXIT

# --- TOOLS_REQUIRED ---
# Runs first so tool availability is reported even when config is unset.
# `command -v` is safe under xtrace — no secrets expanded here.
# If any required tool is missing, nothing downstream can run meaningfully, so
# emit skipped for every remaining check (including TOOLS_OPTIONAL) to keep
# the 12-line contract intact and exit 1.
_required_tools=(curl jq terraform npm)
_tools_missing=()
for _t in "${_required_tools[@]}"; do
  command -v "$_t" >/dev/null 2>&1 || _tools_missing+=("$_t")
done
if [[ ${#_tools_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_TOOLS_REQUIRED=ok"
else
  _missing_csv=$(IFS=,; echo "${_tools_missing[*]}")
  echo "PREFLIGHT_TOOLS_REQUIRED=missing $_missing_csv"
  for _check in PROJECT_POINTER ACCOUNT_PROFILE PROJECT_PROFILE CREDENTIAL \
                API_ACCESS SCOPES PROJECT_SOURCE DNS GA4 FORM_IDS TOOLS_OPTIONAL; do
    echo "PREFLIGHT_${_check}=skipped (required tools missing)"
  done
  exit 1
fi
unset _required_tools _tools_missing _t _missing_csv _check

# Helper: emit PREFLIGHT_TOOLS_OPTIONAL. Called at the end of the script and
# also before any early `exit 1` in the config-discovery branches so the
# contract's 12-line ordering is preserved regardless of exit path.
_emit_tools_optional() {
  local optional_tools=(pandoc pdftotext git)
  local optional_missing=() t
  for t in "${optional_tools[@]}"; do
    command -v "$t" >/dev/null 2>&1 || optional_missing+=("$t")
  done
  if [[ ${#optional_missing[@]} -eq 0 ]]; then
    echo "PREFLIGHT_TOOLS_OPTIONAL=ok"
  else
    local missing_csv
    missing_csv=$(IFS=,; echo "${optional_missing[*]}")
    echo "PREFLIGHT_TOOLS_OPTIONAL=warn $missing_csv"
  fi
}

# --- Config discovery ---
# Three discrete checks: PROJECT_POINTER → ACCOUNT_PROFILE → PROJECT_PROFILE.
# Each validates file existence and required fields before the next check
# depends on them. If POINTER is missing, skip all downstream (no way to find
# the hierarchy files without it).

# Helper: source a file in a subshell (with source builtin shadowed so cascading
# sources don't fire) and print requested var assignments. Caller eval's the
# output into the current shell.
_extract_pointer_var() {
  # Extract the value of a single variable assignment from a shell-syntax
  # file WITHOUT sourcing it (sourcing the pointer would fire its cascading
  # `source` calls, which may reference account/project config files that
  # don't exist yet).
  #
  # Supported forms:
  #   VAR="value"
  #   VAR='value'
  #   VAR=value              (unquoted, up to whitespace or #)
  #   export VAR="value"     (optional leading `export`)
  #   VAR="value"  # comment (trailing comments ignored)
  #
  # Not supported: values that depend on expansion (e.g. VAR="$OTHER"). Those
  # come back as the literal string — preflight will treat the resulting path
  # as nonexistent and surface ACCOUNT_PROFILE/PROJECT_PROFILE as missing,
  # which is a clearer signal to the user than silently proceeding.
  local path="$1" var="$2"
  awk -v V="$var" '
    match($0, "^[[:space:]]*(export[[:space:]]+)?"V"=") {
      rest = substr($0, RSTART + RLENGTH)
      if (rest ~ /^"/) {
        if (match(rest, /^"[^"]*"/)) { print substr(rest, 2, RLENGTH - 2); exit }
      } else if (rest ~ /^\x27/) {
        if (match(rest, /^\x27[^\x27]*\x27/)) { print substr(rest, 2, RLENGTH - 2); exit }
      } else {
        if (match(rest, /^[^[:space:]#]+/)) { print substr(rest, 1, RLENGTH); exit }
      }
    }
  ' "$path"
}

_extract_pointer_vars() {
  local path="$1" v
  for v in HS_LANDER_ACCOUNT HS_LANDER_PROJECT; do
    printf '%s=%q\n' "$v" "$(_extract_pointer_var "$path" "$v")"
  done
}

# Helper: source a file in an isolated subshell (cascades allowed) and print
# requested vars. Used for account / project config files where we want the
# file's own semantics but not the side effect on the parent shell.
#
# Residual edge case (not fully handled):
# If the sourced file itself runs `set -u` AND references an unbound
# variable DURING source execution, bash exits the subshell immediately.
# The printf loop below never runs; `_source_vars` returns empty stdout.
# The parent then sees all requested vars as empty and reports
# ACCOUNT_PROFILE/PROJECT_PROFILE=incomplete with the full field list — a
# plausible-looking but mis-specific diagnosis (the real problem is
# "the file has a set-u error", not "every field is missing").
#
# The `set +u` after `source` below is defence-in-depth for the narrower
# case where the sourced file enables set -u but doesn't reference anything
# unbound; it does NOT rescue the mid-source-abort case above.
#
# Scaffold-shipped configs don't use set -u, so this is a theoretical
# concern for hand-edited configs.
_source_vars() {
  local path="$1"; shift
  (
    set +eu
    # shellcheck source=/dev/null
    source "$path" 2>/dev/null || true
    set +u
    for v in "$@"; do
      printf '%s=%q\n' "$v" "${!v:-}"
    done
  )
}

# --- PROJECT_POINTER ---
if [[ ! -f "$PROJECT_DIR/project.config.sh" ]]; then
  echo "PREFLIGHT_PROJECT_POINTER=missing project.config.sh not found in $PROJECT_DIR"
  echo "PREFLIGHT_ACCOUNT_PROFILE=skipped (no project pointer)"
  echo "PREFLIGHT_PROJECT_PROFILE=skipped (no project pointer)"
  echo "PREFLIGHT_CREDENTIAL=skipped (no project pointer)"
  echo "PREFLIGHT_API_ACCESS=skipped (no project pointer)"
  echo "PREFLIGHT_SCOPES=skipped (no project pointer)"
  echo "PREFLIGHT_PROJECT_SOURCE=skipped (no project pointer)"
  echo "PREFLIGHT_DNS=skipped (no project pointer)"
  echo "PREFLIGHT_GA4=skipped (no project pointer)"
  echo "PREFLIGHT_FORM_IDS=skipped (no project pointer)"
  _emit_tools_optional
  exit 1
fi

# Extract HS_LANDER_ACCOUNT and HS_LANDER_PROJECT from the pointer without
# firing the cascading source lines (those reference files that may not exist).
eval "$(_extract_pointer_vars "$PROJECT_DIR/project.config.sh")"

if [[ -z "${HS_LANDER_ACCOUNT:-}" || -z "${HS_LANDER_PROJECT:-}" ]]; then
  pointer_missing=()
  [[ -z "${HS_LANDER_ACCOUNT:-}" ]] && pointer_missing+=("HS_LANDER_ACCOUNT")
  [[ -z "${HS_LANDER_PROJECT:-}" ]] && pointer_missing+=("HS_LANDER_PROJECT")
  echo "PREFLIGHT_PROJECT_POINTER=incomplete ${pointer_missing[*]}"
  echo "PREFLIGHT_ACCOUNT_PROFILE=skipped (pointer incomplete)"
  echo "PREFLIGHT_PROJECT_PROFILE=skipped (pointer incomplete)"
  echo "PREFLIGHT_CREDENTIAL=skipped (pointer incomplete)"
  echo "PREFLIGHT_API_ACCESS=skipped (pointer incomplete)"
  echo "PREFLIGHT_SCOPES=skipped (pointer incomplete)"
  echo "PREFLIGHT_PROJECT_SOURCE=skipped (pointer incomplete)"
  echo "PREFLIGHT_DNS=skipped (pointer incomplete)"
  echo "PREFLIGHT_GA4=skipped (pointer incomplete)"
  echo "PREFLIGHT_FORM_IDS=skipped (pointer incomplete)"
  _emit_tools_optional
  exit 1
fi

echo "PREFLIGHT_PROJECT_POINTER=ok"

# --- ACCOUNT_PROFILE ---
# Tracks whether the account profile is both present and complete. Used by
# the CREDENTIAL check below so a broken account profile surfaces as
# CREDENTIAL=skipped (pointing the skill at the root cause in the
# ACCOUNT_PROFILE line) rather than a misleading CREDENTIAL=missing that
# would have the skill coach the user to add a Keychain entry when the real
# problem is upstream.
account_profile_ok=0
account_config="${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
if [[ ! -f "$account_config" ]]; then
  echo "PREFLIGHT_ACCOUNT_PROFILE=missing $account_config does not exist"
  required_failed=1
else
  eval "$(_source_vars "$account_config" HUBSPOT_PORTAL_ID HUBSPOT_REGION HUBSPOT_TOKEN_KEYCHAIN_SERVICE)"
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
    required_failed=1
  fi
fi

# --- PROJECT_PROFILE ---
project_config="${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
if [[ ! -f "$project_config" ]]; then
  echo "PREFLIGHT_PROJECT_PROFILE=missing $project_config does not exist"
  required_failed=1
else
  eval "$(_source_vars "$project_config" PROJECT_SLUG DOMAIN DM_UPLOAD_PATH GA4_MEASUREMENT_ID CAPTURE_FORM_ID)"
  project_missing=()
  for v in PROJECT_SLUG DOMAIN DM_UPLOAD_PATH; do
    [[ -z "${!v:-}" ]] && project_missing+=("$v")
  done
  if [[ ${#project_missing[@]} -eq 0 ]]; then
    echo "PREFLIGHT_PROJECT_PROFILE=ok"
  else
    missing_csv=$(IFS=,; echo "${project_missing[*]}")
    echo "PREFLIGHT_PROJECT_PROFILE=incomplete $missing_csv"
    required_failed=1
  fi
fi

# --- Credential + API checks ---

if [[ $account_profile_ok -eq 0 ]]; then
  # Account profile is missing or incomplete; the ACCOUNT_PROFILE line above
  # has already told the skill the root cause. Don't attempt a Keychain
  # lookup (HUBSPOT_TOKEN_KEYCHAIN_SERVICE is absent or empty anyway) and
  # don't conflate this with CREDENTIAL=missing, which the skill treats
  # as "add a Keychain entry for the service name from your account config".
  echo "PREFLIGHT_CREDENTIAL=skipped (account profile missing or incomplete)"
  echo "PREFLIGHT_API_ACCESS=skipped (no credential)"
  echo "PREFLIGHT_SCOPES=skipped (no credential)"
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

  credential_state="missing"   # missing | empty | found
  api_status="000"
  api_curl_exit=0
  ps_status="000"
  ps_curl_exit=0
  scopes_status="000"
  scopes_curl_exit=0
  scopes_body_file=""
  if token=$(security find-generic-password \
               -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" \
               -a "$USER" -w 2>/dev/null); then
    if [[ -n "$token" ]]; then
      credential_state="found"
      # Capture curl's exit code separately (via `|| curl_exit=$?`) so a
      # non-zero exit doesn't trip set -e — we need to distinguish
      # "curl couldn't connect" (unreachable) from "HTTP error response".
      api_status=$(curl -s -o /dev/null -w "%{http_code}" \
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
        fi
      fi
    else
      credential_state="empty"
    fi
  fi

  unset token
  [[ $_xtrace_was_on -eq 1 ]] && set -x
  unset _xtrace_was_on

  case "$credential_state" in
    found)
      echo "PREFLIGHT_CREDENTIAL=found"

      if [[ $api_curl_exit -ne 0 ]]; then
        echo "PREFLIGHT_API_ACCESS=unreachable curl exited with code $api_curl_exit (network, DNS, or TLS failure reaching api.hubapi.com)"
        echo "PREFLIGHT_SCOPES=skipped (API unreachable)"
        echo "PREFLIGHT_PROJECT_SOURCE=skipped (API unreachable)"
        required_failed=1
      else
        case "$api_status" in
          200)
            echo "PREFLIGHT_API_ACCESS=ok"
            ;;
          401)
            echo "PREFLIGHT_API_ACCESS=unauthorized HubSpot returned 401 — token invalid or expired"
            required_failed=1
            ;;
          403)
            echo "PREFLIGHT_API_ACCESS=forbidden HubSpot returned 403 — token lacks required permissions"
            required_failed=1
            ;;
          *)
            echo "PREFLIGHT_API_ACCESS=error HubSpot returned HTTP $api_status"
            required_failed=1
            ;;
        esac

        # SCOPES and PROJECT_SOURCE only run if API access itself is healthy.
        if [[ "$api_status" == "200" ]]; then
          # --- SCOPES ---
          # Introspection endpoint returns JSON: {"userId":...,"hubId":...,"appId":...,"scopes":[...]}
          # We compute: required - granted. Empty → ok; non-empty → missing <list>.
          required_scopes=(
            crm.objects.contacts.read
            crm.objects.contacts.write
            crm.schemas.contacts.write
            crm.lists.read
            crm.lists.write
            forms
            content
          )
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
              echo "PREFLIGHT_SCOPES=ok"
            else
              missing_csv=$(IFS=,; echo "${missing_scopes[*]}")
              echo "PREFLIGHT_SCOPES=missing $missing_csv"
              required_failed=1
            fi
          fi

          # --- PROJECT_SOURCE ---
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
        else
          echo "PREFLIGHT_SCOPES=skipped (API access failed)"
          echo "PREFLIGHT_PROJECT_SOURCE=skipped (API access failed)"
        fi
      fi
      ;;
    empty)
      echo "PREFLIGHT_CREDENTIAL=empty Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' exists but its value is blank"
      echo "  Re-add it with: security add-generic-password -U -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'"
      echo "PREFLIGHT_API_ACCESS=skipped (credential empty)"
      echo "PREFLIGHT_SCOPES=skipped (credential empty)"
      echo "PREFLIGHT_PROJECT_SOURCE=skipped (credential empty)"
      required_failed=1
      ;;
    missing)
      echo "PREFLIGHT_CREDENTIAL=missing Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' not found"
      echo "  Add it with: security add-generic-password -s '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE' -a \"\$USER\" -w 'TOKEN'"
      echo "PREFLIGHT_API_ACCESS=skipped (no credential)"
      echo "PREFLIGHT_SCOPES=skipped (no credential)"
      echo "PREFLIGHT_PROJECT_SOURCE=skipped (no credential)"
      required_failed=1
      ;;
  esac
fi

# --- DNS ---
# Prefer dig (most precise). Fall back to host, then getent. If none is
# installed, report skipped rather than falsely claiming the domain doesn't
# resolve — an adopter on a stripped-down Linux image shouldn't be blocked.
# If DOMAIN itself is unset (e.g. PROJECT_PROFILE was missing or incomplete),
# we have nothing to resolve — emit skipped rather than crashing under set -u.

if [[ -z "${DOMAIN:-}" ]]; then
  echo "PREFLIGHT_DNS=skipped (DOMAIN not set)"
else
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
    # Compute the expected HubSpot CNAME target so the skill can tell the
    # user exactly which DNS record to create. If portal ID or region isn't
    # known (incomplete account profile), the expected string is best-effort.
    expected_cname="${HUBSPOT_PORTAL_ID:-<portal-id>}.group0.sites.hscoscdn-${HUBSPOT_REGION:-<region>}.net"
    echo "PREFLIGHT_DNS=missing $DOMAIN does not resolve (expected CNAME target: $expected_cname)"
    required_failed=1
  fi
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

# --- TOOLS_OPTIONAL ---
_emit_tools_optional

[[ $required_failed -eq 0 ]] || exit 1
exit 0
