#!/usr/bin/env bash
# init-project-pointer.sh — Idempotently create project.config.sh (the
# four-line sourcing chain) in the caller's project directory.
#
# Usage:   bash scripts/init-project-pointer.sh <account> <project>
#          (run from the project directory, or export HS_LANDER_PROJECT_DIR)
# Output:  INIT_POINTER=created|present|conflict <path>
# Exit:    0 on created or present, 1 on conflict or missing args.
#
# "conflict" means project.config.sh already exists but its HS_LANDER_ACCOUNT
# or HS_LANDER_PROJECT values differ from the requested ones. The script
# refuses to overwrite — the skill should surface the conflict to the user
# rather than silently clobber their pointer.
set -euo pipefail

if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  echo "INIT_POINTER=error account and project names required (usage: init-project-pointer.sh <account> <project>)" >&2
  exit 1
fi
account="$1"
project="$2"
project_dir="${HS_LANDER_PROJECT_DIR:-$PWD}"
pointer="$project_dir/project.config.sh"

# Extract a single VAR=value from a shell-syntax file without sourcing it.
# Matches: VAR="value" | VAR='value' | VAR=value | export-prefixed forms.
# Same extractor shape as preflight.sh (keeps behaviour consistent).
_extract_var() {
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

_write_pointer() {
  cat > "$pointer" <<EOF
HS_LANDER_ACCOUNT="$account"
HS_LANDER_PROJECT="$project"
# shellcheck source=/dev/null
source "\${HOME}/.config/hs-lander/\${HS_LANDER_ACCOUNT}/config.sh"
# shellcheck source=/dev/null
source "\${HOME}/.config/hs-lander/\${HS_LANDER_ACCOUNT}/\${HS_LANDER_PROJECT}.sh"
EOF
}

if [[ ! -f "$pointer" ]]; then
  mkdir -p "$project_dir"
  _write_pointer
  echo "INIT_POINTER=created $pointer"
  exit 0
fi

existing_account=$(_extract_var "$pointer" HS_LANDER_ACCOUNT)
existing_project=$(_extract_var "$pointer" HS_LANDER_PROJECT)

if [[ "$existing_account" == "$account" && "$existing_project" == "$project" ]]; then
  echo "INIT_POINTER=present $pointer"
  exit 0
fi

echo "INIT_POINTER=conflict $pointer (existing: account=$existing_account project=$existing_project)"
exit 1
