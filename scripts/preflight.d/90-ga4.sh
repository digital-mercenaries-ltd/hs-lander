#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 90-ga4.sh — emits PREFLIGHT_GA4.
#
# Reads: tools_required_ok, project_pointer_ok, pointer_skip_reason,
#        GA4_MEASUREMENT_ID.
#
# Non-blocking observability: warn when GA4_MEASUREMENT_ID is empty so the
# skill can prompt the operator before deploy. Empty is acceptable for some
# scenarios (e.g. an iframe consumer using its parent's GA4) so this never
# sets required_failed.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_GA4=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_GA4=skipped (${pointer_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ -z "${GA4_MEASUREMENT_ID:-}" ]]; then
  echo "PREFLIGHT_GA4=warn GA4_MEASUREMENT_ID is empty"
else
  echo "PREFLIGHT_GA4=ok"
fi
