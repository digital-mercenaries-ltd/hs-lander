# terraform/modules/landing-page/properties.tf
#
# Per-project CRM contact properties. v1.8.0 extends type support beyond
# plain string to enumeration / bool / number, plus auto-adds two derived
# properties:
#
# 1. <project_slug>_survey_completed (bool) — when var.include_survey is
#    true. Flipped to true by scaffold/src/js/survey-submit.js on submit.
#    Enables segmenting "completed survey" vs. "skipped survey" contacts.
#
# 2. <field.name>_other (string) — for every survey_fields[] entry with
#    other_overflow = true. Captures the free-text typed when the user
#    selects "Other" from the enumeration. Reporting on this property is
#    unconstrained (free-text), accepted as the cost of capturing the
#    overflow at all.
#
# The HubSpot CRM v3 properties API quirks:
# - type and fieldType are paired; valid combinations only.
#   string + text, enumeration + (select|radio|checkbox), bool +
#   booleancheckbox, number + number. Other combinations 400.
# - Enumeration options shape: list of {label, value, displayOrder, hidden}
#   with displayOrder per the order desired in the UI.
# - PATCH (update_method = "PATCH") is fine for label/description edits;
#   type changes are rejected (would require destroy + recreate).

locals {
  # Resolve fieldType default from type when consumer omitted it.
  _custom_properties_resolved = [
    for p in var.custom_properties : merge(p, {
      fieldType = (
        p.fieldType != "" ? p.fieldType :
        p.type == "enumeration" ? "select" :
        p.type == "bool" ? "booleancheckbox" :
        p.type == "number" ? "number" :
        "text"
      )
    })
  ]

  # Auto-added <field>_other sibling for survey fields with other_overflow.
  _other_overflow_properties = [
    for f in var.survey_fields : {
      name      = "${f.name}_other"
      label     = "${f.label} — Other (text)"
      type      = "string"
      fieldType = "text"
      groupName = "contactinformation"
      options   = []
    }
    if try(f.other_overflow, false) && f.type != "single_line_text"
  ]

  # Auto-added survey-completion flag when include_survey is on.
  _survey_completed_properties = var.include_survey ? [{
    name      = "${var.project_slug}_survey_completed"
    label     = "Survey Completed (${var.project_slug})"
    type      = "bool"
    fieldType = "booleancheckbox"
    groupName = "contactinformation"
    options   = []
  }] : []

  effective_custom_properties = concat(
    local._custom_properties_resolved,
    local._other_overflow_properties,
    local._survey_completed_properties,
  )
}

resource "restapi_object" "custom_property" {
  for_each      = { for p in local.effective_custom_properties : p.name => p }
  path          = "/crm/v3/properties/contacts"
  id_attribute  = "name"
  update_method = "PATCH"
  update_path   = "/crm/v3/properties/contacts/{id}"

  data = jsonencode(merge(
    {
      name      = each.value.name
      label     = each.value.label
      type      = each.value.type
      fieldType = each.value.fieldType
      groupName = each.value.groupName
    },
    # options key requirements per type:
    # - enumeration: populated array (one entry per consumer-declared option).
    # - bool: canonical True/False array — HubSpot CRM API rejects bool
    #   property creation without it (applies to both consumer-declared
    #   bools and the auto-added <slug>_survey_completed flag).
    # - string / number: key absent entirely; HubSpot rejects {options: []}
    #   on these types but accepts the key being missing.
    each.value.type == "enumeration" ? {
      options = [
        for i, opt in each.value.options : {
          label        = opt
          value        = opt
          displayOrder = i
          hidden       = false
        }
      ]
      } : each.value.type == "bool" ? {
      options = [
        { label = "True", value = "true", displayOrder = 0, hidden = false },
        { label = "False", value = "false", displayOrder = 1, hidden = false },
      ]
    } : {},
  ))
}
