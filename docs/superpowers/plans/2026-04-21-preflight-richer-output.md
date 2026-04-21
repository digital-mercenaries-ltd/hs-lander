# Plan: Richer preflight.sh output for skill coaching

**Date:** 2026-04-21
**Status:** Ready for implementation — open questions resolved below.

## Context

`scripts/preflight.sh` emits structured `PREFLIGHT_<NAME>=ok|missing|error|warn|skipped` lines that the hs-lander skill parses to decide what guidance to give the user. Today's granularity conflates distinct failure modes — "no HubSpot account at all", "account exists but token expired", and "token works but is missing the forms scope" all currently surface as `PREFLIGHT_API_ACCESS=error` with a freetext HTTP-code string. The skill can't coach the user from a blank state because it can't tell which state it's in.

This plan refactors preflight to distinguish the states the skill needs, plus adds two new checks (`PREFLIGHT_SCOPES`, `PREFLIGHT_ACCOUNT_PROFILE`).

## Already shipped (excluded from scope)

The original request included a sixth item — **post-apply.sh writing form IDs to `project.config.sh` instead of the hierarchy file**. That was fixed in PR #4 (merged 2026-04-21). No further action needed.

## Resolved decisions

- **PREFLIGHT_CREDENTIAL states:** `missing | empty | found`. This renames the current `ok` to `found`, matching the brief's triad. Breaking change for any consumer still keying off `ok` — only the skill consumes this output and the skill-side change is in lockstep.
- **Scope introspection:** use HubSpot's dedicated endpoint `POST /oauth/v2/private-apps/get/access-token-info` (confirmed to exist for Private App tokens / Service Keys; returns `{"userId": ..., "hubId": ..., "appId": ..., "scopes": [...]}`). One API call replaces the earlier per-endpoint-probe scheme. See "SCOPES check — introspection endpoint" below for detail.
- **Symmetric profile splits:** add `PREFLIGHT_PROJECT_PROFILE` alongside `PREFLIGHT_ACCOUNT_PROFILE`. Gives the skill a path-level pointer ("create `~/.config/hs-lander/<account>/<project>.sh`") rather than a variable list it has to reverse-engineer back to a file.

---

## Target output (post-change)

Example of a happy-path run:

```
PREFLIGHT_PROJECT_POINTER=ok
PREFLIGHT_ACCOUNT_PROFILE=ok
PREFLIGHT_PROJECT_PROFILE=ok
PREFLIGHT_CREDENTIAL=found
PREFLIGHT_API_ACCESS=ok
PREFLIGHT_SCOPES=ok
PREFLIGHT_PROJECT_SOURCE=ok
PREFLIGHT_DNS=ok landing.example.com resolves
PREFLIGHT_GA4=ok
PREFLIGHT_FORM_IDS=ok
```

Example of a blank-state run:

```
PREFLIGHT_PROJECT_POINTER=ok
PREFLIGHT_ACCOUNT_PROFILE=incomplete HUBSPOT_PORTAL_ID,HUBSPOT_TOKEN_KEYCHAIN_SERVICE
PREFLIGHT_PROJECT_PROFILE=missing ~/.config/hs-lander/myacct/myproj.sh
PREFLIGHT_CREDENTIAL=skipped (account profile incomplete)
PREFLIGHT_API_ACCESS=skipped (no credential)
PREFLIGHT_SCOPES=skipped (no credential)
PREFLIGHT_PROJECT_SOURCE=skipped (no credential)
PREFLIGHT_DNS=skipped (DOMAIN not set)
PREFLIGHT_GA4=warn GA4_MEASUREMENT_ID is empty
PREFLIGHT_FORM_IDS=warn CAPTURE_FORM_ID is empty (expected before first deploy)
```

Example of an expired-token run:

```
PREFLIGHT_PROJECT_POINTER=ok
PREFLIGHT_ACCOUNT_PROFILE=ok
PREFLIGHT_PROJECT_PROFILE=ok
PREFLIGHT_CREDENTIAL=found
PREFLIGHT_API_ACCESS=unauthorized HubSpot returned 401 — token invalid or expired
PREFLIGHT_SCOPES=skipped (API access failed)
PREFLIGHT_PROJECT_SOURCE=skipped (API access failed)
PREFLIGHT_DNS=ok landing.example.com resolves
PREFLIGHT_GA4=ok
PREFLIGHT_FORM_IDS=ok
```

Example of missing-scope run:

```
PREFLIGHT_PROJECT_POINTER=ok
PREFLIGHT_ACCOUNT_PROFILE=ok
PREFLIGHT_PROJECT_PROFILE=ok
PREFLIGHT_CREDENTIAL=found
PREFLIGHT_API_ACCESS=ok
PREFLIGHT_SCOPES=missing crm.lists.write,forms
PREFLIGHT_PROJECT_SOURCE=ok
PREFLIGHT_DNS=ok landing.example.com resolves
PREFLIGHT_GA4=ok
PREFLIGHT_FORM_IDS=ok
```

Example of DNS-missing run (showing expected CNAME target):

```
PREFLIGHT_DNS=missing landing.example.com does not resolve (expected CNAME target: 12345678.group0.sites.hscoscdn-eu1.net)
```

---

## Exit-code semantics (unchanged principle, refined application)

Exit 1 if any required check is in a blocking state:
- `PROJECT_POINTER` missing / incomplete
- `ACCOUNT_PROFILE` missing / incomplete
- `PROJECT_PROFILE` missing / incomplete
- `CREDENTIAL` missing / empty
- `API_ACCESS` unauthorized / forbidden / unreachable / error
- `SCOPES` missing
- `DNS` missing
- `PROJECT_SOURCE` error (404 remains recoverable)

Exit 0 with warnings for:
- `PROJECT_SOURCE=missing` (first project on account — recoverable)
- `GA4=warn`
- `FORM_IDS=warn`
- `DNS=skipped` (no DNS tool installed — as today)

---

## SCOPES check — introspection endpoint

**Endpoint:** `POST https://api.hubapi.com/oauth/v2/private-apps/get/access-token-info`

**Request:**
- Body: `{"tokenKey": "<the_service_key>"}`
- Header: `Authorization: Bearer <the_service_key>` (redundant if the body alone authenticates, but consistent with every other call preflight makes; HubSpot's docs are ambiguous on which is required — including both is safe).

**Response (happy path, 200):**
```json
{
  "userId": 123456,
  "hubId": 1020304,
  "appId": 2011410,
  "scopes": ["crm.objects.contacts.read", "crm.objects.contacts.write", "..."]
}
```

**Logic:**
1. POST the token. If the response is non-200, emit `PREFLIGHT_SCOPES=error HubSpot returned HTTP <code>` and mark as blocking.
2. Parse the JSON body; extract the `scopes` array.
3. Compute `required - granted` as a set difference.
4. If empty: `PREFLIGHT_SCOPES=ok`.
5. Otherwise: `PREFLIGHT_SCOPES=missing <comma-list-of-missing-scopes>`.

**Required scopes** (hard-coded in preflight, matches `docs/framework.md` Prerequisites):

```
crm.objects.contacts.read
crm.objects.contacts.write
crm.schemas.contacts.write
crm.lists.read
crm.lists.write
forms
content
```

**JSON parsing:** prefer `python3` (present on macOS by default, available on all `ubuntu-latest` GitHub runners) for robust parsing. If `python3` is unavailable, fall back to a shellcheck-clean grep/sed pattern against the known-narrow JSON shape.

**Verification before shipping:** run preflight against a real Private App token that has all 7 scopes; confirm `SCOPES=ok`. Then run against a token with one scope deliberately removed; confirm the missing scope is named correctly. Both tests are manual, one-off; the automated test-preflight uses the mock curl to exercise both code paths.

**Credential safety:** the tokenKey body carries the token. Same xtrace-disabled guard as the other authenticated calls. Response body is parsed for the `scopes` array but never printed verbatim (the response contains `hubId`/`appId` metadata — non-secret, but we only care about the scopes).

---

## Changes by file

### `scripts/preflight.sh`

Restructure into ordered, explicit guards so later checks short-circuit if earlier ones fail:

1. **PROJECT_POINTER** (new name, replacing the implicit project.config.sh check):
   - Does `$PROJECT_DIR/project.config.sh` exist?
   - Does it (once sourced in a guarded subshell) set both `HS_LANDER_ACCOUNT` and `HS_LANDER_PROJECT`?

2. **ACCOUNT_PROFILE** (new):
   - Does `$HOME/.config/hs-lander/$HS_LANDER_ACCOUNT/config.sh` exist?
   - After sourcing in a guarded subshell, are the required account-level fields set and non-empty? (`HUBSPOT_PORTAL_ID`, `HUBSPOT_REGION`, `HUBSPOT_TOKEN_KEYCHAIN_SERVICE`.)
   - Report `ok` / `incomplete <comma-list of missing fields>` / `missing`.

3. **PROJECT_PROFILE** (new, per Q3 recommendation):
   - Does `$HOME/.config/hs-lander/$HS_LANDER_ACCOUNT/$HS_LANDER_PROJECT.sh` exist?
   - Required fields: `PROJECT_SLUG`, `DOMAIN`, `DM_UPLOAD_PATH`. (`GA4_MEASUREMENT_ID` stays a `warn` via the existing `GA4` line; form IDs stay warnings.)
   - Report `ok` / `incomplete <list>` / `missing`.

4. **CREDENTIAL** (refined):
   - `missing`: `security find-generic-password` returns non-zero (no Keychain entry).
   - `empty`: returns zero but the value is blank.
   - `found`: returns zero with a non-empty value. (Renamed from `ok`; breaking change, skill-side consumer updated in lockstep.)

5. **API_ACCESS** (refined):
   - Single call to `GET /account-info/v3/details` with the token.
   - Classify on curl exit code + HTTP code:
     - curl exit ≠ 0 → `unreachable` (DNS, connection refused, TLS failure).
     - HTTP 200 → `ok`.
     - HTTP 401 → `unauthorized`.
     - HTTP 403 → `forbidden`.
     - Anything else → `error HTTP <code>`.

6. **SCOPES** (new):
   - Only run if `API_ACCESS=ok`.
   - Single `POST /oauth/v2/private-apps/get/access-token-info` call (see "SCOPES check — introspection endpoint" above).
   - Parse the `scopes` array, compute set difference against the required 7, emit `ok` or `missing <comma-list>`.

7. **PROJECT_SOURCE** (unchanged: 404 stays recoverable, non-blocking).

8. **DNS** (refined):
   - Same dig/host/getent fallback.
   - On `missing`, append `(expected CNAME target: ${HUBSPOT_PORTAL_ID}.group0.sites.hscoscdn-${HUBSPOT_REGION}.net)` to the detail string.

9. **GA4 / FORM_IDS** (unchanged).

Credential-safety posture unchanged: the whole block from `security` lookup through API/scope probes stays inside the existing xtrace-disabled section. The new scope probes also use `-H "Authorization: Bearer $token"` and must share that guard.

### `tests/test-preflight.sh`

Extend the `curl` mock to:
- Recognise the introspection endpoint (`/oauth/v2/private-apps/get/access-token-info`) in addition to the existing `/account-info/v3/details` and `/crm/v3/properties/contacts/project_source`.
- Accept `MOCK_CURL_<ENDPOINT>_CODE` env vars for each endpoint's HTTP status.
- Accept `MOCK_CURL_SCOPES_BODY` — a JSON fragment (or a comma-list that the mock wraps into JSON) used as the introspection response body when the scope-check curl call has `-o <file>` capturing the body to disk. The real preflight uses `-o /dev/null -w "%{http_code}"` for status-only calls and a separate capture for the scopes call.
- Simulate `curl` exit-code failure via `MOCK_CURL_FAIL=<exit-code>` for the `unreachable` path.

New scenarios (in addition to current 7):

- **A — PROJECT_POINTER missing**: no `project.config.sh` in project dir.
- **B — ACCOUNT_PROFILE missing**: `HS_LANDER_ACCOUNT` set but the account config file doesn't exist.
- **C — ACCOUNT_PROFILE incomplete**: account config file exists but `HUBSPOT_PORTAL_ID` is empty. Assert detail lists the missing field.
- **D — PROJECT_PROFILE missing**: account config is fine, project config file doesn't exist.
- **E — CREDENTIAL=empty**: mock `security` returns zero with empty stdout.
- **F — API_ACCESS=unauthorized** (401): replaces current Scenario 7's 401 → error assertion.
- **G — API_ACCESS=forbidden** (403).
- **H — API_ACCESS=unreachable**: mock `curl` exits non-zero.
- **I — SCOPES=ok**: introspection endpoint returns 200 with a body listing all 7 required scopes (plus maybe others — extras are fine).
- **J — SCOPES=missing subset**: introspection returns a body with 5 of the 7 scopes present. Assert detail lists exactly the 2 missing scopes, comma-separated, in a stable order (e.g. alphabetical).
- **L — SCOPES=error**: introspection returns a 500 (unexpected). Assert detail includes the HTTP code.
- **K — DNS=missing with expected CNAME**: mock `dig` returns empty; assert detail includes `expected CNAME target:` with the correct hostname.

Existing scenarios that need adapting:
- Scenario 2 (missing `HUBSPOT_TOKEN_KEYCHAIN_SERVICE`): update to expect `PREFLIGHT_ACCOUNT_PROFILE=incomplete HUBSPOT_TOKEN_KEYCHAIN_SERVICE` rather than the old `PREFLIGHT_CONFIG=missing`.
- Scenario 7 (401 → error): rename to D per above.

### `docs/framework.md`

Add a "Preflight output reference" subsection under the Authentication section (or its own section) documenting every `PREFLIGHT_*` check, the states each can be in, and what the detail string encodes. This gives adopters who aren't using the skill a way to read the output.

### `CLAUDE.md`

Light touch — update the Scripts description for `preflight.sh` to note it emits richer output. No structural change.

### CI

No workflow changes — `preflight-test` already runs `bash tests/test-preflight.sh`.

---

## TDD sequence

1. Write failing tests for the easier refinements first:
   - Scenario K (DNS with expected CNAME) — small, self-contained.
   - Scenario E (CREDENTIAL=empty) — small.
2. Implement DNS detail-string fix and CREDENTIAL=empty state. GREEN.
3. Split ACCOUNT_PROFILE + PROJECT_PROFILE + PROJECT_POINTER checks out of the current monolithic CONFIG check. Write scenarios A, B, C, D. Implement guards. GREEN.
4. Refine API_ACCESS into 4 states. Write scenarios F, G, H. Implement. GREEN.
5. Add SCOPES check. Write scenarios I, J. Implement. GREEN.
6. Update docs.
7. Verify all 7 existing scenarios (with adapted assertions where relevant) + 12 new scenarios (A–L) = 19 scenarios total, roughly 35+ assertions.

---

## Out of scope

- Skill-side changes (consuming the richer output) — separate session.
- Changes to `tf.sh`, `hs-curl.sh`, `upload.sh`, `post-apply.sh` — these don't produce skill-facing output.
- The post-apply write-target fix — already shipped in PR #4.

---

## Verification

- All existing local suites still pass (build, post-apply, terraform-plan).
- New test-preflight.sh scenarios pass. Target: ~30+ assertions.
- Credential safety: `MOCK_TOKEN` not found in stdout, stderr, or `bash -x` xtrace for any scenario.
- Agnosticism grep still returns zero across the declared scope.
- `shellcheck scripts/preflight.sh tests/test-preflight.sh` clean.
