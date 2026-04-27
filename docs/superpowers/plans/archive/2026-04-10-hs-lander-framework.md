# hs-lander Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the hs-lander framework repo — Terraform modules, shell scripts, scaffold templates, tests, and CI — following TDD.

**Architecture:** Shell scripts handle build (token substitution), deployment (CMS Source Code API upload), and Terraform orchestration (Keychain → TF_VAR_*). Two Terraform modules use Mastercard/restapi provider: `account-setup` (run once per HubSpot account) and `landing-page` (run per project). Scaffold templates let new projects reference the modules by git URL.

**Tech Stack:** Bash, Terraform (Mastercard/restapi ~1.19), HubSpot APIs, GitHub Actions

---

## File Map

### New files to create

```
tests/
├── fixtures/
│   ├── test-helper.sh                    ← Assertion functions (assert_equal, assert_file_contains, etc.)
│   ├── project.config.sh                 ← Known test values for build/post-apply tests
│   └── src/
│       ├── templates/
│       │   ├── landing-page.html         ← Tokens: PORTAL_ID, REGION, HSFORMS_HOST, CAPTURE_FORM_ID
│       │   └── thank-you.html            ← Tokens: DOMAIN
│       ├── css/main.css                  ← Token: DOMAIN
│       ├── js/tracking.js               ← Token: GA4_ID
│       └── emails/
│           └── welcome-body.html         ← Token: DOMAIN
├── test-build.sh
├── test-post-apply.sh
├── test-terraform-plan.sh
└── test-deployment.sh

scripts/
├── build.sh
├── post-apply.sh
├── tf.sh
├── hs-curl.sh
├── upload.sh
├── deploy.sh
├── watch.sh
└── hs.sh

terraform/modules/
├── account-setup/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── landing-page/
    ├── main.tf
    ├── variables.tf
    ├── forms.tf
    ├── pages.tf
    ├── emails.tf
    ├── properties.tf
    ├── lists.tf
    └── outputs.tf

scaffold/
├── project.config.example.sh
├── brief-template.md
├── package.json
├── .gitignore
└── terraform/
    └── main.tf

.github/workflows/
├── ci.yml
└── smoke.yml

docs/
└── framework.md
```

---

### Task 1: Test helper and fixture files

**Files:**
- Create: `tests/fixtures/test-helper.sh`
- Create: `tests/fixtures/project.config.sh`
- Create: `tests/fixtures/src/templates/landing-page.html`
- Create: `tests/fixtures/src/templates/thank-you.html`
- Create: `tests/fixtures/src/css/main.css`
- Create: `tests/fixtures/src/js/tracking.js`
- Create: `tests/fixtures/src/emails/welcome-body.html`

- [ ] **Step 1: Create test assertion helper**

```bash
# tests/fixtures/test-helper.sh
# Minimal test assertion library for hs-lander shell tests.
# Source this at the top of each test file.

PASSES=0
FAILURES=0
TESTS=0

assert_equal() {
  local actual="$1" expected="$2" message="${3:-assert_equal}"
  TESTS=$((TESTS + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_file_exists() {
  local path="$1" message="${2:-file exists: $1}"
  TESTS=$((TESTS + 1))
  if [[ -f "$path" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (file not found)"
  fi
}

assert_dir_exists() {
  local path="$1" message="${2:-dir exists: $1}"
  TESTS=$((TESTS + 1))
  if [[ -d "$path" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (directory not found)"
  fi
}

assert_file_contains() {
  local path="$1" pattern="$2" message="${3:-file contains pattern}"
  TESTS=$((TESTS + 1))
  if grep -q "$pattern" "$path" 2>/dev/null; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (pattern '$pattern' not found in $path)"
  fi
}

assert_file_not_contains() {
  local path="$1" pattern="$2" message="${3:-file does not contain pattern}"
  TESTS=$((TESTS + 1))
  if ! grep -q "$pattern" "$path" 2>/dev/null; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (pattern '$pattern' found in $path but should not be)"
  fi
}

assert_no_tokens() {
  local dir="$1" message="${2:-no __TOKENS__ remain in $1}"
  TESTS=$((TESTS + 1))
  local found
  found=$(grep -r '__[A-Z_]*__' "$dir" 2>/dev/null || true)
  if [[ -z "$found" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message"
    echo "    tokens found:"
    echo "$found" | head -10
  fi
}

assert_command_succeeds() {
  local message="${1:-command succeeds}"
  shift
  TESTS=$((TESTS + 1))
  if "$@" >/dev/null 2>&1; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (exit code $?)"
  fi
}

test_summary() {
  echo ""
  echo "========================================="
  echo "Results: $PASSES passed, $FAILURES failed, $TESTS total"
  echo "========================================="
  if [[ "$FAILURES" -gt 0 ]]; then
    exit 1
  fi
}
```

- [ ] **Step 2: Create fixture project.config.sh**

```bash
# tests/fixtures/project.config.sh
# Fixture config with known test values.
# Used by test-build.sh and test-post-apply.sh.

HUBSPOT_PORTAL_ID="12345678"
HUBSPOT_REGION="eu1"
DOMAIN="test.example.com"
KEYCHAIN_PREFIX="test"
DM_UPLOAD_PATH="/test-project"
GA4_MEASUREMENT_ID="G-TEST12345"
CAPTURE_FORM_ID="abc-123-def"
SURVEY_FORM_ID=""
```

- [ ] **Step 3: Create fixture src/ files with tokens**

`tests/fixtures/src/templates/landing-page.html`:
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Landing Page | __DOMAIN__</title>
  <link rel="stylesheet" href="{{ get_asset_url('__DM_PATH__/css/main.css') }}">
</head>
<body>
  <h1>Welcome</h1>
  <div id="capture-form"></div>
  <script src="//__HSFORMS_HOST__/forms/embed/v2.js"></script>
  <script>
    hbspt.forms.create({
      region: '__REGION__',
      portalId: '__PORTAL_ID__',
      formId: '__CAPTURE_FORM_ID__',
      target: '#capture-form'
    });
  </script>
  <script src="{{ get_asset_url('__DM_PATH__/js/tracking.js') }}"></script>
</body>
</html>
```

`tests/fixtures/src/templates/thank-you.html`:
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Thank You | __DOMAIN__</title>
  <link rel="stylesheet" href="{{ get_asset_url('__DM_PATH__/css/main.css') }}">
</head>
<body>
  <h1>Thank you for signing up.</h1>
  <p>We'll be in touch at __DOMAIN__.</p>
  <script src="{{ get_asset_url('__DM_PATH__/js/tracking.js') }}"></script>
</body>
</html>
```

`tests/fixtures/src/css/main.css`:
```css
/* Styles for __DOMAIN__ */
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  margin: 0;
  padding: 0;
}
```

`tests/fixtures/src/js/tracking.js`:
```javascript
// Google Analytics for __DOMAIN__
(function() {
  var script = document.createElement('script');
  script.src = 'https://www.googletagmanager.com/gtag/js?id=__GA4_ID__';
  script.async = true;
  document.head.appendChild(script);

  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  gtag('js', new Date());
  gtag('config', '__GA4_ID__');
})();
```

`tests/fixtures/src/emails/welcome-body.html`:
```html
<table width="100%" cellpadding="0" cellspacing="0">
  <tr>
    <td align="center">
      <h1>Welcome!</h1>
      <p>Thanks for signing up at __DOMAIN__.</p>
      <p>We'll keep you posted on what's next.</p>
    </td>
  </tr>
</table>
```

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/
git commit -m "feat: add test helper and fixture files for TDD"
```

---

### Task 2: test-build.sh (write failing test)

**Files:**
- Create: `tests/test-build.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# test-build.sh — Validates build.sh token substitution.
# Local only, no network required.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-build.sh`
Expected: FAIL — `scripts/build.sh: No such file or directory`

- [ ] **Step 3: Commit**

```bash
git add tests/test-build.sh
git commit -m "test: add test-build.sh (failing — build.sh not yet implemented)"
```

---

### Task 3: build.sh (make test pass)

**Files:**
- Create: `scripts/build.sh`

- [ ] **Step 1: Implement build.sh**

```bash
#!/usr/bin/env bash
# build.sh — Copy src/ to dist/ and substitute __PLACEHOLDER__ tokens.
# Reads values from project.config.sh in the project root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source config
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
```

- [ ] **Step 2: Make build.sh executable**

Run: `chmod +x scripts/build.sh`

- [ ] **Step 3: Run test to verify it passes**

Run: `bash tests/test-build.sh`
Expected: All assertions PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/build.sh
git commit -m "feat: implement build.sh with token substitution"
```

---

### Task 4: test-post-apply.sh (write failing test)

**Files:**
- Create: `tests/test-post-apply.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# test-post-apply.sh — Validates post-apply.sh writes terraform outputs to config.
# Local only, no network. Uses a mock terraform binary.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-post-apply.sh ==="

# --- Setup ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create fake project structure
mkdir -p "$TMPDIR/scripts" "$TMPDIR/terraform"

cp "$REPO_DIR/scripts/post-apply.sh" "$TMPDIR/scripts/post-apply.sh"

# Write a config file with empty IDs (pre-apply state)
cat > "$TMPDIR/project.config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="12345678"
HUBSPOT_REGION="eu1"
DOMAIN="test.example.com"
KEYCHAIN_PREFIX="test"
DM_UPLOAD_PATH="/test-project"
GA4_MEASUREMENT_ID="G-TEST12345"
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
EOF

# Create mock terraform that returns known outputs
mkdir -p "$TMPDIR/mock-bin"
cat > "$TMPDIR/mock-bin/terraform" <<'MOCK'
#!/usr/bin/env bash
output_name="${!#}"
case "$output_name" in
  capture_form_id) echo "mock-form-id-abc123" ;;
  survey_form_id) echo "" ;;
  list_id) echo "mock-list-id-789" ;;
  *) echo "unknown: $output_name" >&2; exit 1 ;;
esac
MOCK
chmod +x "$TMPDIR/mock-bin/terraform"

# --- Run post-apply with mock terraform ---
echo "Running post-apply.sh..."
PATH="$TMPDIR/mock-bin:$PATH" bash "$TMPDIR/scripts/post-apply.sh"

# --- Assertions ---

echo ""
echo "--- Config values updated ---"
assert_file_contains "$TMPDIR/project.config.sh" 'CAPTURE_FORM_ID="mock-form-id-abc123"' "CAPTURE_FORM_ID updated"
assert_file_contains "$TMPDIR/project.config.sh" 'SURVEY_FORM_ID=""' "SURVEY_FORM_ID stays empty"
assert_file_contains "$TMPDIR/project.config.sh" 'LIST_ID="mock-list-id-789"' "LIST_ID updated"

echo ""
echo "--- Other config values unchanged ---"
assert_file_contains "$TMPDIR/project.config.sh" 'HUBSPOT_PORTAL_ID="12345678"' "portal ID unchanged"
assert_file_contains "$TMPDIR/project.config.sh" 'HUBSPOT_REGION="eu1"' "region unchanged"
assert_file_contains "$TMPDIR/project.config.sh" 'DOMAIN="test.example.com"' "domain unchanged"
assert_file_contains "$TMPDIR/project.config.sh" 'GA4_MEASUREMENT_ID="G-TEST12345"' "GA4 ID unchanged"

echo ""
echo "--- Idempotent (running twice gives same result) ---"
PATH="$TMPDIR/mock-bin:$PATH" bash "$TMPDIR/scripts/post-apply.sh"
assert_file_contains "$TMPDIR/project.config.sh" 'CAPTURE_FORM_ID="mock-form-id-abc123"' "CAPTURE_FORM_ID same after re-run"
assert_file_contains "$TMPDIR/project.config.sh" 'LIST_ID="mock-list-id-789"' "LIST_ID same after re-run"

# Count lines to ensure no duplication
line_count=$(wc -l < "$TMPDIR/project.config.sh")
assert_equal "$line_count" "9" "config file still has 9 lines (no duplication)"

test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-post-apply.sh`
Expected: FAIL — `scripts/post-apply.sh: No such file or directory`

- [ ] **Step 3: Commit**

```bash
git add tests/test-post-apply.sh
git commit -m "test: add test-post-apply.sh (failing — post-apply.sh not yet implemented)"
```

---

### Task 5: post-apply.sh (make test pass)

**Files:**
- Create: `scripts/post-apply.sh`

- [ ] **Step 1: Implement post-apply.sh**

```bash
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
```

- [ ] **Step 2: Make post-apply.sh executable**

Run: `chmod +x scripts/post-apply.sh`

- [ ] **Step 3: Run test to verify it passes**

Run: `bash tests/test-post-apply.sh`
Expected: All assertions PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/post-apply.sh
git commit -m "feat: implement post-apply.sh — terraform outputs to config"
```

---

### Task 6: tf.sh and hs-curl.sh

**Files:**
- Create: `scripts/tf.sh`
- Create: `scripts/hs-curl.sh`

These scripts depend on macOS Keychain and cannot be unit-tested locally. They are tested indirectly by `test-deployment.sh` (Task 14).

- [ ] **Step 1: Implement tf.sh**

```bash
#!/usr/bin/env bash
# tf.sh — Read HubSpot token from Keychain, export TF_VAR_*, run terraform.
# Usage: scripts/tf.sh init|plan|apply|destroy [extra-args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/project.config.sh"

# Read token from Keychain
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-access-token" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-access-token from Keychain." >&2
  echo "Add it with: security add-generic-password -s '${KEYCHAIN_PREFIX}-hubspot-access-token' -a \"\$USER\" -w 'TOKEN'" >&2
  exit 1
}

# Export Terraform variables
export TF_VAR_hubspot_token="$HUBSPOT_TOKEN"
export TF_VAR_hubspot_portal_id="$HUBSPOT_PORTAL_ID"
export TF_VAR_domain="$DOMAIN"
export TF_VAR_hubspot_region="$HUBSPOT_REGION"

# Run terraform
exec terraform -chdir="$PROJECT_DIR/terraform" "$@"
```

- [ ] **Step 2: Implement hs-curl.sh**

```bash
#!/usr/bin/env bash
# hs-curl.sh — Read HubSpot token from Keychain, run curl against HubSpot API.
# Usage: scripts/hs-curl.sh GET /crm/v3/properties/contacts
#        scripts/hs-curl.sh POST /marketing/v3/forms -d '{"name":"test"}'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/project.config.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: hs-curl.sh METHOD /api/path [curl-args...]" >&2
  exit 1
fi

METHOD="$1"
API_PATH="$2"
shift 2

# Read token from Keychain
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-access-token" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-access-token from Keychain." >&2
  exit 1
}

exec curl -s -X "$METHOD" \
  "https://api.hubapi.com${API_PATH}" \
  -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "$@"
```

- [ ] **Step 3: Make scripts executable**

Run: `chmod +x scripts/tf.sh scripts/hs-curl.sh`

- [ ] **Step 4: Commit**

```bash
git add scripts/tf.sh scripts/hs-curl.sh
git commit -m "feat: add tf.sh and hs-curl.sh (Keychain-backed wrappers)"
```

---

### Task 7: upload.sh

**Files:**
- Create: `scripts/upload.sh`

- [ ] **Step 1: Implement upload.sh**

```bash
#!/usr/bin/env bash
# upload.sh — Upload dist/ files to HubSpot Design Manager via CMS Source Code API.
# No HubSpot CLI or PAK needed — uses Service Key from Keychain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/project.config.sh"

DIST_DIR="$PROJECT_DIR/dist"

if [[ ! -d "$DIST_DIR" ]]; then
  echo "ERROR: dist/ not found. Run build.sh first." >&2
  exit 1
fi

# Read token from Keychain
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-access-token" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-access-token from Keychain." >&2
  exit 1
}

API_BASE="https://api.hubapi.com/cms/v3/source-code/developer/content"

# Upload each file in dist/
uploaded=0
failed=0

find "$DIST_DIR" -type f | while read -r file; do
  relative_path="${file#$DIST_DIR/}"
  dm_path="${DM_UPLOAD_PATH}/${relative_path}"

  echo -n "  Uploading ${dm_path}... "

  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "${API_BASE}${dm_path}" \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${file}")

  if [[ "$http_code" =~ ^2 ]]; then
    echo "OK ($http_code)"
    uploaded=$((uploaded + 1))
  else
    echo "FAILED ($http_code)"
    failed=$((failed + 1))
  fi
done

echo ""
echo "Upload complete: $uploaded succeeded, $failed failed"
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
```

- [ ] **Step 2: Make upload.sh executable**

Run: `chmod +x scripts/upload.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/upload.sh
git commit -m "feat: add upload.sh — CMS Source Code API uploader"
```

---

### Task 8: deploy.sh, watch.sh, hs.sh

**Files:**
- Create: `scripts/deploy.sh`
- Create: `scripts/watch.sh`
- Create: `scripts/hs.sh`

- [ ] **Step 1: Implement deploy.sh**

```bash
#!/usr/bin/env bash
# deploy.sh — Build then upload to HubSpot Design Manager.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Build ==="
bash "$SCRIPT_DIR/build.sh"

echo ""
echo "=== Upload ==="
bash "$SCRIPT_DIR/upload.sh"

echo ""
echo "Deploy complete."
```

- [ ] **Step 2: Implement watch.sh**

```bash
#!/usr/bin/env bash
# watch.sh — Build once, then poll for src/ changes and re-deploy.
# Uses stat-based polling (no fswatch/inotify dependency).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_DIR/src"
POLL_INTERVAL="${POLL_INTERVAL:-3}"

# Initial deploy
echo "=== Initial deploy ==="
bash "$SCRIPT_DIR/deploy.sh"

echo ""
echo "Watching $SRC_DIR for changes (every ${POLL_INTERVAL}s)..."
echo "Press Ctrl+C to stop."

# Get initial checksum of src/
_src_checksum() {
  find "$SRC_DIR" -type f -exec stat -f "%m %N" {} \; 2>/dev/null \
    || find "$SRC_DIR" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null \
    | sort | md5sum 2>/dev/null || md5
}

last_checksum=$(_src_checksum)

while true; do
  sleep "$POLL_INTERVAL"
  current_checksum=$(_src_checksum)
  if [[ "$current_checksum" != "$last_checksum" ]]; then
    echo ""
    echo "=== Change detected — re-deploying ==="
    bash "$SCRIPT_DIR/deploy.sh"
    last_checksum=$(_src_checksum)
    echo ""
    echo "Watching for changes..."
  fi
done
```

- [ ] **Step 3: Implement hs.sh**

```bash
#!/usr/bin/env bash
# hs.sh — Optional HubSpot CLI wrapper for local debugging.
# Reads PAK from Keychain. Not part of the core workflow.
# Requires: npm install -g @hubspot/cli
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_DIR/project.config.sh"

# Read PAK from Keychain (separate from Service Key)
HUBSPOT_PAK=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-pak" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read ${KEYCHAIN_PREFIX}-hubspot-pak from Keychain." >&2
  echo "The HubSpot CLI requires a Personal Access Key (PAK), not a Service Key." >&2
  echo "This script is optional — use deploy.sh for the core workflow." >&2
  exit 1
}

export HUBSPOT_PERSONAL_ACCESS_KEY="$HUBSPOT_PAK"
exec hs "$@"
```

- [ ] **Step 4: Make scripts executable**

Run: `chmod +x scripts/deploy.sh scripts/watch.sh scripts/hs.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/deploy.sh scripts/watch.sh scripts/hs.sh
git commit -m "feat: add deploy.sh, watch.sh, hs.sh"
```

---

### Task 9: Terraform account-setup module

**Files:**
- Create: `terraform/modules/account-setup/main.tf`
- Create: `terraform/modules/account-setup/variables.tf`
- Create: `terraform/modules/account-setup/outputs.tf`

- [ ] **Step 1: Create main.tf**

```hcl
# terraform/modules/account-setup/main.tf
#
# Run once per HubSpot account. Creates shared resources
# that all projects on the account depend on.
#
# The restapi provider is inherited from the root module.

resource "restapi_object" "project_source_property" {
  path          = "/crm/v3/properties/contacts"
  id_attribute  = "name"
  update_method = "PATCH"
  update_path   = "/crm/v3/properties/contacts/{id}"

  data = jsonencode({
    name        = "project_source"
    label       = "Project Source"
    type        = "string"
    fieldType   = "text"
    groupName   = "contactinformation"
    description = "Identifies which project/landing page captured this contact"
  })
}
```

- [ ] **Step 2: Create variables.tf**

```hcl
# terraform/modules/account-setup/variables.tf
#
# No variables — this module inherits the restapi provider
# from the root module. Auth is at the provider level.
```

- [ ] **Step 3: Create outputs.tf**

```hcl
# terraform/modules/account-setup/outputs.tf

output "project_source_property_name" {
  description = "Name of the project_source CRM property"
  value       = "project_source"
}
```

- [ ] **Step 4: Commit**

```bash
git add terraform/modules/account-setup/
git commit -m "feat: add account-setup Terraform module"
```

---

### Task 10: Terraform landing-page module — variables and forms

**Files:**
- Create: `terraform/modules/landing-page/variables.tf`
- Create: `terraform/modules/landing-page/forms.tf`
- Create: `terraform/modules/landing-page/main.tf`

- [ ] **Step 1: Create variables.tf**

```hcl
# terraform/modules/landing-page/variables.tf

variable "hubspot_portal_id" {
  type        = string
  description = "HubSpot portal ID"
}

variable "project_slug" {
  type        = string
  description = "Short project identifier (e.g. heard). Used for resource naming and contact segmentation."
}

variable "domain" {
  type        = string
  description = "Page domain (e.g. heard.digitalmercenaries.ai)"
}

variable "landing_slug" {
  type        = string
  default     = ""
  description = "Landing page URL slug (empty = root of subdomain)"
}

variable "thankyou_slug" {
  type        = string
  default     = "thank-you"
  description = "Thank-you page URL slug"
}

variable "capture_form_name" {
  type        = string
  description = "Capture form display name in HubSpot"
}

variable "capture_form_fields" {
  type = list(object({
    name     = string
    label    = string
    type     = string
    required = optional(bool, false)
  }))
  default     = []
  description = "Additional capture form fields beyond email"
}

variable "include_survey" {
  type        = bool
  default     = false
  description = "Whether to create a survey form"
}

variable "survey_form_name" {
  type        = string
  default     = ""
  description = "Survey form display name"
}

variable "survey_fields" {
  type = list(object({
    name     = string
    label    = string
    type     = string
    required = optional(bool, false)
  }))
  default     = []
  description = "Survey form field definitions"
}

variable "email_name" {
  type        = string
  description = "Welcome email name in HubSpot"
}

variable "email_subject" {
  type        = string
  description = "Welcome email subject line"
}

variable "email_from_name" {
  type        = string
  description = "Welcome email sender display name"
}

variable "email_reply_to" {
  type        = string
  description = "Welcome email reply-to address"
}

variable "email_body_path" {
  type        = string
  description = "Path to dist/ welcome email HTML body file"
}

variable "page_landing_name" {
  type        = string
  description = "Landing page display name in HubSpot"
}

variable "page_landing_title" {
  type        = string
  description = "Landing page HTML title"
}

variable "page_thankyou_name" {
  type        = string
  description = "Thank-you page display name in HubSpot"
}

variable "page_thankyou_title" {
  type        = string
  description = "Thank-you page HTML title"
}

variable "template_path_landing" {
  type        = string
  description = "Design Manager template path for landing page"
}

variable "template_path_thankyou" {
  type        = string
  description = "Design Manager template path for thank-you page"
}

variable "custom_properties" {
  type = list(object({
    name      = string
    label     = string
    type      = string
    fieldType = string
    groupName = optional(string, "contactinformation")
  }))
  default     = []
  description = "Additional CRM contact properties for this project"
}
```

- [ ] **Step 2: Create main.tf (module metadata only)**

```hcl
# terraform/modules/landing-page/main.tf
#
# Creates everything for one landing page funnel:
# capture form, optional survey form, landing page, thank-you page,
# welcome email, contact list, and optional CRM properties.
#
# The restapi provider is inherited from the root module.

terraform {
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 1.19"
    }
  }
}
```

- [ ] **Step 3: Create forms.tf**

```hcl
# terraform/modules/landing-page/forms.tf
#
# HubSpot Forms API v3 quirks:
# - Root requires createdAt (any ISO-8601, server overwrites)
# - Email fields require validation.createdAt + validation.configuration.createdAt
# - Non-email fields must NOT have a validation key
# - legalConsentOptions.type = "implicit_consent_to_process" (lowercase)
# - Every field needs objectTypeId = "0-1"

resource "restapi_object" "capture_form" {
  path          = "/marketing/v3/forms"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name      = var.capture_form_name
    createdAt = "2024-01-01T00:00:00Z"
    fieldGroups = [
      {
        groupType    = "default_group"
        richTextType = "NONE"
        fields = concat(
          # Email field (always present, with required validation block)
          [
            {
              name         = "email"
              label        = "Email"
              fieldType    = "email"
              objectTypeId = "0-1"
              required     = true
              validation = {
                createdAt = "2024-01-01T00:00:00Z"
                configuration = {
                  createdAt = "2024-01-01T00:00:00Z"
                }
              }
            }
          ],
          # Additional fields (no validation block for non-email)
          [for field in var.capture_form_fields : {
            name         = field.name
            label        = field.label
            fieldType    = field.type
            objectTypeId = "0-1"
            required     = field.required
          }],
          # Hidden project_source field
          [
            {
              name         = "project_source"
              label        = "Project Source"
              fieldType    = "hidden"
              objectTypeId = "0-1"
              defaultValue = var.project_slug
            }
          ]
        )
      }
    ]
    legalConsentOptions = {
      type = "implicit_consent_to_process"
    }
    configuration = {
      language = "en"
    }
  })
}

resource "restapi_object" "survey_form" {
  count         = var.include_survey ? 1 : 0
  path          = "/marketing/v3/forms"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name      = var.survey_form_name
    createdAt = "2024-01-01T00:00:00Z"
    fieldGroups = [
      {
        groupType    = "default_group"
        richTextType = "NONE"
        fields = concat(
          # Email field
          [
            {
              name         = "email"
              label        = "Email"
              fieldType    = "email"
              objectTypeId = "0-1"
              required     = true
              validation = {
                createdAt = "2024-01-01T00:00:00Z"
                configuration = {
                  createdAt = "2024-01-01T00:00:00Z"
                }
              }
            }
          ],
          # Survey fields (no validation block)
          [for field in var.survey_fields : {
            name         = field.name
            label        = field.label
            fieldType    = field.type
            objectTypeId = "0-1"
            required     = field.required
          }],
          # Hidden project_source field
          [
            {
              name         = "project_source"
              label        = "Project Source"
              fieldType    = "hidden"
              objectTypeId = "0-1"
              defaultValue = var.project_slug
            }
          ]
        )
      }
    ]
    legalConsentOptions = {
      type = "implicit_consent_to_process"
    }
    configuration = {
      language = "en"
    }
  })
}
```

- [ ] **Step 4: Commit**

```bash
git add terraform/modules/landing-page/variables.tf terraform/modules/landing-page/main.tf terraform/modules/landing-page/forms.tf
git commit -m "feat: add landing-page module — variables, main, forms"
```

---

### Task 11: Terraform landing-page module — pages, emails, properties, lists, outputs

**Files:**
- Create: `terraform/modules/landing-page/pages.tf`
- Create: `terraform/modules/landing-page/emails.tf`
- Create: `terraform/modules/landing-page/properties.tf`
- Create: `terraform/modules/landing-page/lists.tf`
- Create: `terraform/modules/landing-page/outputs.tf`

- [ ] **Step 1: Create pages.tf**

```hcl
# terraform/modules/landing-page/pages.tf
#
# Landing page type is set by the API endpoint, not the template.
# Landing pages: /cms/v3/pages/landing-pages (supports A/B testing)
# Thank-you page: /cms/v3/pages/site-pages (standard site page)

resource "restapi_object" "landing_page" {
  path          = "/cms/v3/pages/landing-pages"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name         = var.page_landing_name
    slug         = var.landing_slug
    domain       = var.domain
    htmlTitle    = var.page_landing_title
    templatePath = var.template_path_landing
    state        = "PUBLISHED"
  })
}

resource "restapi_object" "thankyou_page" {
  path          = "/cms/v3/pages/site-pages"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name         = var.page_thankyou_name
    slug         = var.thankyou_slug
    domain       = var.domain
    htmlTitle    = var.page_thankyou_title
    templatePath = var.template_path_thankyou
    state        = "PUBLISHED"
  })
}
```

- [ ] **Step 2: Create emails.tf**

```hcl
# terraform/modules/landing-page/emails.tf

resource "restapi_object" "welcome_email" {
  path          = "/marketing/v3/emails"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name      = var.email_name
    subject   = var.email_subject
    fromName  = var.email_from_name
    replyTo   = var.email_reply_to
    type      = "REGULAR"
    content = {
      html = file(var.email_body_path)
    }
  })
}
```

- [ ] **Step 3: Create properties.tf**

```hcl
# terraform/modules/landing-page/properties.tf

resource "restapi_object" "custom_property" {
  for_each      = { for p in var.custom_properties : p.name => p }
  path          = "/crm/v3/properties/contacts"
  id_attribute  = "name"
  update_method = "PATCH"
  update_path   = "/crm/v3/properties/contacts/{id}"

  data = jsonencode({
    name      = each.value.name
    label     = each.value.label
    type      = each.value.type
    fieldType = each.value.fieldType
    groupName = each.value.groupName
  })
}
```

- [ ] **Step 4: Create lists.tf**

```hcl
# terraform/modules/landing-page/lists.tf
#
# NOTE: The Lists API v3 response wraps in {"list":{...}} which may
# cause issues with the restapi provider's response parsing.
# If this resource fails on apply, lists may need to be created
# via hs-curl.sh or the skill instead.

resource "restapi_object" "contact_list" {
  path          = "/crm/v3/lists"
  id_attribute  = "listId"
  update_method = "PATCH"

  data = jsonencode({
    name             = "${var.project_slug} Contacts"
    objectTypeId     = "0-1"
    processingType   = "DYNAMIC"
    filterBranch = {
      filterBranchType = "OR"
      filterBranches = [
        {
          filterBranchType = "AND"
          filters = [
            {
              filterType = "PROPERTY"
              property   = "project_source"
              operation = {
                operationType = "STRING"
                operator      = "IS_EQUAL_TO"
                value         = var.project_slug
              }
            }
          ]
        }
      ]
    }
  })
}
```

- [ ] **Step 5: Create outputs.tf**

```hcl
# terraform/modules/landing-page/outputs.tf

output "capture_form_id" {
  description = "UUID of the capture form"
  value       = restapi_object.capture_form.id
}

output "survey_form_id" {
  description = "UUID of the survey form (empty string if not created)"
  value       = var.include_survey ? restapi_object.survey_form[0].id : ""
}

output "list_id" {
  description = "Contact list ID"
  value       = restapi_object.contact_list.id
}

output "landing_page_id" {
  description = "CMS landing page ID"
  value       = restapi_object.landing_page.id
}

output "thankyou_page_id" {
  description = "CMS thank-you page ID"
  value       = restapi_object.thankyou_page.id
}

output "welcome_email_id" {
  description = "Marketing email ID (for workflow setup)"
  value       = restapi_object.welcome_email.id
}
```

- [ ] **Step 6: Commit**

```bash
git add terraform/modules/landing-page/
git commit -m "feat: add landing-page module — pages, emails, properties, lists, outputs"
```

---

### Task 12: Terraform plan test harness + test-terraform-plan.sh

**Files:**
- Create: `tests/fixtures/terraform/main.tf`
- Create: `tests/fixtures/terraform/terraform.tfvars`
- Create: `tests/fixtures/emails/welcome-body.html`
- Create: `tests/test-terraform-plan.sh`

- [ ] **Step 1: Create test harness main.tf**

```hcl
# tests/fixtures/terraform/main.tf
# Test harness that calls both modules with fixture values.
# Used by test-terraform-plan.sh to validate plan output.

terraform {
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 1.19"
    }
  }
}

provider "restapi" {
  uri                  = "https://api.hubapi.com"
  write_returns_object = true
  headers = {
    "Authorization" = "Bearer test-token-not-used-for-plan"
    "Content-Type"  = "application/json"
  }
}

module "account_setup" {
  source = "../../../terraform/modules/account-setup"
}

module "landing_page" {
  source = "../../../terraform/modules/landing-page"

  hubspot_portal_id      = "12345678"
  project_slug           = "test-project"
  domain                 = "test.example.com"
  landing_slug           = ""
  thankyou_slug          = "thank-you"
  capture_form_name      = "Test — Signup"
  email_name             = "Test — Welcome"
  email_subject          = "Welcome to Test"
  email_from_name        = "Test Project"
  email_reply_to         = "test@example.com"
  email_body_path        = "${path.module}/../emails/welcome-body.html"
  page_landing_name      = "Test — Landing Page"
  page_landing_title     = "Test Project"
  page_thankyou_name     = "Test — Thank You"
  page_thankyou_title    = "Thank You | Test"
  template_path_landing  = "test-project/templates/landing-page.html"
  template_path_thankyou = "test-project/templates/thank-you.html"
}
```

- [ ] **Step 2: Create fixture email body for terraform file() function**

`tests/fixtures/emails/welcome-body.html`:
```html
<p>Welcome to the test project.</p>
```

- [ ] **Step 3: Write test-terraform-plan.sh**

```bash
#!/usr/bin/env bash
# test-terraform-plan.sh — Validates terraform plan produces expected resources.
# Requires: terraform CLI installed. Downloads restapi provider on first run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-terraform-plan.sh ==="

HARNESS_DIR="$REPO_DIR/tests/fixtures/terraform"

# --- Init ---
echo "Running terraform init..."
terraform -chdir="$HARNESS_DIR" init -backend=false -input=false >/dev/null 2>&1 || {
  echo "terraform init failed"
  terraform -chdir="$HARNESS_DIR" init -backend=false -input=false
  exit 1
}

# --- Plan ---
echo "Running terraform plan..."
PLAN_FILE="$HARNESS_DIR/test.tfplan"
trap 'rm -f "$PLAN_FILE" "$HARNESS_DIR/plan.json"' EXIT

terraform -chdir="$HARNESS_DIR" plan \
  -out="$PLAN_FILE" \
  -input=false \
  -no-color 2>&1 | tee "$HARNESS_DIR/plan.txt"

# --- Parse plan output ---
PLAN_TEXT=$(cat "$HARNESS_DIR/plan.txt")
rm -f "$HARNESS_DIR/plan.txt"

echo ""
echo "--- Expected resources in plan ---"

# Count resources to add
add_count=$(echo "$PLAN_TEXT" | grep -c "will be created" || true)

# Minimum expected: project_source_property + capture_form + landing_page +
# thankyou_page + welcome_email + contact_list = 6
assert_equal "$([ "$add_count" -ge 6 ] && echo "true" || echo "false")" "true" \
  "at least 6 resources to create (got $add_count)"

# Check specific resources by name
assert_file_contains <(echo "$PLAN_TEXT") "project_source_property" \
  "account-setup: project_source CRM property"

assert_file_contains <(echo "$PLAN_TEXT") "capture_form" \
  "landing-page: capture form"

assert_file_contains <(echo "$PLAN_TEXT") "landing_page" \
  "landing-page: landing page"

assert_file_contains <(echo "$PLAN_TEXT") "thankyou_page" \
  "landing-page: thank-you page"

assert_file_contains <(echo "$PLAN_TEXT") "welcome_email" \
  "landing-page: welcome email"

assert_file_contains <(echo "$PLAN_TEXT") "contact_list" \
  "landing-page: contact list"

echo ""
echo "--- No unexpected destroy actions ---"
destroy_count=$(echo "$PLAN_TEXT" | grep -c "will be destroyed" || true)
assert_equal "$destroy_count" "0" "no resources to destroy"

echo ""
echo "--- Resource naming includes project_slug ---"
assert_file_contains <(echo "$PLAN_TEXT") "test-project" \
  "project slug appears in plan"

echo ""
echo "--- Domain matches config ---"
assert_file_contains <(echo "$PLAN_TEXT") "test.example.com" \
  "domain appears in plan"

test_summary
```

- [ ] **Step 4: Run the test**

Run: `bash tests/test-terraform-plan.sh`
Expected: All assertions PASS (modules are already implemented from Tasks 9-11)

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/terraform/ tests/fixtures/emails/ tests/test-terraform-plan.sh
git commit -m "test: add test-terraform-plan.sh with test harness"
```

---

### Task 13: Scaffold templates

**Files:**
- Create: `scaffold/project.config.example.sh`
- Create: `scaffold/brief-template.md`
- Create: `scaffold/package.json`
- Create: `scaffold/.gitignore`
- Create: `scaffold/terraform/main.tf`

- [ ] **Step 1: Create project.config.example.sh**

```bash
# scaffold/project.config.example.sh
#
# Project configuration. Copy to project.config.sh and fill in values.
# project.config.sh is gitignored — never commit real values.

# HubSpot account
HUBSPOT_PORTAL_ID=""           # Portal ID (e.g. 147959629)
HUBSPOT_REGION=""              # eu1 or na1
KEYCHAIN_PREFIX=""             # Keychain service prefix (e.g. dml)

# Project
DOMAIN=""                      # Page domain (e.g. heard.digitalmercenaries.ai)
DM_UPLOAD_PATH=""              # Design Manager path (e.g. /heard)
GA4_MEASUREMENT_ID=""          # Google Analytics 4 ID (e.g. G-XXXXXXXXXX)

# Populated by post-apply.sh after terraform apply
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
```

- [ ] **Step 2: Create brief-template.md**

```markdown
# Landing Page Brief

## Profile
<!-- idea-validation | demo | launch -->
stage: idea-validation

## Source
<!-- How to populate the brief. One of:
     trello:<card-url>     - fetch ICB from Trello card
     file:<path>           - read a markdown file
     directory:<path>      - analyse all materials in directory
     interactive           - skill asks questions
     (or just paste content below under Idea) -->
source:

## Idea
<!-- Describe the product/idea -->

## Target Audience
<!-- Who is this for? -->

## Problem
<!-- What pain does this solve? -->

## Value Proposition
<!-- What does the user get? Why is this different? -->

## Social Proof / Credibility
<!-- Who's behind this? Why should anyone trust it? -->

## Call to Action
action:
urgency:

## Brand Direction
name:
tagline:
tone:
palette:
font:
logo:

## Form Fields
fields: email

## Thank-You Page
next_steps:
include_survey: false
survey_questions:

## Welcome Email
from_name:
reply_to:
subject:
tone:

## Share / Referral
include_share: true
channels: whatsapp, linkedin
share_text:

## HubSpot Config
portal_id:
region:
domain:
keychain_prefix:
dm_upload_path:
ga4_id:
```

- [ ] **Step 3: Create package.json**

```json
{
  "name": "hs-lander-project",
  "version": "1.0.0",
  "private": true,
  "description": "HubSpot landing page project (scaffolded by hs-lander)",
  "scripts": {
    "build": "bash scripts/build.sh",
    "setup": "bash scripts/build.sh && bash scripts/tf.sh apply -auto-approve",
    "post-apply": "bash scripts/post-apply.sh",
    "deploy": "bash scripts/deploy.sh",
    "watch": "bash scripts/watch.sh",
    "tf:init": "bash scripts/tf.sh init",
    "tf:plan": "bash scripts/tf.sh plan",
    "destroy": "bash scripts/tf.sh destroy -auto-approve"
  }
}
```

- [ ] **Step 4: Create .gitignore**

```
# Secrets — never commit
project.config.sh

# Build output
dist/

# Node
node_modules/

# Terraform
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
*.tfplan

# HubSpot CLI (not used in core workflow)
hubspot.config.yml

# IDE / OS
.claude/
.DS_Store
```

- [ ] **Step 5: Create scaffold terraform/main.tf**

```hcl
# scaffold/terraform/main.tf
#
# Calls hs-lander modules by git URL with pinned version.
# Copy this to your project's terraform/ directory.

terraform {
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 1.19"
    }
  }
}

provider "restapi" {
  uri                  = "https://api.hubapi.com"
  write_returns_object = true
  headers = {
    "Authorization" = "Bearer ${var.hubspot_token}"
    "Content-Type"  = "application/json"
  }
}

variable "hubspot_token" {
  type      = string
  sensitive = true
}

variable "hubspot_portal_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "hubspot_region" {
  type = string
}

module "account_setup" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v1.0.0"
}

module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.0.0"

  hubspot_portal_id = var.hubspot_portal_id
  project_slug      = "PROJECT_SLUG"
  domain            = var.domain

  # Page config
  landing_slug           = ""
  thankyou_slug          = "thank-you"
  capture_form_name      = "PROJECT — Signup"
  email_name             = "PROJECT — Welcome"
  email_subject          = "Welcome"
  email_from_name        = "PROJECT"
  email_reply_to         = "PROJECT@digitalmercenaries.ai"
  email_body_path        = "${path.module}/../dist/emails/welcome-body.html"
  page_landing_name      = "PROJECT — Landing Page"
  page_landing_title     = "PROJECT"
  page_thankyou_name     = "PROJECT — Thank You"
  page_thankyou_title    = "Thank You | PROJECT"
  template_path_landing  = "PROJECT_SLUG/templates/landing-page.html"
  template_path_thankyou = "PROJECT_SLUG/templates/thank-you.html"
}

output "capture_form_id" {
  value = module.landing_page.capture_form_id
}

output "survey_form_id" {
  value = module.landing_page.survey_form_id
}

output "list_id" {
  value = module.landing_page.list_id
}
```

- [ ] **Step 6: Commit**

```bash
git add scaffold/
git commit -m "feat: add scaffold templates for new projects"
```

---

### Task 14: test-deployment.sh

**Files:**
- Create: `tests/test-deployment.sh`

This test runs against a live HubSpot instance. It will only pass after a real deployment. It is NOT run in CI's `ci.yml` — only in `smoke.yml`.

- [ ] **Step 1: Write test-deployment.sh**

```bash
#!/usr/bin/env bash
# test-deployment.sh — Validates a live HubSpot deployment.
# Requires: network access, deployed landing page, project.config.sh with real values.
# Usage: bash tests/test-deployment.sh /path/to/project
set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-deployment.sh ==="
echo "Project: $PROJECT_DIR"

source "$PROJECT_DIR/project.config.sh"

# Read token from Keychain
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "${KEYCHAIN_PREFIX}-hubspot-access-token" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read Keychain token. Is this running on macOS with credentials?" >&2
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

landing_html=$(curl -s "$LANDING_URL")
assert_file_contains <(echo "$landing_html") "hbspt.forms.create" \
  "landing page contains HubSpot form embed"
assert_file_contains <(echo "$landing_html") "$HUBSPOT_PORTAL_ID" \
  "landing page contains correct portal ID"
assert_no_tokens <(echo "$landing_html") \
  "no __TOKENS__ in landing page HTML"

echo ""
echo "--- Thank-you page content ---"
thankyou_html=$(curl -s "$THANKYOU_URL")
assert_no_tokens <(echo "$thankyou_html") \
  "no __TOKENS__ in thank-you page HTML"

# --- API checks ---
echo ""
echo "--- HubSpot API verification ---"

if [[ -n "${CAPTURE_FORM_ID:-}" ]]; then
  form_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/forms/${CAPTURE_FORM_ID}")
  assert_equal "$form_status" "200" "capture form exists in HubSpot API"
else
  echo "  SKIP: CAPTURE_FORM_ID not set — run post-apply first"
fi

# Check landing page state via API
if [[ -n "${LANDING_PAGE_ID:-}" ]]; then
  page_json=$(curl -s \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/cms/v3/pages/landing-pages/${LANDING_PAGE_ID}")
  page_state=$(echo "$page_json" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
  assert_equal "$page_state" "PUBLISHED" "landing page is PUBLISHED"
fi

# Check welcome email exists
if [[ -n "${WELCOME_EMAIL_ID:-}" ]]; then
  email_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    "https://api.hubapi.com/marketing/v3/emails/${WELCOME_EMAIL_ID}")
  assert_equal "$email_status" "200" "welcome email exists in HubSpot API"
fi

test_summary
```

- [ ] **Step 2: Commit**

```bash
git add tests/test-deployment.sh
git commit -m "test: add test-deployment.sh (live HubSpot verification)"
```

---

### Task 15: CI workflows

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/smoke.yml`

- [ ] **Step 1: Create ci.yml**

```yaml
# .github/workflows/ci.yml
# Runs on every push and PR: lint, build test, terraform plan test.
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: ShellCheck
        run: shellcheck scripts/*.sh tests/*.sh

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7"

      - name: Terraform fmt
        run: |
          terraform -chdir=terraform/modules/account-setup fmt -check
          terraform -chdir=terraform/modules/landing-page fmt -check

      - name: Terraform validate (account-setup)
        run: |
          terraform -chdir=terraform/modules/account-setup init -backend=false
          terraform -chdir=terraform/modules/account-setup validate

  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run test-build.sh
        run: bash tests/test-build.sh

  plan-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7"

      - name: Run test-terraform-plan.sh
        run: bash tests/test-terraform-plan.sh

  post-apply-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run test-post-apply.sh
        run: bash tests/test-post-apply.sh
```

- [ ] **Step 2: Create smoke.yml**

```yaml
# .github/workflows/smoke.yml
# Manual trigger or release tags. Deploys to real HubSpot and verifies.
name: Smoke Test

on:
  workflow_dispatch:
  push:
    tags: ["v*"]

jobs:
  deploy-and-verify:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.7"

      - name: Store token in Keychain
        env:
          HUBSPOT_TOKEN: ${{ secrets.HUBSPOT_TOKEN }}
        run: |
          security add-generic-password \
            -s "smoke-hubspot-access-token" \
            -a "$USER" -w "$HUBSPOT_TOKEN"

      - name: Scaffold test project
        run: |
          mkdir -p /tmp/smoke-test
          cp -r scaffold/* /tmp/smoke-test/
          cp -r scripts/ /tmp/smoke-test/scripts/
          mkdir -p /tmp/smoke-test/src/templates /tmp/smoke-test/src/css \
                   /tmp/smoke-test/src/js /tmp/smoke-test/src/emails
          cp tests/fixtures/src/templates/* /tmp/smoke-test/src/templates/
          cp tests/fixtures/src/css/* /tmp/smoke-test/src/css/
          cp tests/fixtures/src/js/* /tmp/smoke-test/src/js/
          cp tests/fixtures/src/emails/* /tmp/smoke-test/src/emails/

      - name: Write smoke test config
        env:
          HUBSPOT_PORTAL_ID: ${{ secrets.HUBSPOT_PORTAL_ID }}
          HUBSPOT_REGION: ${{ secrets.HUBSPOT_REGION }}
          SMOKE_DOMAIN: ${{ secrets.SMOKE_DOMAIN }}
        run: |
          cat > /tmp/smoke-test/project.config.sh <<EOF
          HUBSPOT_PORTAL_ID="$HUBSPOT_PORTAL_ID"
          HUBSPOT_REGION="$HUBSPOT_REGION"
          DOMAIN="$SMOKE_DOMAIN"
          KEYCHAIN_PREFIX="smoke"
          DM_UPLOAD_PATH="/smoke-test"
          GA4_MEASUREMENT_ID="G-SMOKETEST"
          CAPTURE_FORM_ID=""
          SURVEY_FORM_ID=""
          LIST_ID=""
          EOF

      - name: Build
        run: cd /tmp/smoke-test && bash scripts/build.sh

      - name: Terraform init + apply
        run: cd /tmp/smoke-test && bash scripts/tf.sh init && bash scripts/tf.sh apply -auto-approve

      - name: Post-apply
        run: cd /tmp/smoke-test && bash scripts/post-apply.sh

      - name: Deploy to Design Manager
        run: cd /tmp/smoke-test && bash scripts/deploy.sh

      - name: Run deployment tests
        run: bash tests/test-deployment.sh /tmp/smoke-test

      - name: Terraform destroy (cleanup)
        if: always()
        run: cd /tmp/smoke-test && bash scripts/tf.sh destroy -auto-approve || true
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/
git commit -m "ci: add CI and smoke test workflows"
```

---

### Task 16: Documentation and v1.0.0 tag

**Files:**
- Create: `docs/framework.md`
- Modify: `README.md`

- [ ] **Step 1: Create docs/framework.md**

```markdown
# hs-lander Framework

## Overview

hs-lander is a reusable framework for deploying HubSpot landing page funnels. It provides:

- **Terraform modules** for creating HubSpot resources (forms, pages, emails, lists)
- **Shell scripts** for building, deploying, and managing projects
- **Scaffold templates** for creating new projects

## Quick Start

### 1. Create a new project

```bash
mkdir my-project && cd my-project
cp -r /path/to/hs-lander/scaffold/* .
cp -r /path/to/hs-lander/scripts/ scripts/
cp project.config.example.sh project.config.sh
# Edit project.config.sh with your values
```

### 2. Add your content

Create your landing page content in `src/`:

```
src/
├── templates/
│   ├── landing-page.html     # Use __PLACEHOLDER__ tokens
│   └── thank-you.html
├── css/main.css
├── js/tracking.js
├── emails/
│   └── welcome-body.html
└── images/
```

### 3. Build and deploy

```bash
npm run build        # src/ → dist/ with token substitution
npm run tf:init      # Initialise Terraform
npm run setup        # Build + terraform apply
npm run post-apply   # Write form IDs to config
npm run build        # Rebuild with form IDs
npm run deploy       # Upload to HubSpot Design Manager
```

## Token Substitution

`build.sh` replaces `__PLACEHOLDER__` tokens in `src/` files with values from `project.config.sh`:

| Token | Source |
|---|---|
| `__PORTAL_ID__` | `HUBSPOT_PORTAL_ID` |
| `__REGION__` | `HUBSPOT_REGION` |
| `__HSFORMS_HOST__` | Derived from region |
| `__CAPTURE_FORM_ID__` | `CAPTURE_FORM_ID` (set by post-apply) |
| `__SURVEY_FORM_ID__` | `SURVEY_FORM_ID` (set by post-apply) |
| `__DOMAIN__` | `DOMAIN` |
| `__GA4_ID__` | `GA4_MEASUREMENT_ID` |
| `__DM_PATH__` | `DM_UPLOAD_PATH` |

## Terraform Modules

### account-setup

Run once per HubSpot account. Creates the `project_source` CRM contact property used for segmenting contacts by project.

### landing-page

Run per project. Creates: capture form, optional survey form, landing page, thank-you page, welcome email, contact list, and optional custom CRM properties.

Both modules use the Mastercard/restapi provider (~1.19) and inherit the provider configuration from the consuming project's root module.

## Authentication

All credentials are stored in macOS Keychain. Scripts read them via `security find-generic-password`.

| Keychain service | Content |
|---|---|
| `${KEYCHAIN_PREFIX}-hubspot-access-token` | HubSpot Service Key |
| `${KEYCHAIN_PREFIX}-hubspot-pak` | Optional — PAK for HubSpot CLI |

## Prerequisites

- HubSpot Marketing Hub Starter + Content Hub Starter
- Service Key with scopes: `crm.objects.contacts.read`, `crm.objects.contacts.write`, `crm.schemas.contacts.write`, `crm.lists.read`, `crm.lists.write`, `forms`, `content`, `transactional-email`
- Terraform CLI
- macOS with Keychain (for local development)
```

- [ ] **Step 2: Update README.md**

```markdown
# hs-lander

Reusable HubSpot landing page framework — Terraform modules, shell scripts, scaffold templates, and Claude Code skill.

## What this does

Takes a landing page project (HTML templates with placeholder tokens, config file) and deploys a complete HubSpot funnel: forms, pages, welcome email, and contact segmentation.

## Usage

See [docs/framework.md](docs/framework.md) for the full guide.

```bash
# Scaffold a new project
cp -r scaffold/* /path/to/my-project/
cp -r scripts/ /path/to/my-project/scripts/

# Build and deploy
cd /path/to/my-project
npm run build && npm run setup && npm run post-apply && npm run deploy
```

## Terraform Modules

Reference in your project's `terraform/main.tf`:

```hcl
module "account_setup" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v1.0.0"
}

module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.0.0"
  # ... variables
}
```

## Licence

Proprietary — Digital Mercenaries Ltd.
```

- [ ] **Step 3: Run all local tests**

```bash
bash tests/test-build.sh
bash tests/test-post-apply.sh
bash tests/test-terraform-plan.sh
```

Expected: All three pass.

- [ ] **Step 4: Commit**

```bash
git add docs/framework.md README.md
git commit -m "docs: add framework guide and update README"
```

- [ ] **Step 5: Push and tag v1.0.0**

```bash
git push origin main
git tag -a v1.0.0 -m "v1.0.0: Initial framework release"
git push origin v1.0.0
```

---

## Self-Review Checklist

### Spec coverage

| Spec requirement | Task |
|---|---|
| build.sh (token substitution) | Tasks 2-3 |
| post-apply.sh (terraform outputs → config) | Tasks 4-5 |
| tf.sh (Keychain → TF_VAR_*) | Task 6 |
| hs-curl.sh (Keychain → curl) | Task 6 |
| upload.sh (CMS Source Code API) | Task 7 |
| deploy.sh (build + upload) | Task 8 |
| watch.sh (poll + redeploy) | Task 8 |
| hs.sh (optional CLI wrapper) | Task 8 |
| account-setup module | Task 9 |
| landing-page module | Tasks 10-11 |
| test-build.sh | Task 2 |
| test-post-apply.sh | Task 4 |
| test-terraform-plan.sh | Task 12 |
| test-deployment.sh | Task 14 |
| Scaffold templates | Task 13 |
| CI workflows | Task 15 |
| Documentation | Task 16 |
| v1.0.0 tag | Task 16 |

### Known limitations

- **Lists API:** The restapi provider may not handle the `{"list":{...}}` response wrapper. If `terraform apply` fails for lists, they'll need to be created via `hs-curl.sh` or the skill. The module includes the resource definition with a comment noting this risk.
- **Email API:** The exact Marketing Emails API v3 request/response format may need adjustment when tested against a live endpoint. The Terraform plan will validate, but apply may require field tweaks.
- **Terraform validate:** The `landing-page` module uses `file()` which requires the email body file to exist at plan time. The test harness includes a fixture file for this.
