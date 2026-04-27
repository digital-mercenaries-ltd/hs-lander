#!/usr/bin/env bash
# test-post-apply.sh — Validates post-apply.sh writes terraform outputs to the
# project-level config file under ~/.config/hs-lander/<account>/<project>.sh,
# NOT to the project-directory sourcing-chain pointer.
# Local only, no network. Uses a mock terraform binary.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-post-apply.sh ==="

# --- Setup ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Simulate the real layout:
#   $TMPDIR/project/          — project working dir (copied scripts, sourcing pointer)
#   $TMPDIR/home/.config/hs-lander/<account>/config.sh   — account-level settings
#   $TMPDIR/home/.config/hs-lander/<account>/<project>.sh — project-level settings (write target)
mkdir -p \
  "$TMPDIR/project/scripts/lib" \
  "$TMPDIR/project/terraform" \
  "$TMPDIR/home/.config/hs-lander/testacct"

cp "$REPO_DIR/scripts/post-apply.sh" "$TMPDIR/project/scripts/post-apply.sh"
# post-apply sources lib/sed-portable.sh
cp "$REPO_DIR/scripts/lib/sed-portable.sh" "$TMPDIR/project/scripts/lib/sed-portable.sh"

# Account config (unchanged by post-apply)
cat > "$TMPDIR/home/.config/hs-lander/testacct/config.sh" <<'EOF'
HUBSPOT_PORTAL_ID="12345678"
HUBSPOT_REGION="eu1"
DOMAIN_PATTERN="*.example.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="test-hubspot-access-token"
EOF

# Project config with empty IDs (pre-apply state) — 7 lines
cat > "$TMPDIR/home/.config/hs-lander/testacct/testproj.sh" <<'EOF'
PROJECT_SLUG="testproj"
DOMAIN="testproj.example.com"
DM_UPLOAD_PATH="/testproj"
GA4_MEASUREMENT_ID="G-TEST12345"
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
EOF

# Sourcing-chain pointer (what `project.config.sh` looks like in a real project)
cat > "$TMPDIR/project/project.config.sh" <<'EOF'
HS_LANDER_ACCOUNT="testacct"
HS_LANDER_PROJECT="testproj"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
EOF

# Record baseline content of files that must NOT change
ACCOUNT_FILE="$TMPDIR/home/.config/hs-lander/testacct/config.sh"
POINTER_FILE="$TMPDIR/project/project.config.sh"
PROJECT_FILE="$TMPDIR/home/.config/hs-lander/testacct/testproj.sh"
account_before=$(cat "$ACCOUNT_FILE")
pointer_before=$(cat "$POINTER_FILE")

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

# --- Run post-apply with mock terraform + overridden HOME ---
echo "Running post-apply.sh..."
HOME="$TMPDIR/home" PATH="$TMPDIR/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMPDIR/project" \
  bash "$TMPDIR/project/scripts/post-apply.sh"

# --- Assertions ---

echo ""
echo "--- Form IDs written to project config ---"
assert_file_contains "$PROJECT_FILE" 'CAPTURE_FORM_ID="mock-form-id-abc123"' "CAPTURE_FORM_ID written to project config"
assert_file_contains "$PROJECT_FILE" 'SURVEY_FORM_ID=""' "SURVEY_FORM_ID stays empty"
assert_file_contains "$PROJECT_FILE" 'LIST_ID="mock-list-id-789"' "LIST_ID written to project config"

echo ""
echo "--- Other project values unchanged ---"
assert_file_contains "$PROJECT_FILE" 'PROJECT_SLUG="testproj"' "PROJECT_SLUG unchanged"
assert_file_contains "$PROJECT_FILE" 'DOMAIN="testproj.example.com"' "DOMAIN unchanged"
assert_file_contains "$PROJECT_FILE" 'DM_UPLOAD_PATH="/testproj"' "DM_UPLOAD_PATH unchanged"
assert_file_contains "$PROJECT_FILE" 'GA4_MEASUREMENT_ID="G-TEST12345"' "GA4 ID unchanged"

echo ""
echo "--- Account config and sourcing pointer untouched ---"
account_after=$(cat "$ACCOUNT_FILE")
pointer_after=$(cat "$POINTER_FILE")
assert_equal "$account_after" "$account_before" "account config unchanged"
assert_equal "$pointer_after" "$pointer_before" "sourcing-chain pointer unchanged"

echo ""
echo "--- Idempotent (running twice gives same result) ---"
HOME="$TMPDIR/home" PATH="$TMPDIR/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMPDIR/project" \
  bash "$TMPDIR/project/scripts/post-apply.sh"
assert_file_contains "$PROJECT_FILE" 'CAPTURE_FORM_ID="mock-form-id-abc123"' "CAPTURE_FORM_ID same after re-run"
assert_file_contains "$PROJECT_FILE" 'LIST_ID="mock-list-id-789"' "LIST_ID same after re-run"

# Count lines to ensure no duplication — project file should stay at 7 lines
line_count=$(wc -l < "$PROJECT_FILE" | tr -d ' ')
assert_equal "$line_count" "7" "project config still has 7 lines (no duplication)"

echo ""
echo "--- v1.9.0 5.8: atomic write — partial failure leaves live profile unchanged ---"
# Simulate an interruption part-way through the field updates by replacing
# `mv` with a stub that fails BEFORE the rename completes. The live profile
# must remain identical to its pre-run state — the writes accumulated against
# the tempfile and never reached the live path.
#
# Capture the post-first-run baseline (the file we expect to be unchanged
# after the aborted second run).
profile_before_abort=$(cat "$PROJECT_FILE")

# Stub `mv` in mock-bin so the atomic step at the end of post-apply.sh fails
# before overwriting the live profile. Other invocations of `mv` elsewhere
# (e.g. inside the lib helpers) are not affected because PATH points first
# at mock-bin, but post-apply only invokes `mv` once — at the atomic step.
cat > "$TMPDIR/mock-bin/mv" <<'MOCK'
#!/usr/bin/env bash
echo "MOCK mv: simulated failure" >&2
exit 1
MOCK
chmod +x "$TMPDIR/mock-bin/mv"

# Mutate terraform mock to return a different value so we can prove the
# update did NOT land if the atomic step fails.
cat > "$TMPDIR/mock-bin/terraform" <<'MOCK'
#!/usr/bin/env bash
output_name="${!#}"
case "$output_name" in
  capture_form_id) echo "should-not-land-zzz" ;;
  survey_form_id) echo "should-not-land-survey" ;;
  list_id) echo "should-not-land-list" ;;
  *) echo "unknown: $output_name" >&2; exit 1 ;;
esac
MOCK
chmod +x "$TMPDIR/mock-bin/terraform"

set +e
HOME="$TMPDIR/home" PATH="$TMPDIR/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMPDIR/project" \
  bash "$TMPDIR/project/scripts/post-apply.sh" >/dev/null 2>&1
abort_rc=$?
set -e

if [[ "$abort_rc" -ne 0 ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "post-apply exits non-zero when atomic mv fails"

profile_after_abort=$(cat "$PROJECT_FILE")
assert_equal "$profile_after_abort" "$profile_before_abort" \
  "live profile unchanged after aborted post-apply (atomic-write guarantee)"

# Belt-and-braces: the would-have-landed values must NOT appear in the live
# profile. If they did, the writes had reached the live path before the abort.
if grep -q "should-not-land" "$PROJECT_FILE"; then
  result="false"
else
  result="true"
fi
assert_equal "$result" "true" \
  "would-have-landed values absent from live profile (writes stayed on tempfile)"

# Also assert no leftover tempfile beside the live profile — the EXIT trap
# in post-apply.sh should remove it even on the failure path.
leftover_count=$(find "$(dirname "$PROJECT_FILE")" -maxdepth 1 -name "$(basename "$PROJECT_FILE").*" | wc -l | tr -d ' ')
assert_equal "$leftover_count" "0" "no leftover tempfile beside live profile after aborted run"

# Restore real `mv` from /bin so subsequent test runs aren't affected.
rm -f "$TMPDIR/mock-bin/mv"

test_summary
