# preflight.d/

Decomposed preflight checks. The runner (`scripts/preflight.sh`) sources every
`*.sh` in this directory in numeric-prefix order and emits the assembled
`PREFLIGHT_*` contract.

## Why the directory exists

Pre-v1.9.0 `scripts/preflight.sh` had grown to 720+ lines with each release
adding 50–80 lines for a new check plus its skip cascade. v1.9.0 Component 3
splits each check into its own file so adding/removing a check is a
single-file change and the maintainer-facing surface ("where do I edit?")
collapses from "scroll through 720 lines" to "create a new file under
`preflight.d/`, copy the template".

Output contract preserved verbatim — `tests/test-preflight.sh` runs unchanged
as the regression canary.

## File ordering

Files are sourced in `LC_ALL=C sort` order so the numeric prefix drives
ordering deterministically across Darwin and Linux runners. Reserve numeric
prefix slots in increments of 5 to leave room for future inserts.

| File                     | Owns line                       |
| ------------------------ | ------------------------------- |
| 00-tools-required.sh     | `PREFLIGHT_TOOLS_REQUIRED`      |
| 10-project-pointer.sh    | `PREFLIGHT_PROJECT_POINTER`     |
| 20-account-profile.sh    | `PREFLIGHT_ACCOUNT_PROFILE`     |
| 30-project-profile.sh    | `PREFLIGHT_PROJECT_PROFILE`     |
| 40-credential.sh         | `PREFLIGHT_CREDENTIAL`          |
| 50-api-access.sh         | `PREFLIGHT_API_ACCESS`          |
| 55-tier.sh               | `PREFLIGHT_TIER`                |
| 60-scopes.sh             | `PREFLIGHT_SCOPES`              |
| 65-project-source.sh     | `PREFLIGHT_PROJECT_SOURCE`      |
| 70-dns.sh                | `PREFLIGHT_DNS`                 |
| 75-domain-connected.sh   | `PREFLIGHT_DOMAIN_CONNECTED`    |
| 80-email-dns.sh          | `PREFLIGHT_EMAIL_DNS`           |
| 90-ga4.sh                | `PREFLIGHT_GA4`                 |
| 95-form-ids.sh           | `PREFLIGHT_FORM_IDS`            |
| 99-tools-optional.sh     | `PREFLIGHT_TOOLS_OPTIONAL`      |

`PREFLIGHT_FRAMEWORK_VERSION` is emitted by the runner directly (always the
first line, before any check files run, so the skill can read the framework
version even if a check file aborts).

The 85- slot is reserved for `85-email-reply-to.sh` (`PREFLIGHT_EMAIL_REPLY_TO`)
landing in v1.9.0 Component 5.

## Shared variables (the interface between check files)

The runner declares these at module scope before sourcing any check file.
Each check file reads the ones it depends on and writes the one(s) it owns.

### Gate flags

| Variable               | Owner check               | Read by                                                                          |
| ---------------------- | ------------------------- | -------------------------------------------------------------------------------- |
| `tools_required_ok`    | 00-tools-required.sh      | every other check                                                                |
| `project_pointer_ok`   | 10-project-pointer.sh     | 20, 30, 40, 70, 75, 80, 90, 95                                                   |
| `account_profile_ok`   | 20-account-profile.sh     | 40                                                                               |
| `project_profile_ok`   | 30-project-profile.sh     | (reserved — currently no consumer; declared for future skip-cascade refinements) |
| `credential_ok`        | 40-credential.sh          | 50, 55, 60, 65                                                                   |
| `api_access_ok`        | 50-api-access.sh          | (reserved — 55/60/65 inspect raw probe results, not this flag)                   |
| `tier`                 | 55-tier.sh                | 60-scopes.sh                                                                     |

### Skip-reason markers

When a gate-check fails it sets a reason marker so downstream files can emit
a precise `=skipped (<reason>)` line that points the skill at the upstream
root cause.

| Variable                | Owner check               | Read by              |
| ----------------------- | ------------------------- | -------------------- |
| `pointer_skip_reason`   | 10-project-pointer.sh     | 20, 30, 40, 70+      |
| `credential_skip_reason`| 40-credential.sh          | 50, 55, 60, 65       |
| `api_skip_reason`       | 50-api-access.sh          | (reserved)           |

### Config-derived values

Loaded from the project pointer / account profile / project profile by the
gate checks, then read by downstream files:

- 10-project-pointer.sh writes `HS_LANDER_ACCOUNT`, `HS_LANDER_PROJECT`.
- 20-account-profile.sh writes `HUBSPOT_PORTAL_ID`, `HUBSPOT_REGION`,
  `HUBSPOT_TOKEN_KEYCHAIN_SERVICE`.
- 30-project-profile.sh writes `PROJECT_SLUG`, `DOMAIN`, `DM_UPLOAD_PATH`,
  `GA4_MEASUREMENT_ID`, `CAPTURE_FORM_ID`, `EMAIL_REPLY_TO`.

### API probe results

40-credential.sh runs four curl probes inside a single xtrace-suppressed
window (so the bearer token doesn't leak under `bash -x`) and exposes the
results to downstream files via these variables:

- `api_status`, `api_curl_exit`, `account_info_body_file`
- `ps_status`, `ps_curl_exit`
- `scopes_status`, `scopes_curl_exit`, `scopes_body_file`
- `domains_status`, `domains_curl_exit`, `domains_body_file`

Why batched: each probe needs the bearer token, which only exists inside the
xtrace-suppressed window in 40-credential.sh. Splitting the curls into
separate files would require either holding the token open across files
(defeating the xtrace guard) or reading from Keychain four times. Keeping
the four probes together preserves the v1.8.0 single-token-window design.
The downstream files (50, 55, 60, 65, 75) only inspect the captured probe
results — they never see the token.

## Required-failure flag

`required_failed` (declared by the runner, mutated by check files) is the
single signal the runner reads to decide its exit code:

- `required_failed=0` at end → `exit 0`
- `required_failed=1` at end → `exit 1`

Any check that detects a blocking failure sets `required_failed=1`.
Warnings and recoverable states (e.g. `PROJECT_SOURCE=missing` for a
first-project-on-account) deliberately do NOT set the flag.

## Sourced lib helpers

The runner sources these once before any check file:

- `scripts/lib/tier-classify.sh` — `classify_tier_from_account_details`,
  `required_scopes_for_tier`. Used by 55, 60.
- `scripts/lib/keychain.sh` — `keychain_read`. Used by 40.
- `scripts/lib/source-vars.sh` — `source_vars`,
  `extract_var_via_parse`. Used by 10, 20, 30.

A check file MAY source additional helpers it owns; the three above are the
common subset shared across multiple files.

## Adding a new check

1. Pick a numeric prefix that places the new file at the right point in the
   ordering. If it gates other checks, choose a low prefix; if it observes
   results from upstream gates, choose one above them.
2. Document the file's reads/writes at the top, following the template in
   the existing files.
3. If your check is gated on an upstream flag, emit `=skipped (<reason>)`
   when the flag is unset, then `return 0` (the runner sources via `source`
   so `return` exits just the check file, not the runner).
4. Add line-presence assertions for the new key to `tests/test-preflight.sh`
   (`PREFLIGHT_CONTRACT_KEYS`) and update the line-count assertions if the
   contract length changes.
