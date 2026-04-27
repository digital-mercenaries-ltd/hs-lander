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
| `__PROJECT_SLUG__` | `PROJECT_SLUG` (used by `survey-submit.js` to compose the `<slug>_survey_completed` property name; v1.8.0) |

## Terraform Modules

### account-setup

Run once per HubSpot account. Creates the `project_source` CRM contact property used for segmenting contacts by project.

### landing-page

Run per project. Creates: capture form, optional survey form, landing page, thank-you page, welcome email, contact list, and optional custom CRM properties.

Required inputs:

- `project_source_property_id = module.account_setup.project_source_property_id` — wires the list resource's creation order behind the `project_source` property so apply cannot race them. Without this the Lists API rejects the filter payload with `The following properties did not exist for the object: project_source`.
- `hubspot_subscription_id` and `hubspot_office_location_id` — per-portal values from HubSpot UI (Settings → Marketing → Email → Subscription Types / Office Locations). The welcome email's `subscriptionDetails` payload is rejected without them. Scope-restricted lookup isn't available with the framework's default scope set; user provides them once in the account profile.
- `email_body_html` — the welcome email's HTML body content, injected into the DnD `primary_rich_text_module` widget. Scaffold reads it via `file("${path.module}/../dist/emails/welcome-body.html")`.

Both modules use the Mastercard/restapi provider (`~> 2.0`, since v1.6.1) and inherit the provider configuration from the consuming project's root module.

**Sender verification (prerequisite):** the `email_reply_to` address must be a verified sender on the HubSpot portal. HubSpot will accept resource creation with an unverified address but the welcome email workflow will not deliver when triggered. Verify the address in HubSpot UI: Marketing → Email → Settings → From Address before relying on send.

**project_source segmentation field (canonical hidden):** every form includes a `project_source` field (single_line_text with `hidden = true` at the form-field level since v1.6.7 and `defaultValue = project slug`) so contact-list filtering by project works. The form-level `hidden` flag is HubSpot's documented mechanism on Forms v3; scaffolded `src/css/main.css` includes belt-and-braces selectors for portals where v3 markup hasn't fully propagated:

```css
.hs-form input[name="project_source"],
.hs-form .hs_project_source { display: none !important; }
```

The CSS alone is no longer load-bearing — but it doesn't hurt to keep it.

**Welcome email PATCH preserves flexAreas (v1.6.7 / v1.7.1).** Pre-v1.6.7 emails had a `update_data` block that dropped `content.flexAreas`, causing the email body to render empty after any `terraform apply`. From v1.6.7 the PATCH payload includes the full `flexAreas` envelope, so editable fields update in place without rebuilding the email body. `terraform plan` against an email last applied with the v1.6.7 fix shows just the field deltas; no taint required.

The destroy + recreate path (taint) is the fallback only for the rare cases where the email's underlying state shape pre-dates the v1.6.7 fix and PATCH cannot recover it. To do that:

```bash
# From the project root
bash scripts/tf.sh taint module.landing_page.restapi_object.welcome_email
npm run tf:plan    # confirms a CREATE action on the email resource
npm run setup      # recreates with the current shape
```

A workflow that was attached to the old email ID in HubSpot must be re-attached to the new email ID — workflow binding is manual and not managed by Terraform. **Note (v1.8.1):** PATCH against a *published* email is rejected by the API regardless of payload shape; deferred fix is tracked in plan `2026-04-27-welcome-email-published-state-handling.md`.

## Hosting modes

The framework is pure plumbing — it sends whatever `DOMAIN` and `LANDING_SLUG` the project profile supplies. Four hosting modes are supported by setting those two variables appropriately; the Terraform code path is identical across all four.

| Mode | `DOMAIN` | `LANDING_SLUG` | HubSpot side | External side |
|------|----------|----------------|--------------|---------------|
| Custom-domain-primary | `heard.example.com` | `""` | Custom domain connected, `isPrimaryLandingPage = true` | CNAME → HubSpot CDN |
| System-domain | `147959629.hs-sites-eu1.com` | `"heard"` | No custom-domain work; system domain is auto-provisioned | Nothing |
| System-domain-redirect | `147959629.hs-sites-eu1.com` | `"heard"` | Same as system-domain | URL-forward `vanity.example.com` → `<system-domain>/<slug>` |
| System-domain-iframe (roadmap) | `147959629.hs-sites-eu1.com` | `"heard"` | Same as system-domain | S3 + CloudFront with iframe wrapper at `vanity.example.com` |

Switch modes by editing the project profile (`set-project-field.sh <account> <project> DOMAIN=... LANDING_SLUG=...`) and re-running `terraform apply`. No re-creation of resources needed — the pages' `domain` and `slug` fields update in place.

Hosting-mode hint is no longer a project-profile field — `HOSTING_MODE_HINT` was removed from `set-project-field.sh`'s allow-list in v1.7.0. The skill stores hosting mode in its own `<project>.skillstate.sh`; the framework infers nothing from it.

## Authentication

All credentials live in macOS Keychain. The account config declares the Keychain service name; scripts use that literal name (never a derived prefix) when reading the token.

**Account config** (`~/.config/hs-lander/<account>/config.sh`):

```bash
HUBSPOT_PORTAL_ID=""               # e.g. 12345678
HUBSPOT_REGION=""                  # eu1 or na1
DOMAIN_PATTERN=""                  # e.g. *.example.com
HUBSPOT_TOKEN_KEYCHAIN_SERVICE=""  # e.g. <account>-hubspot-access-token
HUBSPOT_SUBSCRIPTION_ID=""         # Settings → Marketing → Email → Subscription Types
HUBSPOT_OFFICE_LOCATION_ID=""      # Settings → Marketing → Email → Office Locations
```

Scripts read the token via:

```bash
security find-generic-password -s "$HUBSPOT_TOKEN_KEYCHAIN_SERVICE" -a "$USER" -w
```

The token is never written to disk, env files, terraform.tfvars, or stdout. `scripts/preflight.sh` validates that the Keychain entry exists and that the HubSpot API responds before any build or deploy step runs.

Future service references (GA4 service account, Cloudflare API token, etc.) follow the same `<PURPOSE>_KEYCHAIN_SERVICE` naming pattern and are added to the account config as their respective roadmap items land.

> **Removed in the config-hierarchy refactor:** the optional `scripts/hs.sh` PAK wrapper for the HubSpot CLI. Everything the framework needs runs via Service Key + REST (`scripts/upload.sh`, `scripts/tf.sh`, `scripts/hs-curl.sh`). Adopters who previously relied on `hs.sh` for manual CLI use can either use `hs-curl.sh` for API calls or install the HubSpot CLI themselves outside this framework.

## Pre-scaffold commands

These scripts run directly from the framework install, before a project has scaffolded scripts of its own. They give the skill (or a human operator) a structured surface for discovery and scaffolding, so the workflow is "call named command, parse output" rather than ad-hoc shell.

All of them respect `HS_LANDER_CONFIG_DIR` (default `~/.config/hs-lander`) and, where relevant, `HS_LANDER_PROJECT_DIR` (default `$PWD`) for scripting and testing.

| Script | Output | Exit |
|---|---|---|
| `scripts/accounts-list.sh` | `ACCOUNTS=<csv>` (empty when none) | 0 always |
| `scripts/accounts-describe.sh <account>` | `ACCOUNT_PORTAL_ID=…`, `ACCOUNT_REGION=…`, `ACCOUNT_DOMAIN_PATTERN=…`, `ACCOUNT_TOKEN_KEYCHAIN_SERVICE=…`, `ACCOUNT_SUBSCRIPTION_ID=…`, `ACCOUNT_OFFICE_LOCATION_ID=…`; or `ACCOUNT_STATUS=missing <path>` | 0 on ok, 1 on missing/args |
| `scripts/projects-list.sh <account>` | `PROJECTS=<csv>`; or `ACCOUNT_STATUS=missing <path>` | 0 if account exists, 1 if missing |
| `scripts/init-project-pointer.sh <account> <project>` | `INIT_POINTER=created\|present\|conflict <path>` | 0 on created/present, 1 on conflict/args |
| `scripts/scaffold-project.sh <account> <project>` | Multi-line: `SCAFFOLD_SCRIPTS=`, `SCAFFOLD_TEMPLATE=`, `SCAFFOLD_PROJECT_PROFILE=`, `SCAFFOLD_POINTER=`, terminator `SCAFFOLD=ok`. Errors: `SCAFFOLD=error <reason>` | 0 on ok, 1 on any error |

**Credential safety:** `accounts-describe.sh` never invokes `security` — it prints the Keychain service name but not the token.

**No-clobber:** `init-project-pointer.sh` refuses to overwrite a pointer whose values differ from the requested account/project; `scaffold-project.sh` refuses to overwrite any file it would copy. Both fail loudly so the skill can surface a decision to the user rather than silently changing state.

## Config-mutation commands

The skill (or human operator) uses these to create and update the operational files under `~/.config/hs-lander/<account>/` without hand-writing them. All writes go to a temp file and are atomically `mv`'d into place, so an interrupted write never leaves a half-baked config.

| Script | Purpose | Output | Exit |
|---|---|---|---|
| `scripts/accounts-init.sh <account> <portal-id> <region> <domain-pattern> <token-keychain-service> [<subscription-id>] [<office-location-id>]` | First-time creation of an account profile (`~/.config/hs-lander/<account>/config.sh`). Trailing two args optional — supply when known; otherwise add later via manual edit. | `ACCOUNTS_INIT=created\|conflict\|error <detail>` | 0 on created, 1 on conflict/error |
| `scripts/set-project-field.sh <account> <project> KEY=VALUE [...]` | Update one or more fields in an existing project profile | `SET_FIELD_UPDATED=<key>` or `SET_FIELD_APPENDED=<key>` per pair, then `SET_FIELD=ok`; or `SET_FIELD=error <reason>` | 0 on ok, 1 on error |

**Credential safety:**

- `accounts-init.sh` takes the Keychain *service name* as an argument and writes that reference into the config file. It never reads, writes, or otherwise touches the Keychain itself — adding the actual token is the user's manual step (`security add-generic-password …` or Keychain Access).
- `set-project-field.sh` only accepts project-profile keys: `PROJECT_SLUG`, `DOMAIN`, `DM_UPLOAD_PATH`, `GA4_MEASUREMENT_ID`, `CAPTURE_FORM_ID`, `SURVEY_FORM_ID`, `LIST_ID`, `LANDING_SLUG`, `THANKYOU_SLUG`, `HUBSPOT_SUBSCRIPTION_ID`, `HUBSPOT_OFFICE_LOCATION_ID`, `EMAIL_PREVIEW_TEXT`, `AUTO_PUBLISH_WELCOME_EMAIL`, `EMAIL_REPLY_TO`. Credential-reference fields (`HUBSPOT_TOKEN_KEYCHAIN_SERVICE`) and removed/skill-only keys (`HOSTING_MODE_HINT` since v1.7.0; `INCLUDE_BOTTOM_CTA` since v1.7.1) are rejected with `SET_FIELD=error unknown-key <key>` — no file write happens. Subscription/office-location are account-level by convention but setting them at project level is a legitimate per-project override.

- Account/project arguments are validated against the shared `is_valid_name` regex (`^[a-z0-9][a-z0-9-]*$`) in `scripts/lib/validate-name.sh` (v1.8.1). This defeats path traversal (`..`), uppercase, dots, slashes, and control characters before any path is constructed. Applied uniformly across `accounts-init.sh`, `accounts-describe.sh`, `projects-list.sh`, `init-project-pointer.sh`, `scaffold-project.sh`, and `set-project-field.sh`.

**Validation is up-front:** `set-project-field.sh` checks every `KEY=VALUE` pair before touching the file, so one bad pair in a batch rejects the whole batch and leaves the profile unchanged.

Relationship to the other commands:

- `accounts-init.sh` creates account profiles; `accounts-describe.sh` reads them; `accounts-list.sh` enumerates them.
- `set-project-field.sh` updates existing project profiles; `scaffold-project.sh` creates them with empty stubs; `post-apply.sh` writes form IDs into them after Terraform apply.

## Versioning

The framework version lives in the `VERSION` file at the repo root. A single plain-text line (`1.3.0`, `1.4.0-rc1`, etc.) so it's trivial to read from shell, from the skill, or from a CI step.

Three ways to read it:

- `cat "$FRAMEWORK_HOME/VERSION"` — simplest, works on a tarball.
- `bash "$FRAMEWORK_HOME/scripts/version.sh"` → `FRAMEWORK_VERSION=<value>` — normalises whitespace, emits canonical `KEY=VALUE` output matching the rest of the framework.
- `bash "$FRAMEWORK_HOME/scripts/preflight.sh" | grep ^PREFLIGHT_FRAMEWORK_VERSION=` — the same value as the first line of preflight's output, so parsing preflight already gives the skill a compatibility signal for free.

`scaffold-project.sh` copies `VERSION` into the project root alongside the scripts and scaffold templates, so a project stays pinned to the framework revision it was scaffolded against — even if the framework install later moves ahead. The project's own `preflight.sh` reads its local `VERSION`, so `PREFLIGHT_FRAMEWORK_VERSION` reflects the scaffolded-against version, not the current framework install.

**Release discipline:** bump `VERSION` as part of any PR that changes the skill-facing contract (preflight output, pre-scaffold command set, config-mutation command set). Cut a matching annotated tag (`v<VERSION>`) at merge time so the git history carries the same markers as the file.

## Preflight output reference

`npm run preflight` (or `bash scripts/preflight.sh`) emits one line per check in the form `PREFLIGHT_<NAME>=<state> [detail]`. Exit 0 when every required check is ok or warn; exit 1 when any required check is missing, empty, unauthorized, forbidden, unreachable, or error. Warnings and the `PROJECT_SOURCE=missing` "first project on account" signal are non-blocking.

| Check | States | Detail shape |
|---|---|---|
| `PREFLIGHT_FRAMEWORK_VERSION` | `<version>` \| `unknown` | Always the first line. Value comes from the `VERSION` file at the framework (or project-scaffolded) root. `unknown` when the file is absent — non-blocking; other checks continue normally. The skill uses this to verify compatibility with the expected framework revision |
| `PREFLIGHT_TOOLS_REQUIRED` | `ok` \| `missing` | `missing` is followed by a comma-list of absent tools (`curl`, `jq`, `terraform`, `npm`). This check runs first; if any required tool is absent, preflight emits `skipped (required tools missing)` for every other contract line and exits 1 |
| `PREFLIGHT_PROJECT_POINTER` | `ok` \| `missing` \| `incomplete` | Missing vars listed when `incomplete` (e.g. `HS_LANDER_ACCOUNT HS_LANDER_PROJECT`) |
| `PREFLIGHT_ACCOUNT_PROFILE` | `ok` \| `missing` \| `incomplete` \| `skipped` | When `missing`: absolute path. When `incomplete`: comma-list of missing fields |
| `PREFLIGHT_PROJECT_PROFILE` | `ok` \| `missing` \| `incomplete` \| `skipped` | Same shape as `ACCOUNT_PROFILE` |
| `PREFLIGHT_CREDENTIAL` | `found` \| `missing` \| `empty` \| `skipped` | `missing` includes the Keychain service name and the `security add-generic-password` command to add it |
| `PREFLIGHT_API_ACCESS` | `ok` \| `unauthorized` \| `forbidden` \| `unreachable` \| `error` \| `skipped` | `unauthorized` = 401 (token invalid/expired); `forbidden` = 403; `unreachable` = curl failed to reach `api.hubapi.com`; `error` = unexpected HTTP |
| `PREFLIGHT_TIER` | `<tier>` \| `unknown` \| `skipped` | One of `starter`, `pro`, `ent`, `ent+tx`, or `unknown`. Tier is inferred from a HubSpot-portal probe (subscription level) and feeds the SCOPES check. Added v1.7.0 |
| `PREFLIGHT_SCOPES` | `ok` \| `missing` \| `error` \| `skipped` | `missing` is followed by a comma-list of missing scopes. Required-scope set varies by tier — Starter 7, Pro/Ent 8 (+`marketing-email`), Ent+TX 9 (+`transactional-email`); see `scripts/lib/tier-classify.sh` |
| `PREFLIGHT_PROJECT_SOURCE` | `ok` \| `missing` \| `error` \| `skipped` | `missing` on 404 is **recoverable, non-blocking** — signals "first project on this account" |
| `PREFLIGHT_DNS` | `ok` \| `missing` \| `skipped` | On `missing`, detail includes the expected CNAME target (`<portal-id>.group0.sites.hscoscdn-<region>.net`) so the user knows which record to create |
| `PREFLIGHT_DOMAIN_CONNECTED` | `ok` \| `missing` \| `skipped` | Probes HubSpot's domain-connected status to distinguish system-domain hosting from custom-domain hosting. Added v1.7.0 |
| `PREFLIGHT_EMAIL_DNS` | `ok` \| `warn` \| `missing` \| `skipped` | Probes SPF/DKIM/DMARC for the email-sending domain. Auth domain comes from `EMAIL_REPLY_TO` (the host part) when set, otherwise falls back to `DOMAIN`. Added v1.8.0 |
| `PREFLIGHT_GA4` | `ok` \| `warn` | `warn` when `GA4_MEASUREMENT_ID` is empty (analytics won't fire, but build/deploy still works) |
| `PREFLIGHT_FORM_IDS` | `ok` \| `warn` | `warn` when `CAPTURE_FORM_ID` is empty (expected before first deploy; populated by `post-apply`) |
| `PREFLIGHT_TOOLS_OPTIONAL` | `ok` \| `warn` \| `skipped` | `warn` is followed by a comma-list of absent optional tools (`pandoc`, `pdftotext`, `git`). Non-blocking — these only affect specific skill workflows (source ingest, repo operations). `skipped` only when required tools are missing |

Credential safety: the HubSpot token is read into a local shell variable, used for the three API probes (account-info, project_source, scopes introspection), and unset via EXIT trap. xtrace is disabled around the token-handling block so `bash -x scripts/preflight.sh` does not leak the token either.

## Prerequisites

- HubSpot Marketing Hub Starter (or Pro / Enterprise) + Content Hub Starter
- Service Key with the scope set for your tier:
  - **Starter (7 scopes):** `crm.objects.contacts.read`, `crm.objects.contacts.write`, `crm.schemas.contacts.write`, `crm.lists.read`, `crm.lists.write`, `forms`, `content` — the `content` scope covers the marketing email resource via `/marketing/v3/emails`
  - **Pro / Enterprise (8 scopes):** Starter set + `marketing-email` (publish path)
  - **Enterprise + Transactional add-on (9 scopes):** Pro set + `transactional-email`
  Tier-aware enforcement lives in `scripts/lib/tier-classify.sh`; `PREFLIGHT_TIER` reports detected tier and `PREFLIGHT_SCOPES` lists the missing scopes for that tier.
- macOS with Keychain (for local development)

### CLI tools

The framework requires `curl`, `jq`, `terraform`, and `npm` at runtime. Optional tools `pandoc`, `pdftotext`, and `git` extend specific features (source ingest, version control). Run `bash scripts/preflight.sh` to verify — it reports missing tools via `PREFLIGHT_TOOLS_REQUIRED` and `PREFLIGHT_TOOLS_OPTIONAL` lines.

On macOS (Homebrew):

```bash
brew install curl jq terraform node pandoc poppler git   # poppler provides pdftotext; node ships npm
```

## References

Detailed HubSpot API quirks, HubL syntax, and email anatomy live alongside the framework rather than in this guide so they stay close to the code that exercises them. Index:

| Document | Purpose |
|---|---|
| `references/email-anatomy.md` | Marketing email payload shape (DnD widgets, flexAreas, lifecycle states) |
| `references/email-auth-dns.md` | SPF / DKIM / DMARC requirements probed by `PREFLIGHT_EMAIL_DNS` |
| `references/forms-submissions-api.md` | Forms Submissions API (secure-submit) used by `survey-submit.js` on thank-you pages |
| `references/hubl-cheatsheet.md` | HubL syntax notes for landing-page templates |
| `references/hubspot-api-quirks.md` | Catalogued API quirks: payload shapes, required-but-undocumented fields, version-specific gotchas |

Module code points back at these documents inline (search `references/` in `terraform/modules/`) so the rationale for each quirky payload shape is one click away.
