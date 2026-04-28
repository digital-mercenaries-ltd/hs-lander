#!/usr/bin/env bash
# migrate-project.sh — Sanctioned helper for moving a project from one
# framework version to another. Replaces the manual sequence (edit ?ref=
# in terraform/main.tf, read CHANGELOG, add module-input wiring, etc.)
# with a structured, auditable plan-then-apply flow.
#
# Usage:
#   bash $FRAMEWORK_HOME/scripts/migrate-project.sh [<project-dir>] [<target-version>] [--apply]
#
# Defaults:
#   <project-dir>      $PWD
#   <target-version>   the framework's installed VERSION
#   --apply            absent → plan-only mode; present → write changes
#
# Output contract:
#   MIGRATE=noop pinned=<X>           — current matches target; nothing to do
#   MIGRATE=plan-only N steps         — plan-only run; N steps emitted
#   MIGRATE=ok pinned=<X> → <Y>       — apply succeeded
#   MIGRATE=error <reason>            — exit 1; reasons documented inline
#   MIGRATE_STEP=<n> <description>    — one per migration step
#
# Exit:    0 on noop / plan-only / ok; 1 on error.
set -euo pipefail

# Parse args. --apply is positional-agnostic; surrounding positionals
# default to $PWD and the framework's VERSION.
APPLY=0
project_dir=""
target_version=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *)
      if [[ -z "$project_dir" ]]; then
        project_dir="$arg"
      elif [[ -z "$target_version" ]]; then
        target_version="$arg"
      else
        echo "MIGRATE=error too-many-args (got: $*)" >&2
        exit 1
      fi
      ;;
  esac
done

project_dir="${project_dir:-$PWD}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
framework_home="$(dirname "$script_dir")"

# Default target = installed framework VERSION (the script-shipping
# framework, not the project's local copy).
if [[ -z "$target_version" ]]; then
  if [[ -f "$framework_home/VERSION" ]]; then
    target_version=$(tr -d '[:space:]' < "$framework_home/VERSION")
  else
    echo "MIGRATE=error framework-version-unknown (no VERSION file at $framework_home/VERSION; pass <target-version> explicitly)" >&2
    exit 1
  fi
fi

main_tf="$project_dir/terraform/main.tf"

if [[ ! -f "$main_tf" ]]; then
  echo "MIGRATE=error main-tf-missing $main_tf" >&2
  exit 1
fi

# Extract the project's current ?ref=. Same parser shape as
# preflight.d/05-version-drift.sh.
pinned_ref=$(awk '
  match($0, /\?ref=[^"[:space:]]+/) {
    print substr($0, RSTART + 5, RLENGTH - 5)
    exit
  }
' "$main_tf")

if [[ -z "$pinned_ref" ]]; then
  echo "MIGRATE=error ref-unparseable (no ?ref= found in $main_tf)" >&2
  exit 1
fi

# Strip leading 'v' for version comparison.
pinned_version="${pinned_ref#v}"

if [[ "$pinned_version" == "$target_version" ]]; then
  echo "MIGRATE=noop pinned=$pinned_version (already at target)"
  exit 0
fi

# Validate target appears in CHANGELOG.md. The presence check is cheap;
# refusing to migrate to an undocumented version catches typos.
if [[ -f "$framework_home/CHANGELOG.md" ]]; then
  if ! grep -qE "^## v${target_version}\b" "$framework_home/CHANGELOG.md"; then
    echo "MIGRATE=error unknown-target $target_version (no '## v$target_version' header in CHANGELOG.md)" >&2
    exit 1
  fi
fi

# Source the migration rules and run the chain.
# shellcheck source=/dev/null
source "$script_dir/lib/migration-rules.sh"

export _MIGRATE_PROJECT_DIR="$project_dir"
export _MIGRATE_APPLY="$APPLY"

# Run the chain — emits MIGRATE_STEP= lines as it goes. Captures the
# emitted lines into a tempfile so we can count them.
steps_log=$(mktemp)
trap 'rm -f "$steps_log"' EXIT
run_migration_chain "$pinned_version" "$target_version" | tee "$steps_log"

step_count=$(grep -c '^MIGRATE_STEP=' "$steps_log" || true)

if [[ "$APPLY" -eq 1 ]]; then
  echo "MIGRATE=ok pinned=$pinned_version → $target_version"
else
  echo "MIGRATE=plan-only $step_count steps (re-run with --apply to write changes)"
fi
