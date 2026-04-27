#!/usr/bin/env bash
# source-vars.sh — extract variable values from shell-syntax config files
# without contaminating the caller's shell.
#
# Two helpers, two strategies:
#
# - `source_vars FILE VAR [VAR ...]` runs the file inside a subshell with
#   `set +eu` defence and emits one `VAR=quoted-value` line per requested
#   var. The caller `eval`s the output. Handles complex configs that use
#   variable interpolation, conditionals, etc. (the realistic shape of a
#   hand-edited account profile).
#
# - `extract_var_via_parse FILE VAR` uses `awk` to read the literal value
#   of VAR without sourcing the file. Handles simple `KEY=value` (with or
#   without quotes, with or without `export`) but does not honour shell
#   semantics. Use when the file's contents are framework-controlled
#   (e.g. project.config.sh sourcing pointer written by init-project-
#   pointer.sh) and parsing is preferred for safety / speed.
#
# Sourced by preflight.sh, init-project-pointer.sh, and any future script
# that needs to read config-file values without sourcing-side-effects.

# source_vars FILE VAR [VAR ...]
# Emits `VAR="value"` lines suitable for `eval` consumption.
#
# Residual edge case (preserved from preflight.sh's original implementation):
# If the sourced file itself runs `set -u` AND references an unbound
# variable during source execution, bash exits the subshell immediately;
# the loop below never runs and source_vars returns empty stdout. The
# caller then sees all requested vars as empty. Scaffold-shipped configs
# don't use set -u so this is a theoretical concern for hand-edited
# configs; the `set +u` below is defence-in-depth for the narrower case
# where the file enables set -u but doesn't reference anything unbound.
source_vars() {
  local path="$1"; shift
  (
    set +eu
    # shellcheck source=/dev/null
    source "$path" 2>/dev/null || true
    set +u
    local v
    for v in "$@"; do
      printf '%s=%q\n' "$v" "${!v:-}"
    done
  )
}

# extract_var_via_parse FILE VAR
# Emits the literal value of VAR (unquoted) on stdout, or nothing if VAR
# is not assigned in the file. Handles:
#   VAR="value"
#   VAR='value'
#   VAR=value
#   export VAR=...
extract_var_via_parse() {
  local path="$1" var="$2"
  awk -v V="$var" '
    match($0, "^[[:space:]]*(export[[:space:]]+)?"V"=") {
      rest = substr($0, RSTART + RLENGTH)
      if (rest ~ /^"/) {
        if (match(rest, /^"[^"]*"/)) { print substr(rest, 2, RLENGTH - 2); exit }
      } else if (rest ~ /^\x27/) {
        if (match(rest, /^\x27[^\x27]*\x27/)) { print substr(rest, 2, RLENGTH - 2); exit }
      } else {
        if (match(rest, /^[^[:space:]#]+/)) { print substr(rest, 1, RLENGTH); exit }
      }
    }
  ' "$path"
}
