#!/usr/bin/env bash
# projects-describe.sh — Surface the fields of a project profile so the
# skill (or an operator) can render structured data without `Read`-ing
# ~/.config/hs-lander/<account>/<project>.sh directly.
#
# Mirrors accounts-describe.sh's contract: same shape, same exit codes,
# same error-prefix convention, same empty-line-for-empty-value emission.
# The skill that already parses ACCOUNT_<FIELD>= can parse PROJECT_<FIELD>=
# with no new logic.
#
# Schema source of truth: scripts/set-project-field.sh's ALLOWED_KEYS array.
# The 14 keys this script emits track that array — when set-project-field.sh
# adds a new allowed key, add it here too (and the test fixture).
#
# Usage:   bash scripts/projects-describe.sh <account> <project>
#
# Output (when profile exists, exit 0):
#   PROJECT_SLUG=<value>
#   PROJECT_DOMAIN=<value>
#   PROJECT_DM_UPLOAD_PATH=<value>
#   PROJECT_GA4_MEASUREMENT_ID=<value>
#   PROJECT_CAPTURE_FORM_ID=<value>
#   PROJECT_SURVEY_FORM_ID=<value>
#   PROJECT_LIST_ID=<value>
#   PROJECT_LANDING_SLUG=<value>
#   PROJECT_THANKYOU_SLUG=<value>
#   PROJECT_HUBSPOT_SUBSCRIPTION_ID=<value>
#   PROJECT_HUBSPOT_OFFICE_LOCATION_ID=<value>
#   PROJECT_EMAIL_PREVIEW_TEXT=<value>
#   PROJECT_AUTO_PUBLISH_WELCOME_EMAIL=<value>
#   PROJECT_EMAIL_REPLY_TO=<value>
#
# Output (profile missing):
#   PROJECT_STATUS=missing <path>
#
# Output (invalid name):
#   PROJECT_STATUS=error invalid-account-name '<name>' (...)
#   PROJECT_STATUS=error invalid-project-name '<name>' (...)
#
# Exit:    0 on ok, 1 on missing/invalid/usage error.
#
# Credential safety: only reads project-profile fields. Never invokes
# `security`, never echoes a Keychain reference (none in the schema).
set -euo pipefail

if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  echo "PROJECT_STATUS=error account and project names required (usage: projects-describe.sh <account> <project>)" >&2
  exit 1
fi
account="$1"
project="$2"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/validate-name.sh"
if ! is_valid_name "$account"; then
  echo "PROJECT_STATUS=error invalid-account-name '$account' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi
if ! is_valid_name "$project"; then
  echo "PROJECT_STATUS=error invalid-project-name '$project' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
profile_path="$accounts_dir/$account/$project.sh"

if [[ ! -f "$profile_path" ]]; then
  echo "PROJECT_STATUS=missing $profile_path"
  exit 1
fi

# Source the profile in an isolated subshell to extract values cleanly.
# `set +eu` because hand-edited profiles may have unbound-var quirks; we
# want to read what we can rather than abort on first issue. Empty values
# round-trip as empty strings — consistent with accounts-describe.sh.
values=$(
  set +eu
  # shellcheck source=/dev/null
  source "$profile_path" 2>/dev/null || true
  set +u
  printf 'PROJECT_SLUG=%s\n'                       "${PROJECT_SLUG:-}"
  printf 'PROJECT_DOMAIN=%s\n'                     "${DOMAIN:-}"
  printf 'PROJECT_DM_UPLOAD_PATH=%s\n'             "${DM_UPLOAD_PATH:-}"
  printf 'PROJECT_GA4_MEASUREMENT_ID=%s\n'         "${GA4_MEASUREMENT_ID:-}"
  printf 'PROJECT_CAPTURE_FORM_ID=%s\n'            "${CAPTURE_FORM_ID:-}"
  printf 'PROJECT_SURVEY_FORM_ID=%s\n'             "${SURVEY_FORM_ID:-}"
  printf 'PROJECT_LIST_ID=%s\n'                    "${LIST_ID:-}"
  printf 'PROJECT_LANDING_SLUG=%s\n'               "${LANDING_SLUG:-}"
  printf 'PROJECT_THANKYOU_SLUG=%s\n'              "${THANKYOU_SLUG:-}"
  printf 'PROJECT_HUBSPOT_SUBSCRIPTION_ID=%s\n'    "${HUBSPOT_SUBSCRIPTION_ID:-}"
  printf 'PROJECT_HUBSPOT_OFFICE_LOCATION_ID=%s\n' "${HUBSPOT_OFFICE_LOCATION_ID:-}"
  printf 'PROJECT_EMAIL_PREVIEW_TEXT=%s\n'         "${EMAIL_PREVIEW_TEXT:-}"
  printf 'PROJECT_AUTO_PUBLISH_WELCOME_EMAIL=%s\n' "${AUTO_PUBLISH_WELCOME_EMAIL:-}"
  printf 'PROJECT_EMAIL_REPLY_TO=%s\n'             "${EMAIL_REPLY_TO:-}"
)
printf '%s\n' "$values"
