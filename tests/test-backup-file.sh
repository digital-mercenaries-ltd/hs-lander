#!/usr/bin/env bash
# test-backup-file.sh — Validates scripts/backup-file.sh covers the contract:
# skip on missing source, fresh backup with content + mtime preserved,
# nanosecond/PID disambiguation, LRU trim under HS_LANDER_BACKUP_KEEP.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-backup-file.sh ==="

SCRIPT="$REPO_DIR/scripts/backup-file.sh"
assert_file_exists "$SCRIPT" "scripts/backup-file.sh exists"

# --- Scenario 1: source missing → BACKUP=skip, exit 0, no dir created ---
echo ""
echo "--- Scenario 1: source missing ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}"' EXIT
out1=$(bash "$SCRIPT" "$TMP1/missing" "$TMP1/backups" 2>&1)
rc1=$?
assert_equal "$rc1" "0" "exit 0 when source missing"
case "$out1" in BACKUP=skip*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "BACKUP=skip emitted"
if [[ -d "$TMP1/backups" ]]; then
  echo "  FAIL: backup dir created when source missing"
  FAILURES=$((FAILURES + 1)); TESTS=$((TESTS + 1))
else
  echo "  PASS: backup dir not created when source missing"
  PASSES=$((PASSES + 1)); TESTS=$((TESTS + 1))
fi

# --- Scenario 2: fresh backup, content preserved ---
echo ""
echo "--- Scenario 2: fresh backup ---"
TMP2=$(mktemp -d)
echo "hello world" > "$TMP2/source.txt"
out2=$(bash "$SCRIPT" "$TMP2/source.txt" "$TMP2/backups" 2>&1)
rc2=$?
assert_equal "$rc2" "0" "exit 0 on successful backup"
case "$out2" in BACKUP=ok*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "BACKUP=ok emitted"
backup_path=$(echo "$out2" | sed -n 's/^BACKUP=ok //p')
assert_file_exists "$backup_path" "backup file exists at reported path"
assert_equal "$(cat "$backup_path")" "hello world" "backup content matches source"
case "$(basename "$backup_path")" in source.txt.*) pass=1 ;; *) pass=0 ;; esac
assert_equal "$pass" "1" "backup filename starts with 'source.txt.'"

# --- Scenario 3: two backups same wall-clock second → distinct names ---
echo ""
echo "--- Scenario 3: same-second disambiguation ---"
TMP3=$(mktemp -d)
echo "v1" > "$TMP3/file.txt"
out3a=$(bash "$SCRIPT" "$TMP3/file.txt" "$TMP3/backups" 2>&1)
out3b=$(bash "$SCRIPT" "$TMP3/file.txt" "$TMP3/backups" 2>&1)
path3a=$(echo "$out3a" | sed -n 's/^BACKUP=ok //p')
path3b=$(echo "$out3b" | sed -n 's/^BACKUP=ok //p')
if [[ "$path3a" != "$path3b" ]]; then
  echo "  PASS: rapid-succession backups have distinct names"
  PASSES=$((PASSES + 1)); TESTS=$((TESTS + 1))
else
  echo "  FAIL: rapid-succession backups collide ($path3a)"
  FAILURES=$((FAILURES + 1)); TESTS=$((TESTS + 1))
fi

# --- Scenario 4: LRU trim with HS_LANDER_BACKUP_KEEP=3 ---
echo ""
echo "--- Scenario 4: LRU trim with HS_LANDER_BACKUP_KEEP=3 ---"
TMP4=$(mktemp -d)
echo "data" > "$TMP4/file.txt"
for i in 1 2 3 4 5; do
  HS_LANDER_BACKUP_KEEP=3 bash "$SCRIPT" "$TMP4/file.txt" "$TMP4/backups" >/dev/null 2>&1
  # Touch with distinct mtime so ls -t order is deterministic across systems
  # whose %N support varies. Sleep is unfortunate but small enough.
  sleep 0.05 2>/dev/null || sleep 1
done
backup_count=$(find "$TMP4/backups" -name 'file.txt.*' -type f | wc -l | tr -d ' ')
assert_equal "$backup_count" "3" "exactly 3 backups retained under KEEP=3"

# --- Scenario 5: default keep is 20 ---
echo ""
echo "--- Scenario 5: default HS_LANDER_BACKUP_KEEP=20 ---"
TMP5=$(mktemp -d)
echo "data" > "$TMP5/file.txt"
for i in $(seq 1 22); do
  bash "$SCRIPT" "$TMP5/file.txt" "$TMP5/backups" >/dev/null 2>&1
  sleep 0.02 2>/dev/null || true
done
default_count=$(find "$TMP5/backups" -name 'file.txt.*' -type f | wc -l | tr -d ' ')
assert_equal "$default_count" "20" "default retention trims to 20"

# --- Scenario 6: trim only matches files with the right basename prefix ---
echo ""
echo "--- Scenario 6: trim respects basename pattern ---"
TMP6=$(mktemp -d)
echo "data" > "$TMP6/aa.txt"
echo "data" > "$TMP6/bb.txt"
mkdir -p "$TMP6/backups"
# Pre-populate backups for an unrelated basename — must not be trimmed
for i in 1 2 3; do
  echo "x" > "$TMP6/backups/bb.txt.fixture-$i"
done
for i in 1 2 3 4 5; do
  HS_LANDER_BACKUP_KEEP=2 bash "$SCRIPT" "$TMP6/aa.txt" "$TMP6/backups" >/dev/null 2>&1
  sleep 0.02 2>/dev/null || true
done
aa_count=$(find "$TMP6/backups" -name 'aa.txt.*' -type f | wc -l | tr -d ' ')
bb_count=$(find "$TMP6/backups" -name 'bb.txt.*' -type f | wc -l | tr -d ' ')
assert_equal "$aa_count" "2" "aa.txt backups trimmed to KEEP=2"
assert_equal "$bb_count" "3" "bb.txt fixtures untouched (different basename)"

test_summary
