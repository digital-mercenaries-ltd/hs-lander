#!/usr/bin/env bash
# scaffold-project.sh — Populate the caller's project directory with
# framework scripts and scaffold templates, ensure the project profile
# exists at ~/.config/hs-lander/<account>/<project>.sh, and create the
# four-line sourcing-chain pointer.
#
# Usage:   bash scripts/scaffold-project.sh <account> <project>
#          (run from the target project directory, or export HS_LANDER_PROJECT_DIR)
# Output:
#   SCAFFOLD_SCRIPTS=copied <dest>
#   SCAFFOLD_TEMPLATE=copied <dest>
#   SCAFFOLD_PROJECT_PROFILE=created|present <path>
#   SCAFFOLD_POINTER=created|present <path>
#   SCAFFOLD=ok
# On failure: SCAFFOLD=error <reason>, exit 1.
#
# Does NOT generate brand-specific content (HTML, CSS, SVGs, brief.md).
# That remains the skill's responsibility.
set -euo pipefail

if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  echo "SCAFFOLD=error account and project names required (usage: scaffold-project.sh <account> <project>)" >&2
  exit 1
fi
account="$1"
project="$2"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
framework_home="$(dirname "$script_dir")"
project_dir="${HS_LANDER_PROJECT_DIR:-$PWD}"
accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
account_config="$accounts_dir/$account/config.sh"
project_profile="$accounts_dir/$account/$project.sh"

# 1. Validate account profile exists.
if [[ ! -f "$account_config" ]]; then
  echo "SCAFFOLD=error account-missing $account_config"
  exit 1
fi

# 2. Copy scripts/*.sh into project/scripts/ (no-clobber).
dest_scripts="$project_dir/scripts"
mkdir -p "$dest_scripts"
for entry in "$framework_home/scripts"/*.sh; do
  [[ -f "$entry" ]] || continue
  name=$(basename "$entry")
  if [[ -e "$dest_scripts/$name" ]]; then
    echo "SCAFFOLD=error collision $dest_scripts/$name"
    exit 1
  fi
  cp "$entry" "$dest_scripts/$name"
  chmod +x "$dest_scripts/$name"
done
echo "SCAFFOLD_SCRIPTS=copied $dest_scripts"

# 3. Copy scaffold/* into project dir (no-clobber). Skip project.config.sh here
#    — the pointer is handled by init-project-pointer.sh in step 5 and would
#    collide if the caller pre-created it.
for entry in "$framework_home/scaffold"/*; do
  [[ -e "$entry" ]] || continue
  name=$(basename "$entry")
  [[ "$name" == "project.config.example.sh" ]] && continue
  if [[ -e "$project_dir/$name" ]]; then
    echo "SCAFFOLD=error collision $project_dir/$name"
    exit 1
  fi
  cp -R "$entry" "$project_dir/$name"
done
echo "SCAFFOLD_TEMPLATE=copied $project_dir"

# 4. Ensure the project profile exists (stub if new).
if [[ -f "$project_profile" ]]; then
  echo "SCAFFOLD_PROJECT_PROFILE=present $project_profile"
else
  mkdir -p "$(dirname "$project_profile")"
  cat > "$project_profile" <<EOF
# Project profile for $project under account $account.
# Populated by hs-lander post-apply.sh for form IDs; other fields set by the skill or by hand.
PROJECT_SLUG="$project"
DOMAIN=""
DM_UPLOAD_PATH=""
GA4_MEASUREMENT_ID=""
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
EOF
  echo "SCAFFOLD_PROJECT_PROFILE=created $project_profile"
fi

# 5. Create the sourcing-chain pointer via init-project-pointer.sh so the
#    two scripts stay in lock-step on pointer format.
pointer_out=$(HS_LANDER_PROJECT_DIR="$project_dir" \
              HS_LANDER_CONFIG_DIR="$accounts_dir" \
              bash "$framework_home/scripts/init-project-pointer.sh" "$account" "$project") || {
  echo "SCAFFOLD=error $pointer_out"
  exit 1
}
# Translate INIT_POINTER= output into SCAFFOLD_POINTER= so the scaffold
# contract exposes a single naming convention.
printf '%s\n' "${pointer_out/INIT_POINTER=/SCAFFOLD_POINTER=}"

echo "SCAFFOLD=ok"
