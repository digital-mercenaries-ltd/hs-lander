#!/usr/bin/env bash
# upgrade-project-scripts.sh — Refresh project-local scripts/ from the
# framework's scripts/ directory. Run after bumping ?ref=vX.Y.Z in
# terraform/main.tf and before `npm run setup` / `npm run deploy`.
#
# Usage:
#   bash $FRAMEWORK_HOME/scripts/upgrade-project-scripts.sh [/path/to/project]
#
# If the project path is omitted, uses $PWD.
#
# Behaviour:
# - Backs up existing scripts/ to scripts.bak.<timestamp>/ before touching
#   anything. Restore by `mv scripts scripts.failed && mv scripts.bak.<ts> scripts`.
# - Replaces every *.sh file in the project's scripts/ with the framework's
#   current version. Preserves any non-script files in scripts/ (rare today,
#   but possible — e.g. a project README).
# - Refreshes the lib/ subdirectory in lockstep (added in v1.7.0 for
#   tier-classify.sh; future framework versions may add more lib/ entries).
# - Idempotent — safe to re-run.
#
# This replaces the manual `rm -rf scripts && cp -r $FRAMEWORK_HOME/scripts ...`
# dance that's been required since v1.5.0 (R9 in docs/roadmap.md).

set -euo pipefail

PROJECT_DIR="${1:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
FRAMEWORK_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$PROJECT_DIR/scripts" ]]; then
  echo "ERROR: $PROJECT_DIR/scripts does not exist. Is this a hs-lander project?" >&2
  exit 1
fi

if [[ "$FRAMEWORK_SCRIPTS_DIR" == "$PROJECT_DIR/scripts" ]]; then
  echo "ERROR: source and target scripts/ are the same path ($FRAMEWORK_SCRIPTS_DIR)." >&2
  echo "       Run this script from the framework install, against a project directory:" >&2
  echo "       bash \"\$FRAMEWORK_HOME/scripts/upgrade-project-scripts.sh\" /path/to/project" >&2
  exit 1
fi

echo "Refreshing scripts in $PROJECT_DIR/scripts from $FRAMEWORK_SCRIPTS_DIR"

BACKUP_DIR="$PROJECT_DIR/scripts.bak.$(date +%Y%m%d-%H%M%S)"
cp -r "$PROJECT_DIR/scripts" "$BACKUP_DIR"
echo "  Backup: $BACKUP_DIR"

# Replace top-level *.sh files. Don't delete scripts/ itself in case it
# contains non-script files (rare today, but the contract is "refresh,
# not nuke").
rm -f "$PROJECT_DIR"/scripts/*.sh
cp "$FRAMEWORK_SCRIPTS_DIR"/*.sh "$PROJECT_DIR/scripts/"
chmod +x "$PROJECT_DIR"/scripts/*.sh

# Refresh lib/ subdirectory if the framework has one. Framework v1.7.0
# introduced scripts/lib/ for tier-classify.sh; future versions may add
# more entries. Mirror the framework's full lib/ tree.
if [[ -d "$FRAMEWORK_SCRIPTS_DIR/lib" ]]; then
  rm -rf "$PROJECT_DIR/scripts/lib"
  cp -r "$FRAMEWORK_SCRIPTS_DIR/lib" "$PROJECT_DIR/scripts/lib"
fi

echo "Done."
echo "Next steps:"
echo "  bash scripts/tf.sh init -upgrade"
echo "  bash scripts/tf.sh plan"
echo "  npm run setup     # if plan looks correct"
echo "If anything breaks, restore from $BACKUP_DIR."
