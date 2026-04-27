#!/usr/bin/env bash
# keychain.sh — Read a token from the macOS Keychain with bash xtrace
# suppressed so `bash -x scripts/<caller>.sh` does not leak the value.
#
# Sourced by tf.sh, hs-curl.sh, upload.sh, preflight.sh.
#
# Why this lib exists:
# - Each of those four scripts had its own inline `security find-generic-
#   password` block. Inconsistent xtrace handling: only preflight.sh
#   suppressed xtrace around the call. tf.sh / hs-curl.sh / upload.sh
#   would leak the token to stderr if any operator ran them with `bash -x`
#   for debugging.
# - One shared helper, one consistent error message, one safe xtrace dance,
#   one place to encode the three-state outcome (found / empty / missing).
#
# Caller responsibility (NOT closed by this lib):
# - Once the token is in the caller's scope (e.g. `token=$(keychain_read ...)`),
#   any subsequent expansion that interpolates $token (curl headers,
#   environment exports, etc.) leaks under xtrace. Callers that hand the
#   token to multiple consumers should wrap the entire token-handling block
#   in `set +x` / restore. This lib protects only its own internals.

# keychain_read SERVICE
#
# Three-state outcome (codified in the return code so callers can
# distinguish them without a separate stdout-emptiness check):
#
#   rc 0 — token found and non-empty.   stdout: the token.
#   rc 1 — Keychain entry missing       (security command exited non-zero).
#                                       stderr: structured error + remediation.
#   rc 3 — Keychain entry exists but is empty (security exited 0 with blank
#                                       stdout). stderr: structured error
#                                       distinct from the missing case so the
#                                       caller can coach the operator to
#                                       repopulate the entry rather than add
#                                       a brand-new one.
#
# Why distinguish 1 vs 3: the failure mode and the right remediation differ.
# A missing entry needs `security add-generic-password ...`. An empty entry
# needs `security delete-generic-password ...` followed by add. Without the
# distinction, every consumer that uses `keychain_read || exit 1` accepts an
# empty token and fails later at the first HubSpot API call with a confusing
# 401, instead of a clear "your Keychain entry is blank" message up-front.
# preflight.sh's per-state PREFLIGHT_CREDENTIAL=missing|empty|found contract
# also depends on the distinction.
#
# Xtrace contract: if xtrace is on at entry, this function disables it for
# the duration of the security call (so the assigned token doesn't get
# logged via `+ token=value`) and restores it before returning. If xtrace
# was already off at entry, it stays off.
#
# Defensive arg handling: missing or extra args return rc 2 (matching
# is_valid_name's convention) so callers under `set -u` get a structured
# error instead of an "$1: unbound variable" crash.
keychain_read() {
  if (( $# != 1 )); then
    echo "keychain_read: expected 1 arg (service name), got $#" >&2
    return 2
  fi

  local service="${1:-}"
  local was_xtrace=0
  case "$-" in *x*) was_xtrace=1; set +x ;; esac

  # Capture both the token and the exit code on the same line so $? isn't
  # mutated by anything between security's exit and our read of it. The
  # `! cmd` / then-branch pattern is unsafe here: inside `then`, `$?`
  # reflects the negated test (always 0), not security's actual exit code.
  local token rc
  token=$(security find-generic-password -s "$service" -a "$USER" -w 2>/dev/null)
  rc=$?

  if [[ "$rc" -eq 0 && -n "$token" ]]; then
    printf '%s' "$token"
  elif [[ "$rc" -eq 0 ]]; then
    # security exited 0 but emitted no token — the entry exists with a
    # blank value. Different remediation path from "missing", so emit a
    # different structured error and return rc 3.
    rc=3
    echo "ERROR: Keychain entry '$service' exists but is empty. Replace it with:" >&2
    echo "  security delete-generic-password -s '$service' -a \"\$USER\"" >&2
    echo "  security add-generic-password    -s '$service' -a \"\$USER\" -w 'TOKEN'" >&2
  else
    echo "ERROR: Could not read Keychain entry '$service' (security exit $rc). Add it with:" >&2
    echo "  security add-generic-password -s '$service' -a \"\$USER\" -w 'TOKEN'" >&2
  fi

  # Capture rc into a separate name so a future maintainer who "tidies"
  # the trailing `return "$rc"` to a bare `return` still gets the right
  # value. `(( was_xtrace == 1 ))` mutates $? to 1 (false) when the
  # variable is 0, which would silently make a bare `return` return 1
  # even on success.
  local final_rc="$rc"
  (( was_xtrace == 1 )) && set -x
  return "$final_rc"
}
