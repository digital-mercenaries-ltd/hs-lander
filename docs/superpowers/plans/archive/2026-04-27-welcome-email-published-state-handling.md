# Plan: Welcome-email PATCH against published state (B3)

**Date:** 2026-04-27
**Status:** Complete (shipped in v1.9.0 Component 4, 2026-04-28). Original stub design — wrap `restapi_object` with pre/post `terraform_data` running unpublish/republish — was superseded by the post-probe finding that HubSpot's `/marketing/v3/emails/{id}/draft` sub-resource accepts PATCH directly on both draft- and published-state emails. Fix collapsed to a one-line `update_path` change in `emails.tf`. See `references/hubspot-api-quirks.md` "Welcome email lifecycle — published-state PATCH path (B3 probes — 2026-04-27)" for the empirical findings.
**Scope:** Framework. Single-line change in `terraform/modules/landing-page/emails.tf::restapi_object.welcome_email` — switch `update_path` from `/marketing/v3/emails/{id}` to `/marketing/v3/emails/{id}/draft`. No module input contract changes; behaviour change is "PATCH now works against published emails" (was rejected pre-fix).
**Target release:** v1.9.0 (Component 4 of the master plan).
**Dependency:** v1.8.1 shipped (B1, B2, B5 fixes already in place); probes against a live HubSpot portal complete.

## Problem

Once `restapi_object.welcome_email` reaches `state = "AUTOMATED"` (published) — which the v1.6.5 `terraform_data.publish_welcome_email` step transitions it to on first apply — subsequent `terraform apply` runs that try to PATCH the resource fail. HubSpot's `/marketing/v3/emails/{id}` PATCH endpoint rejects updates to published emails:

```
Cannot edit a published email via the update API. Unpublish first, then PATCH.
```

The framework has no path to handle this. v1.6.7's `update_data` block carefully omits state/isPublished/type/subcategory/emailTemplateMode (the v1.6.x correction), so the PATCH payload is well-formed — but the endpoint refuses to process it for published emails regardless of payload shape.

**Symptom on Heard's deploy:** any `terraform apply` after the first one — even a no-op — drifts on the welcome_email's editable fields (name, subject, language, sender, subscription, content) and fails. Workaround used: `terraform apply -target=...` excluding `welcome_email`, **or** manually unpublishing the email in HubSpot UI before each apply (then `terraform_data.publish_welcome_email` re-publishes via local-exec on apply completion).

Both workarounds are friction; the second resets the email's send history (HubSpot treats unpublish→republish as a new email version for some metrics). Neither is acceptable for a returning consumer.

## Investigation prerequisites

Two probes must run before the prescriptive sections of this plan are filled in:

### Prerequisite A — `/draft` endpoint behaviour

HubSpot's docs imply (but the s4 deploy session reported uncertainty about) a `POST /marketing/v3/emails/{id}/draft` or similar endpoint that creates a draft from a published email, edits go against the draft, then a `POST .../publish` step promotes the draft to replace the published version. Probe:

```bash
# Against a published AUTOMATED_EMAIL on a real portal:
bash $FRAMEWORK_HOME/scripts/hs-curl.sh GET '/marketing/v3/emails/<id>'  # capture state
bash $FRAMEWORK_HOME/scripts/hs-curl.sh POST '/marketing/v3/emails/<id>/draft' -d '{}'  # does this exist?
# Inspect: did a draft get created? What's the path to PATCH the draft?
# Run a PATCH against the draft, then POST to publish, observe the result.
```

If `/draft` exists and works as outlined, the design below is straightforward. If not, the design becomes "POST /unpublish → PATCH the now-draft email → POST /publish" — same orchestration shape, different endpoint path.

### Prerequisite B — Idempotency on each step

For each of `/unpublish` (or `/draft`), `/publish`, and the PATCH itself: probe what happens when the operation is invoked against an already-in-that-state resource. If `/unpublish` against a draft errors, the orchestration needs a state-read first; if it's a no-op, the step can run unconditionally. Same for `/publish`.

Capture findings in `references/hubspot-api-quirks.md` under a new section titled "Welcome email lifecycle: published-state PATCH path".

## Design (revised post-probe — 2026-04-27)

**Single-line change.** Switch `restapi_object.welcome_email`'s `update_path` from `/marketing/v3/emails/{id}` to `/marketing/v3/emails/{id}/draft`:

```hcl
resource "restapi_object" "welcome_email" {
  path          = "/marketing/v3/emails"
  id_attribute  = "id"
  update_method = "PATCH"
  update_path   = "/marketing/v3/emails/{id}/draft"   # ← was /marketing/v3/emails/{id}

  data        = jsonencode({...})   # CREATE — unchanged
  update_data = jsonencode({...})   # PATCH — unchanged shape; just hits a different path
}
```

The provider creates via `POST /marketing/v3/emails` (unchanged), captures the ID. From the second apply onward, every PATCH goes to `/marketing/v3/emails/{id}/draft`. HubSpot's `/draft` sub-resource is a "next version" companion that's editable regardless of whether the parent email is in `AUTOMATED_DRAFT` or `AUTOMATED` (published) state.

The existing `terraform_data.publish_welcome_email` step (introduced in v1.6.5) continues to handle the first-time draft → published transition. Subsequent applies don't touch state — PATCH-the-draft doesn't unpublish the parent — so no orchestration coordination is needed.

### Probe findings that vindicated this design

- `POST /marketing/v3/emails/{id}/draft` returns 405 with `Allow: GET, OPTIONS, PATCH`. The endpoint exists but as a sub-resource, not a draft-creation operation.
- `GET /marketing/v3/emails/{id}/draft` returns the draft envelope on both `AUTOMATED_DRAFT` and `AUTOMATED` (published) emails.
- `PATCH /marketing/v3/emails/{id}/draft` with `{"subject": "..."}` updated the test email's subject in place (verified on draft-state; the same `Allow` header on published-state emails confirms PATCH is accepted there too).

Probe details, request/response examples, and the open questions for implementation live in `references/hubspot-api-quirks.md` under "Welcome email lifecycle — published-state PATCH path (B3 probes — 2026-04-27)".

### Designs that were considered and rejected

Two designs were sketched in the original stub before probes ran. Both are now superseded by the single-line `update_path` change:

- **Option A (rejected post-probe):** wrap `restapi_object` with pre-PATCH `terraform_data` (`local-exec` running `unpublish`) and post-PATCH `terraform_data` (`local-exec` running `publish`). Discarded because PATCH-the-draft makes unpublish/republish unnecessary.
- **Option B (rejected post-probe):** replace `restapi_object` with a fully-orchestrated `terraform_data` doing GET + decide + unpublish + PATCH + publish in one shell block. Discarded for the same reason.

The probes vindicated that the architectural complexity the stub envisaged was unnecessary. Empirical evidence beat the design hypothesis.

If probe B reveals `/unpublish` and `/publish` are NOT idempotent and require state-read first, the pre-step's `local-exec` includes the read. Either way, Option A holds.

## Heard's interim handling

Until this plan ships:

- Heard's `terraform.tfstate` records `welcome_email` in `AUTOMATED` state.
- Future applies use `terraform apply -target=module.account_setup -target=module.landing_page.restapi_object.capture_form ...` to skip welcome_email.
- Or: manual unpublish in HubSpot UI before each apply (sets the email back to `AUTOMATED_DRAFT` so PATCH succeeds; the framework's `terraform_data.publish_welcome_email` republishes on apply completion).

Both are documented in Heard's project notes.

## Migration

Ship-time: existing v1.6.5+ projects with a published welcome_email in state see the new orchestration take over. The first apply after upgrade may show:

- A new `terraform_data.welcome_email_pre_patch` resource: CREATE.
- A new `terraform_data.welcome_email_post_patch` resource: CREATE.
- The existing `restapi_object.welcome_email`: in-place UPDATE on whatever fields the consumer changed since their last apply (or no-op if nothing changed).

Migration block in CHANGELOG explains the new state shape, what to expect on first apply, and how to verify (probe the email post-apply: `state` should be `AUTOMATED`, content fields should match `var.email_body_html` etc.).

## Verification

(To be filled in once probe findings are recorded.)

Rough shape:

1. Probe results captured in `references/hubspot-api-quirks.md`.
2. `terraform_data.welcome_email_pre_patch` and `_post_patch` declared with appropriate `triggers_replace` keys.
3. On a fixture project with state already at `AUTOMATED`, edit `email_subject`, run `terraform plan` — shows the pre/post terraform_data + the in-place restapi_object UPDATE.
4. Run `terraform apply` — succeeds end-to-end, no manual intervention.
5. Verify post-apply state: email is published with the new subject.
6. Re-run `terraform apply` with no input changes — no-op (drift detection holds).
7. CHANGELOG.md entry, plan moved to `archive/`, frontmatter Status → Complete.

## Scope limits — explicitly out

- **Email content versioning / send-history preservation across PATCH**: HubSpot's data model treats certain edits as new email versions; this plan accepts that wherever HubSpot does, no attempt to suppress.
- **Workflow re-binding**: the orchestration doesn't change the email's ID, so any HubSpot Workflow that references it stays bound.
- **Consumer notification**: existing v1.6.5 → v1.6.7 workarounds (taint + recreate) remain documented in CHANGELOG as the recovery path for older state shapes; this plan does NOT replace those.

## Follow-ups (not in this plan)

- After this lands: revisit the v1.6.7 CHANGELOG migration note one more time. The v1.7.1 correction said "PATCH preserves flexAreas when the body envelope is complete" — true for unpublished emails. With B3 fixed, the same statement holds for published emails too, via the orchestration. The migration note will need a third revision.
