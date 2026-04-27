#!/usr/bin/env bash
# backup-file.sh — Timestamped backup of a single file with LRU retention.
#
# Usage:    bash scripts/backup-file.sh <source-path> <backup-dir>
# Output:   BACKUP=skip|ok|error <detail>
# Exit:     0 on skip / ok; 1 on error
#
# Behaviour:
# - If <source-path> does not exist, exit 0 with BACKUP=skip (nothing to back up).
# - Otherwise creates <backup-dir>, writes a timestamped copy preserving mtime,
#   and trims old backups so only the N most recent matching files remain
#   (default 20; override with HS_LANDER_BACKUP_KEEP).
#
# Used by tf.sh (state pre-apply backup) and post-apply.sh (project-profile
# pre-mutation backup). Standalone — no other lib helpers required.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "BACKUP=error usage: backup-file.sh <source-path> <backup-dir>" >&2
  exit 1
fi

src="$1"
backup_dir="$2"
keep="${HS_LANDER_BACKUP_KEEP:-20}"

if [[ ! -f "$src" ]]; then
  echo "BACKUP=skip $src does not exist"
  exit 0
fi

mkdir -p "$backup_dir"

# ISO-8601 UTC + nanoseconds where supported (GNU date), seconds + PID
# elsewhere (BSD date on macOS doesn't support %N — falls through to PID).
ts="$(date -u +%Y-%m-%dT%H-%M-%SZ.%N 2>/dev/null || true)"
if [[ -z "$ts" || "$ts" == *"%N"* || "$ts" == *.N ]]; then
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ).$$"
fi

dest="$backup_dir/$(basename "$src").$ts"

if ! cp -p "$src" "$dest" 2>/dev/null; then
  echo "BACKUP=error cp failed: $src -> $dest" >&2
  exit 1
fi

# Trim to $keep most recent matching backups. Filenames are controlled
# (timestamp-suffixed) so ls/grep/tail is safe here. cp -p preserved mtime
# above so ls -t orders by backup creation time.
pattern="$(basename "$src")."
# shellcheck disable=SC2012
ls -1t "$backup_dir" 2>/dev/null \
  | grep -F "$pattern" \
  | tail -n +$((keep + 1)) \
  | while IFS= read -r old; do
      rm -f "$backup_dir/$old"
    done

echo "BACKUP=ok $dest"
