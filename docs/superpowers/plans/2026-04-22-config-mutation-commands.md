# Plan: Config Mutation Commands (`accounts-init.sh` + `set-project-field.sh`)

**Date:** 2026-04-22
**Status:** Implemented
**Scope:** Framework. Two small new scripts that close the remaining "skill writes operational files directly" gaps.
**Context:** The skill currently has two documented exceptions to its no-shell-improvisation rule:
1. Account profile creation (`~/.config/hs-lander/<account>/config.sh` for a new account) — written by `Write` because there's no framework command.
2. Project profile field population after scaffold (`~/.config/hs-lander/<account>/<project>.sh` — setting `DOMAIN`, `DM_UPLOAD_PATH`, `GA4_MEASUREMENT_ID`) — edited by `Edit` because there's no framework command.

This plan adds the two missing commands so the skill can drop both exceptions and own zero operational-file writes.

## Goal

After this plan lands:

- `accounts-init.sh` creates a new account profile from explicit field arguments
- `set-project-field.sh` updates one or more fields in an existing project profile
- The skill calls these via `Bash` with structured output, matching the convention of the other pre-scaffold commands
- Rule 4 ("Don't hand-write operational files") can apply without exception

---

## Script A: `scripts/accounts-init.sh`

**Purpose:** Create a new account profile at `~/.config/hs-lander/<account>/config.sh` from provided field values.

**Invocation:**

```bash
bash $FRAMEWORK_HOME/scripts/accounts-init.sh \
  <account-name> \
  <portal-id> \
  <region> \
  <domain-pattern> \
  <token-keychain-service>
```

- `<account-name>` — directory name (short, lowercase, matches the `~/.config/hs-lander/<account>/` convention)
- `<domain-pattern>` — may be an empty string if the user has no wildcard pattern (e.g. `""`)

**Behaviour:**

1. Validate account name (lowercase letters, digits, hyphens — no spaces, no `/`)
2. Validate region is `eu1` or `na1`
3. Refuse to overwrite an existing profile — exit with `ACCOUNTS_INIT=conflict <path>` if already present
4. Create `~/.config/hs-lander/<account>/` directory if needed
5. Write `config.sh` with the four fields in the documented order:

   ```
   HUBSPOT_PORTAL_ID="<value>"
   HUBSPOT_REGION="<value>"
   DOMAIN_PATTERN="<value>"
   HUBSPOT_TOKEN_KEYCHAIN_SERVICE="<value>"
   ```

6. Emit `ACCOUNTS_INIT=created <path>` and exit 0

**Output contract:**

- `ACCOUNTS_INIT=created <path>` — profile written successfully (exit 0)
- `ACCOUNTS_INIT=conflict <path>` — profile already exists; refuse to overwrite (exit 1)
- `ACCOUNTS_INIT=error <reason>` — invalid input or filesystem error (exit 1)

**Credential safety:** the `<token-keychain-service>` argument is a *service name*, not a token. The script never touches the Keychain itself — that remains the user's responsibility (via Keychain Access or `security add-generic-password`). The script only writes the service name reference into the config file.

**Test additions** (`tests/test-accounts-init.sh`):

- Fresh account: creates the directory and file with correct content and emits `ACCOUNTS_INIT=created <path>`
- Existing account: refuses with `ACCOUNTS_INIT=conflict <path>` and exit 1
- Invalid name (contains `/` or spaces): rejects with `ACCOUNTS_INIT=error <reason>`
- Invalid region: rejects with `ACCOUNTS_INIT=error <reason>`
- Empty `DOMAIN_PATTERN` is accepted (optional field)
- Quoting is correct: special characters in `DOMAIN_PATTERN` (e.g. `*.example.com`) round-trip through `source` without shell expansion

Use a temp `HS_LANDER_CONFIG_DIR` override in the test harness to avoid polluting the real `~/.config/hs-lander/`.

---

## Script B: `scripts/set-project-field.sh`

**Purpose:** Update one or more fields in an existing project profile at `~/.config/hs-lander/<account>/<project>.sh`.

**Invocation:**

```bash
bash $FRAMEWORK_HOME/scripts/set-project-field.sh \
  <account> <project> \
  KEY=VALUE [KEY=VALUE ...]
```

Multiple `KEY=VALUE` pairs can be passed in one invocation.

**Allowed keys (validated against the project profile schema):**

- `PROJECT_SLUG`
- `DOMAIN`
- `DM_UPLOAD_PATH`
- `GA4_MEASUREMENT_ID`
- `CAPTURE_FORM_ID`
- `SURVEY_FORM_ID`
- `LIST_ID`

Unknown keys are rejected with an error rather than silently written — prevents typos creating zombie variables.

**Behaviour:**

1. Validate account and project profiles exist; if not, exit with `SET_FIELD=error profile-missing <path>`
2. Validate every `KEY=VALUE` pair has a recognised key and syntactically valid value
3. For each pair:
   - If the key already exists in the file, update its value in place (preserve quoting style)
   - If the key is absent, append a new line with the standard format
4. Write the updated file atomically (write to temp, then `mv`)
5. Emit one `SET_FIELD_UPDATED=<key>` or `SET_FIELD_APPENDED=<key>` line per pair, then `SET_FIELD=ok` on success

**Output contract:**

- `SET_FIELD_UPDATED=<key>` — existing line modified
- `SET_FIELD_APPENDED=<key>` — new line added
- `SET_FIELD=ok` — all updates applied; exit 0
- `SET_FIELD=error <reason>` — exit 1. Reasons include: `profile-missing <path>`, `unknown-key <key>`, `invalid-value <key>`, `no-pairs-given`

**Example invocation from the skill (Step 6 post-scaffold):**

```bash
bash $FRAMEWORK_HOME/scripts/set-project-field.sh dml heard \
  DOMAIN="heard.digitalmercenaries.ai" \
  DM_UPLOAD_PATH="/heard" \
  GA4_MEASUREMENT_ID="G-XXXXXXXXXX"
```

Emits:

```
SET_FIELD_UPDATED=DOMAIN
SET_FIELD_UPDATED=DM_UPLOAD_PATH
SET_FIELD_UPDATED=GA4_MEASUREMENT_ID
SET_FIELD=ok
```

**Credential safety:** the script never touches the Keychain. `HUBSPOT_TOKEN_KEYCHAIN_SERVICE` is an account-level field, not a project-level field — this script rejects it if passed, with `SET_FIELD=error unknown-key HUBSPOT_TOKEN_KEYCHAIN_SERVICE`.

**Test additions** (`tests/test-set-project-field.sh`):

- Update an existing key: field is rewritten, no duplicate line, other fields untouched
- Append a new key (not previously in file): new line added in canonical format
- Multiple pairs in one invocation: all applied, output has one line per key
- Unknown key: rejected with `SET_FIELD=error unknown-key <key>`, no file write
- Non-existent profile: rejected with `SET_FIELD=error profile-missing <path>`
- Invalid value (e.g. `KEY=` with trailing garbage): rejected cleanly
- Idempotent: setting a key to the value it already has is a no-op emitting `SET_FIELD_UPDATED=<key>` and `SET_FIELD=ok`, file unchanged on disk (compare hashes)
- Quoting: values containing spaces, quotes, or shell metacharacters round-trip through `source` without breaking
- Atomic write: interrupt mid-write doesn't leave a corrupt file (test via signal injection if feasible; otherwise document the `mv` pattern)

---

## Documentation updates

### `CLAUDE.md`

Add both scripts to the commands listing. Group with other config-mutation commands (`init-project-pointer.sh` is the existing peer).

### `docs/framework.md`

Add a short "Config mutation" section describing when to use each:

- `accounts-init.sh` — first-time creation of an account profile
- `set-project-field.sh` — updating fields in an existing project profile (e.g. after post-apply writes form IDs, or when the user supplies a GA4 ID)
- `init-project-pointer.sh` — creating the `project.config.sh` sourcing chain in a project directory

Note that `post-apply.sh` already writes form IDs via its own logic; `set-project-field.sh` is for skill-driven updates of other fields (`DOMAIN`, `DM_UPLOAD_PATH`, `GA4_MEASUREMENT_ID`). Consider whether `post-apply.sh` should be refactored to use `set-project-field.sh` internally for consistency — not required, but a cleaner composition.

---

## Verification

After implementation:

1. `bash scripts/accounts-init.sh testacct 12345678 eu1 "*.example.com" testacct-hubspot-access-token` in a fresh environment (with `HS_LANDER_CONFIG_DIR` override) creates the expected file and emits the correct line
2. Running it again emits `ACCOUNTS_INIT=conflict` and exits 1 without modifying the existing file
3. `bash scripts/set-project-field.sh testacct testproj GA4_MEASUREMENT_ID=G-ABC123` updates the profile and emits `SET_FIELD_UPDATED=GA4_MEASUREMENT_ID`, `SET_FIELD=ok`
4. Unknown-key rejection works as specified
5. All new tests pass in CI
6. `docs/framework.md` and `CLAUDE.md` list both scripts

## Out of scope

- Replacing the `Write`/`Edit` calls in the skill — that's the companion skill plan
- Refactoring `post-apply.sh` to use `set-project-field.sh` internally — possible follow-up, not required for v1
- Deleting account profiles or removing project-profile fields — out of scope (the skill never deletes operational config)
- Bulk/batch account creation from a manifest — out of scope
