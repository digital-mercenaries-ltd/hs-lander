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

# Update an existing assignment line in $file, or append a new one if no
# matching key is present. A hand-edited profile that has had a line removed
# (e.g. SURVEY_FORM_ID dropped because the project doesn't use a survey)
# would otherwise silently fail to record the value.
_update_field() {
  local key="$1" value="$2" file="$3"
  if grep -q "^${key}=" "$file"; then
    _sed_inplace "s|^${key}=.*|${key}=\"${value}\"|" "$file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$file"
  fi
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
