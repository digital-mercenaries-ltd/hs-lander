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
# Architecture (v1.9.0 Component 3):
# - This file is a thin runner. The actual checks live in scripts/preflight.d/,
#   one file per PREFLIGHT_* line, prefixed with a numeric ordering. The runner
#   sources each check in glob-sorted order so adding/removing a check is a
#   single-file change. Shared variables that act as the interface between
#   check files are declared here and documented in preflight.d/README.md.
#
# Project directory resolution:
# - PROJECT_DIR is $PWD by default, or $HS_LANDER_PROJECT_DIR if set. Invoke
#   from the project directory, or export the env var in automation. The
#   script location is NOT used to find the project — the framework install
#   and the consuming project are separate directories.
#
# Credential safety:
# - The HubSpot token is read from Keychain into a local shell variable, used
#   for the API tests, and unset via EXIT trap. It never appears on stdout,
#   stderr, or in any file.
# - xtrace is suppressed around the curl calls that carry the bearer header
#   (see preflight.d/40-credential.sh), so running `bash -x scripts/preflight.sh`
#   does NOT leak the token.
# - Do not add an ERR trap that prints $BASH_COMMAND — that would leak the
#   curl line including the Authorization header.
set -euo pipefail

# --- Resolve framework paths ---
_preflight_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_preflight_lib_dir="$_preflight_script_dir/lib"
_preflight_d_dir="$_preflight_script_dir/preflight.d"

# Refuse to run if preflight.d/ is missing or empty. This is a load-bearing
# invariant: without check files there is no contract output, only the
# FRAMEWORK_VERSION line — which would silently look like every check passed.
if [[ ! -d "$_preflight_d_dir" ]]; then
  echo "ERROR: preflight.d/ directory missing at $_preflight_d_dir" >&2
  echo "       This file is a thin runner; the checks live in preflight.d/*.sh." >&2
  exit 2
fi
shopt -s nullglob
_preflight_d_files=("$_preflight_d_dir"/*.sh)
shopt -u nullglob
if (( ${#_preflight_d_files[@]} == 0 )); then
  echo "ERROR: preflight.d/ contains no *.sh check files at $_preflight_d_dir" >&2
  exit 2
fi

# --- FRAMEWORK_VERSION ---
# Always the first line. Emitted unconditionally, before any other check, so
# the skill can read the framework version even when downstream checks abort.
# Sourced from the VERSION file at the framework-install (or project-
# scaffolded) root — resolved from this script's own location so it doesn't
# depend on $PWD.
_preflight_version_file="$(dirname "$_preflight_script_dir")/VERSION"
if [[ -f "$_preflight_version_file" ]]; then
  _framework_version=$(tr -d '[:space:]' < "$_preflight_version_file")
else
  _framework_version="unknown"
fi
echo "PREFLIGHT_FRAMEWORK_VERSION=${_framework_version:-unknown}"
unset _preflight_version_file _framework_version

# --- Shared state (interface between check files) ---
# Documented in preflight.d/README.md. Each check file reads any of these it
# depends on and writes the one(s) it owns.
PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
required_failed=0
tools_required_ok=0
project_pointer_ok=0
account_profile_ok=0
project_profile_ok=0
credential_ok=0
api_access_ok=0
tier="unknown"
token=""

# Cascading skip-reason markers. Each gate-check sets these when it fails so
# downstream checks can emit a precise "skipped (<reason>)" line that points
# the skill at the upstream root cause. Empty when the gate is satisfied.
pointer_skip_reason=""        # set by 10-project-pointer.sh
credential_skip_reason=""     # set by 40-credential.sh (or upstream)
api_skip_reason=""            # set by 50-api-access.sh (or upstream)

# API probe results (populated by 40-credential.sh, consumed by 50-api-access.sh,
# 55-tier.sh, 60-scopes.sh, 65-project-source.sh, 75-domain-connected.sh).
api_status="000"
api_curl_exit=0
ps_status="000"
ps_curl_exit=0
scopes_status="000"
scopes_curl_exit=0
scopes_body_file=""
account_info_body_file=""
domains_status="000"
domains_curl_exit=0
domains_body_file=""

# EXIT trap: unset the token and remove any tempfiles created by the API
# probes. Initialised here so it covers any failure path inside the sourced
# check files.
trap 'unset token; rm -f "$scopes_body_file" "$account_info_body_file" "$domains_body_file"' EXIT

# --- Source lib helpers used by check files ---
# Each check file may also source additional helpers it needs; the three below
# are the common subset used by multiple checks.
# shellcheck source=/dev/null
source "$_preflight_lib_dir/tier-classify.sh"
# shellcheck source=/dev/null
source "$_preflight_lib_dir/keychain.sh"
# shellcheck source=/dev/null
source "$_preflight_lib_dir/source-vars.sh"

# --- Source check files in numeric-prefix order ---
# LC_ALL=C sort gives deterministic byte-order across Darwin and Linux runners.
_preflight_d_sorted=()
while IFS= read -r _f; do _preflight_d_sorted+=("$_f"); done < <(printf '%s\n' "${_preflight_d_files[@]}" | LC_ALL=C sort)
for _check_file in "${_preflight_d_sorted[@]}"; do
  # shellcheck source=/dev/null
  source "$_check_file"
done
unset _check_file _preflight_d_files _preflight_d_sorted _preflight_d_dir _preflight_lib_dir _preflight_script_dir _f

[[ $required_failed -eq 0 ]] || exit 1
exit 0
