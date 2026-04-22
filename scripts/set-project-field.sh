#!/usr/bin/env bash
# set-project-field.sh — Update one or more fields in an existing project
# profile at ~/.config/hs-lander/<account>/<project>.sh.
#
# Usage:
#   bash scripts/set-project-field.sh <account> <project> KEY=VALUE [KEY=VALUE ...]
#
# Allowed keys (project-profile schema):
#   PROJECT_SLUG, DOMAIN, DM_UPLOAD_PATH, GA4_MEASUREMENT_ID,
#   CAPTURE_FORM_ID, SURVEY_FORM_ID, LIST_ID
#
# Unknown keys are rejected (prevents typos creating zombie variables).
# Account-level fields (e.g. HUBSPOT_TOKEN_KEYCHAIN_SERVICE) are intentionally
# not on the allow-list — this script never writes credential references.
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

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
profile="$accounts_dir/$account/$project.sh"

if [[ ! -f "$profile" ]]; then
  echo "SET_FIELD=error profile-missing $profile"
  exit 1
fi

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
  keys+=("$k")
  values+=("$v")
done

# Apply all pairs to an in-memory copy, then atomic-replace on disk.
tmp_path="$profile.tmp.$$"
cp "$profile" "$tmp_path"

actions=()
for i in "${!keys[@]}"; do
  k="${keys[$i]}"
  v="${values[$i]}"
  # Match any existing assignment (quoted or unquoted, optional `export `),
  # replace with canonical KEY="value". Escape sed metacharacters in the
  # value so shell/regex metacharacters round-trip safely.
  v_escaped=$(printf '%s' "$v" | sed -e 's/[\\/&]/\\&/g')
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

printf '%s\n' "${actions[@]}"
echo "SET_FIELD=ok"
