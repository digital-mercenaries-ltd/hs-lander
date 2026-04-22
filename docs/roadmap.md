# hs-lander Roadmap

Items beyond the shipped framework. Each reduces manual steps or expands capability.

## Currently on deck (2026-04-22)

What's actively being worked on or is expected next. Updated when releases ship; kept short so readers can see the near-term focus at a glance.

- **v1.5.0 ship (PR #11)** — finish email restructure + hosting-modes plumbing (covers partial R-work — not a single-R item). Blocks Heard re-deploy.
- **v1.6.0 ship** — three more API-drift fixes surfaced by Heard's v1.5.0 apply (welcome-email PATCH, Forms hidden-field, Lists response-wrapping). Non-breaking. Unblocks Heard re-deploy once user cleans up the orphan list (`listId: 21`).
- **R8 — Preflight HubSpot Domain Connection Check** (plan written, implementation pending). Closes the domain-verification gap and simplifies the skill's hosting-mode handling.
- **Plan-review gate + state-backup safeguards** (plans written, pending). Not blocking Heard; worth landing before the next live deploy to reduce blast-radius risk on misconfigured plans.
- **R5 — Subscription check in preflight** (plan still to be written). Useful before anyone tries a fresh account deploy. Consider bundling with the subscription/office-location ID auto-discovery (scope-change).

## Deferred / awaiting trigger

- **R10 — Skill Hygiene Rule 6** — conditional on pattern recurrence
- **R11+ items** — waiting on Heard validation, account tier upgrade, or team adoption signals
- **R14 — Plugin packaging** — waiting on skill-surface stability
- **R15 — Enterprise workflow automation** — waiting on Enterprise subscription

See full entries below.

## Numbering convention

Roadmap items use stable `R#` identifiers that never change. Release versions (`v1.5.0`, `v1.6.0`, etc.) are decided at implementation time based on the actual change's semver impact. One roadmap item may ship as part of a larger release; a single release may bundle several roadmap items. The mapping is maintained in the table below.

Why separate: we don't always know at roadmap-entry time whether an item will be a patch, minor, or major bump, and some items (e.g. R10 Skill Hygiene) may never get a release if their trigger condition doesn't materialise. Tying roadmap IDs to version numbers upfront creates confusion when releases bundle differently than originally planned.

## Roadmap index

| ID | Title | Targeted release | Status |
|---|---|---|---|
| R1 | Automated GA4 Property Setup | TBD (1.x) | Planned |
| R2 | Automated DNS via Cloudflare | TBD (1.x) | Planned |
| R3 | Automated HubSpot Domain Connection | — (API blocked) | Investigated, blocked; superseded by R8 |
| R4 | A/B Testing | TBD (1.x) | Planned |
| R5 | HubSpot Subscription Check in Preflight (+ subscription/office-location ID auto-discovery) | TBD (1.x) | Planned |
| R6 | HubSpot API Contract Monitoring | TBD (1.x / 2.x split) | Planned; plan pending |
| R7 | S3 Iframe Wrapper Hosting Mode | TBD (1.x) | Niche; plan pending |
| R8 | Preflight HubSpot Domain Connection Check | TBD (1.x) | Plan written (`2026-04-22-preflight-domain-hubspot-check.md`) |
| R9 | Operator Ergonomics (version drift, migrate-project, projects-describe) | TBD (1.x) | Planned |
| R10 | Skill Hygiene Rule 6 (no preemptive inspection) | TBD (skill-only) | Conditional on pattern recurrence |
| R11 | CI/CD with GitHub Secrets | TBD (2.x) | Planned |
| R12 | Account Profile Sync | TBD (2.x) | Planned |
| R13 | Skill-Driven End-to-End Deployment Test | TBD (2.x) | Depends on R11 |
| R14 | Claude Code Plugin Packaging | TBD (2.x) | Depends on skill stabilisation |
| R15 | Enterprise-Tier Workflow Automation | TBD (3.x) | Tier-gated |
| M | Maintainer Tooling (Terraform MCP, CONTRIBUTING.md) | — (non-versioned) | Living recommendation |

## Shipped (for cross-reference)

| Release | Roadmap items covered | Notes |
|---|---|---|
| v1.0.0 | — | Initial framework release |
| v1.1.0–v1.3.0 | — | Account config hierarchy, preflight tool checks, framework versioning, richer preflight output, config-mutation commands (`accounts-init.sh`, `set-project-field.sh`), pre-scaffold commands |
| v1.4.0 | — | API drift fixes part 1: Forms API v3 `formType`, property/list race |
| v1.5.0 (pending merge — PR #11) | — | API drift fixes part 2: marketing-email restructure; hosting-modes plumbing (`LANDING_SLUG`, `THANKYOU_SLUG`, account-level subscription + office-location IDs) |
| v1.6.0 | — | API drift fixes part 3 (from Heard v1.5.0 apply): welcome-email PATCH rejects state/publish toggles (→ `update_data` split); Forms v3 dropped `fieldType = "hidden"` (→ `single_line_text` + scaffold CSS hide); Lists API wraps response in `{"list":{...}}` (→ `id_attribute = "list/listId"` + `ignore_all_server_changes`) |
| v1.6.1 | — | Mastercard/restapi provider constraint `~> 1.19` → `~> 2.0` in all three files that declare it. v1.6.0's `ignore_all_server_changes` attribute requires provider 2.0.0+; the v1.19 cap made it unusable. No module contract changes. |
| v1.6.2 | — | Heard v1.6.1 apply drift: `survey_form` missed `fieldType` normalisation (`hidden` → `single_line_text`); both forms' `richTextType = "NONE"` rejected by v3 (`→ "text"`); `landing_page` PATCH hit `PAGE_EXISTS` on `slug=""` collisions (→ `data`/`update_data` split mirroring the v1.6.0 email pattern — `slug`/`domain`/`state` dropped from PATCH). Plus a documented `terraform taint` recovery for pre-v1.6.0 emails stuck in `BATCH_EMAIL`/`DRAFT`. |
| v1.6.3 | — | Forms v3 now requires `legalConsentOptions.privacyText` when `type = "implicit_consent_to_process"` (`Some required fields were not set: [privacyText]`). New `privacy_text` module variable with a GDPR-adequate default; wired into both `capture_form` and `survey_form`. No breaking change; consumers pick up the default automatically. |

---

## R1: Automated GA4 Property Setup

**Current state:** Manual — create GA4 property in Google Analytics UI, add web data stream, copy Measurement ID into `project.config.sh`.

**Goal:** Skill creates the GA4 property, data stream, and injects the Measurement ID automatically.

**Approach:**

The [GA4 Admin API v1](https://developers.google.com/analytics/devops/rest/admin/v1) supports programmatic property and data stream creation:

1. Create GA4 property (`properties.create`) under the account's Google Analytics organisation
2. Create web data stream for the project domain (`properties.dataStreams.create`)
3. Extract Measurement ID (`G-XXXXXXXXXX`) from the response
4. Write `GA4_MEASUREMENT_ID` into `project.config.sh`

**Implementation options:**

| Option | Pros | Cons |
|--------|------|------|
| **Terraform** (`hashicorp/google` provider) | `google_analytics_admin_property` + `google_analytics_admin_data_stream` resources fit naturally in per-project `main.tf` alongside HubSpot resources. Single `terraform apply` creates everything. | Adds a second provider + Google Cloud auth to every project. |
| **Script** (`scripts/ga4-setup.sh`) | Standalone, can run before Terraform. Uses `gcloud` CLI or direct REST. | Separate step in the workflow; config writeback needed before build. |

**Auth:** Google Cloud service account with Analytics Admin role. Credentials stored in Keychain; the account config references them via `GOOGLE_SA_KEY_KEYCHAIN_SERVICE` (per the account-config-hierarchy plan).

**Terraform is the preferred option** — it keeps all infrastructure in one plan and makes the GA4 property part of the project's managed state (so `terraform destroy` cleans it up too).

---

## R2: Automated DNS via Cloudflare

**Current state:** Manual — add a CNAME record at the domain registrar pointing the project subdomain to HubSpot's CDN endpoint.

**Goal:** Skill creates the DNS record automatically when scaffolding a new project.

**Prerequisite:** The account's primary DNS zone is managed by Cloudflare (Cloudflare has the best API tooling and Terraform support of any DNS provider). For client projects on zones not managed by Cloudflare, see the fallback note at the end of this section.

**Approach:**

The [Cloudflare API v4](https://developers.cloudflare.com/api/resources/dns/subresources/records/) and [`cloudflare/cloudflare` Terraform provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs) support DNS record management:

1. Create CNAME record: project domain (`$DOMAIN` from project config) -> `${portal_id}.group0.sites.hscoscdn-${HUBSPOT_REGION}.net` (NA1 portals use `hscoscdn-na1.net`)
2. Set proxy status to **DNS-only** (orange cloud off) — HubSpot manages its own SSL via Let's Encrypt

**Implementation:**

Add to per-project `main.tf`:

```hcl
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "project_cname" {
  zone_id = var.cloudflare_zone_id
  name    = var.project_slug
  content = "${var.hubspot_portal_id}.group0.sites.hscoscdn-${var.hubspot_region}.net"
  type    = "CNAME"
  proxied = false
}
```

**Auth:** Cloudflare API token (DNS Edit scope for the managed zone), stored in Keychain and referenced via `CLOUDFLARE_TOKEN_KEYCHAIN_SERVICE` in the account config.

**For client projects** using custom domains not on Cloudflare, this step remains manual — the skill detects whether the domain zone is Cloudflare-managed and falls back to instructions.

---

## R3: Automated HubSpot Domain Connection

**Current state:** Manual — connect the subdomain in HubSpot UI (Settings -> Domains & URLs), wait for CNAME verification, SSL provisioned by Let's Encrypt. Additionally, the `isPrimaryLandingPage` and `isPrimarySitePage` flags on the domain must be set manually after page creation.

**Investigation outcome (2026-04-22):** The CMS Domains API is GET-only (`/cms/v3/domains` endpoint responds `allow: GET,OPTIONS` to OPTIONS; POST and PATCH return 405). Empirically confirmed via live probes. This is a deliberate HubSpot product decision — domain connection involves SSL provisioning, DNS verification, and billing-tier interactions that HubSpot has gated to the UI.

**What this means:**

- **Full automation is not possible** with the current public API surface. Documented here for completeness so future re-investigation doesn't repeat the work.
- **Verification is possible** — the framework can `GET /cms/v3/domains` and confirm a target domain is connected and has the right primary-page flags set.
- **Partial future automation**, if HubSpot relaxes the API, would cover: create/connect the domain, set `isPrimaryLandingPage = true`, set `isPrimarySitePage = true`, wire `primaryLandingPageId` to the created page.

**Interim concrete work (see separate plan): `PREFLIGHT_DOMAIN_HUBSPOT` check**

Rather than attempting the blocked automation, the framework should detect the domain-connection state at preflight and coach the user through the manual step with high specificity. See `docs/superpowers/plans/2026-04-22-preflight-domain-hubspot-check.md`.

**Dependencies for eventual automation:**

- DNS must propagate before HubSpot can verify the CNAME
- If DNS is automated via Cloudflare (R2), a polling step (`dig` until resolved) gates the domain connection attempt
- Browser-automation alternative (Playwright driving the HubSpot UI) — rejected as fragile and auth-complex; see session notes 2026-04-22

**Fallback (active approach):** the skill polls `GET /cms/v3/domains` via preflight (see plan above) to confirm the domain is connected and the primary-page flag is set. If not, surface clear UI steps.

---

## R4: A/B Testing

**Current state:** Landing pages are created with `landing-page` type (not `site-page`), so they support HubSpot's native A/B testing — but it's manual in the HubSpot UI.

**Goal:** The `landing-page` Terraform module exposes an `ab_variant` variable. When set, it creates a second page variant via the API and configures traffic split.

**Approach:** The Landing Pages API supports creating variations. The module would:

1. Create the primary page (existing behaviour)
2. If `ab_variant = true`, create a second variation with alternative content
3. Configure 50/50 traffic split (or configurable ratio)

**Content generation:** The skill would generate two landing page variants with different layouts, headlines, or CTAs based on the brief's brand direction.

---

## Target: Zero-Touch Pipeline

When R1, R2, and R8 are complete (R3 is blocked indefinitely; R8 is the interim verify-only replacement), the skill workflow from ICB to live landing page becomes fully automated:

```
/hs-lander -> ingest ICB -> generate brand -> scaffold -> build
  -> Terraform apply:
       Cloudflare DNS record
       GA4 property + data stream
       HubSpot resources (forms, pages, email, list)
       HubSpot domain connection (if API supports it)
  -> post-apply: form IDs + GA4 Measurement ID -> config
  -> rebuild with real IDs -> deploy to HubSpot Design Manager
  -> verify: DNS propagated, pages live, forms work, analytics firing
```

**Remaining manual steps** (may not be eliminable):
- HubSpot domain connection (if API doesn't support creation)
- Welcome email workflow activation in HubSpot UI (Workflows API may help here too)
- HubSpot subscription management (Marketing Hub + Content Hub must exist on the account)

---

## R5: HubSpot Subscription Check in Preflight

**Current state:** `preflight.sh` verifies token authentication (`API_ACCESS=ok` via `/account-info/v3/details`) and scope coverage (`SCOPES=ok`), but does not verify the account's subscription tier. A free or starter-lite account could pass preflight and fail mid-apply when Terraform tries to create resources that require Marketing Hub Starter (forms, marketing emails, dynamic lists) or Content Hub Starter (landing pages, Design Manager).

**Failure mode without the check:** late failure during `npm run setup` — some resources apply successfully, then the first tier-restricted resource fails, leaving state mid-flight and requiring cleanup before retry.

**Goal:** Detect missing subscriptions at preflight, before any apply runs, with specific coaching for the user.

**Approach:**

1. The `/account-info/v3/details` response (already fetched by `API_ACCESS` check) includes an `accountType` field and subscription metadata. Parse the existing response — no additional API call needed — to determine whether the portal has the required hubs.
2. Fall back to `/account-info/v3/subscriptions` if the details endpoint doesn't carry enough information to confirm Marketing Hub and Content Hub.
3. Emit a new preflight line:
   - `PREFLIGHT_SUBSCRIPTIONS=ok` — required hubs present
   - `PREFLIGHT_SUBSCRIPTIONS=missing marketing-hub,content-hub` — specific hubs missing
   - `PREFLIGHT_SUBSCRIPTIONS=skipped (API unreachable)` — upstream check failed

**Skill handling:** on `missing`, stop with a coaching message directing the user to HubSpot → Settings → Account & Billing → Products & Add-ons to upgrade the required hubs. On `skipped`, proceed with a warning (the API_ACCESS check would have already blocked).

**Output contract change:** the 12-line preflight contract extends to 13 lines (`SUBSCRIPTIONS` added after `SCOPES`, before `PROJECT_SOURCE`). SKILL.md and tests need updating in the same plan.

**Out of scope:** programmatic subscription upgrade (requires billing workflow — not available in Terraform or the public API).

### Subscription/office-location ID auto-discovery

A related but separate gap (surfaced during Heard's email payload work, 2026-04-22): the `subscriptionDetails.subscriptionId` and `officeLocationId` required by the marketing email payload are portal-specific and currently supplied manually by the user (looked up in HubSpot UI, pasted into the account profile).

Auto-discovery requires the `communication_preferences.read` scope, which would take the framework's required scope count from 7 to 8. Enabling the auto-discovery means:

1. Add `communication_preferences.read` to the required scopes list (breaking change for existing projects — Service Keys must be re-created with the new scope)
2. Extend `accounts-init.sh` or `preflight.sh` to call `GET /communication-preferences/v3/definitions` and surface the default subscription ID
3. Same for `/business-units/v3/` (for office location ID)
4. Update `HUBSPOT_SUBSCRIPTION_ID` and `HUBSPOT_OFFICE_LOCATION_ID` account-profile fields to be auto-populated instead of user-supplied

**Recommendation:** bundle this with the subscription check (R5 main focus) as a combined scope-expansion release. The breaking change to scopes is substantial and worth coordinating with the subscription check work rather than treating as two separate migrations.

### Decision notes (2026-04-22)

- **Coordinate with backup plan.** The current backup-state plan (`docs/superpowers/plans/2026-04-22-backup-state-and-profiles.md`) excludes account-config backups on the rationale that "account config rarely changes." R5's auto-discovery flips that — the framework starts mutating account config itself. When implementing R5, revise the backup plan to add account-config backup to `accounts-init.sh` / any new `accounts-update.sh` wrappers.
- **Scope-count breaking change needs migration messaging.** Going from 7 scopes to 8 invalidates existing Service Keys. Every project has to re-create keys on upgrade. Plan the migration messaging early — CHANGELOG entry, skill coaching, and probably a one-off `PREFLIGHT_SCOPES=mismatch-needs-rotation` state to catch the transition cleanly.

---

## R6: HubSpot API Contract Monitoring

**Current state:** The framework uses Mastercard/restapi (generic REST provider) against HubSpot's APIs. Payloads are static strings built in `forms.tf`, `pages.tf`, `emails.tf` etc. When HubSpot adds a required field or deprecates a shape, Terraform keeps sending the old payload until a deploy fails — silently broken between HubSpot's change and the first attempt to deploy.

Example: HubSpot Forms API v3 became a required-`formType` contract at some point after framework v1.0.0. The drift went undetected until the first real deploy (Heard, 2026-04-22) failed on both form creations. Plan-review-gate (pending) doesn't catch this — the plan looks fine; the payload is the problem.

**Goal:** Detect HubSpot API contract drift within 24 hours of it happening, not at the moment a user tries to ship.

**Approach — two complementary mechanisms, both in scope for R6:**

### 1. Nightly CI smoke test

A scheduled GitHub Actions job that, against a sandbox HubSpot portal:

1. Scaffolds a throwaway project from the current framework tag
2. Runs `npm run setup` to create one of each resource (form, page, email, list, property)
3. Asserts success
4. Runs `npm run destroy` to clean up
5. On failure, opens an issue with the API error verbatim

Catches drift nightly. Requires sandbox portal credentials in GitHub secrets — naturally pairs with R11 CI/CD work.

### 2. Preflight-time schema probe

Extend `preflight.sh` with a new `PREFLIGHT_API_CONTRACTS` check. For each HubSpot API the framework depends on (forms, pages, emails, lists, CRM properties), probe the endpoint's documented schema where one is available and compare against a fingerprint shipped with the framework (`tests/fixtures/api-fingerprints/<endpoint>.json` or similar).

States:

- `PREFLIGHT_API_CONTRACTS=ok` — all probed endpoints match the expected contract
- `PREFLIGHT_API_CONTRACTS=drift <comma-list-of-endpoints>` — at least one endpoint's schema has changed since the framework was tagged; the user may hit apply errors on deploy
- `PREFLIGHT_API_CONTRACTS=unavailable <comma-list-of-endpoints>` — HubSpot doesn't expose a schema for these endpoints; we can't verify them ahead of time
- `PREFLIGHT_API_CONTRACTS=partial drift=<list> unavailable=<list>` — mixed result, both categories

Exit code: 0 for `ok`, `unavailable`, or `partial` with no drift. 0 for `drift` too (warning, not blocking) — the skill surfaces it and asks the user whether to proceed. Not every drift breaks a deploy; we let the human decide.

This is a warning, not a gate. The purpose is informed consent: the user should know the framework's API assumptions may be stale before triggering an apply that could partially fail.

### How they complement

- Nightly CI catches drift *before* any user encounters it — best case, a v1.3.2 patch is shipped before anyone hits the broken endpoint.
- Preflight probe catches drift *at the start of a skill session*, as part of the standard preflight run in Step 1 — long before any content generation, Terraform plan, or apply. The user is warned up-front, with the option to update the framework or stop before investing effort in a doomed deploy.

The preflight probe fires **once per session at Step 1** (the existing Step 1 Preflight), the same point where config, credential, and DNS checks happen. It is deliberately NOT a pre-deploy gate — the whole point is early warning, so the user never spends 20 minutes crafting a brief only to find at deploy that the framework's API assumptions are stale.

Both mechanisms are useful. Neither is redundant.

### Not in scope

- Fixing the drift automatically — requires framework code changes specific to each API shape change
- Monitoring HubSpot changelogs — their release notes are inconsistent; empirical probing is more reliable
- Blocking apply on drift — user judgement, not an automated gate. Plan-review-gate (separate pending plan) covers destructive-action blocking

### Decision notes (2026-04-22)

- **Split vs bundle**: considered splitting nightly smoke (needs R11 CI/CD) from preflight probe (shippable standalone) into separate releases. Current decision: keep R6 as a single item conceptually, but allow the preflight probe to ship first as its own smaller release. The nightly smoke can wait for R11 without blocking the preflight probe.
- **Fingerprint maintenance**: the preflight probe depends on `tests/fixtures/api-fingerprints/<endpoint>.json` files that capture expected API shapes. These need updating every time HubSpot changes an endpoint — i.e. every time the drift the probe is looking for happens. That's a meaningful ongoing cost. Before implementing R6's preflight probe, consider whether the nightly smoke alone is sufficient (it is, for any portal with CI set up — the probe is only valuable for portals without CI coverage).

---

## R7: S3 Iframe Wrapper Hosting Mode

**Current state:** Framework supports three hosting modes via `DOMAIN` + `LANDING_SLUG` values (see `docs/framework.md` "Hosting modes"):
- Custom-domain-primary — connected custom subdomain, pages at root
- System-domain — HubSpot-provided `<portal>.hs-sites-*.com`
- System-domain-redirect — system domain + external URL redirect (e.g. Namecheap URL forwarding)

**Goal:** Add a fourth mode for operators who need the vanity URL to persist in the browser bar but can't or won't connect a custom domain to HubSpot. A minimal S3-hosted HTML page at the vanity subdomain wraps the HubSpot system-domain URL in a full-viewport iframe.

**Approach:**

1. Skill generates a small HTML wrapper (30 lines) that fills the viewport with an iframe pointed at the HubSpot system-domain URL.
2. A helper script (or documented runbook) provisions an S3 bucket + CloudFront distribution + ACM certificate for HTTPS on the vanity subdomain.
3. DNS: CNAME the vanity subdomain to the CloudFront distribution (not HubSpot CDN).
4. Browser URL stays as the vanity subdomain; iframe loads the HubSpot content.

**Why this is a niche mode, not a default:**

- **Third-party cookies blocked in the iframe** — Safari blocks by default, Chrome phasing out. HubSpot tracking (return-visitor attribution, session continuity) degrades meaningfully.
- **X-Frame-Options / CSP risk** — HubSpot may send headers that refuse embedding. Needs empirical verification per portal configuration.
- **SEO invisibility** — search engines see the S3 wrapper page (empty), not the HubSpot content inside.
- **Social previews (OG tags)** — need to be duplicated on the S3 wrapper page, because scrapers don't follow into iframes.
- **GA4 attribution degraded** — cross-domain tracking required to stitch vanity-domain referrals to iframe pageviews.
- **Infrastructure overhead** — S3 + CloudFront + ACM certs vs a single DNS URL-forward record.

**When it's worth doing:**

- Vanity URL must persist in browser bar for brand reasons AND tracking/SEO degradation is acceptable (e.g. pure email-driven campaigns with no organic search expectation)
- Upgrade path to Content Hub Professional is genuinely unavailable (not just deferred)
- Team has existing AWS S3/CloudFront infrastructure to extend

**When to avoid:**

- Short-term workaround pending a Pro upgrade (URL-redirect is cleaner)
- Anything SEO-dependent
- Forms as the primary conversion path (third-party cookie loss makes debugging form issues a nightmare)

**Out of scope:**

- Automating the AWS-side provisioning (S3/CloudFront/ACM via Terraform) — out of scope for hs-lander itself; operators use their own AWS tooling
- Mitigations for the third-party cookie issue — there isn't a good one

### Decision notes (2026-04-22)

- **Priority vs numbering**: R7 precedes R8 numerically but R8 (preflight domain-connection check) is more broadly useful and likely to ship first. Roadmap IDs are stable identifiers, not priority ordering. See "Currently on deck" section above for priority signalling.

---

## R8: Preflight HubSpot Domain Connection Check

**Current state:** `preflight.sh` checks DNS resolution (`PREFLIGHT_DNS`) but has no check for whether the target domain is actually connected in HubSpot. For custom-domain-primary mode, a domain with DNS in place but not yet connected in HubSpot UI causes the landing page to be created at a UUID slug instead of the expected root URL (observed on Heard, 2026-04-22, before the hosting-modes plan proposed switching Heard to system-domain mode).

**Goal:** A new `PREFLIGHT_DOMAIN_HUBSPOT` preflight line that checks `/cms/v3/domains` for the target domain, verifies it's connected, and in custom-domain modes verifies `isPrimaryLandingPage: true` with a `primaryLandingPageId` set.

**Status:** Plan written: `docs/superpowers/plans/2026-04-22-preflight-domain-hubspot-check.md`. Implementation pending.

**Scope coverage:** closes the domain-connection gap at preflight rather than waiting for deploy to fail. Subsumes the check that the skill currently does via a post-preflight `hs-curl.sh` call in the hosting-modes skill plan — once this lands, the skill just reads the preflight output.

---

## R9: Operator Ergonomics — Version Drift, Migration, Project Inspection

Three small-but-related operator-facing gaps, grouped because they share a common theme (smoother upgrade paths and project introspection):

### Project framework-version drift warning

**Problem:** A project's `terraform/main.tf` pins a specific framework tag (e.g. `?ref=v1.0.0`). When the user has a newer framework installed at `~/.local/share/hs-lander/`, the project still uses the pinned older version. Module APIs change between versions (e.g. v1.4.0 adds required `project_source_property_id` input); older projects hitting newer bootstrap won't know until a plan or apply error.

**Fix:** Skill reads the `?ref=` value from the project's `terraform/main.tf` during Step 1 preflight and compares against the framework's installed `VERSION`. If the project is pinned older, surface a warning: "Project pinned to framework v<X>; you have v<Y> installed. Breaking changes may apply — see CHANGELOG. Consider `migrate-project.sh` (R9) to bump automatically."

### `migrate-project.sh` helper

**Problem:** Migrating an existing project from one framework version to another means: bump the `ref=` tag in `terraform/main.tf`, add any new required module inputs (by reading CHANGELOG), run `tf:init`, run `tf:plan`, inspect, apply. Currently manual for every project; error-prone when multiple module-input changes stack up.

**Fix:** A new framework script `scripts/migrate-project.sh <project-dir> <target-version>` that:
1. Reads current `?ref=` from `terraform/main.tf`
2. Fetches the CHANGELOG entries between current and target
3. Shows the user what changes are needed (new inputs, renamed variables, etc.)
4. With user confirmation, applies the diffs and bumps the ref

Idempotent, transactional (writes to temp, moves on success). Supersedes hand-edits for upgrades.

### `projects-describe.sh` framework command

**Problem:** The skill sometimes needs to know what's in a project profile — DOMAIN, LANDING_SLUG, form IDs that `post-apply.sh` has written. Currently the only path is `Read` on `~/.config/hs-lander/<account>/<project>.sh`. That's OK for the skill (rule 3 permits it on explicit paths) but means no structured output, no validation, no single source of truth for profile schema.

**Fix:** Framework command `scripts/projects-describe.sh <account> <project>` that outputs structured `PROJECT_<FIELD>=<value>` lines mirroring `accounts-describe.sh`'s pattern. Skill uses it instead of Read where structured output is more appropriate (mode detection, post-apply state display).

**Bundled release rationale:** all three are operator-ergonomics improvements that become more valuable as the number of projects grows. Heard is project #1 on the framework; at 3+ projects the migration and drift-warning pay for themselves. Ship together.

---

## R10: Skill Hygiene — Rule 6 Against Preemptive Inspection

**Current state:** The skill's Operating Rule 3 permits `Read`/`Glob` on filesystem for inspection. Rule 5 says "diagnose before retrying". Neither forbids *preemptive* inspection of operational files before it's actually needed.

**Observed pattern (Heard session trace, 2026-04-22):** after `projects-list.sh dml` confirmed Heard is a returning project, the skill did a `Read` on `~/.config/hs-lander/dml/heard.sh` to "orient" — before calling `init-project-pointer.sh`. That Read was unnecessary (preflight's structured output would have surfaced anything needed) and added a permission prompt + latency. Pattern has been observed once; deferred for plan-writing until seen again.

**Proposed Rule 6:** Don't inspect operational files preemptively. Structured output from framework commands is the source of truth for operational state. Don't `Read` `~/.config/hs-lander/` files, `project.config.sh`, or Terraform state to "understand the situation" — run the command that answers the question. `Read` on operational files is only appropriate when preflight or another command has explicitly directed you to a file.

**Trigger for promotion to a plan:** observe the preemptive-inspection pattern again on a second real session trace. If it's a one-off, don't over-engineer the ruleset. If it recurs, write the small skill plan and add Rule 6 to SKILL.md.

**Why captured here:** so we don't re-discover the gap cold in a future session and spend the thinking time again.

### Decision notes (2026-04-22)

- **Relationship with Rule 3**: Rule 3 permits `Read`/`Glob` on explicit paths for filesystem inspection. Rule 6 would forbid preemptive inspection. These can coexist but the phrasing needs care: Rule 3 is about *capability* (Read is allowed instead of shelling out); Rule 6 is about *timing* (don't inspect before the workflow tells you to). When Rule 6 is promoted, spell out this distinction in SKILL.md. Draft phrasing: "Rule 6 supplements Rule 3: Read/Glob remain the correct tools when you need filesystem info; Rule 6 says don't need filesystem info before the workflow directs you to it."

---

## R11: CI/CD with GitHub Secrets

**Current state:** All config and credentials are local — account profiles at `~/.config/hs-lander/<account>/`, secrets in macOS Keychain. Deployment runs locally via `npm run deploy`.

**Goal:** Support running the full build-deploy pipeline in GitHub Actions, with credentials stored as GitHub Secrets and config as repository variables.

**Approach:**

The local account profile system (`~/.config/hs-lander/<account>/config.sh`) maps directly to GitHub's two-tier secrets model:

| Local config | GitHub equivalent |
|---|---|
| Account `config.sh` values (portal ID, region) | Organisation-level secrets/variables in the adopting GitHub org |
| Project config values (slug, domain, GA4 ID) | Repository-level secrets/variables |
| `HUBSPOT_TOKEN_KEYCHAIN_SERVICE` + Keychain | Organisation secret `HUBSPOT_TOKEN` (the actual token value) |

**Implementation:**

1. **Deployment workflow** (`.github/workflows/deploy.yml`): triggered on push to `main` or manual dispatch. Reads secrets, writes a temporary `project.config.sh` in the runner, runs `npm run build && npm run deploy`.

2. **Scripts detect environment**: if running in CI (GitHub Actions sets `CI=true`), scripts read from environment variables directly instead of sourcing `~/.config/hs-lander/` and Keychain. The config hierarchy becomes:
   - CI: `$HUBSPOT_PORTAL_ID` etc. come from GitHub Secrets/Variables injected as env vars
   - Local: `$HUBSPOT_PORTAL_ID` etc. come from account profile sourced via `project.config.sh`

3. **No Keychain in CI**: scripts check `if [ "$CI" = "true" ]` and skip the `security find-generic-password` call, expecting `$HUBSPOT_TOKEN` to be set directly as an env var (from GitHub Secrets).

**Auth for CI:** The HubSpot Service Key is stored as an organisation-level secret. Per-project values (domain, GA4 ID, form IDs) are repository-level variables or secrets depending on sensitivity.

**Migration path:** existing local workflows continue to work unchanged. CI is opt-in per repository by adding the deploy workflow and configuring secrets.

---

## R12: Account Profile Sync

**Current state:** Account profiles are local files. Team members must create their own copies manually.

**Goal:** `hs-lander accounts sync` pulls account profiles from a shared source (team repo or GitHub org config).

**Approach:** A shared repo (e.g., the org's `github-org-config`) contains account profile templates. A sync script pulls non-secret values and writes them to `~/.config/hs-lander/`. Secrets remain in each team member's local Keychain (or GitHub Secrets for CI).

This keeps the local-first model but adds team portability.

---

## R13: Skill-Driven End-to-End Deployment Test

**Current state:** End-to-end deployment is verified manually. Local tests (`tests/test-build.sh`, `tests/test-post-apply.sh`, `tests/test-terraform-plan.sh`) cover the framework's moving parts without network, and `tests/test-deployment.sh` can verify a live deployment after the fact — but there is no automated pipeline that exercises the full "brief -> live landing page" flow against real infrastructure.

An earlier draft of this test lived at `.github/workflows/smoke.yml`; it was archived to `docs/archive/workflows/smoke.yml` on 2026-04-21 because it relied on real secrets and didn't exercise the skill. It is preserved as a reference for the eventual replacement.

**Goal:** A periodic (or on-demand) workflow that runs the `hs-lander` skill end-to-end against isolated test resources, verifies the output, and tears everything down.

**Isolation strategy:**

| Resource | Test home |
|---|---|
| HubSpot | **Developer test account** (HubSpot provides free sandbox portals under any developer account). Separate portal ID from production. |
| GA4 | A dedicated GA4 **test property** under the account's Google Analytics organisation, or a sandbox GA4 account. |
| Cloudflare DNS | A test subdomain on the managed zone (e.g. `*.smoke-test.<account-domain>`) or a disposable zone. |
| GitHub | Open question — likely a dedicated throwaway repo under the account's GitHub org (a `*-sandbox` variant works well). Only needed once the skill itself creates a GitHub repo as part of scaffolding. |

**Approach:**

1. Trigger: `workflow_dispatch` and/or weekly schedule. Not on tag push.
2. Runner provisions a fresh project slug (`smoke-${RUN_ID}`).
3. Runs the skill non-interactively against a canned test brief.
4. Skill drives the full pipeline: scaffold -> build -> Terraform apply -> post-apply -> deploy.
5. Verification step: HTTP 200 on landing + thank-you pages, form embed present, no unresolved tokens, HubSpot API confirms resources exist and are PUBLISHED, GA4 property exists and is receiving data (if R1 landed).
6. Cleanup: `terraform destroy`, DNS record deletion, GA4 property archival. Always runs, even on failure.

**Dependencies:**

- R11 (CI/CD with GitHub Secrets) must be in place — the workflow needs non-interactive credentials for HubSpot, Cloudflare, and Google Cloud.
- The skill (Session 3+) must expose a non-interactive mode that takes a brief and config and runs to completion without prompts.
- The test runner writes a valid two-tier config (account + project) in the runner's `~/.config/hs-lander/` — the layout shipped in the account-config-hierarchy refactor.

**Why this is worth doing:**

Manual verification per project catches project-specific issues but not framework regressions. An automated e2e test run after any change to modules, scripts, or the skill itself gives confidence that the pipeline still works end-to-end before a project depends on it.

---

## R14: Claude Code Plugin Packaging

**Current state:** The hs-lander skill is installed by symlinking `~/DocsLocal/skills/hs-lander/` into `~/.claude/skills/hs-lander/`. The framework is cloned by `bootstrap.sh` on first use. Both mechanisms work but aren't portable, aren't versioned together, and require technical setup steps that block wider adoption.

**Goal:** Package the skill + bootstrap + framework references as a first-class Claude Code plugin, installable via `claude plugins install digital-mercenaries-ltd/hs-lander-plugin` (or equivalent). Framework stays as a separate Git-pinned Terraform module source.

**Approach:**

- Move skill content into a plugin directory structure: `plugin.json` + `skills/hs-lander/` + `scripts/bootstrap.sh` + references
- `bootstrap.sh` becomes shorter — the plugin machinery handles installation location; bootstrap only has to ensure the *framework* Git clone exists (same job it has today)
- Plugin permissions declaration: pre-allow the specific script paths the skill invokes, eliminating the permission prompts a fresh user currently sees
- Versioned releases via plugin registry (or Git tags if HubSpot distribution model prefers)

**Dependencies:**

- The skill's interface surface must be stable before packaging — plugin updates cause less friction than rewrites. Don't package until the operating rules and step numbering have stabilised (probably after R9 lands and the operational-ergonomics work is settled).

**What unblocks this:**

- Claude Code plugin marketplace maturity (external dependency — as of 2026-04 the plugin system is production but the distribution story for org-scoped plugins is still evolving)
- A clear team/user who wants to adopt hs-lander without symlinking skills — DML colleagues, or client hand-offs where the client needs to deploy-and-iterate without reading our README

**Positioning:** same functional capability as the symlinked skill — plugin distribution is an *ergonomics* win, not a capability win.

---

## R15: Enterprise-Tier Workflow Automation

**Current state:** The welcome email created by the framework lives in HubSpot as an `AUTOMATED_EMAIL` but requires a manual step to wire it to the form-submission trigger. From SKILL.md Step 11: "set up the welcome-email workflow in HubSpot UI (API for workflows requires Enterprise)".

**Goal:** When running on a HubSpot portal with Marketing Hub Enterprise, automatically create the workflow that triggers the welcome email on form submission, so the skill can deliver a fully-operational funnel end-to-end with no manual HubSpot UI steps after apply.

**Approach:**

- New Terraform resource in `landing-page` module, gated by a variable `enable_automated_workflow = false` (default) or similar
- When enabled, creates a Workflows API object that triggers on form submission and sends the welcome email
- Validate subscription tier at preflight; refuse to enable the flag on non-Enterprise portals with clear messaging

**Why tier-gated:** requires Marketing Hub Enterprise subscription. Workflow API is locked behind that tier. This feature is of zero value to any user below Enterprise. Its addition doesn't benefit the baseline framework. Keep it as an explicit enterprise extension so the feature exists for those who need it without cluttering the default path.

**Alternative (explored and rejected):** Zapier or Make.com as workflow engines — would work on any tier but introduces third-party dependencies, additional auth, and runtime cost per trigger. Enterprise workflows are the clean answer for teams already paying for Enterprise.

---

## Maintainer Tooling (not versioned — living recommendation)

These aren't shipped features; they're setup recommendations for framework maintainers. Documented here so the same suggestions don't get re-discovered per contributor.

### Terraform MCP server for framework development

When editing the Terraform modules (`terraform/modules/landing-page/*.tf` etc.), having the Terraform MCP server installed in your Claude Code configuration is meaningfully helpful: provider docs lookup, resource schema validation, working examples from the Registry. The Mastercard/restapi provider has dense documentation; the MCP makes it browsable without context-switching.

**Not a runtime dependency** — users of the framework don't need it. Only framework maintainers writing new module code benefit.

**Setup:** add to `~/.claude/claude.json` or equivalent per Claude Code's plugin config. See `CONTRIBUTING.md` (when written) for the exact config block.

### Forthcoming: `CONTRIBUTING.md`

The maintainer tooling recommendations above, plus style guide, testing conventions, and the investigation-before-implementation pattern established during v1.4.0 drift fixes, belong in a `CONTRIBUTING.md` at the framework repo root. Not urgent; write it when the first external contributor needs it.

### Open maintainer concerns (captured for future attention)

Gaps noted during plan reviews that haven't yet warranted their own plans:

- **`VERSION.compat` maintenance process**. The file is read by the skill's `check-framework-compat.sh` to decide whether the installed framework version is compatible with the skill's expectations. No documented process for when to update it, who updates it, or how it's kept in sync with actual breaking changes. Worst case: it silently drifts and the compat check becomes either uselessly permissive or spuriously strict. Document the update process (probably: every framework release that touches a script's output contract, a preflight line, or a module input must bump `VERSION.compat` accordingly) and add a CI check that flags commits changing contracts without a `VERSION.compat` update.

- **`preflight.sh` length and structure**. At ~500 lines and growing (with every new preflight check adding ~30-50 lines), `preflight.sh` is approaching maintainability concerns. Plan for R8 introduces a first `lib/` extraction (`scripts/lib/hosting-mode.sh`). A systematic refactor that extracts each `PREFLIGHT_*` check into its own `lib/check-<name>.sh` (sourced and invoked from a trimmer `preflight.sh`) would keep things readable. Not urgent; revisit when the next check addition pushes the file past some pain threshold (say, 700 lines).
