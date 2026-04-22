# terraform/modules/landing-page/emails.tf
#
# HubSpot Marketing Email API v3 quirks (discovered via live probing against
# portal 147959629, 2026-04-22):
#
# - `type = "REGULAR"` gets coerced to "BATCH_EMAIL" (unsendable); use
#   "AUTOMATED_EMAIL" with subcategory = "automated" for a workflow-triggered
#   welcome email.
# - Sender info must live in a nested `from` object; top-level `fromName` /
#   `replyTo` are silently dropped to null.
# - `content.html` is silently discarded. Body HTML must live inside the
#   DnD-style widget tree at content.widgets.primary_rich_text_module.body.rich_text.
# - `subscriptionDetails` is required; subscriptionId and officeLocationId are
#   per-portal values the user must look up in HubSpot UI (Settings →
#   Marketing → Email → Subscription Types / Office Locations).
resource "restapi_object" "welcome_email" {
  path          = "/marketing/v3/emails"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name              = var.email_name
    subject           = var.email_subject
    type              = "AUTOMATED_EMAIL"
    subcategory       = "automated"
    state             = "AUTOMATED"
    emailTemplateMode = "DRAG_AND_DROP"
    language          = var.email_language
    isPublished       = true
    isTransactional   = false

    from = {
      fromName = var.email_from_name
      replyTo  = var.email_reply_to
    }

    subscriptionDetails = {
      subscriptionId   = var.hubspot_subscription_id
      officeLocationId = var.hubspot_office_location_id
    }

    content = {
      templatePath = "@hubspot/email/dnd/Plain_email.html"
      widgets = {
        primary_rich_text_module = {
          body = {
            rich_text = var.email_body_html
          }
        }
      }
    }

    to = {
      limitSendFrequency = false
      suppressGraymail   = false
    }
  })
}
