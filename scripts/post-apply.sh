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

CONFIG_FILE="${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Project config file not found: $CONFIG_FILE" >&2
  echo "Expected at ~/.config/hs-lander/<account>/<project>.sh per the two-tier config layout." >&2
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

# Read outputs from terraform
capture_form_id=$(terraform -chdir="$TF_DIR" output -raw capture_form_id 2>/dev/null || echo "")
survey_form_id=$(terraform -chdir="$TF_DIR" output -raw survey_form_id 2>/dev/null || echo "")
list_id=$(terraform -chdir="$TF_DIR" output -raw list_id 2>/dev/null || echo "")

# Update project config file (in ~/.config/hs-lander/, not the project dir)
_sed_inplace "s|^CAPTURE_FORM_ID=.*|CAPTURE_FORM_ID=\"${capture_form_id}\"|" "$CONFIG_FILE"
_sed_inplace "s|^SURVEY_FORM_ID=.*|SURVEY_FORM_ID=\"${survey_form_id}\"|" "$CONFIG_FILE"
_sed_inplace "s|^LIST_ID=.*|LIST_ID=\"${list_id}\"|" "$CONFIG_FILE"

echo "Config updated: $CONFIG_FILE"
echo "  CAPTURE_FORM_ID=$capture_form_id"
echo "  SURVEY_FORM_ID=$survey_form_id"
echo "  LIST_ID=$list_id"
