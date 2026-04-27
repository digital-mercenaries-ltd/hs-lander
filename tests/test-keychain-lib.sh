#!/usr/bin/env bash
# test-keychain-lib.sh — Unit tests for scripts/lib/keychain.sh.
# Local only, no real Keychain access — mocks `security` via PATH override.
#
# The xtrace-leak assertion is the test that justifies extracting this lib
# in the first place. Without it, the lib could silently regress to leaking
# the token under `bash -x` (the failure mode v1.7.0's preflight already
# guarded against inline; v1.9.0 lifts the guard into the lib so tf.sh,
# hs-curl.sh, upload.sh share the protection).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-keychain-lib.sh ==="

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Mock `security` ---
# Echoes the token iff -s matches the expected service. Standard pattern
# borrowed from test-preflight.sh.
MOCK_TOKEN="abc-123-mock-token-XYZ"
mkdir -p "$TMPDIR/mock-bin"
cat > "$TMPDIR/mock-bin/security" <<MOCK
#!/usr/bin/env bash
service=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -s) service="\$2"; shift 2 ;;
    *)  shift ;;
  esac
done
if [[ "\$service" == "test-service" ]]; then
  echo "$MOCK_TOKEN"
  exit 0
fi
exit 1
MOCK
chmod +x "$TMPDIR/mock-bin/security"

# Source the lib AFTER setting up mocks but BEFORE the PATH adjustment so
# that subshells called below pick up the right `security`.
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/keychain.sh"

PATH="$TMPDIR/mock-bin:$PATH"

# --- Happy path ---
echo ""
echo "--- Happy path ---"
rc=0
token=$(keychain_read "test-service") || rc=$?
assert_equal "$rc" "0" "rc 0 on successful read"
assert_equal "$token" "$MOCK_TOKEN" "token returned matches mock"

# --- Failure path ---
echo ""
echo "--- Failure path ---"
rc=0
token=$(keychain_read "wrong-service" 2>/dev/null) || rc=$?
assert_equal "$rc" "1" "rc 1 when security fails"
assert_equal "$token" "" "no token printed on failure"

# Error message structure
err=$(keychain_read "wrong-service" 2>&1 >/dev/null || true)
if [[ "$err" == *"Could not read Keychain entry 'wrong-service'"* ]]; then
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: error message names the service"
else
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: error message missing or unexpected: '$err'"
fi
if [[ "$err" == *"security add-generic-password"* ]]; then
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: error message hints at the add-password remediation"
else
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: error message missing remediation hint"
fi

# --- xtrace safety: lib's internal token assignment must not leak ---
#
# The lib's contract: while the security call runs and the lib's own
# `local token; token=$(security ...)` assignment happens, xtrace is
# suppressed so `bash -x` does not log `+ token=<value>` from the lib.
#
# Caller responsibility (NOT this test): if the caller does
# `outer=$(keychain_read ...)` with xtrace on, the OUTER assignment leaks.
# That's documented in keychain.sh's preamble. To assert what the lib
# actually promises, this test calls keychain_read in a context where its
# stdout goes to /dev/null and no caller variable captures the token. Any
# token bytes that show up in xtrace then are from the lib's internals
# only.
echo ""
echo "--- xtrace safety (lib's internals) ---"
cat > "$TMPDIR/xtrace-caller.sh" <<EOF
#!/usr/bin/env bash
set -x
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/keychain.sh"
keychain_read "test-service" >/dev/null
EOF
chmod +x "$TMPDIR/xtrace-caller.sh"

xtrace_log=$(PATH="$TMPDIR/mock-bin:$PATH" bash "$TMPDIR/xtrace-caller.sh" 2>&1 >/dev/null)
if [[ "$xtrace_log" == *"$MOCK_TOKEN"* ]]; then
  FAILURES=$((FAILURES + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: token leaked in xtrace output"
  echo "    log excerpt:"
  echo "$xtrace_log" | grep -F "$MOCK_TOKEN" | head -3 | sed 's/^/      /'
else
  PASSES=$((PASSES + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: token does not appear in xtrace output (lib's internals are suppressed)"
fi

# --- xtrace state restoration ---
# If caller had xtrace on, lib should restore it after the call.
# If caller had xtrace off, lib should leave it off.
echo ""
echo "--- xtrace state restoration ---"
cat > "$TMPDIR/xtrace-state.sh" <<EOF
#!/usr/bin/env bash
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/keychain.sh"
set -x
keychain_read "test-service" >/dev/null
case "\$-" in *x*) echo "STATE_AFTER=on" ;; *) echo "STATE_AFTER=off" ;; esac
EOF
chmod +x "$TMPDIR/xtrace-state.sh"

state_after=$(PATH="$TMPDIR/mock-bin:$PATH" bash "$TMPDIR/xtrace-state.sh" 2>/dev/null | grep STATE_AFTER)
assert_equal "$state_after" "STATE_AFTER=on" "xtrace state preserved (caller had it on, lib restored)"

cat > "$TMPDIR/xtrace-off.sh" <<EOF
#!/usr/bin/env bash
# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/keychain.sh"
# xtrace off
keychain_read "test-service" >/dev/null
case "\$-" in *x*) echo "STATE_AFTER=on" ;; *) echo "STATE_AFTER=off" ;; esac
EOF
chmod +x "$TMPDIR/xtrace-off.sh"

state_after=$(PATH="$TMPDIR/mock-bin:$PATH" bash "$TMPDIR/xtrace-off.sh" 2>/dev/null)
assert_equal "$state_after" "STATE_AFTER=off" "xtrace state preserved (caller had it off, lib left it off)"

test_summary
