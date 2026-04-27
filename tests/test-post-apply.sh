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
# v1.9.0 — post-apply now invokes backup-file.sh for the profile
cp "$REPO_DIR/scripts/backup-file.sh" "$TMPDIR/project/scripts/backup-file.sh"

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
echo "--- v1.9.0: profile backup written before mutation ---"
PROFILE_BACKUP_DIR="$TMPDIR/home/.config/hs-lander/testacct/.profile-backups"
assert_dir_exists "$PROFILE_BACKUP_DIR" ".profile-backups directory created"
backup_count=$(find "$PROFILE_BACKUP_DIR" -name 'testproj.sh.*' -type f | wc -l | tr -d ' ')
# Two runs above → two backups (LRU keep default 20).
assert_equal "$backup_count" "2" "two backups present after two post-apply runs"
# First backup must contain pre-mutation state (CAPTURE_FORM_ID="")
oldest_backup=$(find "$PROFILE_BACKUP_DIR" -name 'testproj.sh.*' -type f | sort | head -1)
assert_file_contains "$oldest_backup" 'CAPTURE_FORM_ID=""' "earliest backup is the pre-mutation profile"

echo ""
echo "--- v1.9.0: profile backup LRU honours HS_LANDER_BACKUP_KEEP ---"
# Run 22 more post-apply cycles with KEEP=3 and confirm trim.
KEEP_DIR="$TMPDIR/home/.config/hs-lander/testacct/.profile-backups-keep3"
for _ in 1 2 3 4 5; do
  HOME="$TMPDIR/home" PATH="$TMPDIR/mock-bin:$PATH" \
    HS_LANDER_PROJECT_DIR="$TMPDIR/project" \
    HS_LANDER_BACKUP_KEEP=3 \
    HS_LANDER_PROFILE_BACKUP_DIR="$KEEP_DIR" \
    bash "$TMPDIR/project/scripts/post-apply.sh" >/dev/null
  sleep 0.05 2>/dev/null || true
done
keep3_count=$(find "$KEEP_DIR" -name 'testproj.sh.*' -type f | wc -l | tr -d ' ')
assert_equal "$keep3_count" "3" "HS_LANDER_BACKUP_KEEP=3 retained after 5 runs"

test_summary
