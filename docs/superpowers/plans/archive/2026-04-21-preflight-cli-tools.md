# Plan: Extend preflight.sh with CLI Tool Checks

**Date:** 2026-04-21
**Status:** Implemented
**Scope:** Extension to existing `scripts/preflight.sh`. Small, focused change.
**Context:** `preflight.sh` currently validates config, credentials, HubSpot API access, and DNS. It doesn't check that the CLI tools the framework depends on (`terraform`, `npm`, `jq`, `curl`) are installed. When a tool is missing, the user hits an opaque failure later in the workflow (e.g. "command not found: terraform" from `tf.sh`). This change surfaces tool availability up front as structured preflight output.

## Goal

Add two new preflight checks that report on CLI tool availability:

- `PREFLIGHT_TOOLS_REQUIRED` — blocks the workflow if missing
- `PREFLIGHT_TOOLS_OPTIONAL` — warns but doesn't block (affects ingest only)

Integrate into the existing `PREFLIGHT_*` output format so the skill parses them alongside other checks.

## Changes to `scripts/preflight.sh`

### 1. Add a new section at the top of the script

Insert the check block immediately after `set -euo pipefail` and before the `# --- Config discovery ---` section. This placement ensures tool availability is reported even if downstream config checks fail.

### 2. Required tools check

Tools the framework cannot function without:

| Tool | Used by |
|---|---|
| `curl` | `preflight.sh`, `upload.sh`, `hs-curl.sh` |
| `jq` | `post-apply.sh` (parse terraform outputs), scripts that read HubSpot JSON |
| `terraform` | `tf.sh`, all Terraform-driven resource creation |
| `npm` | Invokes `package.json` scripts — without it, the whole `npm run *` workflow fails |

Implementation:

```bash
required_tools=(curl jq terraform npm)
tools_missing=()
for t in "${required_tools[@]}"; do
  command -v "$t" >/dev/null 2>&1 || tools_missing+=("$t")
done
if [[ ${#tools_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_TOOLS_REQUIRED=ok"
else
  missing_csv=$(IFS=,; echo "${tools_missing[*]}")
  echo "PREFLIGHT_TOOLS_REQUIRED=missing $missing_csv"
  # Early exit — without these tools, downstream checks can't run meaningfully.
  # Emit skipped lines for all downstream checks to maintain the 10-line contract.
  for check in PROJECT_POINTER ACCOUNT_PROFILE PROJECT_PROFILE CREDENTIAL \
               API_ACCESS SCOPES PROJECT_SOURCE DNS GA4 FORM_IDS TOOLS_OPTIONAL; do
    echo "PREFLIGHT_${check}=skipped (required tools missing)"
  done
  exit 1
fi
```

**Note:** The required-tools early exit skips all downstream checks. This means the output contract grows from 10 lines to 12 lines total (with `TOOLS_REQUIRED` and `TOOLS_OPTIONAL` added). Update the skill's handling documentation accordingly (see Skill plan).

### 3. Optional tools check

Tools used only by specific workflows; missing them degrades functionality but doesn't block:

| Tool | Used for |
|---|---|
| `pandoc` | Convert `.docx` to text when ingesting `resources/` or `directory:<path>` sources (skill) |
| `pdftotext` | Convert `.pdf` to text in the same ingest paths (skill) |
| `git` | Version control operations (may be used by the skill for repo setup, not by framework scripts) |
| `dig` / `host` / `getent` | DNS check — already handled by DNS block, keep that graceful fallback |

Implementation:

```bash
optional_tools=(pandoc pdftotext git)
optional_missing=()
for t in "${optional_tools[@]}"; do
  command -v "$t" >/dev/null 2>&1 || optional_missing+=("$t")
done
if [[ ${#optional_missing[@]} -eq 0 ]]; then
  echo "PREFLIGHT_TOOLS_OPTIONAL=ok"
else
  missing_csv=$(IFS=,; echo "${optional_missing[*]}")
  echo "PREFLIGHT_TOOLS_OPTIONAL=warn $missing_csv"
fi
```

Optional-tool absence produces `warn`, not `missing`, and does NOT set `required_failed=1`. The skill decides how to handle it (e.g. if ingesting a directory with PDFs and `pdftotext` is missing, surface the specific guidance).

### 4. Update the credential-safety comment

The comment block at the top of `preflight.sh` notes that xtrace is suppressed around curl calls. The new tool-check section uses only `command -v`, which is safe for xtrace — no change needed. Add a brief note explaining why the tool check runs first.

### 5. Update the header comment listing checks

The current comment section lists the check names. Add `TOOLS_REQUIRED` and `TOOLS_OPTIONAL` to the list, positioned first.

## Changes to `tests/test-preflight.sh`

Add assertions for the new checks:

### Required tools
- With all required tools present: `PREFLIGHT_TOOLS_REQUIRED=ok`
- With a required tool missing (simulate by prepending a PATH that lacks it): `PREFLIGHT_TOOLS_REQUIRED=missing <tool>` and exit code 1
- When `TOOLS_REQUIRED=missing`, all downstream checks emit `=skipped (required tools missing)`
- The output contract has exactly 12 `PREFLIGHT_*` lines in this scenario

### Optional tools
- With all optional tools present: `PREFLIGHT_TOOLS_OPTIONAL=ok`
- With `pandoc` missing: `PREFLIGHT_TOOLS_OPTIONAL=warn pandoc` and exit code 0 (not blocking)
- With all optional tools missing: `PREFLIGHT_TOOLS_OPTIONAL=warn pandoc,pdftotext,git`

### Ordering
- Output lines are in a stable order: `TOOLS_REQUIRED`, `PROJECT_POINTER`, `ACCOUNT_PROFILE`, `PROJECT_PROFILE`, `CREDENTIAL`, `API_ACCESS`, `SCOPES`, `PROJECT_SOURCE`, `DNS`, `GA4`, `FORM_IDS`, `TOOLS_OPTIONAL`

**Note on ordering choice:** `TOOLS_REQUIRED` first (fail fast if missing), `TOOLS_OPTIONAL` last (non-blocking, informational). The skill can parse in order or by name — the 12-line contract remains intact.

## Changes to `docs/framework.md`

Update the Prerequisites section to mention that `preflight.sh` validates CLI tool availability. Add a paragraph:

> The framework requires `curl`, `jq`, `terraform`, and `npm` at runtime. Optional tools `pandoc`, `pdftotext`, and `git` extend specific features (source ingest, version control). Run `bash scripts/preflight.sh` to verify — it reports missing tools via `PREFLIGHT_TOOLS_REQUIRED` and `PREFLIGHT_TOOLS_OPTIONAL` lines.

Install commands reference `brew install ...` for macOS users, matching the style in `skills/hs-lander/references/prerequisites.md`.

## Verification

After implementation:

1. `bash scripts/preflight.sh` on a machine with all tools: emits `PREFLIGHT_TOOLS_REQUIRED=ok` and `PREFLIGHT_TOOLS_OPTIONAL=ok`, exit 0
2. Simulated missing `terraform` (empty PATH): emits `PREFLIGHT_TOOLS_REQUIRED=missing terraform`, all downstream lines `=skipped (required tools missing)`, exit 1
3. Simulated missing `pandoc`: emits `PREFLIGHT_TOOLS_OPTIONAL=warn pandoc`, no effect on exit code or downstream checks
4. `tests/test-preflight.sh` passes with new assertions
5. `grep -c '^PREFLIGHT_' <output>` returns 12 in both the all-ok and tools-required-missing scenarios

## Out of scope

- Version checks (e.g. "terraform >= 1.5") — tool presence is enough for v1
- Auto-install of missing tools — the skill's coaching handles this, not the framework
- Framework self-installation — that's the skill's bootstrap concern
