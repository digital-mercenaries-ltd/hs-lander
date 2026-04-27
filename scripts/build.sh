#!/usr/bin/env bash
# build.sh — Copy src/ to dist/ and substitute __PLACEHOLDER__ tokens.
# Reads values from project.config.sh in the project root.
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"

# inherit_errexit propagates errexit into command substitutions, so a sed
# crash inside `$( ... )` aborts the script instead of silently producing
# an empty value. Requires bash 4.4+. On bash 3.2 (default macOS shell)
# the option is unknown — we soft-fail with a stderr warning so an
# operator running the script directly with /bin/bash knows the
# defensive layer isn't in effect, rather than silently believing it is.
# Most real consumers run via npm scripts that resolve to a Homebrew-
# managed bash 5.x; this guard only affects fallback paths.
if ! shopt -s inherit_errexit 2>/dev/null; then
  echo "WARNING: bash $BASH_VERSION lacks 'inherit_errexit' (need 4.4+)." >&2
  echo "         Defensive errexit-in-command-subst layer is OFF." >&2
  echo "         Consider running via 'npm run build' (Homebrew bash on PATH)" >&2
  echo "         or installing a newer bash." >&2
fi

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
