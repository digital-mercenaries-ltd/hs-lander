#!/usr/bin/env bash
# post-apply.sh — Read terraform outputs and write them to project.config.sh.
# Run after `terraform apply` to populate form IDs and list ID.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_DIR/project.config.sh"
TF_DIR="$PROJECT_DIR/terraform"

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

# Update config file
_sed_inplace "s|^CAPTURE_FORM_ID=.*|CAPTURE_FORM_ID=\"${capture_form_id}\"|" "$CONFIG_FILE"
_sed_inplace "s|^SURVEY_FORM_ID=.*|SURVEY_FORM_ID=\"${survey_form_id}\"|" "$CONFIG_FILE"
_sed_inplace "s|^LIST_ID=.*|LIST_ID=\"${list_id}\"|" "$CONFIG_FILE"

echo "Config updated: $CONFIG_FILE"
echo "  CAPTURE_FORM_ID=$capture_form_id"
echo "  SURVEY_FORM_ID=$survey_form_id"
echo "  LIST_ID=$list_id"
