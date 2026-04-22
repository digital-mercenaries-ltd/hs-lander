# terraform/modules/landing-page/pages.tf
#
# Landing page type is set by the API endpoint, not the template.
# Landing pages: /cms/v3/pages/landing-pages (supports A/B testing)
# Thank-you page: /cms/v3/pages/site-pages (standard site page)
#
# POST vs PATCH split (mirrors the v1.6.0 welcome-email pattern):
#   `data` (POST) declares all create-time fields — name, slug, domain,
#   htmlTitle, templatePath, state — so a freshly created page lands
#   published at the right URL.
#   `update_data` (PATCH) omits slug, domain, state. These are effectively
#   identity-level fields: HubSpot resolves the page URL through
#   primary-landing-page settings on the domain, so a PATCH that tries to
#   move a page to slug="" (root) collides with any existing root page on
#   that domain and is rejected with PAGE_EXISTS. state toggles on PATCH
#   trip similar URL-conflict paths. Projects wanting to rename a slug or
#   move a page between domains should use the HubSpot UI or
#   `terraform taint` + recreation, not a silent in-place PATCH.

resource "restapi_object" "landing_page" {
  path          = "/cms/v3/pages/landing-pages"
  id_attribute  = "id"
  update_method = "PATCH"

  # POST payload — publishes the page at creation time at the declared URL.
  data = jsonencode({
    name         = var.page_landing_name
    slug         = var.landing_slug
    domain       = var.domain
    htmlTitle    = var.page_landing_title
    templatePath = var.template_path_landing
    state        = "PUBLISHED"
  })

  # PATCH payload — editable fields only. slug/domain/state omitted so a
  # PATCH can't collide with the portal's primary-landing-page resolution.
  update_data = jsonencode({
    name         = var.page_landing_name
    htmlTitle    = var.page_landing_title
    templatePath = var.template_path_landing
  })
}

resource "restapi_object" "thankyou_page" {
  path          = "/cms/v3/pages/site-pages"
  id_attribute  = "id"
  update_method = "PATCH"

  # POST payload — publishes the page at creation time at the declared URL.
  data = jsonencode({
    name         = var.page_thankyou_name
    slug         = var.thankyou_slug
    domain       = var.domain
    htmlTitle    = var.page_thankyou_title
    templatePath = var.template_path_thankyou
    state        = "PUBLISHED"
  })

  # PATCH payload — editable fields only. See landing_page above.
  update_data = jsonencode({
    name         = var.page_thankyou_name
    htmlTitle    = var.page_thankyou_title
    templatePath = var.template_path_thankyou
  })
}
