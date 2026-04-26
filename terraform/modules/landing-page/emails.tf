# terraform/modules/landing-page/emails.tf
#
# HubSpot Marketing Email API v3 quirks (discovered via live probing against
# portal 147959629, 2026-04-22 through 2026-04-23):
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
# - PATCH on /marketing/v3/emails/{id} REJECTS state/isPublished/type/
#   subcategory/emailTemplateMode changes with "Cannot schedule or publish an
#   email via the update API. Use the publish API instead." Therefore the
#   update payload (`update_data`) must omit those fields. Create payload
#   (`data`) sends the non-transition state so POST succeeds on a fresh email.
# - Welcome email body must live at content.widgets.primary_rich_text_module.body.html
#   (NOT body.rich_text — accepted on write, never rendered). The widget object
#   needs full metadata (id, name, module_id 1155639, type "module", order, etc.)
#   and content.flexAreas.main.sections[].columns[].widgets must list
#   "primary_rich_text_module" alongside "footer_module" for the layout engine
#   to place it. PATCH silently strips flexAreas to {}, so consumers upgrading
#   from a pre-fix version need a `terraform taint module.landing_page.
#   restapi_object.welcome_email` + apply to recreate via the create path.
# - POST cannot create an email directly in AUTOMATED state. HubSpot rejects
#   with "Creating an email in the published state AUTOMATED is not allowed.
#   Consider using the DRAFT state AUTOMATED_DRAFT." The create-and-publish
#   flow is a two-step sequence:
#     1. POST /marketing/v3/emails with state = "AUTOMATED_DRAFT",
#        isPublished = false.
#     2. POST /marketing/v3/emails/{id}/publish to promote to AUTOMATED.
#   The `terraform_data.publish_welcome_email` resource below runs step 2
#   via local-exec on create and on every recreate (triggers_replace keyed
#   on the email's ID). The publish endpoint is idempotent, so calling it
#   against an already-published email is a no-op — safe on the recreate
#   path after `terraform taint`.
resource "restapi_object" "welcome_email" {
  path          = "/marketing/v3/emails"
  id_attribute  = "id"
  update_method = "PATCH"

  # POST payload — creates the email as a draft. Publishing happens in the
  # separate `terraform_data.publish_welcome_email` step below.
  data = jsonencode({
    name              = var.email_name
    subject           = var.email_subject
    type              = "AUTOMATED_EMAIL"
    subcategory       = "automated"
    state             = "AUTOMATED_DRAFT"
    emailTemplateMode = "DRAG_AND_DROP"
    language          = var.email_language
    isPublished       = false
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
      flexAreas = {
        main = {
          boxFirstElementIndex    = 0
          boxLastElementIndex     = 0
          boxed                   = false
          isSingleColumnFullWidth = true
          sections = [{
            id   = "builtin_section-0"
            path = null
            columns = [{
              id      = "builtin_column_0-0"
              width   = 12
              widgets = ["primary_rich_text_module", "footer_module"]
            }]
            style = {
              backgroundColor = "{{style_settings.background_color}}"
              backgroundType  = "FULL"
              paddingTop      = "0px"
              paddingBottom   = "0px"
              stack           = "LEFT_TO_RIGHT"
            }
          }]
        }
      }
      widgets = {
        primary_rich_text_module = {
          body = {
            html                     = var.email_body_html
            hs_enable_module_padding = false
            module_id                = 1155639
          }
          id         = "primary_rich_text_module"
          name       = "primary_rich_text_module"
          module_id  = 1155639
          order      = 0
          type       = "module"
          label      = null
          smart_type = null
          child_css  = {}
          css        = {}
          styles     = {}
        }
      }
    }

    to = {
      limitSendFrequency = false
      suppressGraymail   = false
    }
  })

  # PATCH payload — omits state/isPublished/type/subcategory/emailTemplateMode
  # (HubSpot rejects transitions on those fields via the update API). Editable
  # fields only: name, subject, language, sender info, subscription,
  # content body.
  update_data = jsonencode({
    name     = var.email_name
    subject  = var.email_subject
    language = var.email_language

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
      flexAreas = {
        main = {
          boxFirstElementIndex    = 0
          boxLastElementIndex     = 0
          boxed                   = false
          isSingleColumnFullWidth = true
          sections = [{
            id   = "builtin_section-0"
            path = null
            columns = [{
              id      = "builtin_column_0-0"
              width   = 12
              widgets = ["primary_rich_text_module", "footer_module"]
            }]
            style = {
              backgroundColor = "{{style_settings.background_color}}"
              backgroundType  = "FULL"
              paddingTop      = "0px"
              paddingBottom   = "0px"
              stack           = "LEFT_TO_RIGHT"
            }
          }]
        }
      }
      widgets = {
        primary_rich_text_module = {
          body = {
            html                     = var.email_body_html
            hs_enable_module_padding = false
            module_id                = 1155639
          }
          id         = "primary_rich_text_module"
          name       = "primary_rich_text_module"
          module_id  = 1155639
          order      = 0
          type       = "module"
          label      = null
          smart_type = null
          child_css  = {}
          css        = {}
          styles     = {}
        }
      }
    }

    to = {
      limitSendFrequency = false
      suppressGraymail   = false
    }
  })
}

# Publish step. Fires via local-exec when the welcome_email is first created
# and whenever it's recreated (triggers_replace keyed on the email's ID).
# `hs-curl.sh` reads the HubSpot token from Keychain, so no credential
# appears in the terraform execution environment. `HS_LANDER_PROJECT_DIR`
# is exported by `scripts/tf.sh` before it invokes terraform, so the
# provisioner inherits it.
#
# The publish endpoint is idempotent — a POST to /publish on an already-
# published email is a no-op, so the replace-triggered rerun after a
# manual taint is safe.
resource "terraform_data" "publish_welcome_email" {
  triggers_replace = [restapi_object.welcome_email.id]

  provisioner "local-exec" {
    command = <<-EOT
      bash "$HS_LANDER_PROJECT_DIR/scripts/hs-curl.sh" POST "/marketing/v3/emails/${restapi_object.welcome_email.id}/publish"
    EOT
  }
}
