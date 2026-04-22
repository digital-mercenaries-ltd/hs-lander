# tests/fixtures/terraform/main.tf
# Test harness that calls both modules with fixture values.
# Used by test-terraform-plan.sh to validate plan output.

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
    "Authorization" = "Bearer test-token-not-used-for-plan"
    "Content-Type"  = "application/json"
  }
}

module "account_setup" {
  source = "../../../terraform/modules/account-setup"
}

module "landing_page" {
  source = "../../../terraform/modules/landing-page"

  hubspot_portal_id          = "12345678"
  project_slug               = "test-project"
  domain                     = "test.example.com"
  project_source_property_id = module.account_setup.project_source_property_id
  landing_slug               = ""
  thankyou_slug              = "thank-you"
  capture_form_name          = "Test — Signup"
  include_survey             = true
  survey_form_name           = "Test — Survey"
  email_name                 = "Test — Welcome"
  email_subject              = "Welcome to Test"
  email_from_name            = "Test Project"
  email_reply_to             = "test@example.com"
  email_body_html            = file("${path.module}/../emails/welcome-body.html")
  hubspot_subscription_id    = "2269639338"
  hubspot_office_location_id = "375327044798"
  page_landing_name          = "Test — Landing Page"
  page_landing_title         = "Test Project"
  page_thankyou_name         = "Test — Thank You"
  page_thankyou_title        = "Thank You | Test"
  template_path_landing      = "test-project/templates/landing-page.html"
  template_path_thankyou     = "test-project/templates/thank-you.html"
}
