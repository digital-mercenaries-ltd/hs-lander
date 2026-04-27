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
is_valid_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}
