#!/usr/bin/env bash
# build.sh — Copy src/ to dist/ and substitute __PLACEHOLDER__ tokens.
# Reads values from project.config.sh in the project root.
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"

# v1.9.0 (Component 2): inherit_errexit so a sed crash inside `$( ... )`
# command substitution propagates instead of silently producing an empty
# value. Defensive against the silent-failure-hunter M1 finding from the
# v1.8.1 review. Requires bash 4.4+; macOS ships 3.2 by default but ALL
# real consumers run via npm scripts that resolve to /usr/bin/env bash on
# their PATH, which on a Homebrew-managed dev box is 5.x. The guard means
# the script still parses on 3.2 and falls back to the (less defensive)
# default errexit semantics there.
shopt -s inherit_errexit 2>/dev/null || true

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/sed-portable.sh"

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

# Sourcing chain (project.config.sh) defines these; shellcheck can't see across
# the source boundary. The underscore-prefixed locals below are sed-escaped
# views of the same values — disable SC2153 (misspelling) so the leading-
# underscore convention doesn't trip the check on every line.
# shellcheck disable=SC2153
_PORTAL_ID=$(sed_escape_replacement "$HUBSPOT_PORTAL_ID")
# shellcheck disable=SC2153
_REGION=$(sed_escape_replacement "$HUBSPOT_REGION")
_HSFORMS_HOST=$(sed_escape_replacement "$HSFORMS_HOST")
_CAPTURE_FORM_ID=$(sed_escape_replacement "${CAPTURE_FORM_ID:-}")
_SURVEY_FORM_ID=$(sed_escape_replacement "${SURVEY_FORM_ID:-}")
# shellcheck disable=SC2153
_DOMAIN=$(sed_escape_replacement "$DOMAIN")
_GA4_ID=$(sed_escape_replacement "$GA4_MEASUREMENT_ID")
_DM_PATH=$(sed_escape_replacement "$DM_UPLOAD_PATH")
_PROJECT_SLUG=$(sed_escape_replacement "${PROJECT_SLUG:-}")

# Token substitution (use | delimiter — DM_UPLOAD_PATH contains /).
# v1.8.0 added __PROJECT_SLUG__ for survey-submit.js's survey_completed
# property name. __SURVEY_FORM_ID__ has been substituted since v1.0.0;
# kept here so it's adjacent to its sibling tokens.
find "$PROJECT_DIR/dist" -type f | while read -r file; do
  sed_inplace \
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
