#!/usr/bin/env bash
# upload.sh — Upload dist/ files to HubSpot Design Manager via CMS Source Code API.
# No HubSpot CLI or PAK needed — uses Service Key from Keychain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$PROJECT_DIR/project.config.sh"

DIST_DIR="$PROJECT_DIR/dist"

if [[ ! -d "$DIST_DIR" ]]; then
  echo "ERROR: dist/ not found. Run build.sh first." >&2
  exit 1
fi

# Read token from Keychain using the service name from the account config.
: "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE:?HUBSPOT_TOKEN_KEYCHAIN_SERVICE must be set in the account config}"
HUBSPOT_TOKEN=$(security find-generic-password \
  -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" \
  -a "$USER" -w 2>/dev/null) || {
  echo "ERROR: Could not read Keychain entry '$HUBSPOT_TOKEN_KEYCHAIN_SERVICE'." >&2
  exit 1
}

API_BASE="https://api.hubapi.com/cms/v3/source-code/developer/content"

# Upload each file in dist/.
# Use process substitution (not pipe) so counters stay in the parent shell.
uploaded=0
failed=0

while IFS= read -r file; do
  relative_path="${file#"$DIST_DIR"/}"
  dm_path="${DM_UPLOAD_PATH}/${relative_path}"

  echo -n "  Uploading ${dm_path}... "

  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "${API_BASE}${dm_path}" \
    -H "Authorization: Bearer ${HUBSPOT_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${file}")

  if [[ "$http_code" =~ ^2 ]]; then
    echo "OK ($http_code)"
    uploaded=$((uploaded + 1))
  else
    echo "FAILED ($http_code)"
    failed=$((failed + 1))
  fi
done < <(find "$DIST_DIR" -type f)

echo ""
echo "Upload complete: $uploaded succeeded, $failed failed"
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
