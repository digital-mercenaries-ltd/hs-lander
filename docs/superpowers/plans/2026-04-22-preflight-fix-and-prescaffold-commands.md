# Plan: Fix preflight PROJECT_DIR + Add Pre-Scaffold Command Set

**Date:** 2026-04-22
**Status:** Pending
**Scope:** Framework. Two related changes that together make the framework consumable by the skill without shell improvisation.

## Context

Live testing (Heard project, 2026-04-22) revealed two framework gaps:

1. **`preflight.sh` resolves `PROJECT_DIR` from its own script location**, so when invoked via the absolute path `bash $FRAMEWORK_HOME/scripts/preflight.sh` from a project directory, it looks for `project.config.sh` inside the framework install (`/Users/rob_dev/.local/share/hs-lander/`) instead of the caller's project. This breaks the Step 1 Preflight flow because Step 1 runs *before* scaffold — the project has no local `scripts/` yet.

2. **The framework has no pre-scaffold command set.** All existing scripts (`build`, `deploy`, `tf`, `post-apply`, `upload`, `watch`, `hs-curl`, `hs`, `preflight`) assume a scaffolded project. Operations the skill currently improvises with `ls`, `pwd`, `cp`, `Write` — discovering accounts, detecting existing project profiles, initialising the project pointer, scaffolding scripts into the project — have no structured-output framework entry points. The skill therefore ad-libs shell, which is fragile, noisy, and collides with the user's hook policies.

This plan fixes both in one pass so the skill's next plan (separate document in the skill repo) can rely on a clean command surface.

## Goal

After this plan lands:

- `preflight.sh` respects `$PWD` (or an explicit project-dir override) as the project location
- The framework exposes a small, consistent pre-scaffold command surface with structured output
- The skill's workflow becomes "call named framework command, parse output, coach user" — no shell improvisation

Both changes preserve the existing `PREFLIGHT_*` / `BOOTSTRAP=*` output contract conventions: single-line structured output, stable key names, exit codes that reflect success/failure.

---

## Part A: Fix `scripts/preflight.sh` project directory resolution

### Current behaviour

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
```

When invoked via `bash /framework/scripts/preflight.sh`, `PROJECT_DIR` resolves to `/framework/`. The subsequent `[[ ! -f "$PROJECT_DIR/project.config.sh" ]]` check looks in the wrong place.

### Change

Replace the derivation with:

```bash
PROJECT_DIR="${HS_LANDER_PROJECT_DIR:-$PWD}"
```

Rationale for this form over alternatives:

- **Env-var override first** lets the skill or CI pass an explicit path without requiring a `cd`
- **`$PWD` fallback** matches the natural usage pattern — run from the project directory
- Removes `SCRIPT_DIR` derivation from the PROJECT_DIR resolution; `SCRIPT_DIR` is still fine for finding sibling scripts if needed

Keep `SCRIPT_DIR` as a separate concept for locating adjacent framework scripts, if the preflight code elsewhere depends on it. Audit the file — currently `SCRIPT_DIR` is only used to compute `PROJECT_DIR`, so the `SCRIPT_DIR` line can be removed entirely.

### Test additions in `tests/test-preflight.sh`

- Invoking `bash /absolute/path/to/framework/scripts/preflight.sh` from a separate project directory correctly resolves `PROJECT_DIR` to the caller's CWD
- Invoking with `HS_LANDER_PROJECT_DIR=/some/path` overrides `$PWD`
- Existing tests (which invoke from the project dir) continue to pass unchanged

### Header-comment update

The script's header comment should document the resolution rule:

> `PROJECT_DIR` is `$PWD` by default, or `$HS_LANDER_PROJECT_DIR` if set. Invoke from the project directory, or export the env var in automation.

### Downstream scripts

Audit other framework scripts for the same pattern (`tf.sh`, `build.sh`, `deploy.sh`, `post-apply.sh`, `upload.sh`, `watch.sh`). If any derive `PROJECT_DIR` from `SCRIPT_DIR`, apply the same fix. Scripts that only run post-scaffold (from the project's local `scripts/`) don't strictly need the change, but consistency is better than selective fixing.

---

## Part B: Pre-scaffold command set

Five new scripts in `scripts/`. Each has a narrow purpose, structured output, and a test. All respect the `HS_LANDER_PROJECT_DIR`/`$PWD` convention established in Part A.

### B1. `scripts/accounts-list.sh`

**Purpose:** Discover which account profiles exist under `~/.config/hs-lander/`.

**Output:**

- `ACCOUNTS=<comma-list>` — non-empty if one or more account directories exist
- `ACCOUNTS=` — empty if none exist (no accounts directory, or directory exists but empty)

**Exit code:** 0 always — absence of accounts is valid state, not error.

**Implementation sketch:**

```bash
#!/usr/bin/env bash
set -euo pipefail
accounts_dir="${HS_LANDER_CONFIG_DIR:-$HOME/.config/hs-lander}"
accounts=()
if [[ -d "$accounts_dir" ]]; then
  for d in "$accounts_dir"/*/; do
    [[ -d "$d" && -f "$d/config.sh" ]] && accounts+=("$(basename "$d")")
  done
fi
csv=$(IFS=,; echo "${accounts[*]:-}")
echo "ACCOUNTS=$csv"
```

### B2. `scripts/accounts-describe.sh <account>`

**Purpose:** Surface the key fields of an account profile for confirmation prompts ("Using account dml, portal 147959629, region eu1. Correct?").

**Output:**

- `ACCOUNT_PORTAL_ID=<value>`
- `ACCOUNT_REGION=<value>`
- `ACCOUNT_DOMAIN_PATTERN=<value>` (may be empty)
- `ACCOUNT_TOKEN_KEYCHAIN_SERVICE=<value>`

**Exit code:** 0 if profile exists and all fields sourced successfully; 1 if profile missing (prints `ACCOUNT_STATUS=missing`).

**Credential safety:** never reads the Keychain, never prints token values — only the service name.

### B3. `scripts/projects-list.sh <account>`

**Purpose:** Discover which project profiles exist under a given account.

**Output:**

- `PROJECTS=<comma-list>` — e.g. `heard,tsc`
- `PROJECTS=` if none

**Exit code:** 0 if account exists (even with zero projects); 1 if account itself is missing.

Detection: enumerate `~/.config/hs-lander/<account>/*.sh` excluding `config.sh`, strip `.sh` suffix.

### B4. `scripts/init-project-pointer.sh <account> <project>`

**Purpose:** Idempotently create `project.config.sh` in `$PWD` (or `$HS_LANDER_PROJECT_DIR`) as the four-line sourcing chain.

**Content produced:**

```bash
HS_LANDER_ACCOUNT="<account>"
HS_LANDER_PROJECT="<project>"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/config.sh"
source "${HOME}/.config/hs-lander/${HS_LANDER_ACCOUNT}/${HS_LANDER_PROJECT}.sh"
```

**Output:**

- `INIT_POINTER=created <path>` — file was created
- `INIT_POINTER=present <path>` — file already exists with correct values; no change
- `INIT_POINTER=conflict <path>` — file exists but has different `HS_LANDER_ACCOUNT` / `HS_LANDER_PROJECT` values. Exit 1 — refuses to overwrite. The skill should surface the conflict to the user rather than silently proceeding.

**Exit codes:** 0 for `created` or `present`, 1 for `conflict` (or missing args).

### B5. `scripts/scaffold-project.sh <account> <project>`

**Purpose:** Copy the framework's `scaffold/` and `scripts/` into the project directory, then ensure the project profile exists at `~/.config/hs-lander/<account>/<project>.sh` (empty template if new).

**Operations:**

1. Validate account profile exists (fail early with `SCAFFOLD=error account-missing` if not)
2. Copy `$FRAMEWORK_HOME/scaffold/*` into project dir, with `--no-clobber` semantics — refuse to overwrite existing files (error if any collision)
3. Copy `$FRAMEWORK_HOME/scripts/*.sh` into project's `scripts/` — same no-clobber
4. If `~/.config/hs-lander/<account>/<project>.sh` doesn't exist, create a stub with the standard fields (`PROJECT_SLUG`, `DOMAIN`, `DM_UPLOAD_PATH`, `GA4_MEASUREMENT_ID`, form IDs empty)
5. Invoke `init-project-pointer.sh <account> <project>` internally to ensure the pointer exists

**Output (multiple lines, one per operation):**

```
SCAFFOLD_SCRIPTS=copied <dest>
SCAFFOLD_TEMPLATE=copied <dest>
SCAFFOLD_PROJECT_PROFILE=created|present <path>
SCAFFOLD_POINTER=created|present <path>
SCAFFOLD=ok
```

On any failure: `SCAFFOLD=error <reason>` and exit 1. Partial success states (e.g. scripts copied but template collision) should surface both lines so the skill can diagnose.

**What scaffold-project.sh does NOT do:** generate content (HTML/CSS/SVGs/brief.md). That remains the skill's responsibility — it's brand-specific content, not framework boilerplate.

### New tests

Add `tests/test-accounts-list.sh`, `tests/test-accounts-describe.sh`, `tests/test-projects-list.sh`, `tests/test-init-project-pointer.sh`, `tests/test-scaffold-project.sh`. Each test should:

- Set up a fixture `~/.config/hs-lander/` structure (use a temp `HS_LANDER_CONFIG_DIR` override)
- Invoke the script
- Assert structured output lines verbatim
- Assert exit code
- Clean up

Add them to CI (`ci.yml`).

---

## Documentation updates

### `CLAUDE.md`

Add a "Pre-scaffold commands" section alongside the existing scripts section, summarising the command surface.

### `docs/framework.md`

Update the "Commands" listing to include the five new scripts with one-line descriptions and output contracts.

---

## Verification

After implementation:

**Part A:**
1. `cd /some/project && bash /path/to/framework/scripts/preflight.sh` correctly resolves to `/some/project` and finds the local `project.config.sh`
2. `HS_LANDER_PROJECT_DIR=/explicit/path bash /path/to/framework/scripts/preflight.sh` overrides `$PWD`
3. All existing preflight tests still pass
4. New test for absolute-path invocation passes

**Part B:**
5. `bash $FRAMEWORK_HOME/scripts/accounts-list.sh` on a fresh machine returns `ACCOUNTS=` (empty, exit 0)
6. After creating `~/.config/hs-lander/dml/config.sh`, returns `ACCOUNTS=dml`
7. `accounts-describe.sh dml` returns the four `ACCOUNT_*` lines
8. `projects-list.sh dml` returns `PROJECTS=heard` given a `heard.sh` under dml
9. `init-project-pointer.sh dml heard` in an empty directory creates `project.config.sh` with the correct sourcing chain; re-running reports `INIT_POINTER=present`
10. `scaffold-project.sh dml heard` populates scripts + scaffold in the project, leaves a project profile stub in the account hierarchy, and reports `SCAFFOLD=ok`
11. Running `scaffold-project.sh` twice reports appropriate `present` states without clobbering
12. All new tests pass in CI

## Out of scope

- Reshaping the skill to use these commands — that's the companion skill plan
- Content generation helpers (HTML, CSS, SVG) — the skill owns content
- Account profile creation (`accounts-init.sh` or similar) — currently handled by the skill's interactive setup. If that moves to the framework, it's a later plan
- Update/upgrade commands for existing projects or accounts — out of scope for v1
