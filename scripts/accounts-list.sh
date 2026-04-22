#!/usr/bin/env bash
# accounts-list.sh — Discover which account profiles exist under
# ~/.config/hs-lander/. Outputs a single structured line so the skill can
# parse without guessing.
#
# Usage:   bash scripts/accounts-list.sh
# Output:  ACCOUNTS=<csv>         (empty when no accounts are configured)
# Exit:    0 always — absence of accounts is valid state, not an error.
#
# An "account" is a subdirectory of ~/.config/hs-lander/ that contains a
# config.sh file. Orphan directories (no config.sh) are ignored.
set -euo pipefail

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"

accounts=()
if [[ -d "$accounts_dir" ]]; then
  for d in "$accounts_dir"/*/; do
    [[ -d "$d" && -f "${d}config.sh" ]] || continue
    accounts+=("$(basename "$d")")
  done
fi

IFS=,
echo "ACCOUNTS=${accounts[*]:-}"
