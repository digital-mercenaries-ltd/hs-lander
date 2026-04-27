#!/usr/bin/env bash
# test-tf.sh — Validates the v1.9.0 `apply` verb in scripts/tf.sh:
# plan-file gate, escape hatch, state backup before apply, plan-file deletion
# on success.
# Local only — uses a mock terraform and a mock `security` (keychain) on PATH.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-tf.sh ==="

SCRIPT="$REPO_DIR/scripts/tf.sh"
assert_file_exists "$SCRIPT" "scripts/tf.sh exists"

# Build a fixture project layout, mock terraform, mock security.
make_project() {
  local dir="$1"
  mkdir -p "$dir/scripts/lib" "$dir/terraform" "$dir/mock-bin"

  cp "$REPO_DIR/scripts/tf.sh" "$dir/scripts/tf.sh"
  cp "$REPO_DIR/scripts/backup-file.sh" "$dir/scripts/backup-file.sh"
  cp "$REPO_DIR/scripts/lib/keychain.sh" "$dir/scripts/lib/keychain.sh"

  cat > "$dir/project.config.sh" <<'PCS'
HS_LANDER_ACCOUNT="testacct"
HS_LANDER_PROJECT="testproj"
HUBSPOT_PORTAL_ID="12345678"
HUBSPOT_REGION="eu1"
DOMAIN="testproj.example.com"
HUBSPOT_TOKEN_KEYCHAIN_SERVICE="test-hubspot-token"
PCS

  # Mock security: emits a fake token.
  cat > "$dir/mock-bin/security" <<'SEC'
#!/usr/bin/env bash
# Always last argument is "-w"; emit a token.
echo "fake-token-xyz"
SEC
  chmod +x "$dir/mock-bin/security"

  # Mock terraform: succeeds, prints a marker, supports apply <plan-file>.
  cat > "$dir/mock-bin/terraform" <<'TF'
#!/usr/bin/env bash
echo "MOCK-TERRAFORM $*" >> "${MOCK_TF_LOG:-/tmp/mock-tf.log}"
exit 0
TF
  chmod +x "$dir/mock-bin/terraform"
}

# --- Scenario 1: apply with no plan file → APPLY=error plan-file-missing ---
echo ""
echo "--- Scenario 1: apply without saved plan → error ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}"' EXIT
make_project "$TMP1"
out1=$(MOCK_TF_LOG="$TMP1/tf.log" PATH="$TMP1/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMP1" \
  bash "$TMP1/scripts/tf.sh" apply 2>&1) && rc1=$? || rc1=$?
assert_equal "$rc1" "1" "exit 1 when plan file missing"
case "$out1" in *"APPLY=error plan-file-missing"*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "APPLY=error plan-file-missing emitted"
# Mock terraform must not have been invoked for an apply
if [[ -f "$TMP1/tf.log" ]] && grep -q "apply" "$TMP1/tf.log"; then
  echo "  FAIL: terraform apply ran despite missing plan file"
  FAILURES=$((FAILURES+1)); TESTS=$((TESTS+1))
else
  echo "  PASS: terraform apply not invoked"
  PASSES=$((PASSES+1)); TESTS=$((TESTS+1))
fi

# --- Scenario 2: apply with saved plan file → APPLY=ok, plan deleted ---
echo ""
echo "--- Scenario 2: apply with saved plan succeeds ---"
TMP2=$(mktemp -d)
make_project "$TMP2"
echo "fake-plan-bytes" > "$TMP2/.hs-lander-plan.bin"
out2=$(MOCK_TF_LOG="$TMP2/tf.log" PATH="$TMP2/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMP2" \
  bash "$TMP2/scripts/tf.sh" apply 2>&1) && rc2=$? || rc2=$?
assert_equal "$rc2" "0" "exit 0 with saved plan"
case "$out2" in *"APPLY=ok"*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "APPLY=ok emitted"
if [[ -f "$TMP2/.hs-lander-plan.bin" ]]; then
  echo "  FAIL: plan file not deleted after apply"
  FAILURES=$((FAILURES+1)); TESTS=$((TESTS+1))
else
  echo "  PASS: plan file deleted after successful apply"
  PASSES=$((PASSES+1)); TESTS=$((TESTS+1))
fi

# --- Scenario 3: state backup runs before apply ---
echo ""
echo "--- Scenario 3: state backup before apply ---"
TMP3=$(mktemp -d)
make_project "$TMP3"
echo "fake-plan-bytes" > "$TMP3/.hs-lander-plan.bin"
echo "STATE-V1" > "$TMP3/terraform/terraform.tfstate"
MOCK_TF_LOG="$TMP3/tf.log" PATH="$TMP3/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMP3" \
  bash "$TMP3/scripts/tf.sh" apply >/dev/null 2>&1
backup_count=$(find "$TMP3/terraform/state-backups" -name 'terraform.tfstate.*' -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equal "$backup_count" "1" "exactly 1 state backup created"
backup_file=$(find "$TMP3/terraform/state-backups" -name 'terraform.tfstate.*' -type f | head -1)
assert_equal "$(cat "$backup_file")" "STATE-V1" "backup contains pre-apply state contents"

# --- Scenario 4: HS_LANDER_UNSAFE_APPLY=1 bypasses plan-file requirement ---
echo ""
echo "--- Scenario 4: unsafe-apply escape hatch ---"
TMP4=$(mktemp -d)
make_project "$TMP4"
echo "STATE-V1" > "$TMP4/terraform/terraform.tfstate"
out4=$(MOCK_TF_LOG="$TMP4/tf.log" PATH="$TMP4/mock-bin:$PATH" \
  HS_LANDER_PROJECT_DIR="$TMP4" \
  HS_LANDER_UNSAFE_APPLY=1 \
  bash "$TMP4/scripts/tf.sh" apply 2>&1) && rc4=$? || rc4=$?
assert_equal "$rc4" "0" "exit 0 under HS_LANDER_UNSAFE_APPLY=1"
case "$out4" in *"APPLY=ok"*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "APPLY=ok under unsafe apply"
case "$out4" in *"WARNING: HS_LANDER_UNSAFE_APPLY=1"*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "noisy warning emitted"
# State backup still happened
backup_count4=$(find "$TMP4/terraform/state-backups" -name 'terraform.tfstate.*' -type f 2>/dev/null | wc -l | tr -d ' ')
assert_equal "$backup_count4" "1" "state backup still runs under unsafe-apply"

test_summary
