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
bash scripts/preflight.sh  # Validate config, credentials, and HubSpot readiness
npm run build              # src/ → dist/ with token substitution
npm run tf:init            # Initialise Terraform
npm run setup              # Build + terraform apply
npm run post-apply         # Write form IDs to config
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

## Prerequisites

- HubSpot Marketing Hub Starter + Content Hub Starter
- Service Key with scopes: `crm.objects.contacts.read`, `crm.objects.contacts.write`, `crm.schemas.contacts.write`, `crm.lists.read`, `crm.lists.write`, `forms`, `content` (7 scopes — `content` covers the marketing email resource via `/marketing/v3/emails`)
- Terraform CLI
- macOS with Keychain (for local development)
