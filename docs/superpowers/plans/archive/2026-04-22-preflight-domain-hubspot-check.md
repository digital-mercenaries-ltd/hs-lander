# Plan: Preflight HubSpot Domain Connection Check

**Date:** 2026-04-22
**Status:** Superseded — most of the design shipped in v1.7.0 as `PREFLIGHT_DOMAIN_CONNECTED` (probes `/cms/v3/domains` for the project's `DOMAIN`, emits `ok | not-primary | missing | skipped | error`). Two pieces of this plan did not ship and are partly obsolete:
**Roadmap reference:** R8

1. **`scripts/lib/hosting-mode.sh`** helper that resolves hosting mode from `DOMAIN` (custom-domain-primary | system-domain | system-domain-redirect | system-domain-iframe). Worth pursuing as a small lib extraction, but not on its own — fold into the `scripts/lib/` consolidation work queued for v1.9.
2. **Mode-aware skipping** of the domain probe for system-domain modes. The plan's design depended on `HOSTING_MODE_HINT` to distinguish redirect from iframe sub-variants; that field was removed in v1.7.0 (skill-only state now). Without it, the framework cannot distinguish the system-domain sub-variants — the skill, which has its own state, does. Parking until R8 needs revisiting.

The R8 roadmap entry should be marked superseded in `docs/roadmap.md`. If a fresh mini-plan covering only the residual work is wanted, write it then; this plan's substantive design is no longer the right starting point.

**Target release:** N/A — superseded by v1.7.0.
**v1.8.1 archive note:** moved to `archive/` during the v1.8.1 plan-archive sweep. Kept for historical reference of the original design rationale.

## Context

`preflight.sh` already checks DNS resolution (`PREFLIGHT_DNS`). DNS resolving is necessary but not sufficient — a domain with DNS in place but not connected in HubSpot UI causes landing pages to be created at UUID slugs rather than the expected root URL (observed on Heard, 2026-04-22, where the `heard.digitalmercenaries.ai` subdomain had DNS set up but hadn't been connected in HubSpot UI).

Additionally, HubSpot's "primary landing page" designation — which decides what gets served at domain root when a page is stored with empty `domain` + empty `slug` — is a per-domain flag that has to be set manually in the HubSpot UI. The Domains API is GET-only (confirmed via probe 2026-04-22), so this can't be automated. But it *can* be verified, and preflight is the right place.

The hosting-modes skill plan currently handles this check via a post-preflight `hs-curl.sh` call from within the skill. That works but breaks the principle that framework owns all operational checks and the skill just reads structured output. Moving the check into `preflight.sh` restores the separation.

## Goal

Add `PREFLIGHT_DOMAIN_HUBSPOT` to the preflight output contract. The check:

1. Reads the target `DOMAIN` from the project profile (via existing config-sourcing chain)
2. Determines hosting mode from `DOMAIN` value (inherits logic from the skill's hosting-modes detection — or, better, exposes it as a reusable helper in a new `scripts/lib/hosting-mode.sh` that both `preflight.sh` and skill share)
3. Calls `GET /cms/v3/domains` and checks whether the target domain appears
4. For custom-domain modes, additionally checks `isPrimaryLandingPage` is true and `primaryLandingPageId` is set
5. For system-domain modes, the check is a no-op (system domains are auto-provisioned by HubSpot; connection state is implicit)

Failure surfaces as a specific preflight result the skill interprets; no skill-side domain probing needed after this lands.

## Output contract

Extends preflight output from 12 lines to 13 (with v1.4.0 changes) or 14 (with both v1.4.0 + v1.5 `PREFLIGHT_SUBSCRIPTIONS`). Position: after `DNS`, before `GA4`.

```
PREFLIGHT_DOMAIN_HUBSPOT=<state> [<detail>]
```

States:

| State | Meaning | Blocking? |
|-------|---------|-----------|
| `ok` | Domain connected and, for custom-domain mode, primary-page flag correctly set | No |
| `skipped` | System-domain mode — nothing to check | No |
| `not-connected <domain>` | Target domain doesn't appear in `/cms/v3/domains` at all | Yes (exit 1) |
| `not-primary <domain>` | Domain connected but `isPrimaryLandingPage=false` | Yes (exit 1) |
| `partial <domain>` | Domain connected, primary-page flag set, but `primaryLandingPageId` doesn't match any of the project's expected pages | Warn (exit 0) |
| `error <reason>` | API call failed | Yes (exit 1) |

Examples:

```
PREFLIGHT_DOMAIN_HUBSPOT=ok heard.digitalmercenaries.ai connected, isPrimaryLandingPage=true
PREFLIGHT_DOMAIN_HUBSPOT=skipped (system-domain mode)
PREFLIGHT_DOMAIN_HUBSPOT=not-connected heard.digitalmercenaries.ai (add via HubSpot UI: Settings → Content → Domains & URLs → Connect a domain)
PREFLIGHT_DOMAIN_HUBSPOT=not-primary heard.digitalmercenaries.ai (connected but Primary Landing Page unset)
```

## Implementation

### New helper: `scripts/lib/hosting-mode.sh`

Exports a function `resolve_hosting_mode` that takes `DOMAIN` (and optionally `HOSTING_MODE_HINT` for the system-domain sub-variants). Returns one of: `custom-domain-primary`, `system-domain`, `system-domain-redirect`, `system-domain-iframe`.

Detection rule (same as the skill's hosting-modes plan):

```bash
resolve_hosting_mode() {
  local domain="$1"
  local hint="${2:-}"

  if [[ "$domain" =~ \.hs-sites[.-] ]] || [[ "$domain" =~ \.hubspotpagebuilder\. ]]; then
    case "$hint" in
      redirect) echo "system-domain-redirect" ;;
      iframe)   echo "system-domain-iframe" ;;
      *)        echo "system-domain" ;;
    esac
  else
    echo "custom-domain-primary"
  fi
}
```

Shared by both `preflight.sh` and, later, the skill if we choose to surface mode to the user explicitly (skill can also invoke this helper rather than duplicating the detection logic).

### `preflight.sh` additions

After the existing `PREFLIGHT_DNS` check:

```bash
# --- PREFLIGHT_DOMAIN_HUBSPOT ---
# Check HubSpot-side domain connection and primary-page state.
# - System domains: auto-provisioned; skip.
# - Custom domains: GET /cms/v3/domains; verify connection and primary flag.
source "$SCRIPT_DIR/lib/hosting-mode.sh"
hosting_mode=$(resolve_hosting_mode "$DOMAIN" "${HOSTING_MODE_HINT:-}")

case "$hosting_mode" in
  system-domain|system-domain-redirect|system-domain-iframe)
    echo "PREFLIGHT_DOMAIN_HUBSPOT=skipped ($hosting_mode)"
    ;;
  custom-domain-primary)
    # Use existing token retrieval pattern (same xtrace suppression as credential block)
    _xtrace_was_on=0
    case "$-" in *x*) _xtrace_was_on=1; set +x ;; esac
    domains_json=$(curl -s -H "Authorization: Bearer $token" "https://api.hubapi.com/cms/v3/domains")
    curl_exit=$?
    [[ $_xtrace_was_on -eq 1 ]] && set -x
    unset _xtrace_was_on

    if [[ $curl_exit -ne 0 ]]; then
      echo "PREFLIGHT_DOMAIN_HUBSPOT=error curl exit $curl_exit"
      required_failed=1
    else
      # Parse: look for $DOMAIN in .results[].domain
      match=$(echo "$domains_json" | jq -r --arg d "$DOMAIN" '.results[] | select(.domain == $d)')
      if [[ -z "$match" ]]; then
        echo "PREFLIGHT_DOMAIN_HUBSPOT=not-connected $DOMAIN (add via HubSpot UI: Settings → Content → Domains & URLs → Connect a domain)"
        required_failed=1
      else
        is_primary=$(echo "$match" | jq -r '.isPrimaryLandingPage')
        primary_id=$(echo "$match" | jq -r '.primaryLandingPageId // empty')
        if [[ "$is_primary" != "true" ]]; then
          echo "PREFLIGHT_DOMAIN_HUBSPOT=not-primary $DOMAIN (Primary Landing Page flag not set in HubSpot UI)"
          required_failed=1
        elif [[ -z "$primary_id" ]]; then
          echo "PREFLIGHT_DOMAIN_HUBSPOT=partial $DOMAIN (Primary Landing Page flag set but no page assigned — set in HubSpot UI after first deploy)"
          # Non-blocking — expected state between first deploy and manual UI step
        else
          echo "PREFLIGHT_DOMAIN_HUBSPOT=ok $DOMAIN connected, isPrimaryLandingPage=true, primaryLandingPageId=$primary_id"
        fi
      fi
    fi
    ;;
esac
```

Place immediately after the DNS check block, inside the branch where credentials are available (it reuses `$token` from the existing API_ACCESS flow).

**Credential safety:** the existing xtrace-suppression pattern around curl-with-Authorization is reused. Token never leaked.

### Token scope

No new OAuth scope required. `GET /cms/v3/domains` works with the `content` scope already required for page management.

### Output ordering update

The preflight output-contract documentation (CLAUDE.md, docs/framework.md, SKILL.md's "Handling preflight results" section) needs a line-count bump and insertion of `DOMAIN_HUBSPOT` between `DNS` and `GA4`.

Current: `TOOLS_REQUIRED, PROJECT_POINTER, ACCOUNT_PROFILE, PROJECT_PROFILE, CREDENTIAL, API_ACCESS, SCOPES, PROJECT_SOURCE, DNS, GA4, FORM_IDS, TOOLS_OPTIONAL` = 12 lines.

After this plan: `... DNS, DOMAIN_HUBSPOT, GA4, ...` = 13 lines.

(After v1.4.0 + v1.5 + this: 14 lines total — `SUBSCRIPTIONS` goes between `SCOPES` and `PROJECT_SOURCE` per v1.5 plan.)

### Tests

`tests/test-preflight.sh` — new fixtures and assertions:

**Custom-domain scenarios:**
- Fixture: `DOMAIN=heard.example.com`, no `HOSTING_MODE_HINT`. Mock HubSpot response with domain connected + primary flag → `PREFLIGHT_DOMAIN_HUBSPOT=ok`
- Same, domain not in mock response → `PREFLIGHT_DOMAIN_HUBSPOT=not-connected`
- Same, domain connected but primary flag false → `PREFLIGHT_DOMAIN_HUBSPOT=not-primary`
- Same, primary flag true but `primaryLandingPageId` empty → `PREFLIGHT_DOMAIN_HUBSPOT=partial` (exit 0)

**System-domain scenarios:**
- Fixture: `DOMAIN=147959629.hs-sites-eu1.com`, `LANDING_SLUG=heard` → `PREFLIGHT_DOMAIN_HUBSPOT=skipped (system-domain)`
- Same + `HOSTING_MODE_HINT=redirect` → `PREFLIGHT_DOMAIN_HUBSPOT=skipped (system-domain-redirect)`

**API failure:**
- Mock HubSpot returning 500 → `PREFLIGHT_DOMAIN_HUBSPOT=error`

### Skill-side follow-up (coordination note)

The hosting-modes skill plan currently defines a post-preflight `GET /cms/v3/domains` call that the skill does itself. Once this framework plan lands, that skill-side logic becomes redundant.

Update the hosting-modes skill plan:

- Remove "post-preflight domain-connection check" section
- Replace with "Parse `PREFLIGHT_DOMAIN_HUBSPOT` and handle per standard pattern":
  - `ok` / `skipped` → proceed
  - `not-connected` → surface the HubSpot UI connection steps (same coaching as currently in the plan)
  - `not-primary` → surface the Primary Landing Page UI step
  - `partial` → note it's expected pre-first-deploy; continue

This is a minor revision to the skill plan that should happen in parallel with this framework plan landing.

## Verification

After implementation:

1. Fresh setup with custom domain + DNS but no HubSpot connection: `PREFLIGHT_DOMAIN_HUBSPOT=not-connected <domain>` with clear remediation text, exit 1
2. Domain connected in HubSpot + primary flag set + `primaryLandingPageId` valid: `ok`, exit 0
3. System-domain mode (`DOMAIN=*.hs-sites-eu1.com`): `skipped`, exit 0 regardless of other state
4. All existing preflight tests continue to pass
5. The 13-line output contract is stable across every scenario
6. Skill's hosting-modes plan is updated to consume this output instead of doing its own probe

## Out of scope

- Automating domain connection — Domains API is GET-only (see roadmap v1.3 for the explored-and-rejected attempt)
- Automating the Primary Landing Page flag — same API limitation
- Cloudflare DNS verification as part of this check — separate concern (v1.2 roadmap)
- Multi-domain projects (single landing page on multiple domains) — not a current use case
