#!/usr/bin/env bash
# test-source-vars.sh — Unit tests for scripts/lib/source-vars.sh.
# Local only, no network required.
#
# The lib provides two helpers with different strategies:
# - source_vars: subshell-source pattern; honours full shell semantics.
# - extract_var_via_parse: awk-parse pattern; literal values only, no
#   sourcing side effects.
#
# Both are exercised indirectly by test-preflight.sh and
# test-init-project-pointer.sh, but neither exercises the full input
# matrix (export-prefixed forms, single-quoted, malformed input, set -u
# edge cases). This dedicated unit test plugs the gap before Components
# 3 and 5 of the v1.9.0 master plan source the lib in new contexts.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-source-vars.sh ==="

# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/source-vars.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- source_vars: basic round-trip ---
echo ""
echo "--- source_vars: KEY=value extraction ---"
cat > "$TMPDIR/simple.sh" <<'CONF'
PROJECT_SLUG="acme"
DOMAIN="acme.example.com"
GA4_MEASUREMENT_ID="G-TEST123"
CONF

eval "$(source_vars "$TMPDIR/simple.sh" PROJECT_SLUG DOMAIN GA4_MEASUREMENT_ID)"
assert_equal "$PROJECT_SLUG" "acme" "source_vars: simple double-quoted value"
assert_equal "$DOMAIN" "acme.example.com" "source_vars: domain with dots"
assert_equal "$GA4_MEASUREMENT_ID" "G-TEST123" "source_vars: GA4 ID"
unset PROJECT_SLUG DOMAIN GA4_MEASUREMENT_ID

# --- source_vars: missing var → empty ---
echo ""
echo "--- source_vars: missing var ---"
eval "$(source_vars "$TMPDIR/simple.sh" UNDEFINED_VAR)"
assert_equal "${UNDEFINED_VAR-NOTSET}" "" "missing var emits empty string (not unset)"
unset UNDEFINED_VAR

# --- source_vars: nonexistent file ---
echo ""
echo "--- source_vars: nonexistent file ---"
# Caller's source `2>/dev/null || true` defence means a missing file does
# not abort the subshell; all requested vars come back empty. preflight
# relies on this for its separate ACCOUNT_PROFILE=missing reporting.
eval "$(source_vars "$TMPDIR/does-not-exist.sh" SOME_VAR)"
assert_equal "${SOME_VAR-NOTSET}" "" "nonexistent file: var emitted as empty"
unset SOME_VAR

# --- source_vars: values with shell metacharacters quoted via %q ---
echo ""
echo "--- source_vars: %q quoting preserves whitespace + metachars ---"
cat > "$TMPDIR/metachars.sh" <<'CONF'
WITH_SPACES="hello world"
WITH_DOLLAR="\$NOT_INTERPOLATED"
WITH_BACKTICK="literal\`backtick"
CONF

eval "$(source_vars "$TMPDIR/metachars.sh" WITH_SPACES WITH_DOLLAR WITH_BACKTICK)"
assert_equal "$WITH_SPACES" "hello world" "value with spaces round-trips"
assert_equal "$WITH_DOLLAR" '$NOT_INTERPOLATED' "value with literal dollar round-trips"
assert_equal "$WITH_BACKTICK" 'literal`backtick' "value with literal backtick round-trips"
unset WITH_SPACES WITH_DOLLAR WITH_BACKTICK

# --- source_vars: variable interpolation honoured by source semantics ---
echo ""
echo "--- source_vars: file-internal interpolation honoured ---"
cat > "$TMPDIR/interp.sh" <<'CONF'
ACCOUNT="dml"
PATH_PREFIX="/projects/${ACCOUNT}"
CONF

eval "$(source_vars "$TMPDIR/interp.sh" ACCOUNT PATH_PREFIX)"
assert_equal "$ACCOUNT" "dml" "interp: ACCOUNT extracted"
assert_equal "$PATH_PREFIX" "/projects/dml" "interp: PATH_PREFIX uses interpolated ACCOUNT"
unset ACCOUNT PATH_PREFIX

# --- source_vars: set-u in source file does NOT abort caller ---
# Documented residual edge case (preserved verbatim from preflight's
# original implementation): a sourced file that runs `set -u` AND
# references an unbound var aborts the subshell mid-source. The printf
# loop never runs, caller sees all vars as empty. This is intentional;
# the lib does not promise to recover from broken config files.
echo ""
echo "--- source_vars: set -u in source file (edge case) ---"
cat > "$TMPDIR/setu.sh" <<'CONF'
set -u
THIS_REFERENCE_ABORTS="$NOT_DEFINED"
NEVER_REACHED="should-not-appear"
CONF

# Should NOT crash the caller — but the subshell aborts mid-source, so the
# `printf` loop in source_vars doesn't run and stdout is empty. Caller's
# vars stay UNSET (not assigned to empty). preflight handles this by
# treating "all vars unset" as ACCOUNT_PROFILE=incomplete with the full
# field list — a misleading-but-non-crashing diagnosis. The test asserts:
#   1. no crash (the eval line below runs to completion)
#   2. requested vars stay unset (verifying the documented behaviour;
#      future code that assumes vars-set-to-empty would silently break)
unset NEVER_REACHED THIS_REFERENCE_ABORTS
eval "$(source_vars "$TMPDIR/setu.sh" NEVER_REACHED THIS_REFERENCE_ABORTS)" \
  || echo "  FAIL: caller crashed under set-u edge case"
assert_equal "${NEVER_REACHED-UNSET}" "UNSET" "set -u edge case: vars stay unset (subshell aborted before printf loop)"
# Lib survived; subsequent operations work.
ok_marker="post-eval-still-ok"
assert_equal "$ok_marker" "post-eval-still-ok" "set -u edge case: caller still runs after eval"

# --- extract_var_via_parse: double-quoted ---
echo ""
echo "--- extract_var_via_parse: form coverage ---"
cat > "$TMPDIR/forms.sh" <<'CONF'
DOUBLE_QUOTED="hello"
SINGLE_QUOTED='world'
UNQUOTED=barewords
EXPORTED_DOUBLE="exported"
LEADING_WS="   has-leading-spaces-around-=-line"
WITH_TRAILING_COMMENT=value-here # trailing comment
CONF

# Add the export-prefixed form on a separate line (heredoc with `export`)
echo 'export EXPORTED_PREFIX="prefixed"' >> "$TMPDIR/forms.sh"

assert_equal "$(extract_var_via_parse "$TMPDIR/forms.sh" DOUBLE_QUOTED)" "hello" \
  "extract: double-quoted"
assert_equal "$(extract_var_via_parse "$TMPDIR/forms.sh" SINGLE_QUOTED)" "world" \
  "extract: single-quoted"
assert_equal "$(extract_var_via_parse "$TMPDIR/forms.sh" UNQUOTED)" "barewords" \
  "extract: unquoted bareword"
assert_equal "$(extract_var_via_parse "$TMPDIR/forms.sh" EXPORTED_DOUBLE)" "exported" \
  "extract: leading 'export' optional"
assert_equal "$(extract_var_via_parse "$TMPDIR/forms.sh" EXPORTED_PREFIX)" "prefixed" \
  "extract: 'export VAR=...' form"
assert_equal "$(extract_var_via_parse "$TMPDIR/forms.sh" WITH_TRAILING_COMMENT)" "value-here" \
  "extract: trailing comment stripped from unquoted value"

# --- extract_var_via_parse: missing var → empty ---
echo ""
echo "--- extract_var_via_parse: missing var ---"
got=$(extract_var_via_parse "$TMPDIR/forms.sh" NOT_PRESENT)
assert_equal "$got" "" "missing var → empty stdout"

# --- extract_var_via_parse: nonexistent file ---
# Awk on a missing file emits a stderr error; we ignore it because the
# caller is responsible for file-existence reporting (preflight, etc.).
got=$(extract_var_via_parse "$TMPDIR/does-not-exist.sh" SOME_VAR 2>/dev/null || true)
assert_equal "$got" "" "nonexistent file → empty stdout (caller reports the absence)"

# --- extract_var_via_parse: variable interpolation NOT expanded ---
# Unlike source_vars, the awk parser only reads literal values. A pointer
# file that uses interpolation (HS_LANDER_ACCOUNT="$ACCOUNT") gets the
# literal $ACCOUNT back. preflight handles this by treating the resulting
# path as nonexistent and surfacing ACCOUNT_PROFILE=missing rather than
# silently following an interpolated path.
echo ""
echo "--- extract_var_via_parse: interpolation NOT expanded ---"
echo 'INTERPOLATED="$NOT_EXPANDED"' > "$TMPDIR/interp-extract.sh"
got=$(extract_var_via_parse "$TMPDIR/interp-extract.sh" INTERPOLATED)
assert_equal "$got" '$NOT_EXPANDED' "extract returns literal value (no shell expansion)"

test_summary
