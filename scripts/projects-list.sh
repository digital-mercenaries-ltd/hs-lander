#!/usr/bin/env bash
# projects-list.sh — Discover which project profiles exist under a given
# account in ~/.config/hs-lander/<account>/.
#
# Usage:   bash scripts/projects-list.sh <account>
# Output:  PROJECTS=<csv>          (empty when the account has zero projects)
# Output (account missing):
#          ACCOUNT_STATUS=missing <path>
# Exit:    0 if account exists (even with zero projects), 1 if account missing
#          or args missing.
#
# A "project" is any *.sh file under the account directory, excluding
# config.sh (which is the account-level profile).
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "ACCOUNT_STATUS=error account name required (usage: projects-list.sh <account>)" >&2
  exit 1
fi
account="$1"

# shellcheck source=lib/validate-name.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/validate-name.sh"
if ! is_valid_name "$account"; then
  echo "ACCOUNT_STATUS=error invalid-account-name '$account' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi

accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
account_dir="$accounts_dir/$account"

if [[ ! -d "$account_dir" ]]; then
  echo "ACCOUNT_STATUS=missing $account_dir"
  exit 1
fi

projects=()
for f in "$account_dir"/*.sh; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f" .sh)
  [[ "$name" == "config" ]] && continue
  projects+=("$name")
done

IFS=,
echo "PROJECTS=${projects[*]:-}"
