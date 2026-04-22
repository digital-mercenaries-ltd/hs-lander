# Changelog

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

2. In `terraform/main.tf`: bump both `source = "... ?ref=v1.4.0"` pins to `?ref=v1.5.0`; add the three new inputs to the `landing_page` module call:

   ```hcl
   module "landing_page" {
     source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.5.0"

     # existing inputs ...
     hubspot_subscription_id    = var.hubspot_subscription_id
     hubspot_office_location_id = var.hubspot_office_location_id
     email_body_html            = file("${path.module}/../dist/emails/welcome-body.html")
     # remove: email_body_path = ...
   }
   ```

   And declare the two new top-level variables (see `scaffold/terraform/main.tf` for the canonical form).

3. Optionally, for hosting modes: set `LANDING_SLUG` and `HOSTING_MODE_HINT` in the project profile (`set-project-field.sh <account> <project> LANDING_SLUG=... HOSTING_MODE_HINT=...`).

4. `npm run tf:init -- -upgrade && npm run tf:plan`. For a project with a partial apply (e.g. Heard), expect `welcome_email` to show as an update (payload restructure). Inspect carefully: any `create` action for a resource that already exists in the portal needs `terraform import` first.

5. **Sender verification:** the `email_reply_to` address must be verified as a sender on the portal before the welcome-email workflow will deliver. See `docs/framework.md` → Sender verification.

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
