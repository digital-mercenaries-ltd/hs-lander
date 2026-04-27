# 10-project-pointer.sh — emits PREFLIGHT_PROJECT_POINTER.
#
# Reads: tools_required_ok.
# Writes: project_pointer_ok, pointer_skip_reason, HS_LANDER_ACCOUNT,
#         HS_LANDER_PROJECT.
#
# Validates that $PROJECT_DIR/project.config.sh exists and that the pointer
# names both an account and a project. Without this we cannot resolve the
# account / project profile paths, so PROJECT_POINTER gates every config-
# derived check below. On failure, sets pointer_skip_reason to the matching
# downstream reason text ("required tools missing" / "no project pointer" /
# "pointer incomplete") so subsequent files emit a precise skipped reason.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_PROJECT_POINTER=skipped (required tools missing)"
  project_pointer_ok=0
  pointer_skip_reason="required tools missing"
  return 0 2>/dev/null || exit 0
fi

if [[ ! -f "$PROJECT_DIR/project.config.sh" ]]; then
  echo "PREFLIGHT_PROJECT_POINTER=missing project.config.sh not found in $PROJECT_DIR"
  project_pointer_ok=0
  pointer_skip_reason="no project pointer"
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

# Extract HS_LANDER_ACCOUNT and HS_LANDER_PROJECT from the pointer WITHOUT
# sourcing it (sourcing the pointer would fire its cascading `source` calls,
# which may reference account/project config files that don't exist yet).
# Uses the lib's `extract_var_via_parse` helper.
#
# Form coverage from extract_var_via_parse: double-quoted, single-quoted,
# unquoted (up to whitespace or #), optional `export` prefix, trailing
# `# comment` stripped from unquoted values. Values depending on shell
# expansion (e.g. VAR="$OTHER") come back as the literal string — the
# downstream ACCOUNT_PROFILE / PROJECT_PROFILE checks then treat the
# resulting path as nonexistent and surface =missing rather than silently
# proceeding.
for _v in HS_LANDER_ACCOUNT HS_LANDER_PROJECT; do
  eval "$(printf '%s=%q' "$_v" "$(extract_var_via_parse "$PROJECT_DIR/project.config.sh" "$_v")")"
done
unset _v

if [[ -z "${HS_LANDER_ACCOUNT:-}" || -z "${HS_LANDER_PROJECT:-}" ]]; then
  pointer_missing=()
  [[ -z "${HS_LANDER_ACCOUNT:-}" ]] && pointer_missing+=("HS_LANDER_ACCOUNT")
  [[ -z "${HS_LANDER_PROJECT:-}" ]] && pointer_missing+=("HS_LANDER_PROJECT")
  echo "PREFLIGHT_PROJECT_POINTER=incomplete ${pointer_missing[*]}"
  project_pointer_ok=0
  pointer_skip_reason="pointer incomplete"
  required_failed=1
  return 0 2>/dev/null || exit 0
fi

echo "PREFLIGHT_PROJECT_POINTER=ok"
project_pointer_ok=1
