# terraform/modules/landing-page/lists.tf

# Dependency anchor: the contact list filters on the project_source CRM
# property, which is created by the account-setup module. Terraform cannot
# infer that ordering from the list's payload alone (the property is
# referenced by name as a string), so we route account-setup's property ID
# through a terraform_data resource and depend on it explicitly. Without
# this, apply races the two resources in parallel and the list hits the
# Lists API before the property has propagated.
resource "terraform_data" "project_source_dependency" {
  input = var.project_source_property_id
}

resource "restapi_object" "contact_list" {
  path          = "/crm/v3/lists"
  id_attribute  = "listId"
  update_method = "PATCH"

  depends_on = [terraform_data.project_source_dependency]

  data = jsonencode({
    name           = "${var.project_slug} Contacts"
    objectTypeId   = "0-1"
    processingType = "DYNAMIC"
    filterBranch = {
      filterBranchType = "OR"
      filterBranches = [
        {
          filterBranchType = "AND"
          filters = [
            {
              filterType = "PROPERTY"
              property   = "project_source"
              operation = {
                operationType = "STRING"
                operator      = "IS_EQUAL_TO"
                value         = var.project_slug
              }
            }
          ]
        }
      ]
    }
  })
}
