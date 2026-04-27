#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154,SC2317
# 00-tools-required.sh — emits PREFLIGHT_TOOLS_REQUIRED.
# Sourced by scripts/preflight.sh; never invoked directly. The shebang above
# exists so static analysis can detect the bash dialect.
#
# Runs first so tool availability is reported even when config is unset.
# `command -v` is safe under xtrace — no secrets expanded here.
#
# When required tools are missing, sets `tools_required_ok=0` so every
# downstream check file falls through to its own skipped branch with the
# matching "(required tools missing)" reason. The runner relies on this
# cascade to keep the contract intact and exit 1.
#
# Owned shared variable: tools_required_ok (1 if all present, 0 otherwise).

_required_tools=(curl jq terraform npm)
_tools_missing=()
for _t in "${_required_tools[@]}"; do
  command -v "$_t" >/dev/null 2>&1 || _tools_missing+=("$_t")
done
if [[ ${#_tools_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_TOOLS_REQUIRED=ok"
  tools_required_ok=1
else
  _missing_csv=$(IFS=,; echo "${_tools_missing[*]}")
  echo "PREFLIGHT_TOOLS_REQUIRED=missing $_missing_csv"
  tools_required_ok=0
  required_failed=1
fi
unset _required_tools _tools_missing _t _missing_csv
