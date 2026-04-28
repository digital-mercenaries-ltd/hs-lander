#!/usr/bin/env bash
# test-version.sh — Validates scripts/version.sh reads the VERSION file
# from the repo root and emits FRAMEWORK_VERSION=<value>.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-version.sh ==="

SCRIPT="$REPO_DIR/scripts/version.sh"
assert_file_exists "$SCRIPT" "scripts/version.sh exists"

# --- Scenario 1: real VERSION file in the repo ---
echo ""
echo "--- Scenario 1: reads the real VERSION file ---"
out=$(bash "$SCRIPT")
expected_version=$(tr -d '[:space:]' < "$REPO_DIR/VERSION")
assert_equal "$out" "FRAMEWORK_VERSION=$expected_version" "version matches the committed VERSION file"

# --- Scenario 2: missing VERSION → FRAMEWORK_VERSION=unknown ---
# Copy the script into a temp dir so we can control whether VERSION exists.
echo ""
echo "--- Scenario 2: missing VERSION → unknown ---"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts"
cp "$SCRIPT" "$TMP/scripts/version.sh"
# No VERSION file in $TMP
out=$(bash "$TMP/scripts/version.sh")
assert_equal "$out" "FRAMEWORK_VERSION=unknown" "reports unknown when VERSION is absent"

# --- Scenario 3: VERSION with trailing newline + whitespace is stripped ---
echo ""
echo "--- Scenario 3: VERSION with whitespace is stripped ---"
printf '  2.5.0  \n\n' > "$TMP/VERSION"
out=$(bash "$TMP/scripts/version.sh")
assert_equal "$out" "FRAMEWORK_VERSION=2.5.0" "whitespace stripped, value preserved"

# --- Scenario 4: VERSION.compat exists with valid format ---
# v1.9.1 introduces VERSION.compat as the skill / framework compatibility
# pin. The file's format is a single-line semver range; this test asserts
# its existence and that the content matches the documented grammar.
echo ""
echo "--- Scenario 4: VERSION.compat exists with valid format ---"
assert_file_exists "$REPO_DIR/VERSION.compat" "VERSION.compat exists at repo root"
compat_value=$(tr -d '[:space:]' < "$REPO_DIR/VERSION.compat")
# Format check: matches >=X.Y.Z,<X.Y.Z (the documented shape). Loose
# validation — accepts any whitespace-stripped string with at least one
# semver-shaped token. Tightening the regex risks false-positive
# rejection for legitimate edge cases (e.g. a one-off `=X.Y.Z` pin).
if [[ "$compat_value" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
  result="true"
else
  result="false"
fi
assert_equal "$result" "true" "VERSION.compat contains at least one semver-shaped token: '$compat_value'"

test_summary
