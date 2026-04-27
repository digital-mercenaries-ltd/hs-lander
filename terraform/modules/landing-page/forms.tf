# terraform/modules/landing-page/forms.tf
#
# HubSpot Forms API v3 quirks:
# - Root requires createdAt (any ISO-8601, server overwrites)
# - Email fields require validation.createdAt + validation.configuration.createdAt
# - Non-email fields must NOT have a validation key
# - legalConsentOptions.type = "implicit_consent_to_process" (lowercase)
# - Every field needs objectTypeId = "0-1"
# - fieldType = "hidden" is NOT a supported subtype of FieldBase in v3.
#   Supported subtypes: datepicker, dropdown, email, file, mobile_phone,
#   multi_line_text, multiple_checkboxes, number, payment_link_radio, phone,
#   radio, single_checkbox, single_line_text. For project_source
#   segmentation we use single_line_text with a defaultValue and the
#   form-level `hidden: true` flag (v1.6.7).
# - legalConsentOptions.privacyText is REQUIRED in v3 when
#   type = "implicit_consent_to_process". Previously accepted without it;
#   v3 rejects with "Some required fields were not set: [privacyText]".
#   Value comes from var.privacy_text (module default is a generic GDPR-
#   adequate disclosure; consumers override per-project when specific
#   legal text is needed).
# - richTextType must be one of [image, text]. The v1/v2 value "NONE" is
#   rejected in v3 ("Enum type must be one of: [image, text]"). We use
#   "text" as the safe default — it declares "this field group carries
#   rich-text metadata" which is a no-op when no rich-text content is
#   present. Removing the key entirely is not safe: v3 schema flags it
#   required on field groups.
# - Each fieldGroup is capped at 3 fields in v3 (rejected with
#   FIELD_GROUP_TOO_MANY_FIELDS). We emit categories of groups per form:
#   email gateway, user-field groups built by chunklist(..., 3), optional
#   "other-overflow" sibling groups (survey_form only, when survey_fields
#   declare other_overflow = true), and the segmentation group carrying
#   project_source. Don't collapse these — 4+ fields will fail.
# - postSubmitAction shapes accepted by Forms v3:
#     {type = "thank_you", value = "<inline HTML>"}    — inline message
#     {type = "redirect_url", value = "<URL>"}         — redirect after submit
#   The redirect URL accepts merge tokens — v1.8.0 ships {{email}} as the
#   default for the captured email's value. Prerequisite A in the v1.8.0
#   plan flagged this for live verification across portals; the syntax
#   below is the most-documented form.

locals {
  # Survey field rendering — switch on field.type.
  # HubSpot Forms v3 quirks per type (verified post-v1.8.0 by Heard's
  # live-portal deploy, which surfaced the original dropdown miss):
  # - single_line_text: just `fieldType = "single_line_text"`, no options
  # - dropdown: `fieldType = "dropdown"` with options populated
  # - multiple_checkboxes: `fieldType = "multiple_checkboxes"` with options
  # - radio: `fieldType = "radio"` with options
  _survey_field_rendered = [
    for f in var.survey_fields : merge(
      {
        name         = f.name
        label        = f.label
        objectTypeId = "0-1"
        required     = f.required
        fieldType = (
          f.type == "single_line_text" ? "single_line_text" :
          f.type == "dropdown" ? "dropdown" :
          f.type == "multiple_checkboxes" ? "multiple_checkboxes" :
          f.type == "radio" ? "radio" :
          "single_line_text"
        )
      },
      length(f.options) > 0 ? {
        options = [
          for i, opt in f.options : {
            label        = opt
            value        = opt
            displayOrder = i
            doubleData   = 0.0
          }
        ]
      } : {},
    )
  ]

  # Overflow sibling fields — one per survey_fields[] entry with
  # other_overflow = true. Hidden via the form-level flag; collected by
  # scaffold/src/js/survey-submit.js when the user types into the paired
  # text input. Backed by `<field>_other` CRM property auto-created in
  # properties.tf.
  _survey_other_fields = [
    for f in var.survey_fields : {
      name         = "${f.name}_other"
      label        = "${f.label} — Other (text)"
      fieldType    = "single_line_text"
      objectTypeId = "0-1"
      hidden       = true
      required     = false
    }
    if try(f.other_overflow, false) && f.type != "single_line_text"
  ]
}

resource "restapi_object" "capture_form" {
  path          = "/marketing/v3/forms"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name      = var.capture_form_name
    formType  = "hubspot"
    createdAt = "2024-01-01T00:00:00Z"
    fieldGroups = concat(
      # 1. Email group — gateway field, single-field group.
      [
        {
          groupType    = "default_group"
          richTextType = "text"
          fields = [
            {
              name         = "email"
              label        = "Email"
              fieldType    = "email"
              objectTypeId = "0-1"
              required     = true
              validation = {
                createdAt = "2024-01-01T00:00:00Z"
                configuration = {
                  createdAt = "2024-01-01T00:00:00Z"
                }
              }
            }
          ]
        }
      ],
      # 2. User-field groups — chunked at 3 to respect v3's per-group cap.
      [
        for chunk in chunklist(var.capture_form_fields, 3) : {
          groupType    = "default_group"
          richTextType = "text"
          fields = [
            for field in chunk : {
              name         = field.name
              label        = field.label
              fieldType    = field.type
              objectTypeId = "0-1"
              required     = field.required
            }
          ]
        }
      ],
      # 3. Segmentation group — project_source, hidden via the canonical
      #    form-level `hidden: true` flag (HubSpot's documented mechanism
      #    on Forms v3). Scaffold CSS adds belt-and-braces selectors for
      #    portals where v3 markup hasn't fully propagated. Kept as
      #    single_line_text because `fieldType = "hidden"` is deprecated
      #    and rejected on Forms v3 — do not revive it.
      [
        {
          groupType    = "default_group"
          richTextType = "text"
          fields = [
            {
              name         = "project_source"
              label        = "Project Source"
              fieldType    = "single_line_text"
              objectTypeId = "0-1"
              hidden       = true
              defaultValue = var.project_slug
            }
          ]
        }
      ]
    )
    legalConsentOptions = {
      type        = "implicit_consent_to_process"
      privacyText = var.privacy_text
    }
    configuration = {
      language = "en"
      # postSubmitAction defaults to redirect_url with the project's
      # thank-you slug + ?email={{email}} merge token, so the survey form
      # on thank-you.html can attribute submissions to the captured contact.
      # Pass capture_post_submit_action_override to keep the v1.7.x inline
      # thank-you behaviour (or to redirect somewhere else entirely).
      # TODO (v1.8.x): verify the {{email}} merge token syntax against a
      # live portal — Prerequisite A in the v1.8.0 plan. Candidate syntaxes
      # per HubSpot docs include {{email}}, {{form_field.email}}, and
      # {{contact.email}}. Update the default below if probes show the
      # live syntax differs.
      postSubmitAction = (
        length(var.capture_post_submit_action_override) > 0
        ? var.capture_post_submit_action_override
        : {
          type  = "redirect_url"
          value = "https://${var.domain}/${var.thankyou_slug == "" ? "thank-you" : var.thankyou_slug}?email={{email}}"
        }
      )
    }
  })
}

# survey_form — the HubSpot-side container for survey submissions.
# NOT rendered via hbspt.forms.create on thank-you.html — see scaffold/src/js/
# survey-submit.js for the static-form + Forms Submissions API pattern.
# Field names declared here MUST match the static form's <input name="...">
# attributes. The skill (separate plan) generates them in lockstep;
# tests/test-deployment.sh asserts the alignment.
resource "restapi_object" "survey_form" {
  count         = var.include_survey ? 1 : 0
  path          = "/marketing/v3/forms"
  id_attribute  = "id"
  update_method = "PATCH"

  # Survey field names match per-project CRM property names (the auto-added
  # <slug>_survey_completed bool plus any consumer-declared custom_properties
  # the survey writes into). Without this depends_on, Terraform parallelises
  # form creation and property creation; the form 400s when the form refers
  # to a property HubSpot doesn't see yet. Heard's v1.8.0 deploy hit this and
  # worked around it with a two-pass apply — v1.8.1 closes that with the
  # graph edge.
  depends_on = [restapi_object.custom_property]

  data = jsonencode({
    name      = var.survey_form_name
    formType  = "hubspot"
    createdAt = "2024-01-01T00:00:00Z"
    fieldGroups = concat(
      # 1. Email group — gateway field, single-field group.
      [
        {
          groupType    = "default_group"
          richTextType = "text"
          fields = [
            {
              name         = "email"
              label        = "Email"
              fieldType    = "email"
              objectTypeId = "0-1"
              required     = true
              validation = {
                createdAt = "2024-01-01T00:00:00Z"
                configuration = {
                  createdAt = "2024-01-01T00:00:00Z"
                }
              }
            }
          ]
        }
      ],
      # 2. User-field groups — chunked at 3, rendering switches on
      #    field.type for dropdown / multiple_checkboxes / radio types
      #    (each carries an options[] array per the v1.8.0 schema).
      [
        for chunk in chunklist(local._survey_field_rendered, 3) : {
          groupType    = "default_group"
          richTextType = "text"
          fields       = chunk
        }
      ],
      # 2a. Overflow sibling groups — one field per survey_fields[] entry
      #     with other_overflow = true; hidden form fields backing the
      #     <field>_other CRM property. Empty list when no fields opt in.
      [
        for chunk in chunklist(local._survey_other_fields, 3) : {
          groupType    = "default_group"
          richTextType = "text"
          fields       = chunk
        }
      ],
      # 3. Segmentation group — project_source, hidden via the canonical
      #    form-level `hidden: true` flag (HubSpot's documented mechanism
      #    on Forms v3). Scaffold CSS adds belt-and-braces selectors for
      #    portals where v3 markup hasn't fully propagated. Kept as
      #    single_line_text because `fieldType = "hidden"` is deprecated
      #    and rejected on Forms v3 — do not revive it.
      [
        {
          groupType    = "default_group"
          richTextType = "text"
          fields = [
            {
              name         = "project_source"
              label        = "Project Source"
              fieldType    = "single_line_text"
              objectTypeId = "0-1"
              hidden       = true
              defaultValue = var.project_slug
            }
          ]
        }
      ]
    )
    legalConsentOptions = {
      type        = "implicit_consent_to_process"
      privacyText = var.privacy_text
    }
    configuration = {
      language = "en"
    }
  })
}
