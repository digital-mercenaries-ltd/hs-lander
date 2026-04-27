#!/usr/bin/env bash
# test-preflight-decomposition.sh — verifies the v1.9.0 Component 3 invariants
# of the preflight.d/ decomposition. Complementary to test-preflight.sh, which
# is the regression canary for the output contract; this file checks the
# runner's behaviour with respect to the check-file directory itself.
#
# Local only. Reuses test-preflight.sh's setup helpers via `source`.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-preflight-decomposition.sh ==="

# We re-implement a minimal setup_env locally rather than sourcing
# test-preflight.sh (which would re-run that file's 174 assertions every
# invocation). Keeps this test scoped to the decomposition invariants.
setup_env() {
  local dir
  dir=$(mktemp -d)
  mkdir -p \
    "$dir/project/scripts" \
    "$dir/project/scripts/lib" \
    "$dir/project/scripts/preflight.d" \
    "$dir/home/.config/hs-lander/testacct" \
    "$dir/mock-bin"
  cp "$REPO_DIR/scripts/preflight.sh" "$dir/project/scripts/preflight.sh"
  chmod +x "$dir/project/scripts/preflight.sh"
  cp "$REPO_DIR/scripts/lib/"*.sh "$dir/project/scripts/lib/"
  cp "$REPO_DIR/scripts/preflight.d/"*.sh "$dir/project/scripts/preflight.d/"
  printf 'test-decomp-1.9.0\n' > "$dir/project/VERSION"
  # Minimal config so the preflight has more than just the FRAMEWORK_VERSION
  # line to emit. The downstream curl mocks aren't needed because the
  # gate-cascade tests never reach the credential probes.
  cat > "$dir/home/.config/hs-lander/testacct/config.sh" <<EOF
HUBSPOT_PORTAL_ID="12345678"
HUBSPOT_REGION="eu1"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="test-hubspot-access-token"
EOF
  cat > "$dir/home/.config/hs-lander/testacct/testproj.sh" <<EOF
PROJECT_SLUG="testproj"
DOMAIN="testproj.example.com"
DM_UPLOAD_PATH="/testproj"
EOF
  cat > "$dir/project/project.config.sh" <<'EOF'
HS_LANDER_ACCOUNT="testacct"
HS_LANDER_PROJECT="testproj"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
EOF
  # Minimal mock binaries so command -v curl/jq/terraform/npm pass. The
  # checks themselves don't have to succeed — we only care about line
  # presence/absence and ordering invariants.
  for tool in curl jq terraform npm dig; do
    cat > "$dir/mock-bin/$tool" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
    chmod +x "$dir/mock-bin/$tool"
  done
  printf '%s' "$dir"
}

run_preflight() {
  local dir="$1" log="$2"
  HOME="$dir/home" PATH="$dir/mock-bin:$PATH" \
    HS_LANDER_PROJECT_DIR="$dir/project" \
    bash "$dir/project/scripts/preflight.sh" >"$log" 2>&1 || true
}

# --- Scenario A: removing one check file drops exactly its line ---
# Asserts the per-file ownership invariant: each PREFLIGHT_<X>= line is owned
# by exactly one file, so removing that file drops exactly one line from the
# output (the FRAMEWORK_VERSION line is owned by the runner, never by a file
# under preflight.d/, so any check-file removal drops the contract length by 1).

echo ""
echo "--- Scenario A: removing one check file drops exactly its line ---"
TMPA=$(setup_env)
trap 'rm -rf "$TMPA" "${TMPB:-}" "${TMPC:-}" "${TMPD:-}" "${TMPE:-}" "${TMPF:-}"' EXIT

LOG_FULL="$TMPA/preflight-full.log"
run_preflight "$TMPA" "$LOG_FULL"
full_count=$(grep -c '^PREFLIGHT_' "$LOG_FULL")
assert_equal "$full_count" "17" "full preflight emits 17 PREFLIGHT_* lines (FRAMEWORK_VERSION + 16 check lines)"

# Remove the 90-ga4.sh check; assert PREFLIGHT_GA4 disappears and line-count
# drops by exactly 1.
rm "$TMPA/project/scripts/preflight.d/90-ga4.sh"
LOG_NOGA4="$TMPA/preflight-noga4.log"
run_preflight "$TMPA" "$LOG_NOGA4"
noga4_count=$(grep -c '^PREFLIGHT_' "$LOG_NOGA4")
assert_equal "$noga4_count" "16" "removing 90-ga4.sh drops line-count by exactly 1"
assert_file_not_contains "$LOG_NOGA4" "^PREFLIGHT_GA4=" "PREFLIGHT_GA4= line absent when 90-ga4.sh removed"
assert_file_contains "$LOG_NOGA4" "^PREFLIGHT_FORM_IDS=" "neighbouring PREFLIGHT_FORM_IDS line still present"
assert_file_contains "$LOG_NOGA4" "^PREFLIGHT_TOOLS_OPTIONAL=" "PREFLIGHT_TOOLS_OPTIONAL still present"

# --- Scenario B: removing the optional-tools check ---
# Different file, different position (last): same invariant should hold.

echo ""
echo "--- Scenario B: removing 99-tools-optional.sh drops only its line ---"
TMPB=$(setup_env)
rm "$TMPB/project/scripts/preflight.d/99-tools-optional.sh"
LOG_B="$TMPB/preflight.log"
run_preflight "$TMPB" "$LOG_B"
b_count=$(grep -c '^PREFLIGHT_' "$LOG_B")
assert_equal "$b_count" "16" "removing 99-tools-optional.sh drops line-count by exactly 1"
assert_file_not_contains "$LOG_B" "^PREFLIGHT_TOOLS_OPTIONAL=" "PREFLIGHT_TOOLS_OPTIONAL absent when 99-tools-optional.sh removed"
assert_file_contains "$LOG_B" "^PREFLIGHT_FORM_IDS=" "PREFLIGHT_FORM_IDS still present"

# --- Scenario C: empty preflight.d/ → runner refuses to run ---
# The runner's load-bearing invariant: without check files, only the
# FRAMEWORK_VERSION line would appear, which would silently look like every
# check passed. Refuse to run instead.

echo ""
echo "--- Scenario C: empty preflight.d/ → runner refuses (exit 2) ---"
TMPC=$(setup_env)
rm "$TMPC/project/scripts/preflight.d/"*.sh
LOG_C="$TMPC/preflight.log"
exit_c=0
HOME="$TMPC/home" PATH="$TMPC/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMPC/project" \
  bash "$TMPC/project/scripts/preflight.sh" >"$LOG_C" 2>&1 || exit_c=$?
assert_equal "$exit_c" "2" "exit 2 when preflight.d/ contains no *.sh files"
assert_file_contains "$LOG_C" "preflight.d/ contains no" "stderr names the empty-directory failure"

# --- Scenario D: missing preflight.d/ → runner refuses to run ---

echo ""
echo "--- Scenario D: missing preflight.d/ → runner refuses (exit 2) ---"
TMPD=$(setup_env)
rm -rf "$TMPD/project/scripts/preflight.d"
LOG_D="$TMPD/preflight.log"
exit_d=0
HOME="$TMPD/home" PATH="$TMPD/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMPD/project" \
  bash "$TMPD/project/scripts/preflight.sh" >"$LOG_D" 2>&1 || exit_d=$?
assert_equal "$exit_d" "2" "exit 2 when preflight.d/ directory is missing"
assert_file_contains "$LOG_D" "preflight.d/ directory missing" "stderr names the missing-directory failure"

# --- Scenario E: ordering is stable across runs ---
# The runner uses LC_ALL=C sort on the glob expansion. Two runs against the
# same check-file set must emit the same line ordering byte-for-byte.

echo ""
echo "--- Scenario E: PREFLIGHT_* line ordering stable across runs ---"
TMPE=$(setup_env)
LOG_E1="$TMPE/preflight-1.log"
LOG_E2="$TMPE/preflight-2.log"
run_preflight "$TMPE" "$LOG_E1"
run_preflight "$TMPE" "$LOG_E2"
order1=$(grep -oE '^PREFLIGHT_[A-Z0-9_]+' "$LOG_E1")
order2=$(grep -oE '^PREFLIGHT_[A-Z0-9_]+' "$LOG_E2")
assert_equal "$order1" "$order2" "PREFLIGHT_* key ordering identical across two runs"

# --- Scenario F: numeric-prefix ordering matches the documented contract ---
# Spot-check that the sort really does drive the documented order: TOOLS_REQUIRED
# first, TOOLS_OPTIONAL last, with the gate cascades (POINTER → ACCOUNT → PROFILE
# → CREDENTIAL) in the documented sequence.

echo ""
echo "--- Scenario F: numeric prefix drives documented contract ordering ---"
TMPF=$(setup_env)
LOG_F="$TMPF/preflight.log"
run_preflight "$TMPF" "$LOG_F"
expected_order=$'PREFLIGHT_FRAMEWORK_VERSION\nPREFLIGHT_TOOLS_REQUIRED\nPREFLIGHT_PROJECT_POINTER\nPREFLIGHT_ACCOUNT_PROFILE\nPREFLIGHT_PROJECT_PROFILE\nPREFLIGHT_CREDENTIAL\nPREFLIGHT_API_ACCESS\nPREFLIGHT_TIER\nPREFLIGHT_SCOPES\nPREFLIGHT_PROJECT_SOURCE\nPREFLIGHT_DNS\nPREFLIGHT_DOMAIN_CONNECTED\nPREFLIGHT_EMAIL_DNS\nPREFLIGHT_EMAIL_REPLY_TO\nPREFLIGHT_GA4\nPREFLIGHT_FORM_IDS\nPREFLIGHT_TOOLS_OPTIONAL'
actual_order=$(grep -oE '^PREFLIGHT_[A-Z0-9_]+' "$LOG_F")
assert_equal "$actual_order" "$expected_order" "documented ordering preserved by numeric prefixes"

test_summary
