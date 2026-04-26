#!/usr/bin/env bash
# test-deployment.sh — Validates a live HubSpot deployment.
# Requires: network access, deployed landing page, project.config.sh with real values.
# Usage: bash tests/test-deployment.sh /path/to/project
set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-deployment.sh ==="
echo "Project: $PROJECT_DIR"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

# Read token from Keychain
: "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:?HUBSPOT_TOKEN_KEYCHAIN_SERVICE must be set in the account config}"
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE'. Is this running on macOS with credentials?" >&2
  exit 1
}

LANDING_URL="https://${DOMAIN}/${LANDING_SLUG:-}"
THANKYOU_URL="https://${DOMAIN}/${THANKYOU_SLUG:-thank-you}"

echo "Landing URL: $LANDING_URL"
echo "Thank-you URL: $THANKYOU_URL"
echo ""

# --- HTTP checks ---
echo "--- Page HTTP responses ---"

landing_status=$(curl -s -o /dev/null -w "%{http_code}" "$LANDING_URL")
assert_equal "$landing_status" "200" "landing page returns HTTP 200"

thankyou_status=$(curl -s -o /dev/null -w "%{http_code}" "$THANKYOU_URL")
assert_equal "$thankyou_status" "200" "thank-you page returns HTTP 200"

# --- Content checks ---
echo ""
echo "--- Landing page content ---"

LANDING_HTML_FILE=$(mktemp)
trap 'rm -f "$LANDING_HTML_FILE" "$THANKYOU_HTML_FILE" "$LANDING_TOKENS_DIR" "$THANKYOU_TOKENS_DIR"' EXIT

curl -s "$LANDING_URL" > "$LANDING_HTML_FILE"
assert_file_contains "$LANDING_HTML_FILE" "hbspt.forms.create" \
  "landing page contains HubSpot form embed"
assert_file_contains "$LANDING_HTML_FILE" "$HUBSPOT_PORTAL_ID" \
  "landing page contains correct portal ID"

# assert_no_tokens expects a directory — wrap file in a temp dir
LANDING_TOKENS_DIR=$(mktemp -d)
cp "$LANDING_HTML_FILE" "$LANDING_TOKENS_DIR/landing.html"
assert_no_tokens "$LANDING_TOKENS_DIR" "no __TOKENS__ in landing page HTML"

echo ""
echo "--- Thank-you page content ---"
THANKYOU_HTML_FILE=$(mktemp)
curl -s "$THANKYOU_URL" > "$THANKYOU_HTML_FILE"
THANKYOU_TOKENS_DIR=$(mktemp -d)
cp "$THANKYOU_HTML_FILE" "$THANKYOU_TOKENS_DIR/thankyou.html"
assert_no_tokens "$THANKYOU_TOKENS_DIR" "no __TOKENS__ in thank-you page HTML"

# --- API checks ---
echo ""
echo "--- HubSpot API verification ---"

if [[ -n "${CAPTURE_FORM_ID:-}" ]]; then
  form_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/forms/${CAPTURE_FORM_ID}")
  assert_equal "$form_status" "200" "capture form exists in HubSpot API"

  # v1.6.7 check: project_source field has the canonical `hidden: true` flag
  # set at field definition time. Catches regressions where the flag is
  # dropped and CSS hiding becomes the sole mechanism (fragile across
  # browsers and Forms v3 markup variants).
  form_json=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/forms/${CAPTURE_FORM_ID}")
  project_source_hidden=$(echo "$form_json" \
    | jq -r '[.fieldGroups[].fields[] | select(.name == "project_source") | .hidden] | first // false')
  assert_equal "$project_source_hidden" "true" "project_source field has hidden=true on capture form"
else
  echo "  SKIP: CAPTURE_FORM_ID not set — run post-apply first"
fi

if [[ -n "${LANDING_PAGE_ID:-}" ]]; then
  page_json=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/cms/v3/pages/landing-pages/${LANDING_PAGE_ID}")
  page_state=$(echo "$page_json" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
  assert_equal "$page_state" "PUBLISHED" "landing page is PUBLISHED"
fi

if [[ -n "${WELCOME_EMAIL_ID:-}" ]]; then
  email_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/emails/${WELCOME_EMAIL_ID}")
  assert_equal "$email_status" "200" "welcome email exists in HubSpot API"

  # v1.6.7 checks: verify the welcome email has the right widget shape and
  # layout placement. Without all three, HubSpot accepts the create silently
  # but the email renders empty. PATCH cannot fix this — consumers must
  # `terraform taint` + recreate. See CHANGELOG migration block.
  email_json=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/emails/${WELCOME_EMAIL_ID}")

  # Check 1: body.html populated (correct field key — body.rich_text is
  # accepted on write but never rendered).
  body_html_length=$(echo "$email_json" \
    | jq -r '.content.widgets.primary_rich_text_module.body.html // "" | length')
  if [[ "$body_html_length" -gt 0 ]]; then
    assert_equal "true" "true" "welcome email body.html is populated"
  else
    assert_equal "true" "false" "welcome email body.html is populated (length=$body_html_length)"
  fi

  # Check 2: flexAreas.main.sections has at least one section (layout
  # placement exists at all).
  flexareas_sections_count=$(echo "$email_json" \
    | jq -r '.content.flexAreas.main.sections | length // 0')
  if [[ "$flexareas_sections_count" -gt 0 ]]; then
    assert_equal "true" "true" "welcome email flexAreas has sections"
  else
    assert_equal "true" "false" "welcome email flexAreas has sections (got $flexareas_sections_count)"
  fi

  # Check 3: the rich-text widget is placed in the layout (not just defined
  # but actually wired into a column's widgets list).
  widget_placed=$(echo "$email_json" \
    | jq -r '[.content.flexAreas.main.sections[].columns[].widgets[]?] | any(. == "primary_rich_text_module")')
  assert_equal "$widget_placed" "true" "primary_rich_text_module is placed in flexAreas layout"
fi

test_summary
