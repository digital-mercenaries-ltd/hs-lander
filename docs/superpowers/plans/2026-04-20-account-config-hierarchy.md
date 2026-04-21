# Plan: Account/Project Config Hierarchy

**Date:** 2026-04-20
**Status:** Pending
**Context:** The framework currently uses `KEYCHAIN_PREFIX` in `project.config.sh` to derive Keychain service names at runtime. This bakes in a naming convention and conflates "key" (config identifier) with "key" (API secret). The framework should support a two-tier config hierarchy — account-level and project-level — with explicit Keychain service name references and no org-specific assumptions.

## Goal

Replace the flat `project.config.sh` + `KEYCHAIN_PREFIX` derivation pattern with:

1. **Account config** at `~/.config/hs-lander/<account>/config.sh` — shared across all projects on one HubSpot account
2. **Project config** at `~/.config/hs-lander/<account>/<project>.sh` — per landing page
3. **Project sourcing chain** — `project.config.sh` in the project directory sources both, in order

The framework code (scripts, modules, scaffold, tests) remains org-agnostic — no DML-specific values or assumptions. Planning docs in `docs/` may reference DML as the primary consumer for context; the verification grep below is scoped to code directories only.

## Directory structure

```
~/.config/hs-lander/
  dml/                              # One directory per HubSpot account
    config.sh                       # Account-level settings + credential references
    heard.sh                        # Project: Heard landing page
    tsc.sh                          # Project: TSC test instance
  tcl/                              # Different HubSpot account
    config.sh
    tsc-landing.sh
```

## Account config format

`~/.config/hs-lander/<account>/config.sh`:

```bash
# Account: <display name>
# HubSpot account-level settings. Shared by all projects on this account.

# Account settings (non-secret)
HUBSPOT_PORTAL_ID=""               # e.g. 147959629
HUBSPOT_REGION=""                  # eu1 or na1
DOMAIN_PATTERN=""                  # e.g. *.digitalmercenaries.ai (used by skill to propose project domains)

# Credential references — Keychain service names (NOT secret values)
# The actual tokens live in macOS Keychain and are read at runtime by scripts.
HUBSPOT_TOKEN_KEYCHAIN_SERVICE=""  # e.g. dml-hubspot-access-token
```

## Project config format

`~/.config/hs-lander/<account>/<project>.sh`:

```bash
# Project: <display name>
# Project-level settings for one landing page.

# Project settings (non-secret)
PROJECT_SLUG=""                    # e.g. heard
DOMAIN=""                          # e.g. heard.digitalmercenaries.ai
DM_UPLOAD_PATH=""                  # e.g. /heard
GA4_MEASUREMENT_ID=""              # e.g. G-XXXXXXXXXX

# Populated by post-apply.sh after terraform apply
CAPTURE_FORM_ID=""
SURVEY_FORM_ID=""
LIST_ID=""
```

## Project directory sourcing chain

`project.config.sh` in the project directory becomes a thin pointer:

```bash
# project.config.sh — sources account + project config
# This file is gitignored. Copy from project.config.example.sh and set the two paths.

HS_LANDER_ACCOUNT="dml"
HS_LANDER_PROJECT="heard"

source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
```

`project.config.example.sh` (committed) documents this:

```bash
# project.config.sh — sources account + project config from ~/.config/hs-lander/
# Copy this file to project.config.sh (gitignored) and set the account/project names.
#
# Account configs live at: ~/.config/hs-lander/<account>/config.sh
# Project configs live at: ~/.config/hs-lander/<account>/<project>.sh
#
# See the framework docs for setup: https://github.com/digital-mercenaries-ltd/hs-lander/blob/main/docs/framework.md

HS_LANDER_ACCOUNT=""     # directory name under ~/.config/hs-lander/
HS_LANDER_PROJECT=""     # project config filename (without .sh)

source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
```

---

## New script: preflight.sh

The framework needs a single entry point that checks everything is ready before build/deploy. This replaces the inline shell snippets currently embedded in the skill.

**`scripts/preflight.sh`** — sources config, validates everything, reports status. Exit 0 if ready, exit 1 if not. Output is structured so the skill (or a human) can parse what's done vs missing.

```bash
#!/usr/bin/env bash
# preflight.sh — validate config, credentials, and HubSpot account readiness
# Sources project.config.sh (which sources account + project configs)
# Reports status of each prerequisite as CHECK_NAME=ok|missing|error
#
# Usage: bash scripts/preflight.sh
# Exit 0: all checks pass. Exit 1: one or more checks failed (details on stdout).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Config discovery ---
# CHECK: project.config.sh exists and is sourceable
# CHECK: account config (HS_LANDER_ACCOUNT set, ~/.config/hs-lander/<account>/config.sh exists)
# CHECK: project config (HS_LANDER_PROJECT set, ~/.config/hs-lander/<account>/<project>.sh exists)
# CHECK: required variables non-empty after sourcing: HUBSPOT_PORTAL_ID, HUBSPOT_REGION, DOMAIN, PROJECT_SLUG, DM_UPLOAD_PATH
# CHECK: HUBSPOT_TOKEN_KEYCHAIN_SERVICE is set

# --- Credential validation ---
# CHECK: Keychain entry exists for $HUBSPOT_TOKEN_KEYCHAIN_SERVICE
#   (runs: security find-generic-password -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" -a "$USER" -w)
#   IMPORTANT: token value is read into a variable, used for the API test, then unset.
#   Never printed, logged, or passed to stdout.
# CHECK: HubSpot API responds 200 to /account-info/v3/details with the token

# --- HubSpot account readiness ---
# CHECK: project_source CRM property exists
#   (GET /crm/v3/properties/contacts/project_source — 200 = exists, 404 = first project on account)
# CHECK: DNS resolves for $DOMAIN (dig +short, non-empty = ok)

# --- Optional checks (non-blocking, reported as warnings) ---
# WARN: GA4_MEASUREMENT_ID empty (analytics won't fire)
# WARN: CAPTURE_FORM_ID empty (expected before first deploy, populated by post-apply)

# --- Output format ---
# Each check prints: PREFLIGHT_<NAME>=ok|missing|error|warn [detail]
# Example:
#   PREFLIGHT_CONFIG=ok
#   PREFLIGHT_CREDENTIAL=ok
#   PREFLIGHT_API_ACCESS=ok
#   PREFLIGHT_PROJECT_SOURCE=missing (first project on this account — account-setup module needed)
#   PREFLIGHT_DNS=ok heard.digitalmercenaries.ai resolves
#   PREFLIGHT_GA4=warn GA4_MEASUREMENT_ID is empty
#   PREFLIGHT_FORM_IDS=warn CAPTURE_FORM_ID is empty (expected before first deploy)
```

This script is deterministic, testable, and contains all the validation logic that was previously scattered across the skill's inline code blocks. The skill never needs to run `security`, `curl`, or `dig` directly — it runs `preflight.sh` and interprets the output.

**Credential safety in preflight.sh:**
- The token is read from Keychain into a local variable, used for the API test, then `unset`
- The token value is NEVER printed to stdout, stderr, or any file
- If the credential is missing, the script prints the Keychain service name and the `security add-generic-password` command the user should run — but never the token itself
- The script does NOT ask for or accept token values as arguments or stdin

### Test for preflight.sh

**`tests/test-preflight.sh`** — local, validates the reporting logic:

Assertions:
- With complete config: all checks report `ok`
- With missing `HUBSPOT_TOKEN_KEYCHAIN_SERVICE`: reports `PREFLIGHT_CREDENTIAL=missing`
- With empty `GA4_MEASUREMENT_ID`: reports `PREFLIGHT_GA4=warn`
- With empty `CAPTURE_FORM_ID`: reports `PREFLIGHT_FORM_IDS=warn`
- Output never contains actual token values (grep for known test token)
- Exit code is 1 when any required check is `missing` or `error`

Add to CI (`ci.yml`) alongside existing test suites.

---

## Changes by file

### Scripts — replace KEYCHAIN_PREFIX with explicit service name

**`scripts/tf.sh`** (lines 14-17):
- Replace: `security find-generic-password -s "${KEYCHAIN_PREFIX}-hubspot-access-token"`
- With: `security find-generic-password -s "${HUBSPOT_TOKEN_KEYCHAIN_SERVICE}"`
- Update error message to reference `HUBSPOT_TOKEN_KEYCHAIN_SERVICE` config variable

**`scripts/hs-curl.sh`** (lines 24-26):
- Same replacement as tf.sh

**`scripts/upload.sh`** (lines 21-23):
- Same replacement as tf.sh

**`scripts/hs.sh`** (lines 15-17):
- This script uses `${KEYCHAIN_PREFIX}-hubspot-pak` for the optional CLI PAK
- Replace with a new optional config variable `HUBSPOT_PAK_KEYCHAIN_SERVICE`
- If not set, skip PAK lookup with a clear message

**`scripts/deploy.sh`**, **`scripts/build.sh`**, **`scripts/watch.sh`**, **`scripts/post-apply.sh`**:
- These source `project.config.sh` but don't use `KEYCHAIN_PREFIX` directly — verify and confirm no changes needed

### Scaffold templates

**`scaffold/project.config.example.sh`**:
- Replace the current flat config with the sourcing-chain format shown above
- Remove `KEYCHAIN_PREFIX` line
- Remove all value lines (portal ID, region, etc.) — these now live in `~/.config/hs-lander/`

**`scaffold/terraform/main.tf`**:
- No changes — it reads `var.hubspot_token` etc. from TF_VAR_* env vars, which tf.sh exports after sourcing config. The indirection is handled at the script level.

**`scaffold/package.json`**:
- No changes needed

**`scaffold/brief-template.md`**:
- The HubSpot Config section currently has: `portal_id`, `region`, `domain`, `keychain_prefix`, `dm_upload_path`, `ga4_id`.
- Move to account config (skill reads from `HS_LANDER_ACCOUNT`, not the brief): `portal_id`, `region`.
- Keep as brief fields (project-specific, captured per landing page): `domain`, `dm_upload_path`, `ga4_id`.
- Remove entirely (now derived from account config): `keychain_prefix`.
- Replace the HubSpot Config section header with a `## Project Config` section containing only the three project-level fields, plus an `account:` field that names which account config to source (`HS_LANDER_ACCOUNT`).

### Tests

**`tests/fixtures/project.config.sh`** (line 8):
- Replace `KEYCHAIN_PREFIX="test"` with `HUBSPOT_TOKEN_KEYCHAIN_SERVICE="test-hubspot-access-token"`
- Add all required config variables that were previously derived

**`tests/test-post-apply.sh`** (line 26):
- Same — replace `KEYCHAIN_PREFIX="test"` with the explicit variables
- Update any assertions that check for `KEYCHAIN_PREFIX` in the config output

**`tests/test-deployment.sh`** (line 21):
- Replace `${KEYCHAIN_PREFIX}-hubspot-access-token` with `${HUBSPOT_TOKEN_KEYCHAIN_SERVICE}`

**`tests/test-build.sh`**, **`tests/test-terraform-plan.sh`**:
- These don't reference `KEYCHAIN_PREFIX` directly — they inherit it via the `tests/fixtures/project.config.sh` fixture. No change needed; confirm by running both suites after fixture updates.

### CI workflows

The active CI workflow (`.github/workflows/ci.yml`) doesn't source `project.config.sh` or touch Keychain — no changes needed.

The archived e2e smoke test (`docs/archive/workflows/smoke.yml`) contains the legacy `KEYCHAIN_PREFIX="smoke"` pattern. That file is reference-only per its own header and will be rewritten when roadmap v2.2 replaces it with a skill-driven e2e test — no action required here.

### Documentation

**`CLAUDE.md`**:
- Update credential rules section to explain account/project config hierarchy
- Replace `KEYCHAIN_PREFIX` references with `HUBSPOT_TOKEN_KEYCHAIN_SERVICE`
- Update architecture section to describe `~/.config/hs-lander/` structure

**`docs/framework.md`**:
- Rewrite Authentication section to describe the two-tier config
- Remove `KEYCHAIN_PREFIX` references
- Remove `${KEYCHAIN_PREFIX}-hubspot-pak` optional entry (PAK is not part of core workflow)
- Fix scope list: 7 scopes, not 8 (transactional-email was dropped)

**`README.md`**:
- Update quick-start section if it references config setup

**`docs/roadmap.md`**:
- Update the Cloudflare DNS section to use `CLOUDFLARE_TOKEN_KEYCHAIN_SERVICE` instead of `KEYCHAIN_PREFIX`-based naming
- Update the GA4 section similarly

---

## Migration path for existing projects

Existing projects (TSC) that use the old `KEYCHAIN_PREFIX` flat config will need a one-time migration:

1. Create `~/.config/hs-lander/<account>/config.sh` with account values
2. Create `~/.config/hs-lander/<account>/<project>.sh` with project values
3. Replace `project.config.sh` contents with the sourcing chain
4. Verify: `npm run build` still works

The skill should handle this automatically when invoked in an existing project directory (detect old-format config, offer to migrate).

---

## What NOT to change

- **Terraform modules** — they receive values via `TF_VAR_*` environment variables. They don't know or care about the config hierarchy. No changes needed.
- **Token substitution** — build.sh reads config variables by name. The names (`HUBSPOT_PORTAL_ID`, `DOMAIN`, etc.) stay the same. Only the source changes (account config vs flat file).
- **Keychain storage** — the actual Keychain entries don't change. Only the config variable that references them changes from derived (`${KEYCHAIN_PREFIX}-hubspot-access-token`) to explicit (`$HUBSPOT_TOKEN_KEYCHAIN_SERVICE`).

---

## Verification

After implementation:

1. `~/.config/hs-lander/test/config.sh` exists with test account values
2. `~/.config/hs-lander/test/testproject.sh` exists with test project values
3. All 3 local test suites pass (test-build, test-post-apply, test-terraform-plan)
4. `grep -r 'KEYCHAIN_PREFIX' scripts/ scaffold/ tests/` returns zero hits
5. `grep -r 'digitalmercenaries\|DML\|Nishbert\|dml-' scripts/ scaffold/ tests/` returns zero hits (excluding docs/plans/)
6. Existing TSC project still builds after migration to new config format
