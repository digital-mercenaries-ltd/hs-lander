#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 05-version-drift.sh — emits PREFLIGHT_VERSION_DRIFT.
#
# Reads: PROJECT_DIR, _preflight_script_dir.
#
# Compares the project's pinned framework `?ref=` (in terraform/main.tf)
# against the installed framework's VERSION. Closes the v1.8.1 scaffold-pin
# defect's recurrence path: that defect was invisible until apply because
# nothing surfaced the drift. This check fires at preflight time, ahead
# of any module-API divergence biting at apply.
#
# Emits one of:
#   PREFLIGHT_VERSION_DRIFT=ok                                 — pinned == installed
#   PREFLIGHT_VERSION_DRIFT=warn pinned=<X> installed=<Y>      — drift detected
#   PREFLIGHT_VERSION_DRIFT=skipped <reason>                   — terraform/main.tf
#                                                                missing or ?ref=
#                                                                unparseable
#
# Non-blocking — `warn` and `skipped` both exit 0. The skill (or operator)
# reads the line and can run scripts/migrate-project.sh to address.

# Discover installed framework version. The runner already resolved
# _preflight_script_dir; VERSION lives one directory up.
_installed_version_file="$(dirname "$_preflight_script_dir")/VERSION"
if [[ -f "$_installed_version_file" ]]; then
  _installed_version=$(tr -d '[:space:]' < "$_installed_version_file")
else
  _installed_version="unknown"
fi

# Discover project's pinned ?ref=. Look in terraform/main.tf at the project
# root. The scaffolded shape is stable: `git::https://...?ref=v1.X.Y`.
_main_tf="$PROJECT_DIR/terraform/main.tf"
if [[ ! -f "$_main_tf" ]]; then
  echo "PREFLIGHT_VERSION_DRIFT=skipped (terraform/main.tf not found at $_main_tf)"
  unset _installed_version_file _installed_version _main_tf
  return 0 2>/dev/null || exit 0
fi

# Extract the first ?ref= we find. The framework's modules are pinned in
# lockstep so multiple matches would all be the same value; we take the
# first as the canonical pin. Lenient match: capture ?ref= followed by
# non-quote / non-whitespace characters. Accommodates standard semver
# (?ref=v1.9.0) plus the test harness's non-semver VERSION shape.
_pinned_ref=$(awk '
  match($0, /\?ref=[^"[:space:]]+/) {
    print substr($0, RSTART + 5, RLENGTH - 5)
    exit
  }
' "$_main_tf")

if [[ -z "$_pinned_ref" ]]; then
  echo "PREFLIGHT_VERSION_DRIFT=skipped (?ref= not found in $_main_tf)"
  unset _installed_version_file _installed_version _main_tf _pinned_ref
  return 0 2>/dev/null || exit 0
fi

# Strip the leading 'v' prefix so the comparison aligns with VERSION's
# format (which is plain `1.9.0`, not `v1.9.0`).
_pinned_version="${_pinned_ref#v}"

if [[ "$_pinned_version" == "$_installed_version" ]]; then
  echo "PREFLIGHT_VERSION_DRIFT=ok"
else
  echo "PREFLIGHT_VERSION_DRIFT=warn pinned=$_pinned_version installed=$_installed_version"
fi

unset _installed_version_file _installed_version _main_tf _pinned_ref _pinned_version
