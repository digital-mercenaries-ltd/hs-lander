# terraform/modules/landing-page/emails.tf

resource "restapi_object" "welcome_email" {
  path          = "/marketing/v3/emails"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name      = var.email_name
    subject   = var.email_subject
    fromName  = var.email_from_name
    replyTo   = var.email_reply_to
    type      = "REGULAR"
    content = {
      html = file(var.email_body_path)
    }
  })
}
