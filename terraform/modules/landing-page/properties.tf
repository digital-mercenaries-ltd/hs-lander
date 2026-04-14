# terraform/modules/landing-page/properties.tf

resource "restapi_object" "custom_property" {
  for_each      = { for p in var.custom_properties : p.name => p }
  path          = "/crm/v3/properties/contacts"
  id_attribute  = "name"
  update_method = "PATCH"
  update_path   = "/crm/v3/properties/contacts/{id}"

  data = jsonencode({
    name      = each.value.name
    label     = each.value.label
    type      = each.value.type
    fieldType = each.value.fieldType
    groupName = each.value.groupName
  })
}
