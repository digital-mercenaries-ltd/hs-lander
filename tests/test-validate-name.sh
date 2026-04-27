#!/usr/bin/env bash
# test-validate-name.sh — Unit tests for scripts/lib/validate-name.sh.
# Local only, no network required.
#
# Closes the v1.8.1 review carryover (test-analyzer #7): the validator
# now sits on the trust boundary for six config-touching scripts and
# previously had no unit-test coverage. A regression that loosens or
# tightens the regex would land green without this guard.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-validate-name.sh ==="

# Source the lib in a subshell guard so its functions don't pollute the
# helper's scope — but we DO need it in this shell to call directly.
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/validate-name.sh"

# --- Valid names ---
echo ""
echo "--- Valid names accepted ---"
for name in "acme" "acme-1" "1" "a" "a1b2c3" "x-y-z" "0" "0-acme"; do
  if is_valid_name "$name"; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    echo "  PASS: '$name' accepted"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    echo "  FAIL: '$name' should have been accepted"
  fi
done

# --- Invalid names ---
echo ""
echo "--- Invalid names rejected ---"
# `'$ENV'` is the literal string we're feeding to is_valid_name — single-quoted
# on purpose so the dollar sign and word are passed through verbatim.
# shellcheck disable=SC2016
for name in ".." "acme/foo" "Acme" "ACME" "acme.com" "" "-acme" "acme_foo" "acme foo" "acme/" "/acme" "acme;rm" "acme\$x" '$ENV'; do
  if ! is_valid_name "$name"; then
    PASSES=$((PASSES + 1))
    TESTS=$((TESTS + 1))
    # Print escaped repr so terminal control chars / dollar signs don't
    # confuse the operator reading the test log.
    printf '  PASS: %q rejected\n' "$name"
  else
    FAILURES=$((FAILURES + 1))
    TESTS=$((TESTS + 1))
    printf '  FAIL: %q should have been rejected\n' "$name"
  fi
done

# --- Arg-count guard (silent-failure-hunter H4 carryover) ---
echo ""
echo "--- Arg-count guard ---"
# Zero args → return 2 (NOT 1) so callers can distinguish "regex failed"
# (return 1) from "called with wrong number of args" (return 2).
rc=0
is_valid_name 2>/dev/null || rc=$?
assert_equal "$rc" "2" "zero args returns 2"

rc=0
is_valid_name "a" "b" 2>/dev/null || rc=$?
assert_equal "$rc" "2" "two args returns 2"

rc=0
is_valid_name "a" "b" "c" 2>/dev/null || rc=$?
assert_equal "$rc" "2" "three args returns 2"

# Stderr error message present on arg-count failure
err=$(is_valid_name "a" "b" 2>&1 >/dev/null || true)
if [[ "$err" == *"expected 1 arg"* ]]; then
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: arg-count error message includes 'expected 1 arg'"
else
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: arg-count error message missing or unexpected: '$err'"
fi

# --- ${1:-} guard (silent-failure-hunter H3 carryover) ---
echo ""
echo "--- set -u resilience ---"
# Caller under set -u passing an unset var: must not crash with
# "$1: unbound variable" before validation runs. The function returns
# (regex fails on empty string) rather than aborting.
rc=0
(
  set -u
  unset_var=""
  unset unset_var
  is_valid_name "${unset_var:-}"
) || rc=$?
assert_equal "$rc" "1" "set -u + unset var via :- → regex fails (return 1, not crash)"

test_summary
