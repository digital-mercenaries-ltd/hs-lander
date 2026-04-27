#!/usr/bin/env bash
# validate-name.sh — defensive validation for account / project names that
# build filesystem paths under ~/.config/hs-lander/<account>/<project>.sh.
#
# Sourced by accounts-init.sh (uses inline regex today; the pattern below
# matches it exactly), scaffold-project.sh, init-project-pointer.sh,
# set-project-field.sh, accounts-describe.sh, projects-list.sh.
#
# Validates that a string is a valid account or project name:
# lowercase letters, digits, hyphens; must start with letter or digit.
# Defeats: path traversal (..), uppercase, dots, slashes, spaces, control
# chars. The pattern matches accounts-init.sh's existing regex, which has
# been the de-facto standard since v1.3.0.
#
# Usage:
#   if ! is_valid_name "$account"; then
#     echo "<COMMAND>=error invalid-account-name '$account' (...)"
#     exit 1
#   fi
#
# Defensive guards (v1.9.0 — silent-failure-hunter H3 / H4):
# - exactly 1 arg required; multi-arg call is a typo (silently validating
#   only the first arg would let through whichever later arg the caller
#   forgot to validate).
# - reads via "${1:-}" so callers under `set -u` who pass a stale or unset
#   variable don't crash with "$1: unbound variable" before validation.
is_valid_name() {
  if (( $# != 1 )); then
    echo "is_valid_name: expected 1 arg, got $#" >&2
    return 2
  fi
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}
