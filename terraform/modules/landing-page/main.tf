# terraform/modules/landing-page/main.tf
#
# Creates everything for one landing page funnel:
# capture form, optional survey form, landing page, thank-you page,
# welcome email, contact list, and optional CRM properties.
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
