# terraform/modules/landing-page/lists.tf
#
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

# HubSpot Lists API v3 response-wrapping quirk:
# POST /crm/v3/lists returns `{"list": {"listId": ..., ...}}` — the actual
# list payload is nested under a `list` key rather than being at the
# response root. The Mastercard/restapi provider supports slash-delimited
# paths in `id_attribute`, so `id_attribute = "list/listId"` correctly
# extracts the ID via internal.apiclient.GetObjectAtKey(response,
# "list/listId"). Without the nested path the provider raises "internal
# validation failed; object ID is not set" and reports "object *may* have
# been created" — leaving an orphan list on the portal.
#
# Drift detection on subsequent reads is disabled via
# `ignore_all_server_changes = true`: GET /crm/v3/lists/{id} returns the
# same wrapped shape, so field-by-field comparison against the flat `data`
# payload would falsely flag every field as drifted. The list has minimal
# updateable state (filter changes typically require replacement anyway),
# so suppressing drift detection is an acceptable trade-off for this
# resource.
resource "restapi_object" "contact_list" {
  path                      = "/crm/v3/lists"
  id_attribute              = "list/listId"
  update_method             = "PATCH"
  ignore_all_server_changes = true

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
