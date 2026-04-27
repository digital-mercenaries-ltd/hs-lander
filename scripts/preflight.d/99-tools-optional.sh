#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 99-tools-optional.sh — emits PREFLIGHT_TOOLS_OPTIONAL.
#
# Reads: tools_required_ok.
#
# Non-blocking observability for tools the framework's nice-to-have features
# rely on: pandoc/pdftotext (for the skill's brief ingestion) and git (for
# history operations). Missing optional tools never set required_failed —
# the warn line just informs the skill what features may be unavailable.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_TOOLS_OPTIONAL=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

_optional_tools=(pandoc pdftotext git)
_optional_missing=()
for _t in "${_optional_tools[@]}"; do
  command -v "$_t" >/dev/null 2>&1 || _optional_missing+=("$_t")
done
if [[ ${#_optional_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_TOOLS_OPTIONAL=ok"
else
  _missing_csv=$(IFS=,; echo "${_optional_missing[*]}")
  echo "PREFLIGHT_TOOLS_OPTIONAL=warn $_missing_csv"
fi
unset _optional_tools _optional_missing _t _missing_csv
