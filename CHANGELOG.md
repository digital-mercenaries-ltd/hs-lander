# Changelog

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
