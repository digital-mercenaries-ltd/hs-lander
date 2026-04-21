# hs-lander Roadmap

Items beyond v1.0.0. Each reduces the manual steps between ICB and live landing page.

---

## v1.1: Automated GA4 Property Setup

**Current state:** Manual — create GA4 property in Google Analytics UI, add web data stream, copy Measurement ID into `project.config.sh`.

**Goal:** Skill creates the GA4 property, data stream, and injects the Measurement ID automatically.

**Approach:**

The [GA4 Admin API v1](https://developers.google.com/analytics/devops/rest/admin/v1) supports programmatic property and data stream creation:

1. Create GA4 property (`properties.create`) under the DML Analytics account
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

## v1.2: Automated DNS via Cloudflare

**Current state:** Manual — add a CNAME record at the domain registrar pointing the project subdomain to HubSpot's CDN endpoint.

**Goal:** Skill creates the DNS record automatically when scaffolding a new project.

**Prerequisite:** Migrate `digitalmercenaries.ai` nameservers to Cloudflare. Cloudflare has the best API tooling and Terraform support of any DNS provider.

**Approach:**

The [Cloudflare API v4](https://developers.cloudflare.com/api/resources/dns/subresources/records/) and [`cloudflare/cloudflare` Terraform provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs) support DNS record management:

1. Create CNAME record: `${project_slug}.${ACCOUNT_DOMAIN}` -> `${portal_id}.group0.sites.hscoscdn-${HUBSPOT_REGION}.net` (NA1 portals use `hscoscdn-na1.net`)
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

## v1.3: Automated HubSpot Domain Connection

**Current state:** Manual — connect the subdomain in HubSpot UI (Settings -> Domains & URLs), wait for CNAME verification, SSL provisioned by Let's Encrypt.

**Goal:** Automate domain connection so no HubSpot UI interaction is needed.

**Investigation needed:**

- The [CMS Domains API](https://developers.hubspot.com/docs/api/cms/domains) can list and get domains (`GET /cms/v3/domains`) but it's unclear whether `POST /cms/v3/domains` (or another endpoint) can programmatically connect a new domain
- Domain connection includes SSL certificate provisioning (Let's Encrypt) which may inherently require UI confirmation
- If not fully automatable, the skill can at least verify the domain is connected and give clear instructions for the one manual step

**Dependencies:**

- DNS must propagate before HubSpot can verify the CNAME
- If DNS is automated via Cloudflare (v1.2), a polling step (`dig` until resolved) gates the domain connection attempt

**Fallback:** Even if creation can't be automated, the skill can poll `GET /cms/v3/domains` after deployment to confirm the domain is connected and pages are reachable, rather than relying on manual verification.

---

## v1.4: A/B Testing

**Current state:** Landing pages are created with `landing-page` type (not `site-page`), so they support HubSpot's native A/B testing — but it's manual in the HubSpot UI.

**Goal:** The `landing-page` Terraform module exposes an `ab_variant` variable. When set, it creates a second page variant via the API and configures traffic split.

**Approach:** The Landing Pages API supports creating variations. The module would:

1. Create the primary page (existing behaviour)
2. If `ab_variant = true`, create a second variation with alternative content
3. Configure 50/50 traffic split (or configurable ratio)

**Content generation:** The skill would generate two landing page variants with different layouts, headlines, or CTAs based on the brief's brand direction.

---

## Target: Zero-Touch Pipeline

When v1.1-v1.3 are complete, the skill workflow from ICB to live landing page becomes fully automated:

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

## v2.0: CI/CD with GitHub Secrets

**Depends on:** the account-config-hierarchy refactor (`docs/superpowers/plans/2026-04-20-account-config-hierarchy.md`). The two-tier mapping below assumes account profiles exist at `~/.config/hs-lander/<account>/`; that layout does not yet exist on v1.0.0.

**Current state (post-hierarchy-refactor):** All config and credentials are local — account profiles at `~/.config/hs-lander/`, secrets in macOS Keychain. Deployment runs locally via `npm run deploy`.

**Goal:** Support running the full build-deploy pipeline in GitHub Actions, with credentials stored as GitHub Secrets and config as repository variables.

**Approach:**

The local account profile system (`~/.config/hs-lander/<account>/config.sh`) maps directly to GitHub's two-tier secrets model:

| Local config | GitHub equivalent |
|---|---|
| Account `config.sh` values (portal ID, region) | Organisation-level secrets/variables in `digital-mercenaries-ltd` |
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

## v2.1: Account Profile Sync

**Depends on:** the account-config-hierarchy refactor (same as v2.0).

**Current state (post-hierarchy-refactor):** Account profiles are local files. Team members must create their own copies manually.

**Goal:** `hs-lander accounts sync` pulls account profiles from a shared source (team repo or GitHub org config).

**Approach:** A shared repo (e.g., the org's `github-org-config`) contains account profile templates. A sync script pulls non-secret values and writes them to `~/.config/hs-lander/`. Secrets remain in each team member's local Keychain (or GitHub Secrets for CI).

This keeps the local-first model but adds team portability.

---

## v2.2: Skill-Driven End-to-End Deployment Test

**Current state:** End-to-end deployment is verified manually. Local tests (`tests/test-build.sh`, `tests/test-post-apply.sh`, `tests/test-terraform-plan.sh`) cover the framework's moving parts without network, and `tests/test-deployment.sh` can verify a live deployment after the fact — but there is no automated pipeline that exercises the full "brief -> live landing page" flow against real infrastructure.

An earlier draft of this test lived at `.github/workflows/smoke.yml`; it was archived to `docs/archive/workflows/smoke.yml` on 2026-04-21 because it relied on real secrets and didn't exercise the skill. It is preserved as a reference for the eventual replacement.

**Goal:** A periodic (or on-demand) workflow that runs the `hs-lander` skill end-to-end against isolated test resources, verifies the output, and tears everything down.

**Isolation strategy:**

| Resource | Test home |
|---|---|
| HubSpot | **Developer test account** (HubSpot provides free sandbox portals under any developer account). Separate portal ID from production. |
| GA4 | A dedicated GA4 **test property** under the DML Analytics account, or a sandbox GA4 account. |
| Cloudflare DNS | A test subdomain on the managed zone (e.g. `*.smoke-test.digitalmercenaries.ai`) or a disposable zone. |
| GitHub | Open question — likely a dedicated throwaway repo in `digital-mercenaries-ltd-sandbox` (or similar). Only needed once the skill itself creates a GitHub repo as part of scaffolding. |

**Approach:**

1. Trigger: `workflow_dispatch` and/or weekly schedule. Not on tag push.
2. Runner provisions a fresh project slug (`smoke-${RUN_ID}`).
3. Runs the skill non-interactively against a canned test brief.
4. Skill drives the full pipeline: scaffold -> build -> Terraform apply -> post-apply -> deploy.
5. Verification step: HTTP 200 on landing + thank-you pages, form embed present, no unresolved tokens, HubSpot API confirms resources exist and are PUBLISHED, GA4 property exists and is receiving data (if v1.1 landed).
6. Cleanup: `terraform destroy`, DNS record deletion, GA4 property archival. Always runs, even on failure.

**Dependencies:**

- v2.0 (CI/CD with GitHub Secrets) must be in place — the workflow needs non-interactive credentials for HubSpot, Cloudflare, and Google Cloud.
- The skill (Session 3+) must expose a non-interactive mode that takes a brief and config and runs to completion without prompts.
- The account-config-hierarchy refactor must be complete so the test runner writes the new two-tier config format, not the legacy flat layout.

**Why this is worth doing:**

Manual verification per project (Heard today, TSC next, etc.) catches project-specific issues but not framework regressions. An automated e2e test run after any change to modules, scripts, or the skill itself gives confidence that the pipeline still works end-to-end before a project depends on it.
