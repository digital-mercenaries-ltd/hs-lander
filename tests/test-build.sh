#!/usr/bin/env bash
# test-build.sh — Validates build.sh token substitution.
# Local only, no network required.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-build.sh ==="

# --- Setup ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create fake project structure
mkdir -p "$TMPDIR/scripts"
cp "$REPO_DIR/scripts/build.sh" "$TMPDIR/scripts/build.sh"
cp "$REPO_DIR/tests/fixtures/project.config.sh" "$TMPDIR/project.config.sh"
cp -r "$REPO_DIR/tests/fixtures/src" "$TMPDIR/src"

# --- Run build ---
echo "Running build.sh..."
(cd "$TMPDIR" && bash scripts/build.sh)

# --- Assertions ---

echo ""
echo "--- Structure ---"
assert_dir_exists "$TMPDIR/dist" "dist/ directory created"
assert_file_exists "$TMPDIR/dist/templates/landing-page.html" "landing-page.html in dist/"
assert_file_exists "$TMPDIR/dist/templates/thank-you.html" "thank-you.html in dist/"
assert_file_exists "$TMPDIR/dist/css/main.css" "main.css in dist/"
assert_file_exists "$TMPDIR/dist/js/tracking.js" "tracking.js in dist/"
assert_file_exists "$TMPDIR/dist/emails/welcome-body.html" "welcome-body.html in dist/"

echo ""
echo "--- No remaining tokens ---"
assert_no_tokens "$TMPDIR/dist" "zero __TOKEN__ placeholders in dist/"

echo ""
echo "--- Correct substitution values ---"
assert_file_contains "$TMPDIR/dist/templates/landing-page.html" "12345678" "portal ID in landing page"
assert_file_contains "$TMPDIR/dist/templates/landing-page.html" "js-eu1.hsforms.net" "EU1 hsforms host in landing page"
assert_file_contains "$TMPDIR/dist/templates/landing-page.html" "eu1" "region in landing page"
assert_file_contains "$TMPDIR/dist/templates/landing-page.html" "abc-123-def" "capture form ID in landing page"
assert_file_contains "$TMPDIR/dist/templates/thank-you.html" "test.example.com" "domain in thank-you page"
assert_file_contains "$TMPDIR/dist/js/tracking.js" "G-TEST12345" "GA4 ID in tracking.js"
assert_file_contains "$TMPDIR/dist/css/main.css" "test.example.com" "domain in CSS"
assert_file_contains "$TMPDIR/dist/emails/welcome-body.html" "test.example.com" "domain in email"
assert_file_contains "$TMPDIR/dist/templates/landing-page.html" "/test-project" "DM path in landing page"

echo ""
echo "--- Empty form IDs don't break build ---"
# Rebuild with empty CAPTURE_FORM_ID
sed "s|^CAPTURE_FORM_ID=.*|CAPTURE_FORM_ID=\"\"|" "$TMPDIR/project.config.sh" > "$TMPDIR/project.config.empty.sh"
mv "$TMPDIR/project.config.empty.sh" "$TMPDIR/project.config.sh"
rm -rf "$TMPDIR/dist"
cp -r "$REPO_DIR/tests/fixtures/src" "$TMPDIR/src"
(cd "$TMPDIR" && bash scripts/build.sh)
assert_no_tokens "$TMPDIR/dist" "zero tokens with empty form ID"

echo ""
echo "--- HSFORMS_HOST for NA1 region ---"
sed "s|^HUBSPOT_REGION=.*|HUBSPOT_REGION=\"na1\"|" "$TMPDIR/project.config.sh" > "$TMPDIR/project.config.na1.sh"
mv "$TMPDIR/project.config.na1.sh" "$TMPDIR/project.config.sh"
rm -rf "$TMPDIR/dist"
cp -r "$REPO_DIR/tests/fixtures/src" "$TMPDIR/src"
(cd "$TMPDIR" && bash scripts/build.sh)
assert_file_contains "$TMPDIR/dist/templates/landing-page.html" "js.hsforms.net" "NA1 hsforms host (no region prefix)"
assert_file_not_contains "$TMPDIR/dist/templates/landing-page.html" "js-eu1" "no EU1 prefix for NA1"

test_summary
