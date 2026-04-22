# Plan: Fix Forms formType + List/Property Race (v1.3.1)

**Date:** 2026-04-22
**Status:** Pending
**Scope:** Framework. Three small targeted fixes to the landing-page module exposed by the first real deploy (Heard, 2026-04-22).
**Target release:** v1.3.1 (patch).

## Context

First apply against a live HubSpot portal (147959629, dml account) against the Heard project produced a partial success:

- Created OK: `project_source` property, 4 custom CRM properties, landing page, thank-you page, welcome email
- Failed: capture form, survey form, contact list

Three distinct bugs surfaced:

1. **Forms API v3 now requires `formType`.** Payloads from `terraform/modules/landing-page/forms.tf` omit this field. HubSpot response: `Some required fields were not set: [formType]`. This is API drift — the field became required at some point after v1.0.0.
2. **List creation racing with `project_source` property creation.** The `landing-page` module's list resource references the `project_source` property name, but Terraform has no edge from the list to the `account-setup` module's property resource. Apply ran them in parallel; list creation hit the API before the property propagated. HubSpot response: `The following properties did not exist for the object: project_source`.
3. **Corollary of (2):** the framework's own `lists.tf` already has a comment anticipating this: "If this resource fails on apply, lists may need to be created via hs-curl.sh or the skill instead." The comment acknowledges the race but doesn't fix it.

Both root causes are one-area fixes. All three failures go away with this plan.

## Fix 1 — Add `formType` to both form payloads

**File:** `terraform/modules/landing-page/forms.tf`

Both `restapi_object` resources (`capture_form` and `survey_form`) build their payload via `jsonencode({ ... })`. Add:

```hcl
formType = "hubspot"
```

alongside the existing `name`, `createdAt`, `fieldGroups`, `legalConsentOptions`, `configuration` etc.

**Valid `formType` values** (per HubSpot Forms API v3): `hubspot`, `legacy`, `quickform`, `emailconfirmation`, `flow`, `blog_comment`, `captcha`, `gdpr`, `gdpr_no_type`, `native`. For programmatically-created embeddable forms, `hubspot` is correct.

### Test additions

**`tests/test-terraform-plan.sh`** — extend the existing plan-parsing test to assert every `restapi_object` resource for forms has `formType` in its payload:

```
plan-output | grep -E '^\s*\+ create' | grep form
# then for each, confirm the rendered data JSON contains "formType":"hubspot"
```

Or simpler: add a unit-level test that runs `terraform console` / `terraform plan -json` and greps the JSON payload for the field.

## Fix 2 — Wire `project_source` as a module dependency

**Root cause:** the `account-setup` module creates the `project_source` property; the `landing-page` module creates the list that references it. No dependency edge exists between the two module calls in `scaffold/terraform/main.tf`, so Terraform parallelises them.

**Approach:** have `account-setup` expose the property's ID as an output, and have `landing-page` accept it as a variable. Even if the value isn't used by the list resource directly, declaring the variable establishes the dependency edge; Terraform will wait.

### Changes to `terraform/modules/account-setup/outputs.tf`

Add:

```hcl
output "project_source_property_id" {
  description = "The project_source CRM contact property created by this module. Used as a dependency anchor by consumers."
  value       = restapi_object.project_source.id
}
```

(Or whatever the resource label is — the existing module already creates it; this just surfaces the ID.)

### Changes to `terraform/modules/landing-page/variables.tf`

Add:

```hcl
variable "project_source_property_id" {
  description = "ID of the project_source CRM property, from the account-setup module. Used as a dependency anchor for the contact list."
  type        = string
}
```

### Changes to `terraform/modules/landing-page/lists.tf`

Add an explicit `depends_on` to the list resource:

```hcl
resource "restapi_object" "contact_list" {
  # existing fields ...
  depends_on = [var.project_source_property_id]
}
```

The reference doesn't have to *use* the value — `depends_on` is what creates the explicit ordering. Using the variable directly in the list's payload (e.g. in a filter clause) would also work and is slightly preferable because it ties the semantic dependency to its actual use, but plumbing a variable through just to pin order is fine.

Also remove the anticipatory comment in `lists.tf` now that the fix is in place.

### Changes to `scaffold/terraform/main.tf`

Wire the output from `account-setup` into the `landing-page` module call:

```hcl
module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.3.1"

  # existing inputs ...
  project_source_property_id = module.account_setup.project_source_property_id
}
```

Update the scaffold template so future projects scaffold with the wiring in place.

### Migration note for existing Heard project

Heard's `terraform/main.tf` was scaffolded against v1.0.0 and needs the new variable wired in. Options:

- Simplest: re-pin `source = "... ?ref=v1.3.1"` and add the `project_source_property_id` line. Re-apply.
- Alternative (longer-term): a framework-side migration helper (e.g. `scripts/migrate-project-terraform.sh <slug>`) that updates the pin and wiring in-place. Out of scope for v1.3.1 — manual edit is fine for now with one existing project.

### Test additions

**`tests/test-terraform-plan.sh`** — the plan should show the list resource has an edge from the property resource. Assert by inspecting `terraform graph` output or by running `terraform plan -json` and checking the `planned_values`/`resource_changes` order.

## Fix 3 — VERSION bump + VERSION.compat

Bump `VERSION` to `1.3.1`. The compatibility range in `VERSION.compat` (if that's how it's encoded — from the skill's `check-framework-compat.sh` behaviour I inferred it reads a range) should continue to cover v1.3.x unless the framework's contract with the skill has changed. This plan changes only module internals, not the command surface or the preflight/output contracts — so no compat bump needed.

## Documentation updates

### `docs/framework.md`

Update the landing-page module variables table to document the new `project_source_property_id` input.

### `CHANGELOG.md` (if one exists; otherwise create)

```
## v1.3.1 (2026-04-22)

### Fixed
- Forms API v3 now requires `formType` field; added `formType = "hubspot"` to both capture and survey form payloads.
- Race condition between contact list creation and `project_source` CRM property creation; list now depends on the property via new `project_source_property_id` input.

### Migration
- Existing projects scaffolded against v1.0.0 need to add `project_source_property_id = module.account_setup.project_source_property_id` to the `landing_page` module call in `terraform/main.tf`, and re-pin `source` to `v1.3.1`.
```

## Verification

After implementation:

1. `terraform validate` passes on both modules
2. `terraform plan` against the Heard project (with the migration applied) shows: 3 creates (capture_form, survey_form, contact_list), 0 destroys, 0 replaces. Existing resources (pages, email, properties) show as `no-op` because they're already in state
3. `terraform apply` completes cleanly end-to-end on a fresh portal (not Heard — Heard has partial state already)
4. All existing framework tests still pass
5. New assertions in `test-terraform-plan.sh` verify `formType` in payloads and the property→list dependency edge
6. Tag `v1.3.1` pushed
7. `scaffold/terraform/main.tf` has the new wiring so future scaffolds work out of the box

## Out of scope

- Migration helper script (`migrate-project-terraform.sh`) — manual migration is fine with one existing project
- API contract monitoring / drift detection (separate roadmap item — v1.6)
- Plan-review-gate (already a separate pending plan — will catch destructive operations but not payload correctness)
- Re-applying against Heard — that's the skill's job once v1.3.1 lands. Pre-re-apply, run `terraform plan` and inspect carefully: if the plan shows *any* creates for resources known to have succeeded in the partial apply (pages, email, properties), state needs `terraform import` first to avoid duplicates
