#!/usr/bin/env bash
# upload.sh — Upload dist/ files to HubSpot Design Manager via CMS Source Code API.
# No HubSpot CLI or PAK needed — uses Service Key from Keychain.
#
# API v3 source-code environments: the path after /source-code/ must be one
# of {draft, published}. The older `developer` environment (used by legacy
# HubSpot CLI internals) is no longer valid and returns HTTP 415
# "Environment specified in path 'developer' is invalid". We publish directly
# (consumers rely on `npm run deploy` going live); a draft workflow could
# live on a future --draft flag if needed.
#
# v3 expects multipart/form-data with a 'file' part. Do NOT add an explicit
# Content-Type header — curl's auto-generated boundary header would be lost
# and the request silently transfers no body (HubSpot returns 2xx but the
# file never lands — "ghost uploads" where status looks fine and templates
# never appear in Design Manager).
set -euo pipefail

PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"

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

API_BASE="https://api.hubapi.com/cms/v3/source-code/published/content"

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
    -F "file=@${file}")

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
