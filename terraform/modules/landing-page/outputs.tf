# terraform/modules/landing-page/outputs.tf

output "capture_form_id" {
  description = "UUID of the capture form"
  value       = restapi_object.capture_form.id
}

output "survey_form_id" {
  description = "UUID of the survey form (empty string if not created)"
  value       = var.include_survey ? restapi_object.survey_form[0].id : ""
}

output "list_id" {
  description = "Contact list ID"
  value       = restapi_object.contact_list.id
}

output "landing_page_id" {
  description = "CMS landing page ID"
  value       = restapi_object.landing_page.id
}

output "thankyou_page_id" {
  description = "CMS thank-you page ID"
  value       = restapi_object.thankyou_page.id
}

output "welcome_email_id" {
  description = "Marketing email ID (for workflow setup)"
  value       = restapi_object.welcome_email.id
}
