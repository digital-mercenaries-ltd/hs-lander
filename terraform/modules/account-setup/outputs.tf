# terraform/modules/account-setup/outputs.tf

output "project_source_property_name" {
  description = "Name of the project_source CRM property"
  value       = "project_source"
}

output "project_source_property_id" {
  description = "ID of the project_source CRM property. Intended as a dependency anchor for consumers (the landing-page module wires this into its contact_list so the list waits for the property to exist)."
  value       = restapi_object.project_source_property.id
}
