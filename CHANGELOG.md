# Changelog

## v1.8.1 (2026-04-27)

Patch release. Twelve surgical fixes from three independent reviews of v1.8.0 (codex code review, architectural review, Heard v1.8.0 deploy session) plus a documentation re-sync. No module input contract changes; no behaviour changes from the consumer's perspective beyond closing the dead-code paths and Starter-blocking defects the reviews surfaced. Existing v1.8.0 state plans clean.

### Fixed

- **Scaffold module pin bumped to v1.8.1** (`scaffold/terraform/main.tf`). Pre-v1.8.1 the pin was stuck at `?ref=v1.6.0`, so newly-scaffolded projects copied v1.8.0 scripts but applied v1.6.0 module code. Every release since v1.6.0 missed silently in fresh scaffolds. Sustainable fix (version-drift warning at preflight time) is queued for v1.9.1.
- **Scaffold root variables wired through.** `scaffold/terraform/main.tf` now declares `email_reply_to`, `email_preview_text`, `auto_publish_welcome_email`, and `capture_post_submit_action_override` as root variables and passes them into `module.landing_page`. Prior to this, `tf.sh` exported `TF_VAR_*` for these values but the scaffold root never consumed them, so `set-project-field.sh ... AUTO_PUBLISH_WELCOME_EMAIL=false` had no effect on Starter consumers.
- **`EMAIL_REPLY_TO` reachable end-to-end.** Added to `preflight.sh`'s `_source_vars` extraction, `set-project-field.sh`'s `ALLOWED_KEYS`, `scaffold-project.sh`'s project-profile stub, and `tf.sh`'s `TF_VAR_*` exports. Pre-v1.8.1, `PREFLIGHT_EMAIL_DNS`'s `EMAIL_REPLY_TO`-then-`DOMAIN` preference order always fell through to `DOMAIN` because no path could populate `EMAIL_REPLY_TO`. Consumers whose email-sending domain differs from their landing-page domain (the common case once a project uses `mail.example.com`) now get the right SPF/DKIM/DMARC records probed.
- **`account-setup/.terraform.lock.hcl` confirmed clean.** Plan's Issue 4 claimed a stale committed lockfile pinning `mastercard/restapi 1.20.0` against `~> 1.19`. Repo audit shows `**/.terraform.lock.hcl` is `.gitignore`d everywhere — no lockfile is tracked, so a fresh `terraform init` always generates against the module's current `~> 2.0` constraint. Live `terraform init -upgrade -backend=false` against the account-setup module confirmed `validate` passes; no committed artefact to update. Issue 4 closed as no-op.
- **Account/project name validation centralised.** New `scripts/lib/validate-name.sh` exports `is_valid_name`. Sourced by `scaffold-project.sh`, `init-project-pointer.sh`, `set-project-field.sh`, `accounts-describe.sh`, and `projects-list.sh`. Defeats path traversal (`..`), uppercase, dots, slashes, and control chars uniformly at the boundary. `accounts-init.sh` keeps its existing inline regex (matches the lib's pattern); a follow-up cleanup can switch it to use the lib helper.
- **`post-apply.sh` honours `HS_LANDER_CONFIG_DIR`.** Was hardcoded to `${HOME}/.config/hs-lander/...`. Now matches the rest of the framework's testability pattern. Also gains an append-if-missing fallback so a hand-edited project profile with a missing line gets the line added rather than silently failing the update.
- **`build.sh` sed substitution escaping.** Replacement values now run through a `_sed_escape` helper that escapes `|`, `&`, and `\`. Pre-v1.8.1 a config value containing any of these (allowed by `set-project-field.sh`'s banned-char check) corrupted the build output silently. Theoretical for current substituted fields; defensive against any future token carrying user-supplied free text.
- **CI shellcheck globs `scripts/lib/`.** `.github/workflows/ci.yml` now lints `scripts/*.sh scripts/lib/*.sh tests/*.sh`. Pre-v1.8.1 `scripts/lib/tier-classify.sh` (and v1.8.1's new `validate-name.sh`) were unlinted.
- **B1: `dropdown` fieldType correction** (`forms.tf`). v1.8.0 mapped `dropdown → "single_line_text"` as an informed-guess; HubSpot Forms v3 rejects this with a fieldType error. Now correctly maps `dropdown → "dropdown"`. Surfaced by Heard's deploy. Lower urgency than B2/B5 because v1.8.0's static-form pattern bypasses the embedded HubSpot survey form.
- **B2: `bool` properties create with canonical True/False options** (`properties.tf`). HubSpot CRM properties API rejects bool property creation without the canonical `[{label:"True",value:"true",displayOrder:0,hidden:false},{label:"False",...,displayOrder:1,...}]` array. The auto-added `<slug>_survey_completed` property hit this on every fresh Starter deploy with `include_survey = true`. Heard worked around manually (created the property via API + `terraform import`); v1.8.1 closes the recurrence path.
- **B5: `survey_form` waits for `custom_property`** (`forms.tf`). Added `depends_on = [restapi_object.custom_property]`. Without this, Terraform parallelises form creation and CRM property creation; HubSpot 400s the form when its field names reference properties not yet on the contact schema. Heard worked around with two-pass apply; v1.8.1 closes the path with a graph edge.
- **Documentation re-sync.** `docs/framework.md`, `CLAUDE.md`, and `README.md` updated for v1.7.x / v1.8.x reality: provider version (`~> 2.0`), `project_source` hide via `hidden = true` form-flag (CSS now belt-and-braces), removal of `HOSTING_MODE_HINT`, full `set-project-field.sh` allow-list, tier-aware scope set, 16-line preflight contract, references/ index, build-token table including `__PROJECT_SLUG__`, scripts/lib/ acknowledged. CLAUDE.md's HubSpot API quirks list condensed to the load-bearing shortlist; full catalogue defers to `references/hubspot-api-quirks.md`.

### Migration

All v1.8.1 changes are non-breaking. `terraform plan` against v1.8.1 should show zero changes for a v1.8.0 project.

To upgrade:

```bash
bash $FRAMEWORK_HOME/scripts/upgrade-project-scripts.sh
# bump ?ref=v1.8.0 → ?ref=v1.8.1 in terraform/main.tf
bash scripts/tf.sh init -upgrade
bash scripts/tf.sh plan
```

For projects that want to use `EMAIL_REPLY_TO` for email-DNS preflight on a domain different from `DOMAIN`, run once:

```bash
bash $FRAMEWORK_HOME/scripts/set-project-field.sh <account> <project> EMAIL_REPLY_TO=hello@mail.example.com
```

Otherwise the existing `DOMAIN`-fallback behaviour is unchanged.

**Heard-specific note.** The B1/B2/B5 fixes ship cleanly for Heard's existing state: B1 is moot (Heard's thank-you uses static `<select>` markup), B2 was worked around via direct API + `terraform import` (future plans no-op; future re-imports clean), B5 was worked around via two-pass apply (the new graph edge means future clean-state applies run in one pass). Net effect: zero state changes.

### Deferred

- **B3 — `welcome_email` PATCH against published state** is architecturally substantial (orchestrate unpublish → PATCH → republish via `terraform_data` local-exec) and tracked separately in `docs/superpowers/plans/2026-04-27-welcome-email-published-state-handling.md`. Likely v1.8.2 or v1.9.0. Heard's interim workaround documented in that plan.

## v1.8.0 (2026-04-27)

Minor release. Survey-funnel completeness (typed survey fields, enumeration-backed CRM properties, working static survey form via Forms Submissions API, capture redirect with email handoff, survey-completion flag, phantom-form documentation) plus email-deliverability preflight (`PREFLIGHT_EMAIL_DNS`). Module input contract changes are additive — existing v1.7.1 projects with `survey_fields = [{type = "single_line_text", ...}]` continue to work without modification. The capture form's default `postSubmitAction` changes from inline thank-you to redirect-with-email, which is the one breaking-ish change; consumers can preserve old behaviour via the new `capture_post_submit_action_override` variable.

### Added

- **`survey_fields[]` field-type extensions.** New types: `dropdown`, `multiple_checkboxes`, `radio` (in addition to the existing `single_line_text`). Each non-text type requires `options = ["A", "B", ...]`. New optional `other_overflow` boolean per field — when true on a non-text field with an "Other" option, the framework auto-emits a sibling `<field.name>_other` (text) HubSpot form field plus a matching CRM string property to capture the free-text typed when the user picks "Other". Validation blocks on the variable enforce options-required and known-type constraints at plan time.
- **`custom_properties[]` type extensions.** New types: `enumeration`, `bool`, `number` (in addition to the existing `string`). `fieldType` becomes optional and defaults from `type` (string→text, enumeration→select, bool→booleancheckbox, number→number). Enumerations require `options = ["A", "B", ...]`. The skill should generate enumeration `custom_properties` in lockstep with matching survey field options so submitted dropdown values land in constrained CRM properties cleanly.
- **`<project_slug>_survey_completed` boolean property** auto-added when `var.include_survey = true`. `scaffold/src/js/survey-submit.js` flips it to `true` on successful survey submission, enabling segmentation between contacts who completed vs. skipped the survey.
- **`scaffold/src/js/survey-submit.js`** (new). Picks the email from URL parameter (`?email=...`), reveals/hides "Other" overflow text inputs as the paired primary field's value changes, collects all field values (semicolon-joined for multi-checkbox; sibling `<field>_other` only when the primary is "Other"), and POSTs to HubSpot's Forms Submissions API at `api.hsforms.com/submissions/v3/integration/secure/submit/<portal>/<form-id>`. New build tokens: `__PROJECT_SLUG__` (used for the survey_completed property name) added to `scripts/build.sh` substitution patterns. `scaffold/src/templates/thank-you.html` wires `data-survey-form` and the script tag.
- **`capture_post_submit_action_override` module variable.** Empty object (default) uses the new redirect-with-email default; pass `{type = "thank_you", value = "..."}` to keep the v1.7.x inline-thank-you behaviour or `{type = "redirect_url", value = "..."}` to redirect to a custom URL.
- **`PREFLIGHT_EMAIL_DNS`** in `scripts/preflight.sh`. Probes the email-auth domain (`EMAIL_REPLY_TO`'s host, falling back to `DOMAIN`) for SPF (HubSpot include + correct `all` mechanism order), DKIM (typed CNAME query against `hs1-<portal-id>._domainkey.<domain>` and `hs2-<portal-id>._domainkey.<domain>`), and DMARC (warn-only). Emits one of: `ok | spf-missing | spf-no-hubspot-include | spf-all-mid-record | dkim-missing | dmarc-missing | region-unknown | skipped`. Preflight contract bumped to 16 `PREFLIGHT_*` lines (FRAMEWORK_VERSION + 15).
- **`tests/test-deployment.sh` schema-alignment check.** Three-way diff: static thank-you survey form `<input name="...">` attributes ↔ HubSpot survey form field names ↔ `custom_properties` names. Catches the failure mode where every individual layer passes its own checks but the layers have drifted out of alignment, so submissions silently land in the wrong (or no) CRM property. Skipped when `INCLUDE_SURVEY=false`.
- **Two new reference docs.** `references/forms-submissions-api.md` documents the embedded-form vs. static-form-plus-Submissions-API split and explains why the survey form uses the latter. `references/email-auth-dns.md` documents the SPF / DKIM / DMARC requirements with the regional-includes table preflight consults.

### Changed

- **Capture form `postSubmitAction` default.** v1.7.x consumers who don't set an override see their capture form switch from inline thank-you snippet to redirect-with-email on next apply. The redirect URL is `https://${var.domain}/${var.thankyou_slug}?email={{email}}`. Set `capture_post_submit_action_override` to preserve old behaviour.
- **`survey_form` header comment** in `forms.tf` documents the Path B contract: the HubSpot-defined survey form is the submission target only, not rendered as an embed; field names must match the static thank-you form's `<input name="...">` attributes.
- **`scripts/lib/tier-classify.sh` Starter row marked verified.** Pro and Ent rows remain informed-guess pending portal access at those tiers.
- **`hubspot-api-quirks.md`** updated with new findings: DKIM selector pattern, SPF mechanism-order rule, capture-form merge-token syntax (TODO until verified), Forms Submissions secure-submit endpoint origin allowlist behaviour.

### Migration

`survey_fields[]` and `custom_properties[]` extensions are additive — existing single-text fields work unchanged.

The capture form `postSubmitAction` default change is the one near-breaking behaviour change. To preserve v1.7.x inline-thank-you behaviour:

```hcl
module "landing_page" {
  capture_post_submit_action_override = {
    type  = "thank_you"
    value = "Thanks for submitting the form."
  }
}
```

Otherwise, plan against v1.8.0 will show an in-place UPDATE to `capture_form` switching the action to redirect.

To upgrade an existing project:

```bash
bash $FRAMEWORK_HOME/scripts/upgrade-project-scripts.sh   # refresh project-local scripts
# bump ?ref=v1.7.1 → ?ref=v1.8.0 in terraform/main.tf
bash scripts/tf.sh init -upgrade
bash scripts/tf.sh plan
# inspect: capture_form will show postSubmitAction in-place UPDATE.
# If you want the old inline behaviour, set the override before applying.
bash scripts/tf.sh apply
```

For projects with `include_survey = true`:

```bash
# After v1.8.0 apply, copy the new survey-submit.js into your project
cp $FRAMEWORK_HOME/scaffold/src/js/survey-submit.js src/js/
# Update src/templates/thank-you.html: add data-survey-form to the survey
# <form>, add the <script src=".../survey-submit.js" defer> tag before
# {{ standard_footer_includes }}, and align <input name="..."> attributes
# with your survey_fields declarations.
npm run build
npm run deploy
```

The `<project_slug>_survey_completed` CRM property is auto-created on apply; nothing to do consumer-side.

**Empirical caveats.** Two prerequisites ship with informed-guess defaults pending real-portal verification:
- Capture form `redirect_url` merge-token syntax (`{{email}}` is the most-documented; alternates include `{{form_field.email}}`, `{{contact.email}}`, `{email}`).
- HubSpot Forms v3 field-shape details for `dropdown` / `multiple_checkboxes` / `radio` (the framework ships `fieldType` mappings that follow Forms v3 docs; verify against a portal-saved form if behaviour differs).

Plus the NA1 SPF include hostname in `references/email-auth-dns.md` is a placeholder pending NA1 portal access. EU1 is verified.

## v1.7.1 (2026-04-27)

Patch — four surgical fixes surfaced by the v1.7.0 deploy round. Test EXIT trap repair, removal of an advisory-only module variable that was misleading consumers, correction of v1.6.7's migration note, and a sanctioned helper for refreshing project-local scripts (R9). Non-breaking; `terraform plan` against v1.7.1 shows zero changes for a v1.7.0 project.

### Fixed

- **`tests/test-deployment.sh` EXIT trap aborted before v1.7.0 served-asset checks.** The trap used `rm -f` for paths created via `mktemp -d`. Under `set -e` the directory `rm -f`s errored, terminating the script before reaching the new served-asset section. Consumers saw "8/8 passed" — the original base tests — and silently missed CSS-200, `hub_generated/template_assets`, scriptloader, `prefers-color-scheme`, `templateType: page` annotation, and `preview_text` widget checks entirely. Trap is now a `cleanup_test_artifacts` function with explicit `rm -f` (files) and `rm -rf` (directories), and tolerates unset/missing late-bound paths so partial-run cleanups don't error.
- **v1.6.7 CHANGELOG migration note overstated PATCH-strip behaviour.** The original note said "PATCH cannot fix existing welcome_email — HubSpot strips flexAreas on PATCH" and prescribed `terraform taint` + recreate as the only path. Empirical evidence is more nuanced: PATCH preserves `flexAreas` when the request body contains the complete section/column envelope. v1.6.7's `update_data` carries the complete structure, so plain `terraform apply` updates existing welcome_email resources in place without recreate. The v1.6.7 migration block is corrected with a v1.7.1-callout banner; consumers stuck on a pre-v1.6.7 broken-PATCH state should try `apply` first, falling back to taint+recreate only if needed. Recreate changes the email ID — re-publishing in UI and re-wiring form follow-up are required after a recreate, both avoidable by plain apply.

### Removed

- **`include_bottom_cta` module variable.** It was advisory-only in v1.7.0 (the scaffold hardcoded the bottom CTA regardless of the variable's value) and misleading consumers who set `false` expecting the second form embed to disappear. Removed from `terraform/modules/landing-page/variables.tf`, `scripts/tf.sh`'s `TF_VAR_*` exports, `scripts/set-project-field.sh` allow-list, and `scaffold-project.sh`'s project-profile stub. To remove the bottom CTA in your project, delete the second `hbspt.forms.create` instance from `src/templates/landing-page.html` — same effect, no variable indirection. `INCLUDE_BOTTOM_CTA` in your project profile (if present) is now ignored — `set-project-field.sh` rejects new attempts to set it. A future release with a real templating layer may reintroduce a properly-wired equivalent.

### Added

- **`scripts/upgrade-project-scripts.sh`** — sanctioned helper for refreshing project-local `scripts/` on framework version bumps. Replaces the manual `rm -rf scripts && cp -r $FRAMEWORK_HOME/scripts ...` dance that's been required since v1.5.0 (R9 in `docs/roadmap.md`). Backs up existing `scripts/` to a timestamped `scripts.bak.<ts>/` directory before replacing. Refreshes the `lib/` subdirectory in lockstep (added in v1.7.0 for `tier-classify.sh`). Idempotent. Usage: `bash $FRAMEWORK_HOME/scripts/upgrade-project-scripts.sh [/path/to/project]`.

### Migration

All v1.7.1 changes are non-breaking for in-place upgrades:

- Test fix is purely additive (more checks now run).
- `include_bottom_cta` removal — consumers who left it at the default `true` see no change. Consumers who set it `false` were already getting `true` behaviour due to the missing wiring; removal makes the variable's absence honest.
- CHANGELOG correction is docs-only.
- `upgrade-project-scripts.sh` is additive and optional.

`terraform plan` against v1.7.1 should show zero changes for a v1.7.0 project. To upgrade:

```bash
bash $FRAMEWORK_HOME/scripts/upgrade-project-scripts.sh
# bump ?ref=v1.7.0 → ?ref=v1.7.1 in terraform/main.tf
bash scripts/tf.sh init -upgrade
bash scripts/tf.sh plan
```

If `INCLUDE_BOTTOM_CTA=...` is set in your project profile, remove the line at your convenience — it's ignored, and a `set-project-field.sh` invocation that tries to set it now returns `SET_FIELD=error unknown-key INCLUDE_BOTTOM_CTA`.

## v1.7.0 (2026-04-26)

Minor release. Substantial scaffold redesign (HubL templates, dark-mode CSS, welcome-email anatomy), preview-text widget on welcome emails, tier-aware preflight, `auto_publish_welcome_email` module flag (Starter portals can suppress the publish step), allow-list updates, and three reference docs documenting the patterns. Six new served-asset/template-metadata checks in `tests/test-deployment.sh`. All new module variables have defaults that preserve v1.6.7 behaviour for existing consumers.

### Added

- **Scaffold `src/` tree.** `scaffold/src/templates/{landing-page,thank-you}.html`, `scaffold/src/css/main.css`, `scaffold/src/js/tracking.js`, `scaffold/src/emails/welcome-body.html`. The framework now ships working defaults that a fresh `npm run build && npm run deploy` produces a renderable landing page from. Templates use HubL primitives — `{# templateType: page #}`, `{{ get_asset_url('__DM_PATH__/...') }}`, `{{ standard_header_includes }}`, `{{ standard_footer_includes }}` — so HubSpot serves them with full runtime support (forms, scriptloader, analytics). CSS uses a `:root` design-token system with `@media (prefers-color-scheme: dark)` overrides. Welcome-email body is structured around the eleven-element anatomy documented in `references/email-anatomy.md`. The skill overwrites with brand-specific content during its workflow; the scaffold defaults exist purely so plumbing tests work pre-skill.
- **`preview_text` widget on welcome emails.** New module variable `email_preview_text` (default empty). When set, populates the inbox preview line shown in Gmail / Apple Mail / Outlook. Widget lives at the head of `flexAreas.main.sections[].columns[].widgets`, ahead of `primary_rich_text_module`. Empty string emits an empty widget; HubSpot tolerates this and clients fall back to the first body line.
- **`auto_publish_welcome_email` module flag** (default `true`). Gates `terraform_data.publish_welcome_email` on `count = var.auto_publish_welcome_email ? 1 : 0`. Default preserves v1.6.5+ behaviour for Pro+ portals where the publish endpoint is reachable. Skill flips to `false` on Starter portals (where the `marketing-email` scope is tier-gated and the publish API returns `MISSING_SCOPES`); the email then waits in `AUTOMATED_DRAFT` for manual UI publish.
- **`include_bottom_cta` module flag** (default `true`). Advisory metadata only — scaffold `landing-page.html` ships a bottom CTA always-on; consumers opt out by editing the template. The variable plumbs through `tf.sh` and the project profile so the skill can record consumer intent without needing a templating engine in `build.sh`.
- **Tier-aware preflight.** `scripts/lib/tier-classify.sh` (new) classifies `accountType` from `/account-info/v3/details` into `starter | pro | ent | ent+tx | unknown`, and provides `required_scopes_for_tier()` to compute the per-tier required scope set. `scripts/preflight.sh` emits two new lines per the contract:
  - `PREFLIGHT_TIER=<label>` — sits between `PREFLIGHT_API_ACCESS` and `PREFLIGHT_SCOPES`. Skipped when API access fails.
  - `PREFLIGHT_DOMAIN_CONNECTED=ok|missing|not-primary|skipped|error` — sits after `PREFLIGHT_DNS`. Probes `/cms/v3/domains` for the project's `DOMAIN`. Catches the temp-slug failure mode v1.6.5 documented (DOMAIN not connected to portal) before `terraform apply` rather than after.
  - `PREFLIGHT_SCOPES` now compares granted scopes against the tier-derived required set. Starter requires the seven base scopes; Pro/Ent add `marketing-email`; Ent+TX adds `transactional-email`. When tier is `starter` and all base scopes are present, emits `PREFLIGHT_SCOPES=ok-starter` (rather than `ok`) so skills can recognise the tier without re-checking.
- **Three reference docs:**
  - `references/email-anatomy.md` — eleven-element welcome-email anatomy, HubSpot merge-tag list, no-manual-UTMs rule.
  - `references/hubl-cheatsheet.md` — required HubL primitives, the "tokens stay, but as arguments to HubL functions" pattern, complete annotated example template.
  - `references/hubspot-api-quirks.md` — empirical surface quirks accumulated across releases (flexAreas write-only on POST, response strips, widget metadata required, tier-gated scopes, etc.).
- **Six new tests in `tests/test-deployment.sh`:** CSS asset returns 200; `hub_generated/template_assets` URL present in served HTML; `/hs/scriptloader/<portal>.js` present; `prefers-color-scheme` block in served CSS; `templateType: page` annotation persists in `cms/v3/source-code/published/metadata`; `preview_text` widget populated when `EMAIL_PREVIEW_TEXT` is set.

### Changed

- **`set-project-field.sh` allow-list** — added `EMAIL_PREVIEW_TEXT`, `AUTO_PUBLISH_WELCOME_EMAIL`, `INCLUDE_BOTTOM_CTA`. Removed `HOSTING_MODE_HINT` (was skill-only state, now lives in `<project>.skillstate.sh` outside the framework's project profile). The removal is enforced — a stale skill clinging to the old key fails loudly with `SET_FIELD=error unknown-key HOSTING_MODE_HINT` rather than silently writing nothing.
- **`scaffold-project.sh`** — copies `scaffold/src/` into the new project alongside `package.json`, `terraform/main.tf`, etc. Project profile stub no longer seeds `HOSTING_MODE_HINT`; gains commented placeholders for `EMAIL_PREVIEW_TEXT`, `AUTO_PUBLISH_WELCOME_EMAIL`, `INCLUDE_BOTTOM_CTA`.
- **`scripts/tf.sh`** — exports `TF_VAR_email_preview_text`, `TF_VAR_auto_publish_welcome_email`, `TF_VAR_include_bottom_cta` from the project profile (with default values matching the module defaults).
- **`primary_rich_text_module.order`** — bumped from `0` to `1` because `preview_text` widget now occupies position `0`. Existing consumers see a no-op PATCH (PATCH preserves widget order; HubSpot accepts the renumber).

### Migration

New scaffold projects (`scaffold-project.sh`) get HubL templates, dark-mode CSS, and welcome-email anatomy by default. Existing projects keep their templates as-is. To upgrade an existing project's scaffold:

```bash
cp $FRAMEWORK_HOME/scaffold/src/templates/*.html src/templates/
cp $FRAMEWORK_HOME/scaffold/src/css/main.css src/css/
cp $FRAMEWORK_HOME/scaffold/src/js/tracking.js src/js/
cp $FRAMEWORK_HOME/scaffold/src/emails/welcome-body.html src/emails/
# then re-stamp project-specific copy/branding (skill does this automatically;
# for hand-edits, replace __PRIMARY_ACCENT__, __BRAND_NAME__, __PRIMARY_CTA_URL__
# etc. with brand values)
npm run build && npm run deploy
bash scripts/tf.sh taint module.landing_page.restapi_object.landing_page
bash scripts/tf.sh taint module.landing_page.restapi_object.thankyou_page
bash scripts/tf.sh apply
```

The taint forces page recreation so the new `templateType`-annotated templates land cleanly in HubSpot's CMS. Module variables `auto_publish_welcome_email` and `include_bottom_cta` default `true`; `email_preview_text` defaults empty (widget renders no preview line until set).

**Allow-list changes:** `HOSTING_MODE_HINT` is no longer accepted by `set-project-field.sh`. New keys accepted: `EMAIL_PREVIEW_TEXT`, `AUTO_PUBLISH_WELCOME_EMAIL`, `INCLUDE_BOTTOM_CTA`.

**Starter consumers:** the skill v1.7.0 plan sets `AUTO_PUBLISH_WELCOME_EMAIL=false` on your project, suppressing the expected `MISSING_SCOPES` error from `publish_welcome_email`. Until the skill is bumped, you can set it manually:

```bash
bash $FRAMEWORK_HOME/scripts/set-project-field.sh \
  <account> <project> AUTO_PUBLISH_WELCOME_EMAIL=false
```

**Empirical caveats.** Two of the v1.7.0 plan's prerequisites ship with informed-guess defaults that need real-portal verification:
- `accountType` → tier label mapping in `scripts/lib/tier-classify.sh` is informed-guess (`STANDARD` → starter, `PROFESSIONAL` → pro, `ENTERPRISE` → ent). Update to match observed values when probes complete.
- Per-tier scope gating is informed-guess (Starter 7 / Pro+Ent 8 / Ent+TX 9). Update when verified against real Service Keys.

`scripts/lib/tier-classify.sh` carries TODO comments where these need verification. A consumer who probes real portals at each tier should update the table and ship as v1.7.1.

## v1.6.7 (2026-04-26)

Patch — two source fixes plus four narrow API-level tests. Welcome emails created since v1.5.0 silently render empty; the `project_source` segmentation field has been visible on rendered forms despite CSS hiding. No new module inputs; no scaffold or preflight changes (those are v1.7.0 scope).

### Fixed

- **Welcome email renders empty for any project deployed under v1.5.0–v1.6.6.** Three compounding bugs in `terraform/modules/landing-page/emails.tf` made the body content unreachable to HubSpot's render engine:
  1. Body content was written to `widgets.primary_rich_text_module.body.rich_text`. HubSpot's render engine reads `body.html`. The API accepts both writes silently but only renders the latter.
  2. The widget object lacked classifying metadata (`id`, `name`, `module_id`, `type`, `order`, `label`, `smart_type`, `child_css`, `css`, `styles`). Without metadata the layout engine cannot classify the widget and skips it.
  3. `content.flexAreas` was absent. HubSpot generates a default layout containing only `footer_module`. Even with correct widget shape there is nowhere for the rich-text body to render.

  Fixed across both `data` (POST) and `update_data` (PATCH) blocks: body field key changed to `html`; full widget metadata supplied (including `module_id: 1155639`, the global HubSpot rich-text module ID — confirmed across multiple portals); explicit `flexAreas.main.sections[].columns[].widgets = ["primary_rich_text_module", "footer_module"]` placement plus the section/column envelope (`backgroundColor`, `backgroundType`, `paddingTop`, `paddingBottom`, `stack`) HubSpot requires to keep the surface from being silently stripped.

- **`project_source` segmentation field visible on rendered forms.** Since v1.5.0 the field has relied on scaffold CSS (`.hs_project_source { display: none; }`) to hide it. HubSpot Forms v3 markup differs from v2 across browsers, so class-name selectors miss in many environments. Both `capture_form` and `survey_form` now set `hidden = true` at field definition — HubSpot's documented mechanism for hiding fields independent of class-name churn. Scaffold CSS remains as defence-in-depth for older portals.

### Added

- **Four API-level checks in `tests/test-deployment.sh`** that catch regressions to the above fixes:
  1. `project_source.hidden == true` on `capture_form`.
  2. `welcome_email.content.widgets.primary_rich_text_module.body.html | length > 0` (correct field key, populated).
  3. `welcome_email.content.flexAreas.main.sections | length > 0` (layout exists).
  4. `welcome_email` flexAreas widgets list contains `primary_rich_text_module` (widget actually placed).

  All checks GET the existing API resources via `WELCOME_EMAIL_ID` / `CAPTURE_FORM_ID` already exported by `post-apply.sh`; no new inputs required.

### Migration

> **v1.7.1 correction.** This migration block originally said *"PATCH cannot fix existing welcome_email resources — HubSpot strips flexAreas on PATCH"* and prescribed `terraform taint` + recreate as the required path. Empirical evidence from the v1.7.0 deploy round is more nuanced: PATCH **preserves** `flexAreas` when the request body contains the **complete** section/column envelope (sections, columns, `path: null`, `breakpointStyles`, etc.). The "stripped to `{main: {}}`" failure mode happened with incomplete envelopes; v1.6.7's `update_data` carries the complete structure, so plain `terraform apply` updates an existing `welcome_email` in place without taint or recreate. Try `apply` first; only fall back to taint+recreate if apply leaves the layout still empty.

The welcome-email widget-shape fix takes effect on v1.6.7+ via either PATCH or CREATE. From v1.6.7 onward, `update_data` contains the complete `flexAreas` structure, so a plain `terraform apply` updates existing welcome_email resources in place.

```bash
# In project directory:
bash scripts/tf.sh apply
```

If apply alone doesn't repair the layout (HubSpot's PATCH may have locked the resource into a state where re-applying the same payload is a no-op), fall back to taint + recreate:

```bash
bash scripts/tf.sh taint module.landing_page.restapi_object.welcome_email
bash scripts/tf.sh apply
```

Note that recreate changes the welcome_email ID, requiring you to:
- Re-publish in HubSpot UI (recreated email goes to AUTOMATED_DRAFT)
- Re-wire any form follow-up email setting (Marketing → Forms → Follow-up tab) since it references the old ID

Plain in-place PATCH avoids both. Try it first.

**On Starter portals**, the recreate path's auto-publish step surfaces a `MISSING_SCOPES` error from HubSpot:

```
This app hasn't been granted all required scopes.
requiredGranularScopes: ["transactional-email", "marketing-email"]
```

This is **expected and harmless** — those scopes are tier-gated and unavailable on Starter regardless of Service Key configuration. The email itself is recreated correctly; only the auto-publish step fails. Manual UI publish (Marketing → Email → '<project> — Welcome' → Review and publish) completes the flow. v1.7.0 makes the publish step opt-out via the `auto_publish_welcome_email` variable so this error stops appearing on Starter.

Pro+ consumers: `publish_welcome_email` continues to fire automatically.

`forms.tf` changes propagate via in-place UPDATE — no taint needed for the form fix. `project_source` field becomes hidden on the rendered form on next apply; existing form ID and submission history preserved.

## v1.6.6 (2026-04-26)

Patch — one-line fix to `scripts/upload.sh` so `npm run deploy` actually transfers file bodies to HubSpot CMS Source Code v3. No Terraform changes; no module input changes.

### Fixed

- **`npm run deploy` reported 8/8 successes but no templates landed in Design Manager.** After v1.6.5 corrected the endpoint (`/developer/content` → `/published/content`), `scripts/upload.sh` continued to send the body as `Content-Type: application/octet-stream` with `--data-binary`. CMS Source Code v3 expects `multipart/form-data` with a `file` part on `PUT /content/{path}`; the octet-stream body returns 2xx (the path is recognised) but treats the body as empty, producing "ghost uploads" where status codes look fine and the live page continues to serve HubSpot's "template not found" fallback. Switched the curl invocation to `-F "file=@${file}"` (curl auto-generates the multipart boundary header — do not set `Content-Type` manually or the boundary header is clobbered). Header comment updated to record the requirement.

### Migration

No Terraform changes. `scripts/upload.sh` lives in each project's checked-out copy — projects scaffolded against earlier versions need the updated `upload.sh`. Until a `hs-lander-refresh-scripts` command lands (roadmap), manually copy `scripts/upload.sh` from `$FRAMEWORK_HOME/scripts/upload.sh` into the project, or apply the inline change (`-H "Content-Type: application/octet-stream"` removed; `--data-binary "@${file}"` → `-F "file=@${file}"`). Bundle this with the v1.6.5 endpoint refresh if you skipped that one.

## v1.6.5 (2026-04-23)

Patch — two source fixes surfaced when Heard deployed against v1.6.4. No module input changes; one new `terraform_data` resource inside the `landing-page` module (see migration below); one one-line script path change.

### Fixed

- **Welcome-email POST rejected `state = "AUTOMATED"`.** HubSpot's Marketing Email API v3 requires automated emails be created as `AUTOMATED_DRAFT` and promoted to `AUTOMATED` via a separate `POST /marketing/v3/emails/{id}/publish` call. v1.6.0 shipped the "correct" final state in the create payload because the only portal we probed had a pre-existing published email — the create path wasn't exercised end-to-end. Fresh POST now returns `Creating an email in the published state AUTOMATED is not allowed. Consider using the DRAFT state AUTOMATED_DRAFT.` Heard's `terraform taint` + apply destroyed the stuck pre-v1.6.0 email and failed to create the replacement, leaving the portal with no welcome email at all. Create payload now sends `state = "AUTOMATED_DRAFT"` / `isPublished = false`; a new `terraform_data.publish_welcome_email` resource fires `POST /publish` via `scripts/hs-curl.sh` after the email resource lands, promoting it to `AUTOMATED`. The provisioner's `triggers_replace` is keyed on the email's ID so it re-runs after a `terraform taint` recreate. Publish endpoint is idempotent — safe to re-run against an already-published email.
- **`npm run deploy` 8/8 uploads failed with HTTP 415.** `scripts/upload.sh:27` hard-coded the endpoint as `.../cms/v3/source-code/developer/content`. The `developer` environment isn't a valid source-code environment in CMS v3 — must be `draft` or `published`. Changed to `/published/content` (direct-to-live matches the current `npm run deploy` contract; a `--draft` mode could be added later). Header comment notes the valid values.

### Migration

Re-pin `?ref=v1.6.4` → `?ref=v1.6.5` and run `npm run tf:init -- -upgrade && npm run tf:plan`. Expected:

- **`terraform_data.publish_welcome_email`: CREATE** — this is a new resource inside the `landing-page` module; every consumer sees it on the first apply under v1.6.5 regardless of whether they already have a published email. If the email already exists and is already `AUTOMATED`, the provisioner's `POST /publish` is a no-op (idempotent endpoint) — safe.
- `welcome_email`: no-op if your email resource is intact; CREATE if you're on a post-taint path (the old stuck email was destroyed under a previous version but the replacement didn't land because of this bug).
- No other resource movement.

**`scripts/upload.sh` lives in each project's checked-out copy** — projects scaffolded against earlier versions need the updated `upload.sh`. Until a `hs-lander-refresh-scripts` command lands (roadmap), manually copy `scripts/upload.sh` from `$FRAMEWORK_HOME/scripts/upload.sh` into the project. Alternatively, apply the one-line change (`/developer/content` → `/published/content`) in place.

## v1.6.4 (2026-04-23)

Patch — HubSpot Forms v3 caps each `fieldGroup` at 3 fields (`FormFieldError.FIELD_GROUP_TOO_MANY_FIELDS`). Surfaced by Heard's survey with 4 questions (email + 4 + project_source = 6 fields in one group). Internal payload restructure; no module input changes.

### Fixed

- **Forms with >2 user fields rejected at validation.** Both `capture_form` and `survey_form` now emit a three-part `fieldGroups` list: an email-only group, a sequence of user-field groups generated by `chunklist(var.*_fields, 3)` (empty when the input list is empty), and a segmentation group holding `project_source`. Visual rendering stacks the groups on the page but submissions route identically.

### Migration

Re-pin `?ref=v1.6.3` → `?ref=v1.6.4`. Consumers with an existing live form see `capture_form` (and `survey_form` when present) as an in-place UPDATE — HubSpot accepts `fieldGroups` reshape on PATCH, form ID preserved, no submission-history loss.

Projects with empty `capture_form_fields` and `survey_fields` emit two groups (email + segmentation). Projects with 1–3 user fields emit three groups. Projects with 4–6 user fields emit four groups. And so on.

No caller-controlled grouping in this patch — fixed partitioning covers every current use case without a breaking `list(list(object))` module-contract change. If group-boundary control becomes needed (e.g. for rich-text dividers between sections), that's a future enhancement.

## v1.6.3 (2026-04-23)

Patch — HubSpot Forms v3 now requires `privacyText` inside `legalConsentOptions` when `type = "implicit_consent_to_process"`. Previously accepted without it; the v3 API now rejects form creation with `Some required fields were not set: [privacyText]`. New optional module input with a GDPR-adequate default; no breaking change.

### Fixed

- **Form creation rejected for missing `privacyText`.** Both `capture_form` and `survey_form` now declare `privacyText = var.privacy_text` inside `legalConsentOptions`. New module variable `privacy_text` defaults to a generic disclosure (`"We'll use the information you provide to send you occasional updates. You can unsubscribe at any time."`). Consumers override per-project when specific legal text is needed.

### Migration

No migration needed — the new variable has a default, so projects re-pinning `?ref=v1.6.2` → `?ref=v1.6.3` pick it up automatically on the next `tf:init -upgrade && tf:plan`. For projects that want custom legal text, pass `privacy_text = "..."` to the `landing_page` module call, or set the variable's value at the root by declaring `variable "privacy_text" { type = string }` and wiring it to `module.landing_page.privacy_text`.

`PRIVACY_TEXT` is not on the `set-project-field.sh` allow-list yet; the module default is expected to suit most projects. Adding a project-profile key for it is tracked as a follow-up if consumers start overriding it often.

## v1.6.2 (2026-04-23)

Patch — three small source fixes surfaced by Heard's 2026-04-23 re-deploy against v1.6.1, plus a documented recovery path for pre-v1.6.0 emails stuck in the legacy payload shape. No module inputs or outputs change; no script changes.

### Fixed

- **`survey_form` still used `fieldType = "hidden"`.** v1.6.0 converted `capture_form` from `"hidden"` to `"single_line_text"` but the matching edit to `survey_form` (`forms.tf:120`) was missed — the two blocks had different leading comments so a `replace_all` match slipped by. Apply errored with the same `Could not resolve type id 'hidden' as a subtype of FieldBase` v1.6.0 fixed for `capture_form`. Normalised the surrounding comment block so future edits catch both variants.
- **Forms v3 tightened `richTextType` to `[image, text]`.** Both form field-groups declared `richTextType = "NONE"`, previously accepted, now rejected with `Enum type must be one of: [image, text]`. Masked by the earlier `"hidden"` error in v1.6.0 probes. Both field groups now use `"text"` (the safe default — declares "this field group carries rich-text metadata" which is a no-op when no rich-text content is present). Dropping the key entirely is not safe: v3 schema flags it required on field groups.
- **`landing_page` PATCH hit `PAGE_EXISTS` when `slug=""` was sent.** The landing-page resource sent `slug`, `domain`, `state` on every PATCH. On a portal whose system domain already hosts a root-slug page (TSC's `tsc-landing.digitalmercenaries.ai/`), a PATCH to `slug = ""` fell through HubSpot's primary-landing-page resolution and collided with the existing root page, failing the whole apply before any real change (a name/title tweak) could reconcile. Both `landing_page` and `thankyou_page` now mirror the v1.6.0 welcome-email pattern: `data` (POST) keeps all six fields for correct create-time publishing; `update_data` (PATCH) sends only `name`, `htmlTitle`, `templatePath`. `slug`, `domain`, and `state` are treated as identity-level and can only be changed via `terraform taint` + recreation or the HubSpot UI — not via a silent in-place PATCH.

### Migration

Re-pin `?ref=v1.6.1` → `?ref=v1.6.2` and run `npm run tf:init -- -upgrade && npm run tf:plan`. For a project on v1.6.1 with a partial apply:

- `capture_form` and `survey_form`: CREATE (neither landed under v1.6.1 because both errored out)
- `landing_page`: in-place UPDATE — the new `update_data` is a strict subset of what it sent before, so the `PAGE_EXISTS` error clears without URL collision
- `thankyou_page`: no-op or small UPDATE
- `welcome_email`: no-op on the editable fields already reconciled under v1.6.1

**Stuck pre-v1.6.0 welcome emails.** Emails created by framework ≤ v1.5.0 have `type = "BATCH_EMAIL"` / `state = "DRAFT"` / `isPublished = false`. v1.6.0+ deliberately omits those fields from the PATCH payload (HubSpot's `/marketing/v3/emails/{id}` PATCH rejects transitions on them). Running `terraform plan` against such an email shows editable-field updates but no state transition. To promote the email to the current shape:

```bash
# From the project root
bash scripts/tf.sh taint module.landing_page.restapi_object.welcome_email
npm run tf:plan    # confirms a CREATE action on the email resource
npm run setup      # recreates with AUTOMATED_EMAIL / AUTOMATED / isPublished=true
```

`taint` marks the resource for destroy+recreate on the next apply. The resulting email has the correct `type` / `state` / `subcategory` / `isPublished` and matches what a fresh v1.6.0+ apply would produce. A workflow that was attached to the old email ID in HubSpot must be re-attached to the new email ID — workflow binding is manual and not managed by Terraform.

## v1.6.1 (2026-04-23)

Patch — bumps the `Mastercard/restapi` provider constraint from `~> 1.19` to `~> 2.0` across all three files that declare it (`scaffold/terraform/main.tf`, `terraform/modules/landing-page/main.tf`, `terraform/modules/account-setup/main.tf`). No module contract changes; no script changes.

### Fixed

- **v1.6.0 `ignore_all_server_changes` attribute was unusable.** `terraform/modules/landing-page/lists.tf` uses `ignore_all_server_changes = true` to suppress drift detection on HubSpot's wrapped Lists API response. That attribute was added to `Mastercard/restapi` in v2.0.0 (April 2024), but both framework modules still pinned the provider to `~> 1.19` (cap 1.20.0), so every v1.6.0 apply errored at plan time with an unknown-attribute diagnostic. Terraform intersects module and root constraints, so the bump must live in the framework modules — bumping only the consuming project's root yields `no suitable version is available` because `~> 1.19, ~> 2.0` has no solution.

### Migration

Consumers pinning `?ref=v1.6.0` re-pin to `?ref=v1.6.1` and run `npm run tf:init -- -upgrade`. Terraform will select a 2.x provider automatically. No module inputs or outputs change. 2.x is additive over 1.x per the provider's own 2.0.0 release notes (the v2 attributes like `ignore_all_server_changes` are opt-in); existing committed 1.x state migrates in place without resource replacement. Projects still on v1.5.0 or earlier don't need to act — their module refs still install `~> 1.19`.

Capped at `~> 2.0` rather than a wider range: v3.0.0 of the provider is a plugin-framework rewrite and warrants its own migration plan if pursued.

## v1.6.0 (2026-04-22)

Minor bump — no breaking change to the module contract, but all three `landing-page` resources whose apply failed against Heard portal 147959629 under v1.5.0 are reworked. Projects already on v1.5.0 with successful applies will see `welcome_email` and `contact_list` as in-place updates; `capture_form` and `survey_form` will be updated in place as well. No new required inputs; re-pin `?ref=v1.6.0` and re-run `tf:init -upgrade && tf:plan`.

### Fixed

- **Welcome email PATCH rejected by HubSpot.** `/marketing/v3/emails/{id}` PATCH with `state = "AUTOMATED"` and `isPublished = true` returns `Cannot schedule or publish an email via the update API. Use the publish API instead.` — HubSpot forbids toggling state/publish status on update. The email resource now declares a separate `update_data` payload that omits `state`, `isPublished`, `type`, `subcategory`, and `emailTemplateMode`; `data` (POST) keeps them so creation still publishes the email. Subsequent applies only PATCH the editable fields (name, subject, language, `from`, `subscriptionDetails`, `content`, `to`).
- **Forms API v3 dropped `fieldType = "hidden"`.** Create-time error: `Could not resolve type id 'hidden' as a subtype of FieldBase; known type ids = [datepicker, dropdown, email, file, mobile_phone, multi_line_text, multiple_checkboxes, number, payment_link_radio, phone, radio, single_checkbox, single_line_text]`. The `project_source` segmentation field on both `capture_form` and `survey_form` now uses `fieldType = "single_line_text"` with `defaultValue = var.project_slug`. The field is rendered by the HubSpot embed; scaffolded `src/css/main.css` must hide `input[name="project_source"]` and `.hs_project_source` (see `docs/framework.md` → project_source segmentation field).
- **Lists API wraps response in `{"list": {...}}`.** Terraform's Mastercard/restapi provider threw `internal validation failed; object ID is not set` on create because it looked for `listId` at the response root rather than under `.list`. The provider's `id_attribute` supports slash-delimited paths (confirmed in `internal/apiclient/utils.go: GetObjectAtKey`), so the list resource now sets `id_attribute = "list/listId"`. Drift detection on reads is suppressed (`ignore_all_server_changes = true`) because the wrapped GET response would otherwise falsely flag every field as drifted against the flat `data` payload.

### Changed

- `scaffold/terraform/main.tf` refs bumped to `v1.6.0`.
- `docs/framework.md` gains a callout documenting the `project_source` CSS hide requirement for scaffolded projects.

### Migration

For projects on v1.5.0 with a clean apply: bump `?ref=v1.5.0` → `?ref=v1.6.0` in `terraform/main.tf`, `npm run tf:init -- -upgrade && npm run tf:plan`, then `npm run setup`.

For projects on v1.5.0 with a **partial apply that left orphan resources on the portal** (e.g. Heard: list created but missing from state): delete the orphan list on the portal first (e.g. `bash scripts/hs-curl.sh DELETE /crm/v3/lists/<listId>`), then re-apply. Without cleanup, the next apply will create a duplicate list.

Add to scaffolded `src/css/main.css`:

```css
.hs-form input[name="project_source"],
.hs-form .hs_project_source { display: none !important; }
```

## v1.5.0 (2026-04-22) — BREAKING

Minor bump — breaking change to both the module contract and the marketing email payload. The `landing-page` module takes three new required inputs (`hubspot_subscription_id`, `hubspot_office_location_id`, `email_body_html`); the previous `email_body_path` input is removed. All projects re-pinning their `source` ref must be rewired (see Migration below).

### Fixed

- **Marketing email was a hollow shell.** Live-probing the welcome email created by v1.4.0 against portal 147959629 revealed three distinct drift issues the API accepted silently at create time: `type = "REGULAR"` coerced to `"BATCH_EMAIL"` (not sendable via workflow); top-level `fromName` / `replyTo` dropped to null because the API expects a nested `from` object; `content.html` silently discarded because modern Marketing Email API expects DnD-widget content. The new payload uses `type = "AUTOMATED_EMAIL"` with `subcategory = "automated"`, nested `from { fromName, replyTo }`, `subscriptionDetails { subscriptionId, officeLocationId }`, and DnD content with the body inside `content.widgets.primary_rich_text_module.body.rich_text`.

### Added

- **Hosting modes plumbing.** `LANDING_SLUG`, `THANKYOU_SLUG`, and `HOSTING_MODE_HINT` are first-class project-profile keys. The landing-page module already accepted `landing_slug`/`thankyou_slug` inputs since v1.0.0; v1.5.0 adds the `TF_VAR_*` exports in `tf.sh` and the project-profile stub, plus the four-mode decision table in `docs/framework.md` (custom-domain-primary, system-domain, system-domain-redirect, system-domain-iframe). The framework code path is identical across all four — mode selection lives in the project config.
- **Account-level subscription + office-location fields.** `HUBSPOT_SUBSCRIPTION_ID` and `HUBSPOT_OFFICE_LOCATION_ID` in `~/.config/hs-lander/<account>/config.sh`; read by `tf.sh` into `TF_VAR_*`; accepted as optional trailing args by `accounts-init.sh`; surfaced by `accounts-describe.sh` in new `ACCOUNT_SUBSCRIPTION_ID`/`ACCOUNT_OFFICE_LOCATION_ID` lines. These are per-portal values the user looks up once in HubSpot UI (Settings → Marketing → Email → Subscription Types / Office Locations) — the framework doesn't probe them (would need a scope we don't currently request).
- **Extended `set-project-field.sh` allow-list.** New keys: `LANDING_SLUG`, `THANKYOU_SLUG`, `HOSTING_MODE_HINT`, `HUBSPOT_SUBSCRIPTION_ID`, `HUBSPOT_OFFICE_LOCATION_ID`. The last two are account-level by convention but the sourcing chain makes per-project overrides straightforward.

### Changed

- `scaffold-project.sh` project-profile stub includes the three hosting-mode fields.
- `scaffold/terraform/main.tf` refs bumped to `v1.5.0`; declares top-level `landing_slug`, `thankyou_slug`, `hubspot_subscription_id`, `hubspot_office_location_id` variables and wires them through.
- `docs/framework.md` gains a **Hosting modes** section with the four-mode decision table and an explicit **Sender verification** prerequisite callout.

### Migration

For projects scaffolded against earlier versions:

1. Add to `~/.config/hs-lander/<account>/config.sh`:

   ```bash
   HUBSPOT_SUBSCRIPTION_ID="<from HubSpot UI: Settings → Marketing → Email → Subscription Types>"
   HUBSPOT_OFFICE_LOCATION_ID="<from HubSpot UI: Settings → Marketing → Email → Office Locations>"
   ```

2. In `terraform/main.tf`, declare the four new top-level variables alongside the existing `hubspot_token` / `hubspot_portal_id` / `domain` / `hubspot_region` declarations:

   ```hcl
   variable "hubspot_subscription_id"    { type = string }
   variable "hubspot_office_location_id" { type = string }
   variable "landing_slug" {
     type    = string
     default = ""
   }
   variable "thankyou_slug" {
     type    = string
     default = "thank-you"
   }
   ```

   The first two are required — `tf.sh` will export `TF_VAR_hubspot_subscription_id` / `TF_VAR_hubspot_office_location_id` from the account config, so `terraform plan` needs the variable declarations to receive them. The two slug variables have defaults matching custom-domain-primary hosting mode; non-default values are set per-project via `set-project-field.sh` (see step 4).

3. In the same file, bump both `source = "... ?ref=v1.4.0"` pins to `?ref=v1.5.0` and update the `landing_page` module call:

   ```hcl
   module "landing_page" {
     source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.5.0"

     # existing inputs ...
     hubspot_subscription_id    = var.hubspot_subscription_id
     hubspot_office_location_id = var.hubspot_office_location_id
     email_body_html            = file("${path.module}/../dist/emails/welcome-body.html")
     landing_slug               = var.landing_slug
     thankyou_slug              = var.thankyou_slug
     # remove: email_body_path = ...
   }
   ```

   See `scaffold/terraform/main.tf` for the complete canonical form.

4. Optionally, for hosting modes: set `LANDING_SLUG` and `HOSTING_MODE_HINT` in the project profile (`set-project-field.sh <account> <project> LANDING_SLUG=... HOSTING_MODE_HINT=...`).

5. `npm run tf:init -- -upgrade && npm run tf:plan`. For a project with a partial apply (e.g. Heard), expect `welcome_email` to show as an update (payload restructure). Inspect carefully: any `create` action for a resource that already exists in the portal needs `terraform import` first.

6. **Sender verification:** the `email_reply_to` address must be verified as a sender on the portal before the welcome-email workflow will deliver. See `docs/framework.md` → Sender verification.

7. **Workflow binding is manual.** Setting `state = "AUTOMATED"` on the email resource is not the same as attaching it to a workflow trigger. The framework creates a send-ready email; attaching it to a form-submission workflow is a HubSpot UI step (Automation → Workflows → New workflow → "Send marketing email"). This was manual under v1.4.0 too — noted here because the new `AUTOMATED_EMAIL` type reads as if it self-wires.

## v1.4.0 (2026-04-22)

Minor bump because the `landing-page` module takes a new required input (`project_source_property_id`). Any project re-pinning its `source` ref must also add this wiring or terraform init will reject the call.

### Fixed

- Forms API v3 drift: `formType` is now a required field on the `/marketing/v3/forms` payload. Both `capture_form` and `survey_form` resources in the `landing-page` module now set `formType = "hubspot"`. Without this, apply failed with `Some required fields were not set: [formType]`.
- Race condition between `account-setup.project_source_property` and `landing-page.contact_list`. Previously the two modules ran in parallel during apply, and the list hit the Lists API before the `project_source` CRM property had propagated, failing with `The following properties did not exist for the object: project_source`. The `landing-page` module now accepts a new `project_source_property_id` input and uses a `terraform_data` anchor + explicit `depends_on` to force ordering.

### Migration

Projects scaffolded against v1.0.0–v1.3.0 need a one-line addition plus a ref bump in `terraform/main.tf`:

```hcl
module "account_setup" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v1.4.0"
}

module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.4.0"

  # existing inputs ...
  project_source_property_id = module.account_setup.project_source_property_id
}
```

Then `terraform init -upgrade && terraform plan`. Inspect the plan carefully before re-applying against a partially-applied portal: if any previously-succeeded resource (pages, email, properties) shows as `create`, import it first with `terraform import` to avoid duplicates.

## v1.3.0 (2026-04-22)

Framework versioning (`VERSION` file, `scripts/version.sh`, `PREFLIGHT_FRAMEWORK_VERSION` first-line of preflight output, `SCAFFOLD_VERSION` copied into scaffolded projects). Consumed by the hs-lander skill to verify compatibility with the framework revision it expects.

See PRs #7–#9 for the full set of pre-scaffold and config-mutation commands that shipped alongside.

## v1.0.0 (2026-04-14)

Initial framework release. Two Terraform modules (`account-setup`, `landing-page`), build/deploy/preflight scripts, scaffold templates, 39 local-test assertions, CI workflows.
