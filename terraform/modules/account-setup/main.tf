# terraform/modules/account-setup/main.tf
#
# Run once per HubSpot account. Creates shared resources
# that all projects on the account depend on.
#
# The restapi provider is inherited from the root module.

terraform {
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 1.19"
    }
  }
}

resource "restapi_object" "project_source_property" {
  path          = "/crm/v3/properties/contacts"
  id_attribute  = "name"
  update_method = "PATCH"
  update_path   = "/crm/v3/properties/contacts/{id}"

  data = jsonencode({
    name        = "project_source"
    label       = "Project Source"
    type        = "string"
    fieldType   = "text"
    groupName   = "contactinformation"
    description = "Identifies which project/landing page captured this contact"
  })
}
