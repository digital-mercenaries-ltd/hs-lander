# terraform/modules/landing-page/lists.tf
#
# NOTE: The Lists API v3 response wraps in {"list":{...}} which may
# cause issues with the restapi provider's response parsing.
# If this resource fails on apply, lists may need to be created
# via hs-curl.sh or the skill instead.

resource "restapi_object" "contact_list" {
  path          = "/crm/v3/lists"
  id_attribute  = "listId"
  update_method = "PATCH"

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
