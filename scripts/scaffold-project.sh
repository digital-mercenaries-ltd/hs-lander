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
# Ships scaffold/src/ as working framework defaults (HubL templates, dark-mode
# CSS, welcome-email anatomy) so a fresh project can `npm run build && npm run
# deploy` immediately for dogfooding. The skill overwrites with brand-specific
# copy and brand tokens (__PRIMARY_ACCENT__, __BRAND_NAME__, __PRIMARY_CTA_URL__)
# during its workflow. Brand-specific content remains the skill's responsibility;
# scaffold defaults exist purely so plumbing tests work pre-skill.
set -euo pipefail

if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  echo "SCAFFOLD=error account and project names required (usage: scaffold-project.sh <account> <project>)" >&2
  exit 1
fi
account="$1"
project="$2"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
framework_home="$(dirname "$script_dir")"

# shellcheck source=lib/validate-name.sh
source "$script_dir/lib/validate-name.sh"

if ! is_valid_name "$account"; then
  echo "SCAFFOLD=error invalid-account-name '$account' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi
if ! is_valid_name "$project"; then
  echo "SCAFFOLD=error invalid-project-name '$project' (expected lowercase letters, digits, hyphens; must start with letter or digit)"
  exit 1
fi
project_dir="${HS_LANDER_PROJECT_DIR:-$PWD}"
accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
account_config="$accounts_dir/$account/config.sh"
project_profile="$accounts_dir/$account/$project.sh"

# 1. Validate account profile exists.
if [[ ! -f "$account_config" ]]; then
  echo "SCAFFOLD=error account-missing $account_config"
  exit 1
fi

# 2. Plan all copies. Gather source→dest pairs for scripts/ and scaffold/ in
#    one pass and check EVERY target is clear before touching the filesystem.
#    Two-pass design: a collision in the middle of copying would otherwise
#    leave the project in a partial-scaffold state that won't re-run cleanly.
dest_scripts="$project_dir/scripts"
script_sources=()
script_dests=()
for entry in "$framework_home/scripts"/*.sh; do
  [[ -f "$entry" ]] || continue
  script_sources+=("$entry")
  script_dests+=("$dest_scripts/$(basename "$entry")")
done

template_sources=()
template_dests=()
for entry in "$framework_home/scaffold"/*; do
  [[ -e "$entry" ]] || continue
  name=$(basename "$entry")
  # project.config.example.sh is superseded by the pointer init-project-pointer.sh
  # writes in step 5 — copying it would force a collision on every real project.
  [[ "$name" == "project.config.example.sh" ]] && continue
  template_sources+=("$entry")
  template_dests+=("$project_dir/$name")
done

version_src="$framework_home/VERSION"
version_dest="$project_dir/VERSION"

for dest in "${script_dests[@]}" "${template_dests[@]}" "$version_dest"; do
  if [[ -e "$dest" ]]; then
    echo "SCAFFOLD=error collision $dest"
    exit 1
  fi
done

# 3. Execute copies. All targets verified clear above, so any failure here is
#    a filesystem error, not a contract violation.
mkdir -p "$dest_scripts"
for i in "${!script_sources[@]}"; do
  cp "${script_sources[$i]}" "${script_dests[$i]}"
  chmod +x "${script_dests[$i]}"
done
echo "SCAFFOLD_SCRIPTS=copied $dest_scripts"

for i in "${!template_sources[@]}"; do
  cp -R "${template_sources[$i]}" "${template_dests[$i]}"
done
echo "SCAFFOLD_TEMPLATE=copied $project_dir"

# Copy VERSION so the project keeps a frozen record of which framework
# version it was scaffolded against. preflight.sh reads this from the
# project's root (../VERSION relative to preflight.sh), so the project's
# preflight always reports the version that shipped with the copied scripts.
if [[ -f "$version_src" ]]; then
  cp "$version_src" "$version_dest"
  echo "SCAFFOLD_VERSION=copied $version_dest"
else
  echo "SCAFFOLD_VERSION=skipped (framework VERSION file not found at $version_src)"
fi

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

# Hosting-mode plumbing (v1.5.0+). Defaults match custom-domain-primary mode.
# See docs/framework.md "Hosting modes" for how to configure each mode.
LANDING_SLUG=""
THANKYOU_SLUG="thank-you"

# Email + landing-page module flags (v1.7.0). All have module defaults that
# preserve v1.6.7 behaviour; uncomment + set when you want to override.
# EMAIL_PREVIEW_TEXT=""             # Inbox preview line; empty disables the preview_text widget
# AUTO_PUBLISH_WELCOME_EMAIL=true   # Skill flips to false on Starter portals (publish endpoint scope-gated)

# Email-sending domain (v1.8.1). Used both as the welcome email's reply-to
# header and by PREFLIGHT_EMAIL_DNS to probe the right SPF/DKIM/DMARC
# records when email sends from a subdomain (e.g. mail.example.com) that
# differs from DOMAIN. Empty falls back to DOMAIN.
EMAIL_REPLY_TO=""
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
