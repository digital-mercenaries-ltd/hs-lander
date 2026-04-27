# Forms Submissions API vs. embedded forms

hs-lander uses two different patterns for getting data from a project's HTML into HubSpot, depending on which form is in play. This document explains why they diverge and when to use each.

## The two patterns

### Pattern A — Embedded form (`hbspt.forms.create`)

```html
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

HubSpot's runtime renders the form, handles validation, builds the consent UI, manages spam protection, and submits via its own internal pipeline. The project's HTML provides only the target div.

**When to use:** the **capture form** on `landing-page.html`. Keeping it embedded means HubSpot's anti-spam, validation, and CAPTCHA stay in play. The cost is design control: HubSpot's stylesheet renders the form with HubSpot's defaults; project CSS overrides via `.hs-form-field { ... }` selectors and friends.

### Pattern B — Static form + Forms Submissions API

```html
<form data-survey-form>
  <select name="<slug>_role" required>
    <option>Engineer</option>
    <option>Designer</option>
    <option>Other</option>
  </select>
  <input type="text" data-other-overflow-for="<slug>_role" hidden>
  <button type="submit">Send answers</button>
</form>
<script src="{{ get_asset_url('__DM_PATH__/js/survey-submit.js') }}" defer></script>
```

The project's HTML renders the form directly. JS catches submit, collects field values, POSTs to HubSpot's Forms Submissions API:

```
POST https://api.hsforms.com/submissions/v3/integration/secure/submit/<portal>/<form-id>
Content-Type: application/json

{ "submittedAt": ..., "fields": [...], "context": {...} }
```

The HubSpot-defined form (Terraform `restapi_object.survey_form`) exists as the submission target — the form ID acts as the implicit authorisation token — but is never rendered as an embed. Field names declared in the Terraform form payload **must** match the static form's `<input name="...">` attributes, or submissions silently fail validation.

**When to use:** the **survey form** on `thank-you.html`. The branded thank-you page design matters; surrendering rendering to HubSpot's stylesheet would force a CSS-recovery battle that's costly and brittle. The cost is the JS submit handler (shipped as `scaffold/src/js/survey-submit.js`) and the schema-alignment risk between the static markup and the Terraform form definition (mitigated by `tests/test-deployment.sh`'s schema-alignment check).

## Why the survey form needs a HubSpot form ID at all

Forms Submissions API requires a valid form ID. The form acts as a schema container — HubSpot validates the submission against the form's declared fields, applies its consent/legal flags, routes the data to the contact CRM, and triggers any associated workflow.

If the framework rendered the survey as a pure `<form action="https://your-server/...">` POSTed elsewhere, it would have to reproduce all of that out-of-band: schema validation, CRM property mapping, consent capture, workflow triggers. The form-ID-as-schema-token pattern shortcuts all of it; the framework's only burden is keeping the static markup's field names aligned with the form's field definitions.

## The "secure submit" endpoint

Note the `/secure/` segment in the URL. There's also an `/integration/submit/` endpoint without `/secure/` — same shape, different security profile. The secure variant is what HubSpot's own embedded forms use under the hood; it accepts submissions only when the request originates from a domain on the portal's connected-domains allowlist.

For our pattern, secure is correct: the project's domain is on the portal's allowlist (set up during landing-page deploy), and submissions from that origin are accepted. Cross-origin POSTs from arbitrary scripts are rejected, providing a baseline anti-CSRF guarantee.

## Failure modes and mitigations

| Failure mode | Cause | Mitigation |
|---|---|---|
| Static form names drift from Terraform form definition | Hand-edits to thank-you.html or `survey_fields` change one without updating the other | `tests/test-deployment.sh` v1.8.0+ schema-alignment check (three-way diff: static names ↔ HubSpot form names ↔ `custom_properties` names). Skill regenerates them in lockstep. |
| Submission carries no email | URL parameter `?email=` missing (consumer landed on `/thank-you` directly, not via capture redirect) | `survey-submit.js` logs and refuses submit; UI feedback is on the consumer's roadmap (TODO comment in the JS). |
| HubSpot form's `formType` rejected | Forms v3 API drift | Caught by `tests/test-terraform-plan.sh` formType assertion. |
| `<field>_other` overflow text submitted when primary field's value isn't "Other" | Bad UX state — field shouldn't have been visible | `survey-submit.js`'s `bindOverflowReveal` keeps the overflow input hidden unless the primary's value matches `^other(\s|\(|$)/i`; collection logic re-checks at submit time. |
| Multi-select checkboxes packed wrong | HubSpot's multi-select convention is `;`-joined, not `,`-joined | `survey-submit.js`'s `collectFields` joins with `;`. Verify against HubSpot's CRM contact view that values render as discrete chips, not one long string. |

## When to revisit

If a future release adds Playwright tests, the static-form-plus-Submissions pattern becomes much easier to verify end-to-end (browser-driven submit + CRM read-back). At that point, embedded-form rendering may also become viable for the survey form (the Playwright test handles the styling-recovery confidence the manual approach can't), and the framework could collapse to one pattern. Until then: keep them split.
