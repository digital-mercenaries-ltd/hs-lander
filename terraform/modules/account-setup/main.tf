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
      version = "~> 2.0"
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

  # Portal-shared resource. Every per-project landing-page deployment on
  # the same HubSpot portal references this property by name in its
  # contact-list filter. Destroying it orphans every other project on the
  # portal — the list filter would point at a name that no longer exists,
  # and any subsequent project apply recreates the property fresh, losing
  # the historical segmentation tags written to existing contacts.
  #
  # prevent_destroy turns any plan that would destroy or replace this
  # resource into a hard Terraform error. Genuine portal retirement
  # requires removing this block first — a deliberate, auditable two-step.
  lifecycle {
    prevent_destroy = true
  }
}
