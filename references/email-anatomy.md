# Welcome-email anatomy

Single source of truth for the welcome-email body shipped by `scaffold/src/emails/welcome-body.html`. The framework Terraform module wraps this body inside HubSpot's `@hubspot/email/dnd/Plain_email.html` DnD template, which provides the `<!DOCTYPE>` / `<html>` / `<head>` / `<body>` shell, the legal unsubscribe footer, and the physical-address block. The body file therefore ships **inner HTML only** — no shell tags.

This file documents the eleven anatomy elements consumers should retain. Skill copy-generation references this list (skill plan §Step 7).

## Inner-HTML-only constraint

Do **not** add `<!DOCTYPE>`, `<html>`, `<head>`, `<body>`, or `<style>` tags to `welcome-body.html`. HubSpot's DnD email template wraps the body, and a duplicate shell breaks rendering in some clients. Inline styles via `style="…"` attributes are fine; a `<style>` block at the top of the body is not.

## Eleven elements

| # | Element | Default in scaffold | Purpose |
|---|---|---|---|
| 1 | **Preheader** | Hidden span; ~85–110 chars | Inbox preview text. Often a dedicated `preview_text` widget on the email is preferred (see Fix 4 in v1.7.0); the in-body preheader is belt-and-braces for clients that don't render the preview widget. |
| 2 | **View-in-browser link** | `{{ view_as_page_url }}` HubSpot merge tag, small/muted, top of body | Lets recipients on broken-rendering clients open the email in a browser. |
| 3 | **Brand wordmark / logo** | `<img>` referencing the project's `logo.svg` (skill substitutes path); fallback text mark | Identifies the sender at the top. |
| 4 | **Headline** | One short line confirming the user's action ("You're in.") | Anchors the email's purpose at first glance. |
| 5 | **Subhead** | One sentence restating what was signed up for | Bridges the headline to the body. Reduces "wait, what was this for?" disengagement. |
| 6 | **Body** | 2–4 short paragraphs | The actual message. Keep paragraphs tight; mobile clients clip beyond ~3 short paragraphs. |
| 7 | **Primary CTA** | Single button, profile-aware destination, token `__PRIMARY_CTA_URL__` | One thing for the reader to do next. Skill substitutes the URL per profile (e.g. waitlist → calendar booking; launch → product page). |
| 8 | **Secondary engagement** | Share-with-a-friend row (LinkedIn, WhatsApp, forward via email); commented out by default | Optional virality nudge. Conditional on a `share_channels` brief field; scaffold ships commented-out so the default email is uncluttered. |
| 9 | **Reply prompt** | "Hit reply if X" line | Encourages two-way contact, especially valuable for early-funnel lists where reply-engagement is a quality signal. |
| 10 | **Sign-off** | Team / project name (token `__BRAND_NAME__`) | Ends the message with attribution; avoids the "feels like noreply" effect. |
| 11 | **Cadence note** | One line setting expectation ("We send roughly one update a fortnight.") | Sets honest expectations about future contact frequency. Reduces unsubscribe rates. |

The exact copy is the skill's responsibility (see skill plan §Step 7). The scaffold ships generic placeholder text so consumers can dogfood the email rendering before final copy lands.

## Available HubSpot merge tags

Always-available in any marketing email body:

- `{{ view_as_page_url }}` — server-side URL to the rendered email as a public web page.
- `{{ unsubscribe_link }}` — opt-out URL. The DnD template footer emits this automatically; only add a body-level link if the design calls for one.
- `{{ contact.firstname|default:"there" }}` — personalisation with a fallback. The `|default` filter is critical; without it, contacts whose first name is missing render as `Hi  ,` (space-comma).
- `{{ contact.email }}` — recipient's email address. Useful in "we sent this to {{ contact.email }}" footer notes.

Plus any custom property defined on the contact CRM object: `{{ contact.<property_name> }}` with optional `|default:"…"` filter.

Test merge tags in HubSpot's Email → Preview → Recipient dropdown before publishing — the renderer fills them in against a real contact, surfacing missing-data fallbacks.

## No manual UTM parameters in in-email links

HubSpot auto-tags marketing emails with its own tracking parameters (`utm_source`, `utm_medium`, `utm_campaign`, `utm_content` set to the email name and link metadata) and **overwrites manual ones** on the click-through redirect. Manual UTMs in body links are at best ignored and at worst create double-tagged URLs that mis-attribute the click in GA4.

UTMs **are** appropriate on share-out links — LinkedIn / WhatsApp / forward-via-email destinations — because users land outside HubSpot's email-tracking scope. Skill prompts for these via the `share_channels` brief field.

Rule of thumb: if the click destination opens via HubSpot's redirect (any URL the recipient clicks from inside the email body), no manual UTMs. If the click leaves HubSpot's tracking entirely (a pre-formatted social-share intent URL), manual UTMs are fine.

## Tokens scaffolded into welcome-body.html

These are substituted by `scripts/build.sh` (or by the skill at scaffold time, depending on which) before the body content is sent to HubSpot:

- `__BRAND_NAME__` — project's brand / team name (from project profile or skill prompt).
- `__PRIMARY_CTA_URL__` — destination for the primary CTA button. Profile-dependent.
- `__DOMAIN__` — project domain (used in any landing-page redirect).

The skill's brand-direction step is responsible for resolving these to real values; scaffold ships placeholder values so the email body renders without manual intervention during framework testing.

## Reference: example body skeleton

```html
<!-- 1. Preheader (hidden) -->
<span style="display:none;font-size:0;color:transparent;line-height:0;max-height:0;max-width:0;opacity:0;overflow:hidden;">
  Welcome to __BRAND_NAME__ — your sign-up is confirmed.
</span>

<!-- 2. View in browser -->
<p style="font-size:11px;color:#888;text-align:right;margin:0 0 16px;">
  <a href="{{ view_as_page_url }}" style="color:#888;">View in browser</a>
</p>

<!-- 3. Brand mark -->
<p style="text-align:center;margin:0 0 24px;">
  <strong>__BRAND_NAME__</strong>
</p>

<!-- 4. Headline -->
<h1 style="margin:0 0 8px;">You're in, {{ contact.firstname|default:"friend" }}.</h1>

<!-- 5. Subhead -->
<p style="margin:0 0 24px;color:#555;">Thanks for joining the __BRAND_NAME__ list.</p>

<!-- 6. Body -->
<p>Body paragraph one — what they signed up for.</p>
<p>Body paragraph two — what happens next.</p>

<!-- 7. Primary CTA -->
<p style="text-align:center;margin:32px 0;">
  <a href="__PRIMARY_CTA_URL__" style="background:#0A0A0B;color:#FFF;padding:12px 24px;text-decoration:none;border-radius:4px;display:inline-block;">
    Open __BRAND_NAME__
  </a>
</p>

<!-- 8. Secondary engagement (uncomment to activate) -->
<!--
<p style="text-align:center;margin:32px 0;font-size:14px;">
  Know someone who'd like this?
  <a href="https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2F__DOMAIN__%2F&utm_source=welcome_email&utm_medium=share">Share on LinkedIn</a>
  ·
  <a href="https://wa.me/?text=...">Share on WhatsApp</a>
</p>
-->

<!-- 9. Reply prompt -->
<p>Hit reply if you've got questions or feedback. We read every one.</p>

<!-- 10. Sign-off -->
<p>— The __BRAND_NAME__ team</p>

<!-- 11. Cadence note -->
<p style="font-size:12px;color:#888;margin-top:24px;">
  We send roughly one update a fortnight. Unsubscribe any time via the link below.
</p>
```

The `<!-- N. Element -->` comments are deliberate — they label each anatomy slot so per-project edits target the right element. Keep them in the scaffold; skills/projects can strip them on final copy if desired but defaults retain the labels for maintainability.
