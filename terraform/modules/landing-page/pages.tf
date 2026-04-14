# terraform/modules/landing-page/pages.tf
#
# Landing page type is set by the API endpoint, not the template.
# Landing pages: /cms/v3/pages/landing-pages (supports A/B testing)
# Thank-you page: /cms/v3/pages/site-pages (standard site page)

resource "restapi_object" "landing_page" {
  path          = "/cms/v3/pages/landing-pages"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name         = var.page_landing_name
    slug         = var.landing_slug
    domain       = var.domain
    htmlTitle    = var.page_landing_title
    templatePath = var.template_path_landing
    state        = "PUBLISHED"
  })
}

resource "restapi_object" "thankyou_page" {
  path          = "/cms/v3/pages/site-pages"
  id_attribute  = "id"
  update_method = "PATCH"

  data = jsonencode({
    name         = var.page_thankyou_name
    slug         = var.thankyou_slug
    domain       = var.domain
    htmlTitle    = var.page_thankyou_title
    templatePath = var.template_path_thankyou
    state        = "PUBLISHED"
  })
}
