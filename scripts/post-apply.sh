#!/usr/bin/env bash
# post-apply.sh — Read terraform outputs and write them to the project-level
# config file under ~/.config/hs-lander/<account>/<project>.sh.
# Run after `terraform apply` to populate form IDs and list ID.
#
# Notes on the two-tier config layout:
# - project.config.sh in the project dir is a sourcing-chain pointer (sets
#   HS_LANDER_ACCOUNT + HS_LANDER_PROJECT, then sources account + project
#   config files from ~/.config/hs-lander/).
# - Form IDs live in the project-level file, not the pointer — so this
#   script derives the target path from HS_LANDER_ACCOUNT/HS_LANDER_PROJECT
#   and writes there.
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
TF_DIR="$PROJECT_DIR/terraform"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

: "${HS_LANDER_ACCOUNT:?HS_LANDER_ACCOUNT must be set in project.config.sh}"
: "${HS_LANDER_PROJECT:?HS_LANDER_PROJECT must be set in project.config.sh}"

CONFIG_DIR="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
CONFIG_FILE="${CONFIG_DIR}/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Project config file not found: $CONFIG_FILE" >&2
  echo "Expected at \$HS_LANDER_CONFIG_DIR/<account>/<project>.sh (default ~/.config/hs-lander/) per the two-tier config layout." >&2
  exit 1
fi

# Portable in-place sed
_sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Escape sed replacement-side metacharacters: |, &, and \. Mirrors
# set-project-field.sh's _has_banned_char permits — | and & can survive
# operator edits to the profile and end up reaching post-apply via the
# sourcing chain. Today's terraform outputs (numeric form/list IDs) won't
# carry them, but the helper is general-purpose and forward-compatible.
_sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# Update (or append) a KEY=VALUE assignment in $file.
#
# - Matches `KEY=`, `export KEY=`, and either form with leading whitespace,
#   in lockstep with set-project-field.sh's pattern (lines 158-161). A
#   hand-edited profile using `export CAPTURE_FORM_ID=...` would otherwise
#   accumulate a duplicate assignment.
# - Distinguishes grep exit 1 (no match → append) from exit 2+ (IO error
#   → fail loudly). The default `if grep -q ...; then` collapses both,
#   silently routing IO failures to the append branch.
# - Sed-escapes the value so |, &, and \ in future string-valued outputs
#   round-trip cleanly.
_update_field() {
  local key="$1" value="$2" file="$3"
  local rc=0
  grep -qE "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" || rc=$?
  case "$rc" in
    0)
      local escaped
      escaped=$(_sed_escape "$value")
      _sed_inplace -E "s|^[[:space:]]*(export[[:space:]]+)?${key}=.*|${key}=\"${escaped}\"|" "$file"
      ;;
    1)
      printf '%s="%s"\n' "$key" "$value" >> "$file"
      ;;
    *)
      echo "ERROR: grep exited $rc reading $file (likely permission or IO error)" >&2
      exit 1
      ;;
  esac
}

# Read outputs from terraform
capture_form_id=$(terraform -chdir="$TF_DIR" output -raw capture_form_id 2>/dev/null || echo "")
survey_form_id=$(terraform -chdir="$TF_DIR" output -raw survey_form_id 2>/dev/null || echo "")
list_id=$(terraform -chdir="$TF_DIR" output -raw list_id 2>/dev/null || echo "")

# Update project config file (in $HS_LANDER_CONFIG_DIR, not the project dir)
_update_field "CAPTURE_FORM_ID" "$capture_form_id" "$CONFIG_FILE"
_update_field "SURVEY_FORM_ID" "$survey_form_id" "$CONFIG_FILE"
_update_field "LIST_ID" "$list_id" "$CONFIG_FILE"

echo "Config updated: $CONFIG_FILE"
echo "  CAPTURE_FORM_ID=$capture_form_id"
echo "  SURVEY_FORM_ID=$survey_form_id"
echo "  LIST_ID=$list_id"
