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
# - One shared helper, one consistent error message, one safe xtrace dance.
#
# Caller responsibility (NOT closed by this lib):
# - Once the token is in the caller's scope (e.g. `token=$(keychain_read ...)`),
#   any subsequent expansion that interpolates $token (curl headers,
#   environment exports, etc.) leaks under xtrace. Callers that hand the
#   token to multiple consumers should wrap the entire token-handling block
#   in `set +x` / restore. This lib protects only its own internals.

# keychain_read SERVICE
#
# On success: prints the token on stdout, returns 0.
# On failure: prints a structured error to stderr, returns the security
#             command's exit code (1 for not-found is the common case).
#
# Xtrace contract: if xtrace is on at entry, this function disables it
# for the duration of the security call (so the assigned token doesn't
# get logged via `+ token=value`) and restores it before returning. If
# xtrace was already off at entry, it stays off.
keychain_read() {
  local service="$1"
  local was_xtrace=0
  case "$-" in *x*) was_xtrace=1; set +x ;; esac

  # Capture both the token and the exit code on the same line so $? isn't
  # mutated by anything between security's exit and our read of it. The
  # `! cmd` / then-branch pattern is unsafe here: inside `then`, `$?`
  # reflects the negated test (always 0), not security's actual exit code.
  local token rc
  token=$(security find-generic-password -s "$service" -a "$USER" -w 2>/dev/null)
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    printf '%s' "$token"
  else
    echo "ERROR: Could not read Keychain entry '$service' (security exit $rc). Add it with:" >&2
    echo "  security add-generic-password -s '$service' -a \"\$USER\" -w 'TOKEN'" >&2
  fi

  (( was_xtrace == 1 )) && set -x
  return "$rc"
}
