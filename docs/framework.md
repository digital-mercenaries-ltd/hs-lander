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
# Edit project.config.sh with your values
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
npm run build        # src/ → dist/ with token substitution
npm run tf:init      # Initialise Terraform
npm run setup        # Build + terraform apply
npm run post-apply   # Write form IDs to config
npm run build        # Rebuild with form IDs
npm run deploy       # Upload to HubSpot Design Manager
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

All credentials are stored in macOS Keychain. Scripts read them via `security find-generic-password`.

| Keychain service | Content |
|---|---|
| `${KEYCHAIN_PREFIX}-hubspot-access-token` | HubSpot Service Key |
| `${KEYCHAIN_PREFIX}-hubspot-pak` | Optional — PAK for HubSpot CLI |

## Prerequisites

- HubSpot Marketing Hub Starter + Content Hub Starter
- Service Key with scopes: `crm.objects.contacts.read`, `crm.objects.contacts.write`, `crm.schemas.contacts.write`, `crm.lists.read`, `crm.lists.write`, `forms`, `content`, `transactional-email`
- Terraform CLI
- macOS with Keychain (for local development)
