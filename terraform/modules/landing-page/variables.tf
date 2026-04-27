# terraform/modules/landing-page/variables.tf

variable "hubspot_portal_id" {
  type        = string
  description = "HubSpot portal ID"
}

variable "project_source_property_id" {
  type        = string
  description = "ID of the project_source CRM property, surfaced by the account-setup module. Used as a dependency anchor so the contact list waits for the property to exist before the Lists API references it by name."
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

variable "privacy_text" {
  type        = string
  default     = "We'll use the information you provide to send you occasional updates. You can unsubscribe at any time."
  description = "Short privacy disclosure shown beneath form fields. Required by HubSpot Forms v3 when legalConsentOptions.type = implicit_consent_to_process."
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

variable "email_body_html" {
  type        = string
  description = "Raw HTML to embed inside the welcome email's primary rich-text widget. Rendered within HubSpot's DnD plain email template. Scaffold reads this from dist/emails/welcome-body.html via file()."
}

variable "email_language" {
  type        = string
  default     = "en-gb"
  description = "Email language code (e.g. en-gb, en-us, fr, de)."
}

variable "email_preview_text" {
  type        = string
  default     = ""
  description = "Inbox preview line shown after the subject in Gmail / Apple Mail / Outlook. ~85-110 chars ideal. Empty string emits an empty preview_text widget; HubSpot tolerates this and the client falls back to the first body line."
}

variable "auto_publish_welcome_email" {
  type        = bool
  default     = true
  description = "Whether to automatically publish the welcome email post-create via the publish_welcome_email terraform_data resource. Default true preserves v1.6.5+ behaviour for Pro+ portals where the publish endpoint requires marketing-email scope. Set to false on Starter portals (the publish API endpoint is unavailable, scope is gated by tier); the email goes to UI-publish manually after deploy. Skill flips this via set-project-field.sh AUTO_PUBLISH_WELCOME_EMAIL=false when preflight detects Starter."
}

variable "hubspot_subscription_id" {
  type        = string
  description = "HubSpot subscription ID for the welcome email. Look up in HubSpot UI: Settings → Marketing → Email → Subscription Types. Per-portal value."
}

variable "hubspot_office_location_id" {
  type        = string
  description = "HubSpot office location ID for the welcome email. Look up in HubSpot UI: Settings → Marketing → Email → Office Locations. Per-portal value."
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
