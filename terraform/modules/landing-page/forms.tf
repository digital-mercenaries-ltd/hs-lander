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

resource "restapi_object" "capture_form" {
  path          = "/marketing/v3/forms"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name      = var.capture_form_name
    formType  = "hubspot"
    createdAt = "2024-01-01T00:00:00Z"
    fieldGroups = [
      {
        groupType    = "default_group"
        richTextType = "NONE"
        fields = concat(
          # Email field (always present, with required validation block)
          [
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
          ],
          # Additional fields (no validation block for non-email)
          [for field in var.capture_form_fields : {
            name         = field.name
            label        = field.label
            fieldType    = field.type
            objectTypeId = "0-1"
            required     = field.required
          }],
          # project_source segmentation field — hidden in the rendered form
          # via CSS (see scaffold/src/css/main.css). Kept as
          # single_line_text because Forms v3 rejects fieldType = "hidden".
          [
            {
              name         = "project_source"
              label        = "Project Source"
              fieldType    = "single_line_text"
              objectTypeId = "0-1"
              defaultValue = var.project_slug
            }
          ]
        )
      }
    ]
    legalConsentOptions = {
      type = "implicit_consent_to_process"
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
    fieldGroups = [
      {
        groupType    = "default_group"
        richTextType = "NONE"
        fields = concat(
          [
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
          ],
          [for field in var.survey_fields : {
            name         = field.name
            label        = field.label
            fieldType    = field.type
            objectTypeId = "0-1"
            required     = field.required
          }],
          [
            {
              name         = "project_source"
              label        = "Project Source"
              fieldType    = "hidden"
              objectTypeId = "0-1"
              defaultValue = var.project_slug
            }
          ]
        )
      }
    ]
    legalConsentOptions = {
      type = "implicit_consent_to_process"
    }
    configuration = {
      language = "en"
    }
  })
}
