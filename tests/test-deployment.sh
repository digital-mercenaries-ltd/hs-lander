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
# v1.7.1: rm -f errors on directory paths under set -e, aborting the test
# script before the v1.7.0 served-asset checks ran. Split into files vs
# directories with a cleanup function. Late-bound paths (THANKYOU_HTML_FILE,
# *_TOKENS_DIR, CSS_FILE) are checked for existence at cleanup time so the
# function tolerates whichever scenario aborts the script.
cleanup_test_artifacts() {
  rm -f "${LANDING_HTML_FILE:-}"
  rm -f "${THANKYOU_HTML_FILE:-}"
  rm -f "${CSS_FILE:-}"
  rm -rf "${LANDING_TOKENS_DIR:-}"
  rm -rf "${THANKYOU_TOKENS_DIR:-}"
}
trap cleanup_test_artifacts EXIT

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

  # v1.7.0 check 6: preview_text widget populated when EMAIL_PREVIEW_TEXT is
  # set. When empty, widget renders without preview line and clients fall
  # back to first body line — accepted state, no assertion fails.
  if [[ -n "${EMAIL_PREVIEW_TEXT:-}" ]]; then
    preview_text_value=$(echo "$email_json" \
      | jq -r '.content.widgets.preview_text.body.value // ""')
    if [[ "$preview_text_value" == "$EMAIL_PREVIEW_TEXT" ]]; then
      assert_equal "true" "true" "preview_text widget value matches EMAIL_PREVIEW_TEXT"
    else
      assert_equal "true" "false" "preview_text widget value matches EMAIL_PREVIEW_TEXT (got '$preview_text_value')"
    fi
  fi
fi

# v1.7.0 served-page checks — these depend on the HubL scaffold rewrite, so
# they're meaningful only against projects deployed under v1.7.0+ scaffold.
# A pre-v1.7.0 project (raw-HTML scaffold) will fail these by design — the
# point is to catch scaffold-drift back to static HTML.

# Check 1 (v1.7.0): CSS asset returns 200. Extract the URL from served HTML
# and probe directly. Catches broken upload paths, missing files, scaffold
# not rewritten.
echo ""
echo "--- Served-asset checks (v1.7.0 scaffold) ---"

css_url=$(grep -oE 'href="[^"]*main\.css[^"]*"' "$LANDING_HTML_FILE" | head -n 1 | sed -E 's/^href="//; s/"$//')
if [[ -n "$css_url" ]]; then
  # Resolve protocol-relative or relative URLs against the landing URL.
  case "$css_url" in
    //*)  css_url="https:$css_url" ;;
    /*)   css_url="https://${DOMAIN}${css_url}" ;;
    http*) ;;
    *)    css_url="$LANDING_URL/$css_url" ;;
  esac
  css_status=$(curl -s -o /dev/null -w "%{http_code}" "$css_url")
  assert_equal "$css_status" "200" "main.css served from $css_url returns 200"
else
  echo "  SKIP: no main.css URL found in served landing HTML"
fi

# Check 2 (v1.7.0): hub_generated/template_assets URL present. Confirms HubL
# get_asset_url() compiled into a HubSpot served-asset path. Static-HTML
# templates (missing templateType: page annotation) won't have this.
assert_file_contains "$LANDING_HTML_FILE" "hub_generated/template_assets" \
  "served HTML contains hub_generated/template_assets URL (HubL compilation worked)"

# Check 3 (v1.7.0): scriptloader script-tag present. standard_header_includes
# emits this; without it forms degrade silently.
assert_file_contains "$LANDING_HTML_FILE" "/hs/scriptloader/${HUBSPOT_PORTAL_ID}.js" \
  "served HTML contains /hs/scriptloader/<portal>.js (standard_header_includes fired)"

# Check 4 (v1.7.0): prefers-color-scheme block in fetched CSS. Catches
# minification stripping the @media block or scaffold drift back to single-mode.
if [[ -n "$css_url" ]] && [[ "$css_status" == "200" ]]; then
  # CSS_FILE is picked up by cleanup_test_artifacts on EXIT (its trap was
  # installed at the top of the script and tolerates unset/missing paths).
  CSS_FILE=$(mktemp)
  curl -s "$css_url" > "$CSS_FILE"
  assert_file_contains "$CSS_FILE" "prefers-color-scheme" \
    "served CSS contains @media (prefers-color-scheme: dark) block"
fi

# Check 5 (v1.7.0): templateType: page annotation persists in served-template
# metadata. The annotation is stripped from served HTML (it's a HubL comment),
# but the source-code metadata API exposes it. Catches scaffold drift back
# to static HTML.
if [[ -n "${DM_UPLOAD_PATH:-}" ]]; then
  template_meta=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/cms/v3/source-code/published/metadata${DM_UPLOAD_PATH}/templates/landing-page.html")
  template_type=$(echo "$template_meta" | jq -r '.templateType // ""')
  # HubSpot returns the annotation value (e.g. "PAGE" or "page" — case may vary).
  case "$(echo "$template_type" | tr '[:upper:]' '[:lower:]')" in
    page)
      assert_equal "true" "true" "landing-page.html declares templateType: page"
      ;;
    *)
      assert_equal "page" "$template_type" "landing-page.html declares templateType: page"
      ;;
  esac
fi

# v1.8.0 Schema-alignment: the static survey form on thank-you.html, the
# HubSpot-defined survey form (Terraform), and the project's CRM custom
# properties must declare matching field/property names. Drift between any
# two of them produces a silent failure where the form looks fine but
# submissions land in the wrong (or no) CRM property. Three-way diff via
# `comm -3`; empty diff means alignment.
if [[ "${INCLUDE_SURVEY:-false}" == "true" ]] && [[ -n "${SURVEY_FORM_ID:-}" ]] && [[ -n "${PROJECT_SLUG:-}" ]]; then
  echo ""
  echo "--- Schema alignment (static form ↔ HubSpot survey form ↔ custom_properties) ---"

  # Names <input name="..."> attributes in the static thank-you form,
  # filtered to those prefixed with the project slug (skips `email`,
  # `project_source`, etc.).
  static_names=$(grep -oE 'name="[a-zA-Z0-9_]+"' "$LANDING_HTML_FILE" "$THANKYOU_HTML_FILE" 2>/dev/null \
    | sed 's/.*name="\([^"]*\)"/\1/' \
    | sort -u \
    | grep -E "^${PROJECT_SLUG}_" || true)

  hubspot_names=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/forms/${SURVEY_FORM_ID}" \
    | jq -r '.fieldGroups[].fields[].name' \
    | sort -u \
    | grep -E "^${PROJECT_SLUG}_" || true)

  prop_names=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/crm/v3/properties/contacts" \
    | jq -r --arg slug "${PROJECT_SLUG}" '.results[] | select(.name | startswith($slug + "_")) | select(.name != $slug + "_survey_completed") | .name' \
    | sort -u || true)

  # Pairwise diffs. comm -3 outputs lines unique to one side or the other;
  # empty result means full overlap.
  diff_static_hubspot=$(comm -3 <(printf '%s\n' "$static_names") <(printf '%s\n' "$hubspot_names") | tr -d '\t')
  diff_static_props=$(comm -3 <(printf '%s\n' "$static_names") <(printf '%s\n' "$prop_names") | tr -d '\t')

  if [[ -z "$diff_static_hubspot" ]] && [[ -z "$diff_static_props" ]]; then
    static_count=$(printf '%s\n' "$static_names" | grep -c . || true)
    assert_equal "true" "true" "schema alignment ($static_count survey fields aligned across static / HubSpot / CRM)"
  else
    if [[ -n "$diff_static_hubspot" ]]; then
      echo "  static form ↔ HubSpot survey form mismatch:"
      printf '%s\n' "$diff_static_hubspot" | sed 's/^/    /'
    fi
    if [[ -n "$diff_static_props" ]]; then
      echo "  static form ↔ custom_properties mismatch:"
      printf '%s\n' "$diff_static_props" | sed 's/^/    /'
    fi
    assert_equal "aligned" "drifted" "schema alignment (static / HubSpot / CRM names match)"
  fi
fi

test_summary
