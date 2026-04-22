#!/usr/bin/env bash
# watch.sh — Build once, then poll for src/ changes and re-deploy.
# Uses stat-based polling (no fswatch/inotify dependency).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
SRC_DIR="$PROJECT_DIR/src"
POLL_INTERVAL="${POLL_INTERVAL:-3}"

# Initial deploy
echo "=== Initial deploy ==="
bash "$SCRIPT_DIR/deploy.sh"

echo ""
echo "Watching $SRC_DIR for changes (every ${POLL_INTERVAL}s)..."
echo "Press Ctrl+C to stop."

# Get checksum of src/
_src_checksum() {
  if [[ "$(uname)" == "Darwin" ]]; then
    find "$SRC_DIR" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort | md5
  else
    find "$SRC_DIR" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort | md5sum
  fi
}

last_checksum=$(_src_checksum)

while true; do
  sleep "$POLL_INTERVAL"
  current_checksum=$(_src_checksum)
  if [[ "$current_checksum" != "$last_checksum" ]]; then
    echo ""
    echo "=== Change detected — re-deploying ==="
    bash "$SCRIPT_DIR/deploy.sh"
    last_checksum=$(_src_checksum)
    echo ""
    echo "Watching for changes..."
  fi
done
