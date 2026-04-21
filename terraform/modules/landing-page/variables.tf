# terraform/modules/landing-page/variables.tf

variable "hubspot_portal_id" {
  type        = string
  description = "HubSpot portal ID"
}

variable "project_slug" {
  type        = string
  description = "Short project identifier (e.g. my-project). Used for resource naming and contact segmentation."
}

variable "domain" {
  type        = string
  description = "Page domain (e.g. landing.example.com)"
}

variable "landing_slug" {
  type        = string
  default     = ""
  description = "Landing page URL slug (empty = root of subdomain)"
}

variable "thankyou_slug" {
  type        = string
  default     = "thank-you"
  description = "Thank-you page URL slug"
}

variable "capture_form_name" {
  type        = string
  description = "Capture form display name in HubSpot"
}

variable "capture_form_fields" {
  type = list(object({
    name     = string
    label    = string
    type     = string
    required = optional(bool, false)
  }))
  default     = []
  description = "Additional capture form fields beyond email"
}

variable "include_survey" {
  type        = bool
  default     = false
  description = "Whether to create a survey form"
}

variable "survey_form_name" {
  type        = string
  default     = ""
  description = "Survey form display name"
}

variable "survey_fields" {
  type = list(object({
    name     = string
    label    = string
    type     = string
    required = optional(bool, false)
  }))
  default     = []
  description = "Survey form field definitions"
}

variable "email_name" {
  type        = string
  description = "Welcome email name in HubSpot"
}

variable "email_subject" {
  type        = string
  description = "Welcome email subject line"
}

variable "email_from_name" {
  type        = string
  description = "Welcome email sender display name"
}

variable "email_reply_to" {
  type        = string
  description = "Welcome email reply-to address"
}

variable "email_body_path" {
  type        = string
  description = "Path to dist/ welcome email HTML body file"
}

variable "page_landing_name" {
  type        = string
  description = "Landing page display name in HubSpot"
}

variable "page_landing_title" {
  type        = string
  description = "Landing page HTML title"
}

variable "page_thankyou_name" {
  type        = string
  description = "Thank-you page display name in HubSpot"
}

variable "page_thankyou_title" {
  type        = string
  description = "Thank-you page HTML title"
}

variable "template_path_landing" {
  type        = string
  description = "Design Manager template path for landing page"
}

variable "template_path_thankyou" {
  type        = string
  description = "Design Manager template path for thank-you page"
}

variable "custom_properties" {
  type = list(object({
    name      = string
    label     = string
    type      = string
    fieldType = string
    groupName = optional(string, "contactinformation")
  }))
  default     = []
  description = "Additional CRM contact properties for this project"
}
