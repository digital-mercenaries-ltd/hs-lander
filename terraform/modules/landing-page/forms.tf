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
#   segmentation we use single_line_text with a defaultValue and hide it in
#   the rendered form via CSS (scaffolded main.css hides
#   input[name="project_source"] and its wrapping field group).
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
#   FIELD_GROUP_TOO_MANY_FIELDS). We emit three categories of groups per
#   form: one email group (always), one or more user-field groups built
#   by chunklist(..., 3) on the module input (zero groups when the input
#   is empty), and one segmentation group carrying project_source. Don't
#   collapse these back into a single group — 4+ fields will fail.

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
      #    Empty when var.capture_form_fields is []; no group emitted.
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
    }
  })
}

resource "restapi_object" "survey_form" {
  count         = var.include_survey ? 1 : 0
  path          = "/marketing/v3/forms"
  id_attribute  = "id"
  update_method = "PATCH"

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
      # 2. User-field groups — chunked at 3 to respect v3's per-group cap.
      #    Empty when var.survey_fields is []; no group emitted.
      [
        for chunk in chunklist(var.survey_fields, 3) : {
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
    }
  })
}
