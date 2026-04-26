# HubSpot API quirks discovered across hs-lander releases

Empirical observations about HubSpot's APIs that bit us, surfaced by live deployments. Each entry documents the quirk, the symptom, and how the framework handles it. Update this file when a new API quirk is discovered; consumers of the framework consult it to understand why specific decisions were made.

## Marketing Email v3 — `flexAreas` write-only on POST

**Quirk:** `PATCH /marketing/v3/emails/{id}` silently strips `content.flexAreas` to `{}` regardless of payload. The endpoint accepts widget-content edits (e.g. `body.html` updates) but rejects layout edits silently — no 400, no warning, just a stripped response.

**Symptom:** Welcome email's body content updates correctly via `terraform apply`, but the layout shows only the default `footer_module` section. Body widget exists in the widget tree but isn't placed in any column → renders empty.

**Workaround:** Layout placement is achievable only via POST (create path) or via UI editing. Consumers upgrading from a release that lacked the correct `flexAreas` payload need a one-time `terraform taint module.landing_page.restapi_object.welcome_email && tf:apply` to recreate via POST. v1.6.7's CHANGELOG migration documents this.

**Framework handling:** `terraform/modules/landing-page/emails.tf` includes the full `flexAreas` shape on both `data` (POST) and `update_data` (PATCH) blocks. The PATCH carries it for completeness even though HubSpot strips it; doing so avoids future divergence if the API is fixed.

## Marketing Email v3 — POST/PATCH responses omit `flexAreas`

**Quirk:** Even when `flexAreas` is in the request payload and HubSpot honours it, the API response (`api_response` in restapi terms) omits `flexAreas` entirely. A `GET /marketing/v3/emails/{id}` call afterward shows the layout was actually persisted.

**Symptom:** `terraform apply` output shows what looks like a stripped layout. Confused operators run additional applies trying to "fix" it.

**Workaround:** Trust GET, not the write-response. After every apply that touches `welcome_email`, verify via `bash $FRAMEWORK_HOME/scripts/hs-curl.sh GET '/marketing/v3/emails/<id>'` and inspect `.content.flexAreas` directly.

**Framework handling:** `tests/test-deployment.sh` uses GET-based assertions (added in v1.6.7) rather than relying on `terraform output`.

## Marketing Email v3 — `module_id: 1155639` is global

**Quirk:** HubSpot's rich-text DnD module has a globally-shared module ID (`1155639`) that's identical across portals, not per-portal. Verified across multiple portals in v1.6.7's Prerequisite A probe.

**Framework handling:** `module_id = 1155639` is hard-coded in `emails.tf`. If a future probe surfaces a portal where a different ID is needed, the value must be plumbed through as a module input — but no consumer has hit that case to date.

## Marketing Email v3 — widget metadata required for rendering

**Quirk:** A widget object lacking metadata (`id`, `name`, `module_id`, `type`, `order`, `label`, `smart_type`, `child_css`, `css`, `styles`) is accepted by the API but not classifiable by HubSpot's render engine. The widget exists in the data tree but doesn't render.

**Framework handling:** Both `primary_rich_text_module` and `preview_text` widgets in `emails.tf` carry full metadata blocks per the v1.6.7 / v1.7.0 fixes.

## Marketing Email v3 — POST cannot create in `AUTOMATED` state

**Quirk:** POST to `/marketing/v3/emails` with `state = "AUTOMATED"` and `isPublished = true` returns:

```
Creating an email in the published state AUTOMATED is not allowed.
Consider using the DRAFT state AUTOMATED_DRAFT.
```

PATCH likewise rejects state transitions: `Cannot schedule or publish an email via the update API. Use the publish API instead.`

**Workaround:** Two-step create-and-publish flow:

1. POST `/marketing/v3/emails` with `state = "AUTOMATED_DRAFT"`, `isPublished = false`.
2. POST `/marketing/v3/emails/{id}/publish` to promote to `AUTOMATED`.

**Framework handling:** v1.6.5 introduced `terraform_data.publish_welcome_email` with a `local-exec` provisioner that fires step 2 via `scripts/hs-curl.sh`. Triggers replace on the email's ID so the publish re-runs on every recreate. Endpoint is idempotent — re-publishing an already-published email is a no-op.

## Marketing Email v3 — `marketing-email` and `transactional-email` scopes are tier-gated

**Quirk:** The `marketing-email` scope (required by the publish endpoint) and `transactional-email` scope (required for transactional sending) cannot be granted on a Service Key on Starter portals — HubSpot rejects with `your account does not have access to the scope`. The gating is at the subscription tier, not at Service Key permission level.

**Symptom:** On Starter, `terraform_data.publish_welcome_email`'s `local-exec` returns:

```
This app hasn't been granted all required scopes.
requiredGranularScopes: ["transactional-email", "marketing-email"]
```

**Framework handling:** v1.7.0 introduced `var.auto_publish_welcome_email` (default `true`). The skill flips this to `false` on Starter portals, gating the publish step out so the email recreates correctly and consumers manually publish via UI. Tier detection lives in `scripts/lib/tier-classify.sh`.

## Forms v3 — `fieldType: hidden` deprecated

**Quirk:** `fieldType = "hidden"` is rejected on Forms v3 with `Could not resolve type id 'hidden' as a subtype of FieldBase`. Supported subtypes are: `datepicker`, `dropdown`, `email`, `file`, `mobile_phone`, `multi_line_text`, `multiple_checkboxes`, `number`, `payment_link_radio`, `phone`, `radio`, `single_checkbox`, `single_line_text`.

**Framework handling:** `project_source` segmentation field uses `fieldType = "single_line_text"` with `hidden = true` (the canonical Forms v3 hide flag, added in v1.6.7). Scaffold CSS provides belt-and-braces selectors as defence-in-depth.

## Forms v3 — `fieldGroup` capped at 3 fields

**Quirk:** Each `fieldGroup` accepts at most 3 fields; v3 rejects with `FormFieldError.FIELD_GROUP_TOO_MANY_FIELDS`.

**Framework handling:** Both `capture_form` and `survey_form` in `forms.tf` emit a three-part `fieldGroups` list: an email-only group, a sequence of user-field groups generated by `chunklist(var.*_fields, 3)`, and a segmentation group holding `project_source`. v1.6.4 introduced this.

## Forms v3 — `legalConsentOptions.privacyText` required

**Quirk:** When `legalConsentOptions.type = "implicit_consent_to_process"`, v3 requires `privacyText` (rejects with `Some required fields were not set: [privacyText]`). Previously accepted without it.

**Framework handling:** `var.privacy_text` (default GDPR-adequate disclosure) wired into both forms. v1.6.3.

## Forms v3 — `richTextType` enum tightened to `[image, text]`

**Quirk:** `richTextType = "NONE"` (previously accepted) is now rejected: `Enum type must be one of: [image, text]`. Removing the key entirely is also rejected; v3 schema flags it required on field groups.

**Framework handling:** All field groups use `richTextType = "text"` (safe default — declares "this field group carries rich-text metadata" as a no-op when no rich-text content is present). v1.6.2.

## Forms v3 — form follow-up email is UI-only

**Quirk:** `/marketing/v3/forms/{id}` does not expose the form follow-up email setting. Cannot be set or read via API on any tier.

**Framework handling:** Welcome email is delivered via a contact-list-triggered Workflow rather than form follow-up. Workflow binding is manual at v1.7.0 (skill-coached); R-roadmap item to API-automate when HubSpot exposes it.

## Pages v3 — `slug` / `domain` / `state` are create-time only

**Quirk:** `PATCH /cms/v3/pages/landing-pages/{id}` with `slug`, `domain`, or `state` in the payload triggers `PAGE_EXISTS` collisions on portals with a root-slug page already on the system domain. Identity-level fields cannot be updated via PATCH; they require recreate via taint or UI editing.

**Framework handling:** Both `landing_page` and `thankyou_page` in `pages.tf` use the `data` (POST) / `update_data` (PATCH) split. Create payload carries all six fields; PATCH carries only `name`, `htmlTitle`, `templatePath`. v1.6.2.

## Lists v3 — response wrapped in `{"list": {...}}`

**Quirk:** `POST /crm/v3/lists` returns `{"list": {"listId": "…", …}}`. The restapi provider expects unwrapped objects; the wrap breaks resource-import.

**Framework handling:** `lists.tf` uses `id_attribute = "list/listId"` (`/`-separated path syntax restapi treats as nested) and `ignore_all_server_changes = true` (provider 2.0+). v1.6.0 / v1.6.1.

## Lists v3 — property must exist before list-creation references it

**Quirk:** Creating a contact list with a filter on a property creates a race: if the property doesn't exist when the list is created, the list creates successfully but with the filter silently dropped.

**Framework handling:** `terraform_data.project_source_dependency` anchor in `lists.tf` plus `depends_on` on `contact_list` ensures property creation precedes list creation. v1.4.0.

## CMS Source Code v3 — environment must be `draft` or `published`

**Quirk:** `PUT /cms/v3/source-code/<env>/content/<path>` requires `<env>` to be `draft` or `published`. The legacy `developer` environment used by HubSpot CLI internals returns HTTP 415: `Environment specified in path 'developer' is invalid`.

**Framework handling:** `scripts/upload.sh` uses `/published/content` (matches the `npm run deploy` direct-to-live contract). `--draft` mode is a future v1.8.0 feature. v1.6.5.

## CMS Source Code v3 — body must be `multipart/form-data`

**Quirk:** `PUT /content/{path}` with `Content-Type: application/octet-stream` and `--data-binary` returns 2xx but discards the file body — "ghost uploads" where status codes look fine and templates never appear in Design Manager.

**Framework handling:** `scripts/upload.sh` uses curl `-F "file=@${file}"` so curl auto-generates the `multipart/form-data; boundary=...` Content-Type. Explicit `Content-Type` headers are forbidden — they would clobber the boundary. v1.6.6.

## Templates served as static HTML when `templateType: page` annotation missing

**Quirk:** A template uploaded to Design Manager without a `{# templateType: page #}` annotation is served as static HTML — no HubL compilation, `{{ get_asset_url(...) }}` literally appears in output, forms degrade silently because the embed script can't resolve.

**Framework handling:** `scaffold/src/templates/*.html` ships the annotation as the first line. v1.7.0's tests/test-deployment.sh check (#5) verifies the annotation persists in served-template metadata.

## Account info — `accountType` field for tier classification

**Quirk:** `GET /account-info/v3/details` returns the canonical tier signal in `accountType`. Probable values per tier (informed-guess, verify before relying):

- `STANDARD` — Starter
- `PROFESSIONAL` — Professional
- `ENTERPRISE` — Enterprise

Subscription/add-on identifiers may live under `subscriptions[]` or `extensions[]` paths; field paths vary by portal seeded data.

**Framework handling:** `scripts/lib/tier-classify.sh` (added in v1.7.0) reads `accountType` and emits `starter` / `pro` / `ent` / `ent+tx` labels. The classifier carries TODO comments where field values are informed-guess pending real-portal probes; update via observed values when probes complete.

## HubSpot rendering cache — Design Manager → served-page latency

**Quirk:** Design Manager template uploads can take ~30–60 seconds to propagate to served landing pages. Cache invalidation is not synchronous with the upload-success response.

**Framework handling:** Post-deploy verification in `tests/test-deployment.sh` should accept stale-cache responses on the first probe or sleep 60s before asserting served-template content. v1.7.0 adds documentation for this in the skill plan; a sleep is at the consumer's discretion in their CI/dogfood flow.

## CRM property creation — race with contact-list filtering

Same as the Lists race above; consolidated entry kept here for cross-reference. See "Lists v3 — property must exist before list-creation references it."

## CRM property — `objectTypeId = "0-1"` always

**Quirk:** Every contact-side custom property requires `objectTypeId = "0-1"`. Form fields likewise. Other object types use different IDs but landing pages in the framework only deal with contacts.

**Framework handling:** Hard-coded throughout `forms.tf` and `account-setup/main.tf`. Documentation note rather than dynamic value.
