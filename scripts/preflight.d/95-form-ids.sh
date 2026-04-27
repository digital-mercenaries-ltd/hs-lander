#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 95-form-ids.sh — emits PREFLIGHT_FORM_IDS.
#
# Reads: tools_required_ok, project_pointer_ok, pointer_skip_reason,
#        CAPTURE_FORM_ID.
#
# Non-blocking observability: warn when CAPTURE_FORM_ID is empty (expected
# before the first deploy — the form ID is populated by post-apply.sh after
# the first terraform apply creates the form). Never sets required_failed.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_FORM_IDS=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_FORM_IDS=skipped (${pointer_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ -z "${CAPTURE_FORM_ID:-}" ]]; then
  echo "PREFLIGHT_FORM_IDS=warn CAPTURE_FORM_ID is empty (expected before first deploy)"
else
  echo "PREFLIGHT_FORM_IDS=ok"
fi
