#!/usr/bin/env bash
# deploy.sh — Build then upload to HubSpot Design Manager.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Build ==="
bash "$SCRIPT_DIR/build.sh"

echo ""
echo "=== Upload ==="
bash "$SCRIPT_DIR/upload.sh"

echo ""
echo "Deploy complete."
