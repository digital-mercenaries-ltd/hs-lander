# Plan: Welcome-email PATCH against published state (B3)

**Date:** 2026-04-27
**Status:** Pending — stub. Problem and rough design captured; investigation prerequisites need to run before the prescriptive sections are filled in.
**Scope:** Framework. `terraform/modules/landing-page/emails.tf` orchestrates the welcome email's lifecycle correctly when the resource is in published state. No module input contract changes; behaviour change is "PATCH now works against published emails" (currently fails).
**Target release:** v1.8.2 if shipped before v1.9.0, otherwise folded into v1.9.0 alongside the lib + safety-pair work (the orchestration would benefit from the lib pattern's error handling).
**Dependency:** v1.8.1 shipped (so B1, B2, B5 are out of the way before this re-architects emails.tf).

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

## Design (sketch — to be filled in after probes)

Replace the current `restapi_object.welcome_email` with an orchestration that handles the lifecycle properly. Two design candidates, decided post-probe:

### Option A — Wrap `restapi_object` in pre/post `terraform_data` steps

Keep `restapi_object.welcome_email` as the resource shape Terraform manages, but bracket it with:

- **Pre-PATCH `terraform_data`** that runs `local-exec`: GET current state, if published POST to `/unpublish` (or equivalent draft-creation step). `triggers_replace` keyed on a hash of the editable fields so it only runs when there's something to PATCH.
- **Post-PATCH `terraform_data`**: POSTs to `/publish` if the email was published before. Same hash trigger.

Pro: minimal change to the existing `restapi_object`. Con: state coordination between three resources is fiddly.

### Option B — Replace `restapi_object` with a fully-orchestrated `terraform_data`

Single resource that does GET + decide + unpublish + PATCH + publish in one `local-exec`. State handled in a single shell script.

Pro: simpler dependency graph; all logic in one place. Con: drift detection lost (Terraform can't read the resource's current state and compare to declared), every apply runs the full orchestration unconditionally.

### Recommendation (subject to probe findings)

Option A. Drift detection is genuinely useful here — the welcome email is the most-edited resource in the framework, and Terraform showing "no changes" when there are no changes is a real ergonomic win. Option B's "every apply unconditionally re-runs" pattern would be noisy and would log API calls for no reason on a no-op apply.

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
