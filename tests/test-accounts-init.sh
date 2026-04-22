#!/usr/bin/env bash
# test-accounts-init.sh — Validates scripts/accounts-init.sh creates account
# profiles safely: correct content, refuses overwrite, rejects invalid input.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_DIR/tests/fixtures/test-helper.sh"

echo "=== test-accounts-init.sh ==="

SCRIPT="$REPO_DIR/scripts/accounts-init.sh"
assert_file_exists "$SCRIPT" "scripts/accounts-init.sh exists"

run() {
  local cfg="$1"; shift
  local log="$1"; shift
  HS_LANDER_CONFIG_DIR="$cfg" bash "$SCRIPT" "$@" >"$log" 2>&1
  echo "$?"
}

# --- Scenario 1: fresh create ---
echo ""
echo "--- Scenario 1: fresh create ---"
TMP1=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}"' EXIT
exit1=$(run "$TMP1" "$TMP1/log" dml 147959629 eu1 "*.example.com" dml-hubspot-access-token || true)
assert_equal "$exit1" "0" "exit 0 on fresh create"
assert_file_contains "$TMP1/log" "^ACCOUNTS_INIT=created" "created line emitted"
assert_file_exists "$TMP1/dml/config.sh" "config.sh written"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_PORTAL_ID="147959629"$' "portal id written"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_REGION="eu1"$' "region written"
assert_file_contains "$TMP1/dml/config.sh" '^DOMAIN_PATTERN="\*\.example\.com"$' "domain pattern written"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_TOKEN_KEYCHAIN_SERVICE="dml-hubspot-access-token"$' "service name written"
# v1.5.0: subscription + office-location lines always emitted (empty when
# the optional trailing args are omitted). Keeps schema uniform across
# account configs — readers never need to branch on field presence.
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_SUBSCRIPTION_ID=""$' "subscription id present as empty on 5-arg create"
assert_file_contains "$TMP1/dml/config.sh" '^HUBSPOT_OFFICE_LOCATION_ID=""$' "office location id present as empty on 5-arg create"

# Round-trip: sourcing the written file yields the original values.
(
  # shellcheck source=/dev/null
  source "$TMP1/dml/config.sh"
  [[ "$HUBSPOT_PORTAL_ID" == "147959629" ]] || exit 10
  [[ "$HUBSPOT_REGION" == "eu1" ]] || exit 11
  [[ "$DOMAIN_PATTERN" == "*.example.com" ]] || exit 12
  [[ "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" == "dml-hubspot-access-token" ]] || exit 13
) && rt=ok || rt=fail
assert_equal "$rt" "ok" "sourced values round-trip (including the * in DOMAIN_PATTERN)"

# --- Scenario 2: overwrite refused ---
echo ""
echo "--- Scenario 2: existing profile → conflict ---"
TMP2="$TMP1" # re-use dir to keep the just-created profile
before=$(cat "$TMP2/dml/config.sh")
exit2=$(run "$TMP2" "$TMP2/log2" dml 99999999 na1 "*.other.com" different-service || true)
assert_equal "$exit2" "1" "exit 1 on conflict"
assert_file_contains "$TMP2/log2" "^ACCOUNTS_INIT=conflict" "conflict line emitted"
after=$(cat "$TMP2/dml/config.sh")
assert_equal "$after" "$before" "existing profile untouched on conflict"

# --- Scenario 3: invalid account name (slash) ---
echo ""
echo "--- Scenario 3: invalid account name ---"
TMP3=$(mktemp -d)
exit3=$(run "$TMP3" "$TMP3/log" "bad/name" 1 eu1 "" svc || true)
assert_equal "$exit3" "1" "exit 1 on invalid account name"
assert_file_contains "$TMP3/log" "^ACCOUNTS_INIT=error invalid-account-name" "invalid-account-name reported"

# --- Scenario 4: invalid region ---
echo ""
echo "--- Scenario 4: invalid region ---"
TMP4=$(mktemp -d)
exit4=$(run "$TMP4" "$TMP4/log" dml 1 us1 "" svc || true)
assert_equal "$exit4" "1" "exit 1 on invalid region"
assert_file_contains "$TMP4/log" "^ACCOUNTS_INIT=error invalid-region" "invalid-region reported"

# --- Scenario 5: empty DOMAIN_PATTERN accepted ---
echo ""
echo "--- Scenario 5: empty DOMAIN_PATTERN accepted ---"
TMP5=$(mktemp -d)
exit5=$(run "$TMP5" "$TMP5/log" dml 1 eu1 "" svc || true)
assert_equal "$exit5" "0" "exit 0 when DOMAIN_PATTERN is empty"
assert_file_contains "$TMP5/dml/config.sh" '^DOMAIN_PATTERN=""$' "empty domain pattern written as empty string"

# --- Scenario 6: wrong arg count ---
echo ""
echo "--- Scenario 6: wrong arg count ---"
TMP6=$(mktemp -d)
HS_LANDER_CONFIG_DIR="$TMP6" bash "$SCRIPT" dml 1 eu1 >"$TMP6/log" 2>&1 && exit6=0 || exit6=$?
assert_equal "$exit6" "1" "exit 1 when arg count wrong"

# --- Scenario 7: banned characters in field values are rejected ---
# Prevents writing values that won't round-trip through source (injected
# command substitution, broken canonical quoting, etc.).
echo ""
echo "--- Scenario 7: banned chars rejected ---"
TMP7=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}"' EXIT

# Banned char in domain_pattern (double-quote)
HS_LANDER_CONFIG_DIR="$TMP7" bash "$SCRIPT" dml 1 eu1 'has"quote' svc >"$TMP7/log-quote" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on double-quote in domain_pattern"
assert_file_contains "$TMP7/log-quote" "^ACCOUNTS_INIT=error invalid-value" "invalid-value reported for quote"

# Banned char in token-service (dollar)
HS_LANDER_CONFIG_DIR="$TMP7" bash "$SCRIPT" dml 1 eu1 "" 'svc$injected' >"$TMP7/log-dollar" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on dollar in token-service"

# Banned char in portal-id (backtick)
HS_LANDER_CONFIG_DIR="$TMP7" bash "$SCRIPT" dml 'bad`tick`' eu1 "" svc >"$TMP7/log-tick" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on backtick in portal-id"

# File must not exist after any of the rejections (account-dir may be created
# by a prior mkdir in a future refactor — check just that the config.sh is absent)
if [[ -f "$TMP7/dml/config.sh" ]]; then
  assert_equal "present" "must-NOT-exist" "no config.sh created after rejection"
else
  assert_equal "1" "1" "no config.sh written on banned-char rejection"
fi

# --- Scenario 8: 7-arg variant writes subscription + office-location ---
echo ""
echo "--- Scenario 8: 7-arg variant populates subscription + office-location ---"
TMP8=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}" "${TMP8:-}" "${TMP9:-}" "${TMP10:-}"' EXIT
exit8=$(run "$TMP8" "$TMP8/log" acme 147959629 eu1 "*.acme.com" acme-svc 2269639338 375327044798 || true)
assert_equal "$exit8" "0" "exit 0 on 7-arg create"
assert_file_contains "$TMP8/acme/config.sh" '^HUBSPOT_SUBSCRIPTION_ID="2269639338"$' "subscription id populated"
assert_file_contains "$TMP8/acme/config.sh" '^HUBSPOT_OFFICE_LOCATION_ID="375327044798"$' "office location id populated"

# --- Scenario 9: 6-arg variant (subscription set, office-location empty) ---
echo ""
echo "--- Scenario 9: 6-arg variant populates only subscription ---"
TMP9=$(mktemp -d)
exit9=$(run "$TMP9" "$TMP9/log" acme 147959629 eu1 "*.acme.com" acme-svc 2269639338 || true)
assert_equal "$exit9" "0" "exit 0 on 6-arg create"
assert_file_contains "$TMP9/acme/config.sh" '^HUBSPOT_SUBSCRIPTION_ID="2269639338"$' "subscription id populated on 6-arg"
assert_file_contains "$TMP9/acme/config.sh" '^HUBSPOT_OFFICE_LOCATION_ID=""$' "office location empty when 7th arg omitted"

# --- Scenario 10: too many args rejected ---
echo ""
echo "--- Scenario 10: 8 args rejected ---"
TMP10=$(mktemp -d)
HS_LANDER_CONFIG_DIR="$TMP10" bash "$SCRIPT" acme 1 eu1 "" svc sub office extra >"$TMP10/log" 2>&1 && exit10=0 || exit10=$?
assert_equal "$exit10" "1" "exit 1 on 8-arg call"
assert_file_contains "$TMP10/log" "^ACCOUNTS_INIT=error usage:" "usage error reported"

# --- Scenario 11: banned chars in subscription/office args ---
echo ""
echo "--- Scenario 11: banned chars in subscription/office-location rejected ---"
TMP11=$(mktemp -d)
trap 'rm -rf "$TMP1" "${TMP2:-}" "${TMP3:-}" "${TMP4:-}" "${TMP5:-}" "${TMP6:-}" "${TMP7:-}" "${TMP8:-}" "${TMP9:-}" "${TMP10:-}" "${TMP11:-}"' EXIT

HS_LANDER_CONFIG_DIR="$TMP11" bash "$SCRIPT" acme 1 eu1 "" svc 'sub$inj' "" >"$TMP11/log-sub" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on dollar in subscription-id"
assert_file_contains "$TMP11/log-sub" "^ACCOUNTS_INIT=error invalid-value subscription_id" "invalid-value reported for subscription_id"

HS_LANDER_CONFIG_DIR="$TMP11" bash "$SCRIPT" acme 1 eu1 "" svc "" 'off`tick`' >"$TMP11/log-off" 2>&1 && r=0 || r=$?
assert_equal "$r" "1" "exit 1 on backtick in office-location-id"

if [[ -f "$TMP11/acme/config.sh" ]]; then
  assert_equal "present" "must-NOT-exist" "no config.sh created after banned-char rejection"
else
  assert_equal "1" "1" "no config.sh written on banned-char rejection"
fi

test_summary
