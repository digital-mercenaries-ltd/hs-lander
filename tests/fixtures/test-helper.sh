# tests/fixtures/test-helper.sh
# Minimal test assertion library for hs-lander shell tests.
# Source this at the top of each test file.

PASSES=0
FAILURES=0
TESTS=0

assert_equal() {
  local actual="$1" expected="$2" message="${3:-assert_equal}"
  TESTS=$((TESTS + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_file_exists() {
  local path="$1" message="${2:-file exists: $1}"
  TESTS=$((TESTS + 1))
  if [[ -f "$path" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (file not found)"
  fi
}

assert_dir_exists() {
  local path="$1" message="${2:-dir exists: $1}"
  TESTS=$((TESTS + 1))
  if [[ -d "$path" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (directory not found)"
  fi
}

assert_file_contains() {
  local path="$1" pattern="$2" message="${3:-file contains pattern}"
  TESTS=$((TESTS + 1))
  if grep -q "$pattern" "$path" 2>/dev/null; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (pattern '$pattern' not found in $path)"
  fi
}

assert_file_not_contains() {
  local path="$1" pattern="$2" message="${3:-file does not contain pattern}"
  TESTS=$((TESTS + 1))
  if ! grep -q "$pattern" "$path" 2>/dev/null; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (pattern '$pattern' found in $path but should not be)"
  fi
}

assert_no_tokens() {
  local dir="$1" message="${2:-no __TOKENS__ remain in $1}"
  TESTS=$((TESTS + 1))
  local found
  found=$(grep -r '__[A-Z_]*__' "$dir" 2>/dev/null || true)
  if [[ -z "$found" ]]; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message"
    echo "    tokens found:"
    echo "$found" | head -10
  fi
}

assert_command_succeeds() {
  local message="${1:-command succeeds}"
  shift
  TESTS=$((TESTS + 1))
  if "$@" >/dev/null 2>&1; then
    PASSES=$((PASSES + 1))
    echo "  PASS: $message"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: $message (exit code $?)"
  fi
}

test_summary() {
  echo ""
  echo "========================================="
  echo "Results: $PASSES passed, $FAILURES failed, $TESTS total"
  echo "========================================="
  if [[ "$FAILURES" -gt 0 ]]; then
    exit 1
  fi
}
