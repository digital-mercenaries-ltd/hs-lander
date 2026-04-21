# hs-lander Framework

## Overview

hs-lander is a reusable framework for deploying HubSpot landing page funnels. It provides:

- **Terraform modules** for creating HubSpot resources (forms, pages, emails, lists)
- **Shell scripts** for building, deploying, and managing projects
- **Scaffold templates** for creating new projects

## Quick Start

### 1. Create a new project

```bash
mkdir my-project && cd my-project
cp -r /path/to/hs-lander/scaffold/* .
cp -r /path/to/hs-lander/scripts/ scripts/
cp project.config.example.sh project.config.sh
# Set HS_LANDER_ACCOUNT and HS_LANDER_PROJECT in project.config.sh
# Create the account config if it doesn't exist yet:
#   ~/.config/hs-lander/<account>/config.sh    — portal ID, region, HUBSPOT_TOKEN_KEYCHAIN_SERVICE
# Create the project config:
#   ~/.config/hs-lander/<account>/<project>.sh — slug, domain, DM upload path, GA4 ID
```

### 2. Add your content

Create your landing page content in `src/`:

```
src/
├── templates/
│   ├── landing-page.html     # Use __PLACEHOLDER__ tokens
│   └── thank-you.html
├── css/main.css
├── js/tracking.js
├── emails/
│   └── welcome-body.html
└── images/
```

### 3. Build and deploy

```bash
npm run preflight          # Validate config, credentials, and HubSpot readiness
npm run build              # src/ → dist/ with token substitution
npm run tf:init            # Initialise Terraform
npm run setup              # Build + terraform apply
npm run post-apply         # Write form IDs to ~/.config/hs-lander/<account>/<project>.sh
npm run build              # Rebuild with form IDs
npm run deploy             # Upload to HubSpot Design Manager
```

## Token Substitution

`build.sh` replaces `__PLACEHOLDER__` tokens in `src/` files with values from `project.config.sh`:

| Token | Source |
|---|---|
| `__PORTAL_ID__` | `HUBSPOT_PORTAL_ID` |
| `__REGION__` | `HUBSPOT_REGION` |
| `__HSFORMS_HOST__` | Derived from region |
| `__CAPTURE_FORM_ID__` | `CAPTURE_FORM_ID` (set by post-apply) |
| `__SURVEY_FORM_ID__` | `SURVEY_FORM_ID` (set by post-apply) |
| `__DOMAIN__` | `DOMAIN` |
| `__GA4_ID__` | `GA4_MEASUREMENT_ID` |
| `__DM_PATH__` | `DM_UPLOAD_PATH` |

## Terraform Modules

### account-setup

Run once per HubSpot account. Creates the `project_source` CRM contact property used for segmenting contacts by project.

### landing-page

Run per project. Creates: capture form, optional survey form, landing page, thank-you page, welcome email, contact list, and optional custom CRM properties.

Both modules use the Mastercard/restapi provider (~1.19) and inherit the provider configuration from the consuming project's root module.

## Authentication

All credentials live in macOS Keychain. The account config declares the Keychain service name; scripts use that literal name (never a derived prefix) when reading the token.

**Account config** (`~/.config/hs-lander/<account>/config.sh`):

```bash
HUBSPOT_PORTAL_ID=""               # e.g. 12345678
HUBSPOT_REGION=""                  # eu1 or na1
DOMAIN_PATTERN=""                  # e.g. *.example.com
HUBSPOT_TOKEN_KEYCHAIN_SERVICE=""  # e.g. <account>-hubspot-access-token
```

Scripts read the token via:

```bash
security find-generic-password -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" -a "$USER" -w
```

The token is never written to disk, env files, terraform.tfvars, or stdout. `scripts/preflight.sh` validates that the Keychain entry exists and that the HubSpot API responds before any build or deploy step runs.

Future service references (GA4 service account, Cloudflare API token, etc.) follow the same `<PURPOSE>_KEYCHAIN_SERVICE` naming pattern and are added to the account config as their respective roadmap items land.

> **Removed in the config-hierarchy refactor:** the optional `scripts/hs.sh` PAK wrapper for the HubSpot CLI. Everything the framework needs runs via Service Key + REST (`scripts/upload.sh`, `scripts/tf.sh`, `scripts/hs-curl.sh`). Adopters who previously relied on `hs.sh` for manual CLI use can either use `hs-curl.sh` for API calls or install the HubSpot CLI themselves outside this framework.

## Preflight output reference

`npm run preflight` (or `bash scripts/preflight.sh`) emits one line per check in the form `PREFLIGHT_<NAME>=<state> [detail]`. Exit 0 when every required check is ok or warn; exit 1 when any required check is missing, empty, unauthorized, forbidden, unreachable, or error. Warnings and the `PROJECT_SOURCE=missing` "first project on account" signal are non-blocking.

| Check | States | Detail shape |
|---|---|---|
| `PREFLIGHT_TOOLS_REQUIRED` | `ok` \| `missing` | `missing` is followed by a comma-list of absent tools (`curl`, `jq`, `terraform`, `npm`). This check runs first; if any required tool is absent, preflight emits `skipped (required tools missing)` for every other contract line and exits 1 |
| `PREFLIGHT_PROJECT_POINTER` | `ok` \| `missing` \| `incomplete` | Missing vars listed when `incomplete` (e.g. `HS_LANDER_ACCOUNT HS_LANDER_PROJECT`) |
| `PREFLIGHT_ACCOUNT_PROFILE` | `ok` \| `missing` \| `incomplete` \| `skipped` | When `missing`: absolute path. When `incomplete`: comma-list of missing fields |
| `PREFLIGHT_PROJECT_PROFILE` | `ok` \| `missing` \| `incomplete` \| `skipped` | Same shape as `ACCOUNT_PROFILE` |
| `PREFLIGHT_CREDENTIAL` | `found` \| `missing` \| `empty` \| `skipped` | `missing` includes the Keychain service name and the `security add-generic-password` command to add it |
| `PREFLIGHT_API_ACCESS` | `ok` \| `unauthorized` \| `forbidden` \| `unreachable` \| `error` \| `skipped` | `unauthorized` = 401 (token invalid/expired); `forbidden` = 403; `unreachable` = curl failed to reach `api.hubapi.com`; `error` = unexpected HTTP |
| `PREFLIGHT_SCOPES` | `ok` \| `missing` \| `error` \| `skipped` | `missing` is followed by a comma-list of missing scopes — the skill can name them directly |
| `PREFLIGHT_PROJECT_SOURCE` | `ok` \| `missing` \| `error` \| `skipped` | `missing` on 404 is **recoverable, non-blocking** — signals "first project on this account" |
| `PREFLIGHT_DNS` | `ok` \| `missing` \| `skipped` | On `missing`, detail includes the expected CNAME target (`<portal-id>.group0.sites.hscoscdn-<region>.net`) so the user knows which record to create |
| `PREFLIGHT_GA4` | `ok` \| `warn` | `warn` when `GA4_MEASUREMENT_ID` is empty (analytics won't fire, but build/deploy still works) |
| `PREFLIGHT_FORM_IDS` | `ok` \| `warn` | `warn` when `CAPTURE_FORM_ID` is empty (expected before first deploy; populated by `post-apply`) |
| `PREFLIGHT_TOOLS_OPTIONAL` | `ok` \| `warn` \| `skipped` | `warn` is followed by a comma-list of absent optional tools (`pandoc`, `pdftotext`, `git`). Non-blocking — these only affect specific skill workflows (source ingest, repo operations). `skipped` only when required tools are missing |

Credential safety: the HubSpot token is read into a local shell variable, used for the three API probes (account-info, project_source, scopes introspection), and unset via EXIT trap. xtrace is disabled around the token-handling block so `bash -x scripts/preflight.sh` does not leak the token either.

## Prerequisites

- HubSpot Marketing Hub Starter + Content Hub Starter
- Service Key with scopes: `crm.objects.contacts.read`, `crm.objects.contacts.write`, `crm.schemas.contacts.write`, `crm.lists.read`, `crm.lists.write`, `forms`, `content` (7 scopes — `content` covers the marketing email resource via `/marketing/v3/emails`)
- macOS with Keychain (for local development)

### CLI tools

The framework requires `curl`, `jq`, `terraform`, and `npm` at runtime. Optional tools `pandoc`, `pdftotext`, and `git` extend specific features (source ingest, version control). Run `bash scripts/preflight.sh` to verify — it reports missing tools via `PREFLIGHT_TOOLS_REQUIRED` and `PREFLIGHT_TOOLS_OPTIONAL` lines.

On macOS (Homebrew):

```bash
brew install curl jq terraform node pandoc poppler git   # poppler provides pdftotext; node ships npm
```
