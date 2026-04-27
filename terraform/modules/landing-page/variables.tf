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

variable "capture_post_submit_action_override" {
  type        = any
  default     = {}
  description = <<EOT
Override the default capture-form postSubmitAction with a custom one. Empty
object (default) uses the framework's redirect_url to the project's thank-you
slug with ?email={{email}} merge token, which lets the survey form on
thank-you.html attribute submissions to the captured contact. Pass e.g.
{ type = "thank_you", value = "Thanks for submitting." } to keep the inline
HubSpot thank-you snippet (v1.7.x default).
EOT
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
    name           = string
    label          = string
    type           = string
    required       = optional(bool, false)
    options        = optional(list(string), [])
    other_overflow = optional(bool, false)
  }))
  default     = []
  description = <<EOT
Survey form field definitions. Each field declares:
- name: HubSpot internal field name (matches a custom_properties entry by name)
- label: visible label
- type: one of "single_line_text", "dropdown", "multiple_checkboxes", "radio"
- required: bool (default false)
- options: list of strings — REQUIRED when type ∈ {dropdown, multiple_checkboxes, radio};
  ignored otherwise.
- other_overflow: bool (default false) — when true AND options[] contains "Other"
  (or any case-insensitive variant), the framework emits a sibling
  "<field.name>_other" string CRM property + HubSpot form field so the static
  thank-you form's overflow text input has a backing field. Ignored when
  type = "single_line_text".
EOT

  validation {
    condition = alltrue([
      for f in var.survey_fields : (
        contains(["single_line_text", "dropdown", "multiple_checkboxes", "radio"], f.type)
      )
    ])
    error_message = "survey_fields[].type must be one of: single_line_text, dropdown, multiple_checkboxes, radio."
  }

  validation {
    condition = alltrue([
      for f in var.survey_fields : (
        f.type == "single_line_text" || length(f.options) > 0
      )
    ])
    error_message = "survey_fields[] of type dropdown / multiple_checkboxes / radio must declare a non-empty options list."
  }
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
    fieldType = optional(string, "")
    groupName = optional(string, "contactinformation")
    options   = optional(list(string), [])
  }))
  default     = []
  description = <<EOT
Additional CRM contact properties for this project. Each property declares:
- name: HubSpot internal name
- label: visible label
- type: "string" | "enumeration" | "bool" | "number"
- fieldType: "text" | "select" | "checkbox" | "radio" | "booleancheckbox" | "number"
  (auto-defaulted from type when omitted: string→text, enumeration→select,
  bool→booleancheckbox, number→number)
- groupName: HubSpot property group; defaults to "contactinformation"
- options: list of strings — REQUIRED when type = "enumeration"; ignored otherwise

Survey form fields with type ∈ {dropdown, multiple_checkboxes, radio} should
map to custom_properties entries with type = "enumeration" and matching
options. The skill generates these in lockstep so submitted values land in
constrained CRM properties cleanly.
EOT

  validation {
    condition = alltrue([
      for p in var.custom_properties : (
        contains(["string", "enumeration", "bool", "number"], p.type)
      )
    ])
    error_message = "custom_properties[].type must be one of: string, enumeration, bool, number."
  }

  validation {
    condition = alltrue([
      for p in var.custom_properties : (
        p.type != "enumeration" || length(p.options) > 0
      )
    ])
    error_message = "custom_properties[] of type enumeration must declare a non-empty options list."
  }
}
