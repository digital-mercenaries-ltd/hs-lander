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

# Escape sed replacement-side metacharacters: |, &, and \. set-project-field.sh's
# banned-char check accepts | and & today, so any value reaching this script
# may carry them. The | in particular ends our chosen substitution delimiter
# and corrupts the build silently. Token names (left side) are hard-coded so
# they don't need escaping; only the right-hand value does.
_sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

_PORTAL_ID=$(_sed_escape "$HUBSPOT_PORTAL_ID")
_REGION=$(_sed_escape "$HUBSPOT_REGION")
_HSFORMS_HOST=$(_sed_escape "$HSFORMS_HOST")
_CAPTURE_FORM_ID=$(_sed_escape "${CAPTURE_FORM_ID:-}")
_SURVEY_FORM_ID=$(_sed_escape "${SURVEY_FORM_ID:-}")
_DOMAIN=$(_sed_escape "$DOMAIN")
_GA4_ID=$(_sed_escape "$GA4_MEASUREMENT_ID")
_DM_PATH=$(_sed_escape "$DM_UPLOAD_PATH")
_PROJECT_SLUG=$(_sed_escape "${PROJECT_SLUG:-}")

# Token substitution (use | delimiter — DM_UPLOAD_PATH contains /).
# v1.8.0 added __PROJECT_SLUG__ for survey-submit.js's survey_completed
# property name. __SURVEY_FORM_ID__ has been substituted since v1.0.0;
# kept here so it's adjacent to its sibling tokens.
find "$PROJECT_DIR/dist" -type f | while read -r file; do
  _sed_inplace \
    -e "s|__PORTAL_ID__|${_PORTAL_ID}|g" \
    -e "s|__REGION__|${_REGION}|g" \
    -e "s|__HSFORMS_HOST__|${_HSFORMS_HOST}|g" \
    -e "s|__CAPTURE_FORM_ID__|${_CAPTURE_FORM_ID}|g" \
    -e "s|__SURVEY_FORM_ID__|${_SURVEY_FORM_ID}|g" \
    -e "s|__DOMAIN__|${_DOMAIN}|g" \
    -e "s|__GA4_ID__|${_GA4_ID}|g" \
    -e "s|__DM_PATH__|${_DM_PATH}|g" \
    -e "s|__PROJECT_SLUG__|${_PROJECT_SLUG}|g" \
    "$file"
done

echo "Build complete: $PROJECT_DIR/dist/"
