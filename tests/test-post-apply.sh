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
line_count=$(wc -l < "$TMPDIR/project.config.sh" | tr -d ' ')
assert_equal "$line_count" "9" "config file still has 9 lines (no duplication)"

test_summary
