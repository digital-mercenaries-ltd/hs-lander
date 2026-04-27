# 70-dns.sh — emits PREFLIGHT_DNS.
#
# Reads: tools_required_ok, project_pointer_ok, pointer_skip_reason, DOMAIN,
#        HUBSPOT_PORTAL_ID, HUBSPOT_REGION.
#
# Prefers dig (most precise). Falls back to host, then getent. If none is
# installed, reports skipped rather than falsely claiming the domain doesn't
# resolve — an adopter on a stripped-down Linux image shouldn't be blocked.
# If DOMAIN itself is unset (e.g. PROJECT_PROFILE was missing or incomplete),
# we have nothing to resolve — emit skipped rather than crashing under set -u.

if [[ "$tools_required_ok" -ne 1 ]]; then
  echo "PREFLIGHT_DNS=skipped (required tools missing)"
  return 0 2>/dev/null || exit 0
fi

if [[ "$project_pointer_ok" -ne 1 ]]; then
  echo "PREFLIGHT_DNS=skipped (${pointer_skip_reason})"
  return 0 2>/dev/null || exit 0
fi

if [[ -z "${DOMAIN:-}" ]]; then
  echo "PREFLIGHT_DNS=skipped (DOMAIN not set)"
  return 0 2>/dev/null || exit 0
fi

dns_result=""
dns_tool=""
if command -v dig >/dev/null 2>&1; then
  dns_tool="dig"
  dns_result=$(dig +short "$DOMAIN" 2>/dev/null || true)
elif command -v host >/dev/null 2>&1; then
  dns_tool="host"
  dns_result=$(host -W 2 "$DOMAIN" 2>/dev/null | awk '/has address/ {print $4; exit}' || true)
elif command -v getent >/dev/null 2>&1; then
  dns_tool="getent"
  dns_result=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)
fi

if [[ -z "$dns_tool" ]]; then
  echo "PREFLIGHT_DNS=skipped (no DNS tool available — install dig or host)"
elif [[ -n "$dns_result" ]]; then
  echo "PREFLIGHT_DNS=ok $DOMAIN resolves"
else
  # Compute the expected HubSpot CNAME target so the skill can tell the user
  # exactly which DNS record to create. If portal ID or region isn't known
  # (incomplete account profile), the expected string is best-effort.
  expected_cname="${HUBSPOT_PORTAL_ID:-<portal-id>}.group0.sites.hscoscdn-${HUBSPOT_REGION:-<region>}.net"
  echo "PREFLIGHT_DNS=missing $DOMAIN does not resolve (expected CNAME target: $expected_cname)"
  required_failed=1
fi
