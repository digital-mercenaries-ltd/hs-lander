# Changelog

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
