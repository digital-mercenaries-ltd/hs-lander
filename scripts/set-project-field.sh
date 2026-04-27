#!/usr/bin/env bash
# set-project-field.sh — Update one or more fields in an existing project
# profile at ~/.config/hs-lander/<account>/<project>.sh.
#
# Usage:
#   bash scripts/set-project-field.sh <account> <project> KEY=VALUE [KEY=VALUE ...]
#
# Allowed keys (project-profile schema):
#   PROJECT_SLUG, DOMAIN, DM_UPLOAD_PATH, GA4_MEASUREMENT_ID,
#   CAPTURE_FORM_ID, SURVEY_FORM_ID, LIST_ID,
#   LANDING_SLUG, THANKYOU_SLUG,
#   HUBSPOT_SUBSCRIPTION_ID, HUBSPOT_OFFICE_LOCATION_ID,
#   EMAIL_PREVIEW_TEXT, AUTO_PUBLISH_WELCOME_EMAIL,
#   EMAIL_REPLY_TO
#
# v1.7.0: HOSTING_MODE_HINT removed (was skill-only state, lives in
# <project>.skillstate.sh now). EMAIL_PREVIEW_TEXT, AUTO_PUBLISH_WELCOME_EMAIL,
# INCLUDE_BOTTOM_CTA added — all map to module variables via tf.sh exports
# (defaults preserve v1.6.7 behaviour for projects that don't set them).
# v1.7.1: INCLUDE_BOTTOM_CTA removed (variable was advisory-only and
# consumers were misled into setting false expecting effect; the scaffold
# template's bottom CTA is edited directly to opt out).
#
# Unknown keys are rejected (prevents typos creating zombie variables).
# Account-level credential fields (e.g. HUBSPOT_TOKEN_KEYCHAIN_SERVICE) are
# intentionally not on the allow-list — this script never writes credential
# references. HUBSPOT_SUBSCRIPTION_ID and HUBSPOT_OFFICE_LOCATION_ID are
# account-level by convention but appear here because the project-profile
# sourcing chain pulls them into the same shell scope; setting them at
# project level is a legitimate per-project override.
#
# Output contract:
#   SET_FIELD_UPDATED=<key>       — existing line rewritten
#   SET_FIELD_APPENDED=<key>      — new line added
#   SET_FIELD=ok                  — all pairs applied (exit 0)
#   SET_FIELD=error <reason>      — exit 1. Reasons: profile-missing <path>,
#                                   unknown-key <key>, invalid-pair <arg>,
#                                   no-pairs-given
set -euo pipefail

ALLOWED_KEYS=(
  PROJECT_SLUG
  DOMAIN
  DM_UPLOAD_PATH
  GA4_MEASUREMENT_ID
  CAPTURE_FORM_ID
  SURVEY_FORM_ID
  LIST_ID
  LANDING_SLUG
  THANKYOU_SLUG
  HUBSPOT_SUBSCRIPTION_ID
  HUBSPOT_OFFICE_LOCATION_ID
  EMAIL_PREVIEW_TEXT
  AUTO_PUBLISH_WELCOME_EMAIL
  EMAIL_REPLY_TO
)

_is_allowed_key() {
  local k="$1" a
  for a in "${ALLOWED_KEYS[@]}"; do
    [[ "$a" == "$k" ]] && return 0
  done
  return 1
}

if [[ $# -lt 2 ]]; then
  echo "SET_FIELD=error usage: set-project-field.sh <account> <project> KEY=VALUE [...]" >&2
  exit 1
fi
account="$1"
project="$2"
shift 2

if [[ $# -eq 0 ]]; then
  echo "SET_FIELD=error no-pairs-given"
  exit 1
fi

# shellcheck source=lib/validate-name.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/validate-name.sh"
if ! is_valid_name "$account"; then
  echo "SET_FIELD=error invalid-account-name '$account' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi
if ! is_valid_name "$project"; then
  echo "SET_FIELD=error invalid-project-name '$project' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
profile="$accounts_dir/$account/$project.sh"

if [[ ! -f "$profile" ]]; then
  echo "SET_FIELD=error profile-missing $profile"
  exit 1
fi

# Reject values that can't round-trip through canonical `KEY="value"` quoting
# or that would break the sed substitution used for in-place rewrites.
# These characters have no legitimate use in the allow-listed project-profile
# fields (domains, paths, ids, GA4 measurement IDs). Rejecting up-front is
# simpler and safer than trying to escape them correctly through two layers
# (sed replacement AND double-quoted shell syntax).
#
# Banned: " $ ` \ and any control char (newline, tab, etc.).
_has_banned_char() {
  [[ "$1" == *'"'* || "$1" == *'$'* || "$1" == *'`'* || "$1" == *"\\"* ]] && return 0
  # Any control char (0x00-0x1F, 0x7F): use tr + -n to test for non-printable.
  [[ "$1" != "$(printf '%s' "$1" | tr -d '[:cntrl:]')" ]] && return 0
  return 1
}

# Validate every pair up front. No partial writes — if one pair is bad,
# no file is touched.
keys=()
values=()
for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    echo "SET_FIELD=error invalid-pair '$arg' (expected KEY=VALUE)"
    exit 1
  fi
  k="${arg%%=*}"
  v="${arg#*=}"
  if [[ -z "$k" ]]; then
    echo "SET_FIELD=error invalid-pair '$arg' (empty key)"
    exit 1
  fi
  if ! _is_allowed_key "$k"; then
    echo "SET_FIELD=error unknown-key $k"
    exit 1
  fi
  if _has_banned_char "$v"; then
    # Don't echo the raw value — it may contain terminal control codes.
    echo "SET_FIELD=error invalid-value $k (contains disallowed character: double-quote, dollar, backtick, backslash, or control char)"
    exit 1
  fi
  keys+=("$k")
  values+=("$v")
done

# Apply all pairs to an in-memory copy, then atomic-replace on disk. EXIT
# trap cleans up the temp files even if the script is killed or sed fails
# mid-loop — otherwise stale *.tmp.* files accumulate in the config dir.
tmp_path="$profile.tmp.$$"
trap 'rm -f "$tmp_path" "$tmp_path.edit"' EXIT
cp "$profile" "$tmp_path"

actions=()
for i in "${!keys[@]}"; do
  k="${keys[$i]}"
  v="${values[$i]}"
  # Match any existing assignment (quoted or unquoted, optional `export `)
  # and replace with canonical KEY="value". We use `|` as the sed delimiter,
  # so escape `\`, `|`, and `&` (the whole-match metachar) in the value.
  # The other "scary" shell metachars (" $ ` \ newline) are rejected up-front
  # by _has_banned_char, so we don't need to escape them here.
  v_escaped=$(printf '%s' "$v" | sed -e 's/[\\|&]/\\&/g')
  if grep -qE "^[[:space:]]*(export[[:space:]]+)?$k=" "$tmp_path"; then
    # In-place edit on the temp copy. `sed -i` differs between BSD/GNU
    # so we use the portable `sed ... > new && mv` dance.
    sed -E "s|^[[:space:]]*(export[[:space:]]+)?$k=.*$|$k=\"$v_escaped\"|" "$tmp_path" > "$tmp_path.edit"
    mv "$tmp_path.edit" "$tmp_path"
    actions+=("SET_FIELD_UPDATED=$k")
  else
    printf '%s="%s"\n' "$k" "$v" >> "$tmp_path"
    actions+=("SET_FIELD_APPENDED=$k")
  fi
done

mv "$tmp_path" "$profile"
trap - EXIT

printf '%s\n' "${actions[@]}"
echo "SET_FIELD=ok"
