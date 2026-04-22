# scaffold/terraform/main.tf
#
# Calls hs-lander modules by git URL with pinned version.
# Copy this to your project's terraform/ directory.

terraform {
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 1.19"
    }
  }
}

provider "restapi" {
  uri                  = "https://api.hubapi.com"
  write_returns_object = true
  headers = {
    "Authorization" = "Bearer ${var.hubspot_token}"
    "Content-Type"  = "application/json"
  }
}

variable "hubspot_token" {
  type      = string
  sensitive = true
}

variable "hubspot_portal_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "hubspot_region" {
  type = string
}

variable "landing_slug" {
  type    = string
  default = ""
}

variable "thankyou_slug" {
  type    = string
  default = "thank-you"
}

variable "hubspot_subscription_id" {
  type = string
}

variable "hubspot_office_location_id" {
  type = string
}

module "account_setup" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/account-setup?ref=v1.6.0"
}

module "landing_page" {
  source = "git::https://github.com/digital-mercenaries-ltd/hs-lander//terraform/modules/landing-page?ref=v1.6.0"

  hubspot_portal_id          = var.hubspot_portal_id
  project_slug               = "PROJECT_SLUG"
  domain                     = var.domain
  project_source_property_id = module.account_setup.project_source_property_id

  # Page config
  landing_slug  = var.landing_slug
  thankyou_slug = var.thankyou_slug

  capture_form_name      = "PROJECT — Signup"
  email_name             = "PROJECT — Welcome"
  email_subject          = "Welcome"
  email_from_name        = "PROJECT"
  email_reply_to         = "PROJECT@example.com"
  email_body_html        = file("${path.module}/../dist/emails/welcome-body.html")
  page_landing_name      = "PROJECT — Landing Page"
  page_landing_title     = "PROJECT"
  page_thankyou_name     = "PROJECT — Thank You"
  page_thankyou_title    = "Thank You | PROJECT"
  template_path_landing  = "PROJECT_SLUG/templates/landing-page.html"
  template_path_thankyou = "PROJECT_SLUG/templates/thank-you.html"

  hubspot_subscription_id    = var.hubspot_subscription_id
  hubspot_office_location_id = var.hubspot_office_location_id
}

output "capture_form_id" {
  value = module.landing_page.capture_form_id
}

output "survey_form_id" {
  value = module.landing_page.survey_form_id
}

output "list_id" {
  value = module.landing_page.list_id
}
