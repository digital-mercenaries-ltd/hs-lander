#!/usr/bin/env bash
# test-sed-portable.sh — Unit tests for scripts/lib/sed-portable.sh.
# Local only, no network required.
#
# The lib's `sed_inplace` and `sed_escape_replacement` are now sourced by
# build.sh, post-apply.sh, and set-project-field.sh. A regression that
# changes the escape pattern (e.g. dropping `\\` from the character class)
# silently corrupts build output only when a real consumer ships a value
# containing the dropped metachar — exactly the silent-failure mode this
# unit test guards against.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-sed-portable.sh ==="

# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/sed-portable.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- sed_inplace works (BSD or GNU) ---
echo ""
echo "--- sed_inplace ---"
echo "before" > "$TMPDIR/file.txt"
sed_inplace 's|before|after|' "$TMPDIR/file.txt"
got=$(cat "$TMPDIR/file.txt")
assert_equal "$got" "after" "sed_inplace replaces in place (no backup file written)"
# BSD sed -i '' should NOT have created file.txt'' — bug in earlier inline
# implementations on macOS.
if [[ -f "$TMPDIR/file.txt''" ]]; then
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: sed_inplace left a backup file with empty-string suffix (BSD bug)"
else
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: sed_inplace did not leave a backup file"
fi

# Multi-expression form (-e ... -e ...) works
echo "alpha-beta" > "$TMPDIR/multi.txt"
sed_inplace -e 's|alpha|gamma|' -e 's|beta|delta|' "$TMPDIR/multi.txt"
got=$(cat "$TMPDIR/multi.txt")
assert_equal "$got" "gamma-delta" "sed_inplace with multiple -e flags"

# Extended regex (-E) form works
echo "v1.2.3" > "$TMPDIR/regex.txt"
sed_inplace -E 's|v([0-9]+)\.([0-9]+)\.([0-9]+)|major=\1 minor=\2 patch=\3|' "$TMPDIR/regex.txt"
got=$(cat "$TMPDIR/regex.txt")
assert_equal "$got" "major=1 minor=2 patch=3" "sed_inplace with -E extended regex"

# --- sed_escape_replacement ---
echo ""
echo "--- sed_escape_replacement: identity for safe values ---"
for safe in "hello" "abc-123" "test.example.com" "/path/to/something" "a@b.c"; do
  got=$(sed_escape_replacement "$safe")
  if [[ "$got" == "$safe" ]]; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    echo "  PASS: round-trip '$safe'"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "  FAIL: '$safe' → '$got' (should be identity)"
  fi
done

# Empty input
got=$(sed_escape_replacement "")
assert_equal "$got" "" "sed_escape_replacement empty string round-trips to empty"

# --- sed_escape_replacement: metacharacters escaped ---
echo ""
echo "--- sed_escape_replacement: metacharacter escaping ---"
got=$(sed_escape_replacement 'foo|bar')
assert_equal "$got" 'foo\|bar' "pipe escaped"

got=$(sed_escape_replacement 'foo&bar')
assert_equal "$got" 'foo\&bar' "ampersand escaped"

got=$(sed_escape_replacement 'foo\bar')
assert_equal "$got" 'foo\\bar' "backslash escaped"

got=$(sed_escape_replacement 'a|b&c\d')
assert_equal "$got" 'a\|b\&c\\d' "all three metacharacters escaped together"

# --- End-to-end: escape then sed-substitute round-trips literally ---
echo ""
echo "--- End-to-end: escape + sed substitution ---"
# A token in a file gets replaced with a value containing each metachar.
# After substitution the file should contain the value LITERALLY (not
# interpreted by sed).
for value in 'foo|bar' 'foo&bar' 'foo\bar' 'a|b&c\d'; do
  echo "PLACEHOLDER" > "$TMPDIR/end-to-end.txt"
  escaped=$(sed_escape_replacement "$value")
  sed_inplace "s|PLACEHOLDER|${escaped}|g" "$TMPDIR/end-to-end.txt"
  got=$(cat "$TMPDIR/end-to-end.txt")
  if [[ "$got" == "$value" ]]; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    printf '  PASS: %q round-trips through escape+sed\n' "$value"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    printf '  FAIL: %q became %q (should round-trip)\n' "$value" "$got"
  fi
done

test_summary
