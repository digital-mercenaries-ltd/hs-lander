# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

hs-lander — a reusable HubSpot landing page framework. Terraform modules, build pipeline, deployment scripts, and scaffold templates for creating landing page funnels from product briefs.

**Owner:** Digital Mercenaries Ltd (`digital-mercenaries-ltd` GitHub org)

## Status

Current version: see `VERSION` (framework SSoT). `preflight.sh` emits it as `PREFLIGHT_FRAMEWORK_VERSION=<value>` so the skill can check compatibility. Bump `VERSION` in any PR that changes the skill-facing contract; cut a matching `v<VERSION>` tag on merge.

v1.0.0 framework built (Session 2 of the orchestration plan complete). All scripts, both Terraform modules, scaffold templates, the local test suite (550+ assertions across 12 test scripts), and CI workflows are in place.

**Shipped (latest first):**
- v1.8.1 (2026-04-27) — review-and-deploy defects + documentation re-sync (12 fixes from codex review, architectural review, and Heard v1.8.0 deploy)
- v1.8.0 — survey schema, email DNS preflight, capture redirect, survey-submit.js
- v1.7.1 — test-trap, include_bottom_cta removal, migration correction, project-script refresh
- v1.7.0 — HubL scaffold, dark-mode CSS, email anatomy, tier-aware preflight
- v1.6.x series — landing-page apply drift, provider bump, forms privacy text, field-group cap, email publish + upload endpoint, multipart upload, email rendering + form-field hide
- v1.5.0 — hosting modes + landing slug
- v1.4.0 — API drift fixes (forms + email)
- v1.3.x — preflight, scaffold, config-mutation commands
- v1.0.0–v1.2.x — initial framework, two-tier config hierarchy, account-aware preflight

**In flight (elsewhere):**
- `hs-lander` skill in `~/DocsLocal/skills/` — iterating; framework-compatibility feedback flows back to this repo (cf. v1.7.0/v1.8.0/v1.8.1).

**Next:**
- End-to-end deployment testing is done manually per-project at this stage; an automated skill-driven e2e test is a roadmap item (v2.2). Original smoke workflow archived at `docs/archive/workflows/smoke.yml`.
- Session 4 onwards (per-project deployments) happens in per-project repos, not this one — waits on the skill landing.

**Reference docs:**
- Design spec: `~/DocsLocal/digital-mercenaries-ltd/dml-github-org-config/docs/specs/2026-04-10-hs-lander-design.md`
- Orchestration plan: `~/DocsLocal/digital-mercenaries-ltd/dml-github-org-config/docs/plans/2026-04-10-hs-lander-orchestration.md`
- This repo's implementation plan: `docs/superpowers/plans/2026-04-10-hs-lander-framework.md`
- Framework guide: `docs/framework.md`

## Commands

### Framework tests (this repo)

```bash
# Run all local tests
bash tests/test-build.sh
bash tests/test-post-apply.sh
bash tests/test-terraform-plan.sh
bash tests/test-preflight.sh
bash tests/test-accounts-list.sh
bash tests/test-accounts-describe.sh
bash tests/test-projects-list.sh
bash tests/test-init-project-pointer.sh
bash tests/test-scaffold-project.sh
bash tests/test-accounts-init.sh
bash tests/test-set-project-field.sh
bash tests/test-version.sh

# Run deployment test against a live project (requires HubSpot creds + a deployed project directory)
# bash tests/test-deployment.sh /path/to/project
# Nothing automated invokes this today — see roadmap v2.2 for the planned skill-driven e2e test.

# Lint
shellcheck scripts/*.sh tests/*.sh
terraform -chdir=terraform/modules/account-setup fmt -check
terraform -chdir=terraform/modules/landing-page fmt -check
terraform -chdir=terraform/modules/account-setup validate
terraform -chdir=terraform/modules/landing-page validate
```

### Per-project commands (defined in scaffold/package.json)

```bash
npm run preflight   # validate config/credential/API/DNS before build/deploy
npm run build       # src/ → dist/ with token substitution
npm run setup       # build + terraform apply
npm run post-apply  # terraform outputs → ~/.config/hs-lander/<account>/<project>.sh
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
│   ├── lib/
│   │   ├── tier-classify.sh     ← Tier → required-scope mapping (Starter/Pro/Ent/Ent+TX)
│   │   └── validate-name.sh     ← Shared `is_valid_name` regex used by config-touching scripts
│   ├── build.sh             ← src/ → dist/ with token substitution
│   ├── deploy.sh            ← build + upload to HubSpot Design Manager
│   ├── upload.sh            ← PUT files to CMS Source Code API (no CLI needed)
│   ├── watch.sh             ← build + poll for changes
│   ├── post-apply.sh        ← terraform outputs → project.config.sh
│   ├── preflight.sh         ← PREFLIGHT_<NAME>=<state> lines covering tools, config, credential, API, scopes, DNS, email DNS
│   ├── tf.sh                ← Keychain → TF_VAR_* → terraform
│   ├── hs-curl.sh           ← Keychain → curl HubSpot API
│   ├── version.sh               ← FRAMEWORK_VERSION=<value> from ../VERSION
│   ├── upgrade-project-scripts.sh ← Refresh a project's scripts/ from a newer framework install (v1.7.1)
│   ├── accounts-list.sh         ← ACCOUNTS=<csv> of configured accounts (pre-scaffold)
│   ├── accounts-describe.sh     ← ACCOUNT_* fields for a given account (pre-scaffold)
│   ├── accounts-init.sh         ← Create a new account profile from args (config mutation)
│   ├── projects-list.sh         ← PROJECTS=<csv> under an account (pre-scaffold)
│   ├── init-project-pointer.sh  ← Idempotently write project.config.sh sourcing chain (pre-scaffold)
│   ├── scaffold-project.sh      ← Copy scripts + scaffold, stub project profile, write pointer (pre-scaffold)
│   └── set-project-field.sh     ← Update KEY=VALUE fields in an existing project profile (config mutation)
├── scaffold/                ← Template for new projects
│   ├── project.config.example.sh
│   ├── brief-template.md
│   ├── package.json
│   ├── .gitignore
│   └── terraform/main.tf   ← Calls modules by git URL
├── tests/
│   ├── fixtures/
│   ├── test-build.sh             ← Local, no network
│   ├── test-post-apply.sh        ← Local, no network
│   ├── test-terraform-plan.sh    ← Local, parses plan output
│   ├── test-preflight.sh         ← Local, mocks security/curl/dig
│   ├── test-accounts-list.sh     ← Local, sandboxed HS_LANDER_CONFIG_DIR
│   ├── test-accounts-describe.sh ← Local, sandboxed; verifies security is never invoked
│   ├── test-projects-list.sh     ← Local, sandboxed
│   ├── test-init-project-pointer.sh ← Local, sandboxed HS_LANDER_PROJECT_DIR
│   ├── test-scaffold-project.sh  ← Local, end-to-end pre-scaffold flow
│   ├── test-accounts-init.sh     ← Local, sandboxed account-profile creation
│   ├── test-set-project-field.sh ← Local, sandboxed project-field updates
│   ├── test-version.sh           ← Local, version.sh + VERSION file
│   └── test-deployment.sh        ← Network required, live HubSpot
└── .github/workflows/
    └── ci.yml               ← Lint + build test + plan test (every push)
```

An end-to-end deployment workflow (`smoke.yml`) was drafted during v1.0.0 but archived to `docs/archive/workflows/smoke.yml` rather than shipped — see roadmap v2.2 for the intended skill-driven replacement.

### How the pieces connect

**Terraform modules** create HubSpot resources (forms, pages, email, lists). The `account-setup` module runs once per account; `landing-page` runs per project. Both inherit the `restapi` provider from the consuming project's root `main.tf` — they never take `hubspot_token` as a variable.

**Scripts** are generic and config-driven. They source `project.config.sh`, which is a thin sourcing-chain pointer into `~/.config/hs-lander/<account>/config.sh` (shared account settings + credential references) and `~/.config/hs-lander/<account>/<project>.sh` (per-landing-page settings). Keychain service names are explicit — `HUBSPOT_TOKEN_KEYCHAIN_SERVICE` in the account config — never derived. Scripts live in this framework repo and are copied into per-project repos at scaffold time.

**Project directory resolution:** scripts use `PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"` — invoke from the project directory, or export the env var. Scripts no longer derive `PROJECT_DIR` from their own location, so the framework install directory and the consuming project directory can differ.

**Pre-scaffold commands** (run directly from the framework install, before a project has scaffolded scripts of its own):

- `accounts-list.sh` → `ACCOUNTS=<csv>` of configured accounts (or empty, exit 0)
- `accounts-describe.sh <account>` → four `ACCOUNT_*` fields, or `ACCOUNT_STATUS=missing <path>` and exit 1
- `projects-list.sh <account>` → `PROJECTS=<csv>` under that account (exit 1 if account missing)
- `init-project-pointer.sh <account> <project>` → `INIT_POINTER=created|present|conflict <path>`, exit 1 on conflict
- `scaffold-project.sh <account> <project>` → copies scripts + scaffold/*, creates project profile stub under `~/.config/hs-lander/<account>/<project>.sh`, writes pointer. Emits multi-line `SCAFFOLD_*` contract ending with `SCAFFOLD=ok`. No-clobber; fails with `SCAFFOLD=error collision <path>` rather than overwriting.

**Config-mutation commands** (skill-driven writes to operational files, so the skill itself owns zero `Write`/`Edit` calls on `~/.config/hs-lander/`):

- `accounts-init.sh <account> <portal-id> <region> <domain-pattern> <token-keychain-service>` → `ACCOUNTS_INIT=created|conflict|error <detail>`. Validates account name and region; writes atomically; refuses to overwrite an existing profile. Never touches the Keychain.
- `set-project-field.sh <account> <project> KEY=VALUE [KEY=VALUE ...]` → one `SET_FIELD_UPDATED=<key>` or `SET_FIELD_APPENDED=<key>` per pair, ending with `SET_FIELD=ok`. Allowed keys (project-profile schema): `PROJECT_SLUG`, `DOMAIN`, `DM_UPLOAD_PATH`, `GA4_MEASUREMENT_ID`, `CAPTURE_FORM_ID`, `SURVEY_FORM_ID`, `LIST_ID`, `LANDING_SLUG`, `THANKYOU_SLUG`, `HUBSPOT_SUBSCRIPTION_ID`, `HUBSPOT_OFFICE_LOCATION_ID`, `EMAIL_PREVIEW_TEXT`, `AUTO_PUBLISH_WELCOME_EMAIL`, `EMAIL_REPLY_TO`. Unknown keys — including `HUBSPOT_TOKEN_KEYCHAIN_SERVICE` and (since v1.7.0) `HOSTING_MODE_HINT` — are rejected up-front with no file write. The shared `is_valid_name` regex rejects account/project arguments containing `..`, slashes, uppercase, etc.

All pre-scaffold and config-mutation commands respect `HS_LANDER_CONFIG_DIR` (default `~/.config/hs-lander`) and `HS_LANDER_PROJECT_DIR` (default `$PWD`) for testability.

**Scaffold** is the template for new projects. A project's `terraform/main.tf` references these modules by git URL with a pinned version tag.

**Token substitution** is the build mechanism: `build.sh` copies `src/` → `dist/` and replaces `__PLACEHOLDER__` tokens with values from `project.config.sh` via sed.

## Key design decisions

- **Terraform provider:** Mastercard/restapi `~> 2.0` (generic REST, not HubSpot-specific; bumped from `~> 1.19` in v1.6.1). All resources use `update_method = "PATCH"`.
- **Auth:** Service Keys preferred (one credential per account). Scripts read from macOS Keychain via `security find-generic-password`. No credentials on disk.
- **CLI elimination:** `upload.sh` uses CMS Source Code API directly — no HubSpot CLI or PAK needed.
- **Modules inherit provider:** Root `main.tf` configures the `restapi` provider. Modules inherit it.
- **Per-project Terraform state:** Each project has its own state. Isolated blast radius.
- **Contact segmentation:** `project_source` CRM property hidden via Forms API `hidden = true` flag (canonical since v1.6.7); CSS selectors are belt-and-braces. Per-project dynamic lists, both managed by Terraform.
- **Tier-aware preflight (v1.7.0):** required scope set varies by HubSpot tier — Starter 7, Pro/Ent 8 (+`marketing-email`), Ent+TX 9 (+`transactional-email`). See `scripts/lib/tier-classify.sh`.

## HubSpot API quirks (load-bearing only)

The full quirks catalogue lives in `references/hubspot-api-quirks.md`. The shortlist below is the load-bearing set that recurs in module code:

- Forms v3 fieldType vocabulary is closed: `single_line_text`, `dropdown`, `multiple_checkboxes`, `radio`, `email`, etc. Treating `dropdown` as a `single_line_text` (the v1.8.0 miss) is rejected.
- Forms v3 fieldGroup is capped at 3 fields — `chunklist(..., 3)` is the only safe way to assemble groups.
- `hidden = true` is the canonical hide mechanism on Forms v3 (since v1.6.7); `fieldType = "hidden"` is rejected.
- CRM properties: `bool` requires the canonical True/False `options` array (v1.8.1); `enumeration` requires populated options; `string`/`number` must NOT carry the `options` key.
- Marketing emails (v1.5.0+): create as `state = "AUTOMATED_DRAFT"` then publish via local-exec; PATCH against published state is rejected (deferred fix — see plan `2026-04-27-welcome-email-published-state-handling.md`).
- Lists v3 wraps responses in `{"list":{...}}` which breaks the restapi provider's id_attribute path — use `id_attribute = "list/listId"`.
- EU1 forms embed: `//js-eu1.hsforms.net/forms/embed/v2.js` + `region: 'eu1'`. NA1: no region property.

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
| `__PROJECT_SLUG__` | `PROJECT_SLUG` | Used by survey-submit.js for `<slug>_survey_completed` (v1.8.0) |

## Credential rules

All secrets live in macOS Keychain. The account config (`~/.config/hs-lander/<account>/config.sh`) declares `HUBSPOT_TOKEN_KEYCHAIN_SERVICE` — the literal Keychain service name — and scripts read the token via `security find-generic-password -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" -a "$USER" -w`. The actual token is never derived from a prefix; it's referenced by explicit name.

Additional credentials follow the same `<PURPOSE>_KEYCHAIN_SERVICE` naming convention (`GOOGLE_SA_KEY_KEYCHAIN_SERVICE`, `CLOUDFLARE_TOKEN_KEYCHAIN_SERVICE`, etc.) and are added to the account config as future roadmap items land.

**Never** write tokens to disk, env files, shell history, or terraform.tfvars.
**Never** run `hs init` — the HubSpot CLI path was dropped; everything uses Service Keys via REST.
