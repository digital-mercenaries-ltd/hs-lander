#!/usr/bin/env bash
# build.sh — Copy src/ to dist/ and substitute __PLACEHOLDER__ tokens.
# Reads values from project.config.sh in the project root.
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"

# Source config
# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

# Derive HSFORMS_HOST from region
if [[ "$HUBSPOT_REGION" == "eu1" ]]; then
  HSFORMS_HOST="js-eu1.hsforms.net"
else
  HSFORMS_HOST="js.hsforms.net"
fi

# Clean and copy
rm -rf "$PROJECT_DIR/dist"
cp -r "$PROJECT_DIR/src" "$PROJECT_DIR/dist"

# Portable in-place sed
_sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Token substitution (use | delimiter — DM_UPLOAD_PATH contains /)
find "$PROJECT_DIR/dist" -type f | while read -r file; do
  _sed_inplace \
    -e "s|__PORTAL_ID__|${HUBSPOT_PORTAL_ID}|g" \
    -e "s|__REGION__|${HUBSPOT_REGION}|g" \
    -e "s|__HSFORMS_HOST__|${HSFORMS_HOST}|g" \
    -e "s|__CAPTURE_FORM_ID__|${CAPTURE_FORM_ID:-}|g" \
    -e "s|__SURVEY_FORM_ID__|${SURVEY_FORM_ID:-}|g" \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__GA4_ID__|${GA4_MEASUREMENT_ID}|g" \
    -e "s|__DM_PATH__|${DM_UPLOAD_PATH}|g" \
    "$file"
done

echo "Build complete: $PROJECT_DIR/dist/"
