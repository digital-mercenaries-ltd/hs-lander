#!/usr/bin/env bash
# test-set-project-field.sh — Validates scripts/set-project-field.sh updates
# project profiles safely: rewrite-in-place, append, reject unknown keys,
# reject non-existent profile, idempotent re-runs, atomic write, and
# quoting round-trip.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-set-project-field.sh ==="

SCRIPT="$REPO_DIR/scripts/set-project-field.sh"
assert_file_exists "$SCRIPT" "scripts/set-project-field.sh exists"

seed_profile() {
  local dir="$1"
  mkdir -p "$dir/dml"
  cat > "$dir/dml/heard.sh" <<'EOF'
PROJECT_SLUG="heard"
DOMAIN="old.example.com"
DM_UPLOAD_PATH="/old"
GA4_MEASUREMENT_ID=""
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
EOF
}

run() {
  local cfg="$1"; shift
  local log="$1"; shift
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: update existing key ---
echo ""
echo "--- Scenario 1: update existing key ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}" "${TMP8:-}"' EXIT
seed_profile "$TMP1"
exit1=$(run "$TMP1" "$TMP1/log" dml heard DOMAIN="heard.example.com" || true)
assert_equal "$exit1" "0" "exit 0 on update"
assert_file_contains "$TMP1/log" "^SET_FIELD_UPDATED=DOMAIN$" "update reported"
assert_file_contains "$TMP1/log" "^SET_FIELD=ok$" "ok terminator"
assert_file_contains "$TMP1/dml/heard.sh" '^DOMAIN="heard\.example\.com"$' "new DOMAIN written"
# Other fields untouched
assert_file_contains "$TMP1/dml/heard.sh" '^PROJECT_SLUG="heard"$' "PROJECT_SLUG unchanged"
assert_file_contains "$TMP1/dml/heard.sh" '^DM_UPLOAD_PATH="/old"$' "DM_UPLOAD_PATH unchanged"
# No duplicate DOMAIN line
domain_count=$(grep -c '^DOMAIN=' "$TMP1/dml/heard.sh")
assert_equal "$domain_count" "1" "no duplicate DOMAIN line"
# File stays at 7 lines
line_count=$(wc -l < "$TMP1/dml/heard.sh" | tr -d ' ')
assert_equal "$line_count" "7" "file still 7 lines"

# --- Scenario 2: append new key (not previously in file) ---
echo ""
echo "--- Scenario 2: append new key ---"
TMP2=$(mktemp -d)
mkdir -p "$TMP2/dml"
cat > "$TMP2/dml/heard.sh" <<'EOF'
PROJECT_SLUG="heard"
EOF
exit2=$(run "$TMP2" "$TMP2/log" dml heard GA4_MEASUREMENT_ID="G-ABC123" || true)
assert_equal "$exit2" "0" "exit 0 on append"
assert_file_contains "$TMP2/log" "^SET_FIELD_APPENDED=GA4_MEASUREMENT_ID$" "append reported"
assert_file_contains "$TMP2/dml/heard.sh" '^GA4_MEASUREMENT_ID="G-ABC123"$' "new field appended"

# --- Scenario 3: multiple pairs in one invocation ---
echo ""
echo "--- Scenario 3: multiple pairs in one invocation ---"
TMP3=$(mktemp -d)
seed_profile "$TMP3"
exit3=$(run "$TMP3" "$TMP3/log" dml heard \
  DOMAIN="heard.new.com" \
  DM_UPLOAD_PATH="/heard" \
  GA4_MEASUREMENT_ID="G-XYZ789" \
  || true)
assert_equal "$exit3" "0" "exit 0 with multiple pairs"
assert_file_contains "$TMP3/log" "^SET_FIELD_UPDATED=DOMAIN$" "DOMAIN reported"
assert_file_contains "$TMP3/log" "^SET_FIELD_UPDATED=DM_UPLOAD_PATH$" "DM_UPLOAD_PATH reported"
assert_file_contains "$TMP3/log" "^SET_FIELD_UPDATED=GA4_MEASUREMENT_ID$" "GA4 reported"
assert_file_contains "$TMP3/dml/heard.sh" '^DOMAIN="heard\.new\.com"$' "DOMAIN value updated"
assert_file_contains "$TMP3/dml/heard.sh" '^DM_UPLOAD_PATH="/heard"$' "DM_UPLOAD_PATH value updated"
assert_file_contains "$TMP3/dml/heard.sh" '^GA4_MEASUREMENT_ID="G-XYZ789"$' "GA4 value updated"

# --- Scenario 4: unknown key → rejected, file untouched ---
echo ""
echo "--- Scenario 4: unknown key rejected ---"
TMP4=$(mktemp -d)
seed_profile "$TMP4"
before=$(cat "$TMP4/dml/heard.sh")
exit4=$(run "$TMP4" "$TMP4/log" dml heard \
  DOMAIN="ok.example.com" \
  HUBSPOT_TOKEN_KEYCHAIN_SERVICE="oops-credential-field" \
  || true)
assert_equal "$exit4" "1" "exit 1 on unknown key"
assert_file_contains "$TMP4/log" "^SET_FIELD=error unknown-key HUBSPOT_TOKEN_KEYCHAIN_SERVICE$" "unknown-key reported by name"
after=$(cat "$TMP4/dml/heard.sh")
assert_equal "$after" "$before" "file untouched — up-front validation rejected the whole batch"

# --- Scenario 5: non-existent profile ---
echo ""
echo "--- Scenario 5: missing profile ---"
TMP5=$(mktemp -d)
exit5=$(run "$TMP5" "$TMP5/log" nope missing GA4_MEASUREMENT_ID=G-1 || true)
assert_equal "$exit5" "1" "exit 1 when profile missing"
assert_file_contains "$TMP5/log" "^SET_FIELD=error profile-missing" "profile-missing reported"

# --- Scenario 6: invalid pair (no equals sign) ---
echo ""
echo "--- Scenario 6: invalid pair ---"
TMP6=$(mktemp -d)
seed_profile "$TMP6"
exit6=$(run "$TMP6" "$TMP6/log" dml heard "bareword-no-equals" || true)
assert_equal "$exit6" "1" "exit 1 on invalid pair"
assert_file_contains "$TMP6/log" "^SET_FIELD=error invalid-pair" "invalid-pair reported"

# --- Scenario 7: idempotent re-run (set to current value) → file unchanged ---
echo ""
echo "--- Scenario 7: idempotent update ---"
TMP7=$(mktemp -d)
seed_profile "$TMP7"
# Prime: set DOMAIN to a known value
run "$TMP7" "$TMP7/log" dml heard DOMAIN="same.example.com" >/dev/null
hash_before=$(shasum "$TMP7/dml/heard.sh" | awk '{print $1}')
# Re-set to the same value
exit7=$(run "$TMP7" "$TMP7/log2" dml heard DOMAIN="same.example.com" || true)
assert_equal "$exit7" "0" "exit 0 on idempotent re-set"
hash_after=$(shasum "$TMP7/dml/heard.sh" | awk '{print $1}')
assert_equal "$hash_after" "$hash_before" "file content identical when value unchanged"

# --- Scenario 8: value with shell metacharacters round-trips ---
echo ""
echo "--- Scenario 8: quoting round-trip ---"
TMP8=$(mktemp -d)
seed_profile "$TMP8"
# Use a value with spaces, dots, and an asterisk. Plain shell metacharacters
# are enough — we don't need to stress-test embedded double-quotes here.
exit8=$(run "$TMP8" "$TMP8/log" dml heard DOMAIN="some host *.example.com" || true)
assert_equal "$exit8" "0" "exit 0 with metacharacter value"
assert_file_contains "$TMP8/dml/heard.sh" '^DOMAIN="some host \*\.example\.com"$' "value written with canonical quotes"
# Round-trip through source
(
  # shellcheck source=/dev/null
  source "$TMP8/dml/heard.sh"
  [[ "$DOMAIN" == "some host *.example.com" ]] || exit 10
) && rt=ok || rt=fail
assert_equal "$rt" "ok" "sourced value matches what we set (glob not expanded)"

# --- Scenario 9: pipe | in value is handled (not confused with sed delimiter) ---
# Regression guard for the sed-delimiter bug: `|` is now escaped in the
# replacement string rather than terminating the substitution.
echo ""
echo "--- Scenario 9: pipe in value round-trips ---"
TMP9=$(mktemp -d)
seed_profile "$TMP9"
exit9=$(HS_LANDER_CONFIG_DIR="$TMP9" bash "$SCRIPT" dml heard DOMAIN="a|b|c" >"$TMP9/log" 2>&1; echo $?)
assert_equal "$exit9" "0" "exit 0 with pipe in value"
assert_file_contains "$TMP9/dml/heard.sh" '^DOMAIN="a|b|c"$' "pipe written literally"
(
  # shellcheck source=/dev/null
  source "$TMP9/dml/heard.sh"
  [[ "$DOMAIN" == "a|b|c" ]] || exit 10
) && rt=ok || rt=fail
assert_equal "$rt" "ok" "pipe value round-trips via source"

# --- Scenario 10: value with banned chars is rejected — no file write ---
# Any of: double-quote, dollar, backtick, backslash, or control char.
# These can't round-trip through canonical `KEY="value"` quoting.
echo ""
echo "--- Scenario 10: banned chars rejected ---"
TMP10=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}" "${TMP8:-}" "${TMP9:-}" "${TMP10:-}"' EXIT
seed_profile "$TMP10"
before=$(cat "$TMP10/dml/heard.sh")

# Double-quote
HS_LANDER_CONFIG_DIR="$TMP10" bash "$SCRIPT" dml heard 'DOMAIN=has"quote' >"$TMP10/log-quote" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on double-quote in value"
assert_file_contains "$TMP10/log-quote" "^SET_FIELD=error invalid-value DOMAIN" "invalid-value reported for quote"

# Dollar (command/var expansion risk on source)
HS_LANDER_CONFIG_DIR="$TMP10" bash "$SCRIPT" dml heard 'DOMAIN=has$dollar' >"$TMP10/log-dollar" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on dollar in value"

# Backtick (command substitution risk on source)
HS_LANDER_CONFIG_DIR="$TMP10" bash "$SCRIPT" dml heard 'DOMAIN=has`tick`' >"$TMP10/log-tick" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on backtick in value"

# Backslash
HS_LANDER_CONFIG_DIR="$TMP10" bash "$SCRIPT" dml heard 'DOMAIN=has\backslash' >"$TMP10/log-bs" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on backslash in value"

# Newline (via $'...')
HS_LANDER_CONFIG_DIR="$TMP10" bash "$SCRIPT" dml heard "DOMAIN=$(printf 'a\nb')" >"$TMP10/log-nl" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on newline in value"

# File must be byte-identical after every rejection
after=$(cat "$TMP10/dml/heard.sh")
assert_equal "$after" "$before" "file unchanged across all banned-char rejections"

# --- Scenario 11: no stale .tmp.* files left behind after a successful run ---
echo ""
echo "--- Scenario 11: successful run leaves no stale temp ---"
TMP11=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}" "${TMP8:-}" "${TMP9:-}" "${TMP10:-}" "${TMP11:-}"' EXIT
seed_profile "$TMP11"
HS_LANDER_CONFIG_DIR="$TMP11" bash "$SCRIPT" dml heard DOMAIN=clean.example.com >/dev/null
stale=$(find "$TMP11/dml" -maxdepth 1 -name 'heard.sh.tmp.*' | wc -l | tr -d ' ')
assert_equal "$stale" "0" "no stale .tmp.* files in account dir after success"

# --- Scenario 12: v1.5.0 hosting-modes / subscription allow-list extensions ---
# LANDING_SLUG, THANKYOU_SLUG, HUBSPOT_SUBSCRIPTION_ID, HUBSPOT_OFFICE_LOCATION_ID
# landed in v1.5.0. HOSTING_MODE_HINT was on the v1.5.0 allow-list but removed
# in v1.7.0 (skill-only state, lives in <project>.skillstate.sh now —
# Scenario 14 verifies the rejection). HUBSPOT_TOKEN_KEYCHAIN_SERVICE
# remains rejected (Scenario 4 still covers that).
echo ""
echo "--- Scenario 12: v1.5.0 hosting-modes / subscription keys ---"
TMP12=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}" "${TMP8:-}" "${TMP9:-}" "${TMP10:-}" "${TMP11:-}" "${TMP12:-}" "${TMP13:-}" "${TMP14:-}"' EXIT
seed_profile "$TMP12"
exit12=$(run "$TMP12" "$TMP12/log" dml heard \
  LANDING_SLUG="heard" \
  THANKYOU_SLUG="thanks" \
  HUBSPOT_SUBSCRIPTION_ID="2269639338" \
  HUBSPOT_OFFICE_LOCATION_ID="375327044798" \
  || true)
assert_equal "$exit12" "0" "exit 0 with v1.5.0 hosting-modes / subscription keys"
assert_file_contains "$TMP12/log" "^SET_FIELD=ok$" "ok terminator emitted"
assert_file_contains "$TMP12/dml/heard.sh" '^LANDING_SLUG="heard"$' "LANDING_SLUG written"
assert_file_contains "$TMP12/dml/heard.sh" '^THANKYOU_SLUG="thanks"$' "THANKYOU_SLUG written"
assert_file_contains "$TMP12/dml/heard.sh" '^HUBSPOT_SUBSCRIPTION_ID="2269639338"$' "HUBSPOT_SUBSCRIPTION_ID written"
assert_file_contains "$TMP12/dml/heard.sh" '^HUBSPOT_OFFICE_LOCATION_ID="375327044798"$' "HUBSPOT_OFFICE_LOCATION_ID written"

# --- Scenario 13: v1.7.0 allow-list extensions accepted ---
# EMAIL_PREVIEW_TEXT, AUTO_PUBLISH_WELCOME_EMAIL, INCLUDE_BOTTOM_CTA all
# added in v1.7.0 for the welcome-email anatomy and tier-aware publish gate.
echo ""
echo "--- Scenario 13: v1.7.0 allow-list extensions ---"
TMP13=$(mktemp -d)
seed_profile "$TMP13"
exit13=$(run "$TMP13" "$TMP13/log" dml heard \
  EMAIL_PREVIEW_TEXT="You are in. Reply with one word: ready or curious." \
  AUTO_PUBLISH_WELCOME_EMAIL="false" \
  INCLUDE_BOTTOM_CTA="true" \
  || true)
assert_equal "$exit13" "0" "exit 0 with v1.7.0 keys"
assert_file_contains "$TMP13/log" "^SET_FIELD=ok$" "[Scenario 13] ok terminator emitted"
assert_file_contains "$TMP13/dml/heard.sh" '^EMAIL_PREVIEW_TEXT="You are in. Reply with one word: ready or curious.\"$' "EMAIL_PREVIEW_TEXT written"
assert_file_contains "$TMP13/dml/heard.sh" '^AUTO_PUBLISH_WELCOME_EMAIL="false"$' "AUTO_PUBLISH_WELCOME_EMAIL written"
assert_file_contains "$TMP13/dml/heard.sh" '^INCLUDE_BOTTOM_CTA="true"$' "INCLUDE_BOTTOM_CTA written"

# --- Scenario 14: HOSTING_MODE_HINT rejected (v1.7.0 removal) ---
# HOSTING_MODE_HINT was removed from the allow-list in v1.7.0 because the
# skill now stores hosting-mode state in <project>.skillstate.sh outside
# the framework's project profile. Verify the rejection so a stale skill
# clinging to the old key fails loudly rather than silently writing nothing.
echo ""
echo "--- Scenario 14: HOSTING_MODE_HINT rejected (v1.7.0) ---"
TMP14=$(mktemp -d)
seed_profile "$TMP14"
exit14=$(run "$TMP14" "$TMP14/log" dml heard HOSTING_MODE_HINT="redirect" || true)
assert_equal "$exit14" "1" "[Scenario 14] exit 1 when HOSTING_MODE_HINT is set"
assert_file_contains "$TMP14/log" "^SET_FIELD=error unknown-key HOSTING_MODE_HINT$" "[Scenario 14] unknown-key error emitted"

test_summary
