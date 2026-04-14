# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

hs-lander — a reusable HubSpot landing page framework. Terraform modules, build pipeline, deployment scripts, and scaffold templates for creating landing page funnels from product briefs.

**Owner:** Digital Mercenaries Ltd (`digital-mercenaries-ltd` GitHub org)

## Current status

Greenfield TDD build — Session 2 of the orchestration plan.

**Spec:** `~/DocsLocal/digital-mercenaries-ltd/dml-github-org-config/docs/specs/2026-04-10-hs-lander-design.md`
**Orchestration plan:** `~/DocsLocal/digital-mercenaries-ltd/dml-github-org-config/docs/plans/2026-04-10-hs-lander-orchestration.md`

Read both files at the start of each session. The spec is the approved design. The orchestration plan's "Session 2" section describes what to build and its exit criteria.

### TDD build order

1. Write `test-build.sh` → implement `build.sh`
2. Write `test-post-apply.sh` → implement `post-apply.sh`
3. Implement remaining scripts: `tf.sh`, `hs-curl.sh`, `upload.sh`, `deploy.sh`, `watch.sh`
4. Write `test-terraform-plan.sh` → implement Terraform modules (`account-setup`, `landing-page`)
5. Create scaffold templates
6. Write `test-deployment.sh` (passes only after a real deployment)
7. Create CI workflows
8. Tag `v1.0.0`

### Exit criteria

- All local tests pass (`test-build.sh`, `test-post-apply.sh`, `test-terraform-plan.sh`)
- CI pipeline runs green on push
- `v1.0.0` tag published
- Scaffold can produce a working project directory

## Commands

### Framework tests (this repo)

```bash
# Run all local tests
bash tests/test-build.sh
bash tests/test-post-apply.sh
bash tests/test-terraform-plan.sh

# Run deployment test (requires live HubSpot — not for local dev)
bash tests/test-deployment.sh

# Lint
shellcheck scripts/*.sh tests/*.sh
terraform -chdir=terraform/modules/account-setup fmt -check
terraform -chdir=terraform/modules/landing-page fmt -check
terraform -chdir=terraform/modules/account-setup validate
terraform -chdir=terraform/modules/landing-page validate
```

### Per-project commands (defined in scaffold/package.json)

```bash
npm run build       # src/ → dist/ with token substitution
npm run setup       # build + terraform apply
npm run post-apply  # terraform outputs → project.config.sh
npm run deploy      # build + upload dist/ to HubSpot
npm run watch       # build + poll for changes
npm run tf:init     # terraform init
npm run tf:plan     # terraform plan
npm run destroy     # terraform destroy
```

## Architecture

```
hs-lander/
├── terraform/modules/
│   ├── account-setup/       ← Run once per HubSpot account (shared resources)
│   └── landing-page/        ← Run per project (forms, pages, email, list)
├── scripts/                 ← Generic, config-driven shell scripts
│   ├── build.sh             ← src/ → dist/ with token substitution
│   ├── deploy.sh            ← build + upload to HubSpot Design Manager
│   ├── upload.sh            ← PUT files to CMS Source Code API (no CLI needed)
│   ├── watch.sh             ← build + poll for changes
│   ├── post-apply.sh        ← terraform outputs → project.config.sh
│   ├── tf.sh                ← Keychain → TF_VAR_* → terraform
│   ├── hs-curl.sh           ← Keychain → curl HubSpot API
│   └── hs.sh                ← Optional CLI wrapper (not core workflow)
├── scaffold/                ← Template for new projects
│   ├── project.config.example.sh
│   ├── brief-template.md
│   ├── package.json
│   ├── .gitignore
│   └── terraform/main.tf   ← Calls modules by git URL
├── tests/
│   ├── fixtures/
│   ├── test-build.sh        ← Local, no network
│   ├── test-post-apply.sh   ← Local, no network
│   ├── test-terraform-plan.sh ← Local, parses plan output
│   └── test-deployment.sh   ← Network required, live HubSpot
└── .github/workflows/
    ├── ci.yml               ← Lint + build test + plan test (every push)
    └── smoke.yml            ← Real deploy + verify (manual/release)
```

### How the pieces connect

**Terraform modules** create HubSpot resources (forms, pages, email, lists). The `account-setup` module runs once per account; `landing-page` runs per project. Both inherit the `restapi` provider from the consuming project's root `main.tf` — they never take `hubspot_token` as a variable.

**Scripts** are generic and config-driven. They source `project.config.sh` for values and derive Keychain service names from `KEYCHAIN_PREFIX`. Scripts live in this framework repo and are copied into per-project repos at scaffold time.

**Scaffold** is the template for new projects. A project's `terraform/main.tf` references these modules by git URL with a pinned version tag.

**Token substitution** is the build mechanism: `build.sh` copies `src/` → `dist/` and replaces `__PLACEHOLDER__` tokens with values from `project.config.sh` via sed.

## Key design decisions

- **Terraform provider:** Mastercard/restapi ~1.19 (generic REST, not HubSpot-specific). All resources use `update_method = "PATCH"`.
- **Auth:** Service Keys preferred (one credential per account). Scripts read from macOS Keychain via `security find-generic-password`. No credentials on disk.
- **CLI elimination:** `upload.sh` uses CMS Source Code API directly — no HubSpot CLI or PAK needed.
- **Modules inherit provider:** Root `main.tf` configures the `restapi` provider. Modules inherit it.
- **Per-project Terraform state:** Each project has its own state. Isolated blast radius.
- **Contact segmentation:** `project_source` CRM property (hidden form field) + per-project dynamic lists, both managed by Terraform.

## HubSpot API quirks (critical for Terraform modules)

- Forms API v3: root requires `createdAt` (any ISO-8601, server overwrites)
- Email fields: require `validation.createdAt` + `validation.configuration.createdAt`
- Non-email fields: must NOT have `validation` key
- `legalConsentOptions.type` = `"implicit_consent_to_process"` (lowercase)
- Every field needs `objectTypeId = "0-1"`
- Lists API v3 wraps in `{"list":{...}}` which breaks restapi provider
- `templateType: page` is the only valid annotation for DM templates
- Landing-page type is set by the API endpoint, not the template
- Asset paths must use `{{ get_asset_url() }}` in HubL templates
- EU1 forms: `//js-eu1.hsforms.net/forms/embed/v2.js` + `region: 'eu1'`
- NA1 forms: `//js.hsforms.net/forms/embed/v2.js` (no region property)

## Build tokens

| Token | Config variable | Notes |
|---|---|---|
| `__PORTAL_ID__` | `HUBSPOT_PORTAL_ID` | |
| `__REGION__` | `HUBSPOT_REGION` | |
| `__HSFORMS_HOST__` | Derived | eu1 → `js-eu1.hsforms.net`, na1 → `js.hsforms.net` |
| `__CAPTURE_FORM_ID__` | `CAPTURE_FORM_ID` | Empty on first build |
| `__SURVEY_FORM_ID__` | `SURVEY_FORM_ID` | Empty if no survey |
| `__DOMAIN__` | `DOMAIN` | |
| `__GA4_ID__` | `GA4_MEASUREMENT_ID` | |
| `__DM_PATH__` | `DM_UPLOAD_PATH` | |

## Credential rules

All secrets live in macOS Keychain. Pattern: `${KEYCHAIN_PREFIX}-hubspot-access-token`.
**Never** write tokens to disk, env files, shell history, or terraform.tfvars.
**Never** run `hs init`.
