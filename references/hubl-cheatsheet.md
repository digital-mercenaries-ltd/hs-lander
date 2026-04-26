# HubL primitives for hs-lander landing pages

HubL (HubSpot Markup Language) is HubSpot's server-side templating layer for CMS pages. Templates that lack the right HubL primitives are served as static HTML — CSS 404s, forms degrade silently, scriptloader doesn't fire, analytics don't load. This file lists every HubL primitive a landing page needs and explains the "tokens stay, but as arguments to HubL functions" pattern hs-lander uses.

## Required primitives in every scaffold template

### 1. `templateType: page` annotation (first line)

```jinja
{# templateType: page #}
```

Without this, HubSpot serves the file as static HTML — no HubL compilation. Symptoms: relative URLs fail, `{{ get_asset_url(...) }}` literally appears in output, forms degrade because the embed script can't resolve.

The annotation is HubL-comment syntax (`{# ... #}`); the comment itself is invisible in rendered HTML.

### 2. `{{ standard_header_includes }}` (in `<head>`, before custom CSS)

```jinja
<head>
  <meta charset="utf-8">
  <title>{{ page_meta.html_title }}</title>
  {{ standard_header_includes }}
  <link rel="stylesheet" href="{{ get_asset_url('__DM_PATH__/css/main.css') }}">
</head>
```

This emits HubSpot's runtime: scriptloader (`/hs/scriptloader/<portal>.js`), analytics (`/hs-tracking/...`), CSP-safe form-embed support, jQuery (legacy compatibility). **Forms depend on it.** A page without `standard_header_includes` may visually render the embed div but never initialise the form widget.

Place it in `<head>` *before* custom stylesheets so HubSpot styles can be overridden by project CSS.

### 3. `{{ get_asset_url(path) }}` for assets

```jinja
<link rel="stylesheet" href="{{ get_asset_url('__DM_PATH__/css/main.css') }}">
<script src="{{ get_asset_url('__DM_PATH__/js/tracking.js') }}"></script>
<img src="{{ get_asset_url('__DM_PATH__/images/logo.svg') }}" alt="…">
```

Resolves the path against HubSpot's `hub_generated/template_assets/...` URL when the page is served. Without it, assets uploaded to Design Manager are reachable only via raw `cdn` URLs that aren't stable across portal regions.

**Why tokens still appear inside the function call:** `__DM_PATH__` is a build-time placeholder that `scripts/build.sh` substitutes (per `project.config.sh`'s `DM_UPLOAD_PATH`) before the file is uploaded. The substitution happens via sed at the byte level — it replaces `__DM_PATH__` regardless of surrounding context, so `{{ get_asset_url('__DM_PATH__/css/main.css') }}` becomes `{{ get_asset_url('/myproject/css/main.css') }}` after build, and HubL evaluates that at serve time. Tokens stay; they're just arguments to HubL functions instead of raw URLs.

Likewise `__DOMAIN__` is build-substituted (used in canonical-link tags, fallback URLs, etc.) and `__PORTAL_ID__`, `__REGION__`, `__HSFORMS_HOST__`, `__CAPTURE_FORM_ID__`, `__SURVEY_FORM_ID__`, `__GA4_ID__` get substituted into form embed scripts and tracking pixels.

### 4. `{{ standard_footer_includes }}` (just before `</body>`)

```jinja
  <!-- page content -->
  {{ standard_footer_includes }}
</body>
```

Emits any deferred scripts HubSpot wants at the foot — tracking pings on view, anti-bot checks, analytics flush. Cheap to include; missing it can break analytics on slow connections.

### 5. Form embed (no manual `<script src="//js-eu1.hsforms.net/...">`)

`standard_header_includes` already loads the embed script. The current scaffold's manual `<script src="//__HSFORMS_HOST__/forms/embed/v2.js"></script>` is redundant once HubL primitives are in place. Drop it; rely on the includes.

```jinja
<div id="signup-form"></div>
<script>
  hbspt.forms.create({
    region: '__REGION__',
    portalId: '__PORTAL_ID__',
    formId: '__CAPTURE_FORM_ID__',
    target: '#signup-form'
  });
</script>
```

`region` is omitted in NA1; `js.hsforms.net` is the embed host with no region prop. The `__REGION__` and `__HSFORMS_HOST__` tokens are substituted at build per `HUBSPOT_REGION` in the project config.

## Personalisation via merge tags

Available in any HubL template:

- `{{ contact.firstname|default:"there" }}` — recipient's first name with fallback. The `|default:"…"` filter is essential; raw `{{ contact.firstname }}` renders empty when the contact has no name on file.
- `{{ contact.email }}` — recipient's email.
- `{{ contact.<custom_property> }}` — any custom CRM property.
- `{{ page_meta.html_title }}` — the page's HTML title (set in HubSpot UI or via the `htmlTitle` field on the landing-page resource).
- `{{ portal_id }}` — useful for debugging output but rarely needed in production templates.

Test merge tags via HubSpot's Page Editor → Preview → Choose contact dropdown before publishing.

## Conditional rendering (`{% if %}`)

```jinja
{% if contact.firstname %}
  Hi {{ contact.firstname }},
{% else %}
  Hi there,
{% endif %}
```

The pipe-default filter is usually cleaner for this specific case (`{{ contact.firstname|default:"there" }}`), but `{% if %}` is needed for any conditional that's not "fall back to a literal string."

## What does NOT work

- Server-side includes (SSI) — `<!--#include virtual="…"-->` is silently ignored.
- Bare `<?php ?>` blocks — HubSpot is not PHP.
- Custom HubL filters — only the documented set is available; custom filters require a HubSpot module template, not a page template.
- Tokens-inside-tokens — `{{ get_asset_url(__DM_PATH__) }}` (no quotes) does not work; use `{{ get_asset_url('__DM_PATH__/path') }}` (token inside the string argument).

## Annotated complete example

A minimal but production-grade landing page template demonstrating every primitive:

```jinja
{# templateType: page #}
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="color-scheme" content="light dark">
  <title>{{ page_meta.html_title|default:"__BRAND_NAME__" }}</title>
  {{ standard_header_includes }}
  <link rel="stylesheet" href="{{ get_asset_url('__DM_PATH__/css/main.css') }}">
</head>
<body>
  <header>
    <img src="{{ get_asset_url('__DM_PATH__/images/logo.svg') }}" alt="__BRAND_NAME__">
  </header>
  <main>
    <h1>__BRAND_NAME__</h1>
    <div id="signup-form"></div>
    <!-- bottom CTA — duplicate form embed; HubSpot dedupes by email on submission -->
    <div id="signup-form-bottom"></div>
    <script>
      hbspt.forms.create({
        region: '__REGION__',
        portalId: '__PORTAL_ID__',
        formId: '__CAPTURE_FORM_ID__',
        target: '#signup-form'
      });
      hbspt.forms.create({
        region: '__REGION__',
        portalId: '__PORTAL_ID__',
        formId: '__CAPTURE_FORM_ID__',
        target: '#signup-form-bottom'
      });
    </script>
    <script src="{{ get_asset_url('__DM_PATH__/js/tracking.js') }}"></script>
  </main>
  {{ standard_footer_includes }}
</body>
</html>
```

Skill substitutes `__BRAND_NAME__` per project (skill plan §Step 7). The framework's `build.sh` substitutes the `__PORTAL_ID__` / `__REGION__` / `__CAPTURE_FORM_ID__` / `__DM_PATH__` tokens.
