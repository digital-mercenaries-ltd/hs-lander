# Plan: Account/Project Config Hierarchy

**Date:** 2026-04-20
**Status:** Pending
**Context:** The framework currently uses `KEYCHAIN_PREFIX` in `project.config.sh` to derive Keychain service names at runtime. This bakes in a naming convention and conflates "key" (config identifier) with "key" (API secret). The framework should support a two-tier config hierarchy — account-level and project-level — with explicit Keychain service name references and no org-specific assumptions.

## Goal

Replace the flat `project.config.sh` + `KEYCHAIN_PREFIX` derivation pattern with:

1. **Account config** at `~/.config/hs-lander/<account>/config.sh` — shared across all projects on one HubSpot account
2. **Project config** at `~/.config/hs-lander/<account>/<project>.sh` — per landing page
3. **Project sourcing chain** — `project.config.sh` in the project directory sources both, in order

The framework remains org-agnostic. No DML-specific values or assumptions anywhere.

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
# See the framework docs for setup: https://github.com/digital-mercenaries-ltd/hs-lander/docs/framework.md

HS_LANDER_ACCOUNT=""     # directory name under ~/.config/hs-lander/
HS_LANDER_PROJECT=""     # project config filename (without .sh)

source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
```

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
- Remove `keychain_prefix:` field from the HubSpot Config section — this is now an account-level setting, not a brief field
- Rename remaining fields to match the new config variable names

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
- Verify these don't reference `KEYCHAIN_PREFIX` — if they do, update

### CI workflows

**`.github/workflows/smoke.yml`** (line 51):
- Replace `KEYCHAIN_PREFIX="smoke"` with `HUBSPOT_TOKEN_KEYCHAIN_SERVICE="smoke-hubspot-access-token"`
- Update the rest of the smoke test to use the new config structure

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
