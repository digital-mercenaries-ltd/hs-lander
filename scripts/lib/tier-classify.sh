#!/usr/bin/env bash
# tier-classify.sh — classify a HubSpot portal's tier from
# /account-info/v3/details JSON. Sourced by preflight.sh.
#
# TODO (verify across portals): the accountType → tier-label mapping below
# is informed-guess. v1.7.0 ships with these defaults; an adopter who probes
# real portals at each tier should update this table to match observed
# values. See docs/superpowers/plans/2026-04-26-v1.7.0-... Prerequisite A.
#
# Probable values (confirm and patch as portals are sampled):
#   "STANDARD"     → starter
#   "PROFESSIONAL" → pro
#   "ENTERPRISE"   → ent
#   anything else  → unknown (preflight emits unknown; consumer treats
#                   conservatively, default to pro scope set)
#
# Output labels (used by preflight.sh):
#   starter | pro | ent | ent+tx | unknown
#
# `ent+tx` (Enterprise + Transactional Email add-on) is detected via a
# separate signal — usually a subscription/extension entry referencing
# transactional email. Without that signal, Ent classifies as `ent` (eight
# scopes including marketing-email but excluding transactional-email).
#
# Contract:
#   classify_tier_from_account_details "$ACCOUNT_INFO_JSON"
# Echoes one of: starter | pro | ent | ent+tx | unknown

classify_tier_from_account_details() {
  local json="$1"
  local account_type
  account_type=$(printf '%s' "$json" | jq -r '.accountType // "UNKNOWN"' 2>/dev/null)

  # Detect the Transactional Email add-on. The exact path varies — check the
  # likely surfaces and accept any positive match. Update the jq path when a
  # confirmed source-of-truth surface is identified.
  local has_tx
  has_tx=$(printf '%s' "$json" | jq -r '
    [
      ((.subscriptions // []) | map(.name? // .id? // "") | join(" ")),
      ((.extensions // []) | map(.name? // .id? // "") | join(" "))
    ] | join(" ")
    | test("transactional[-_ ]?email"; "i")
  ' 2>/dev/null)

  case "$account_type" in
    STARTER|STANDARD)
      echo "starter"
      ;;
    PROFESSIONAL)
      echo "pro"
      ;;
    ENTERPRISE)
      if [[ "$has_tx" == "true" ]]; then
        echo "ent+tx"
      else
        echo "ent"
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Map a tier label to its required scope set. Echoes one scope per line.
#   starter → 7 base scopes
#   pro     → 7 + marketing-email
#   ent     → same as pro
#   ent+tx  → ent + transactional-email
#   unknown → conservatively returns the pro set (so consumers don't accidentally
#             ship without marketing-email when the tier classifier failed)
required_scopes_for_tier() {
  local tier="$1"
  local base=(
    "crm.objects.contacts.read"
    "crm.objects.contacts.write"
    "crm.schemas.contacts.write"
    "crm.lists.read"
    "crm.lists.write"
    "forms"
    "content"
  )
  local s
  for s in "${base[@]}"; do echo "$s"; done
  case "$tier" in
    pro|ent|unknown)
      echo "marketing-email"
      ;;
    ent+tx)
      echo "marketing-email"
      echo "transactional-email"
      ;;
    starter)
      ;;
  esac
}
