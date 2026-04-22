# Plan: Backup Terraform State and Project Profiles Before Apply

**Date:** 2026-04-22
**Status:** Pending
**Scope:** Framework. Adds timestamped backups of both Terraform state and the project profile before every apply path, giving a short-term rollback window after any unwanted change.
**Companion plan:** `2026-04-22-plan-review-gate.md` — pre-apply review. These two plans together close the "skill loop could destroy/duplicate resources" exposure. Independent; can land in either order.

## Problem

Two operational files carry deploy-critical state and neither has reliable history:

1. **`terraform/terraform.tfstate`** — records HubSpot resource IDs and module state. Terraform writes `terraform.tfstate.backup` on each apply, but that's only the *immediately-previous* state. Disk failure, accidental delete, or a problematic apply with no prior backup creates orphan resources in HubSpot that Terraform no longer knows about.

2. **`~/.config/hs-lander/<account>/<project>.sh`** — carries form IDs, list ID, and other values written by `post-apply.sh`. Equally critical for project function. If lost or corrupted, the project can't be rebuilt without a fresh deploy that orphans the live resources.

## Goal

- Every Terraform apply path (including escape hatches) creates a timestamped backup of state *before* execution
- Every `post-apply.sh` run creates a timestamped backup of the project profile *before* modification
- N most recent backups retained (default 20); older ones trimmed
- Documented restore procedure for both file types
- Clear note on sync-service exposure for operators who use Time Machine, iCloud, etc.

Backups are local and short-term. The plan explicitly positions this as an **interim** safeguard: remote Terraform backend (S3, HCP Terraform, etc.) is the durable solution and belongs on the roadmap.

## Design

### Unified backup helper

Single script used by both `tf.sh` and `post-apply.sh`:

**New: `scripts/backup-file.sh <source-path> <backup-dir> [--keep N]`**

Behaviour:
1. If `<source-path>` does not exist, exit 0 silently (nothing to back up — first run).
2. Create `<backup-dir>` if missing.
3. Generate timestamp: `date -u +%Y-%m-%dT%H-%M-%SZ.%N` where `%N` is nanoseconds (falls back gracefully on systems without nanosecond support — includes PID as tiebreaker).
4. Copy `<source-path>` to `<backup-dir>/<basename-of-source>.<timestamp>`.
5. Sort existing backups in `<backup-dir>` matching the basename pattern; delete all but the `--keep` most recent (default 20, override with `HS_LANDER_BACKUP_KEEP`).
6. Emit `BACKUP=ok <path>` on success; `BACKUP=error <reason>` and exit 1 on failure.

Output contract:
- `BACKUP=skip <reason>` — source didn't exist (expected on first run)
- `BACKUP=ok <backup-path>` — successful backup
- `BACKUP=error <reason>` — failure; *does not* prevent the caller from proceeding (caller decides; usually proceed with a warning, because blocking deploy on a backup failure is its own problem)

### Invocation sites

**Terraform state — inside `tf.sh apply`:**

Before running `terraform apply`:

```
bash "$SCRIPT_DIR/backup-file.sh" "$PROJECT_DIR/terraform/terraform.tfstate" \
  "$PROJECT_DIR/terraform/state-backups"
```

This runs for *every* apply path:
- `npm run apply` via the chained `npm run setup`
- Direct `bash scripts/tf.sh apply`
- Escape-hatch `HS_LANDER_UNSAFE_APPLY=1 bash scripts/tf.sh apply` — backup still runs because it's unconditional inside the `apply` verb

**Project profile — inside `post-apply.sh`:**

Before reading Terraform outputs and calling `set-project-field.sh` (or the current in-place update path if that refactor hasn't landed):

```
profile_path="$HOME/.config/hs-lander/$HS_LANDER_ACCOUNT/$HS_LANDER_PROJECT.sh"
bash "$SCRIPT_DIR/backup-file.sh" "$profile_path" \
  "$HOME/.config/hs-lander/$HS_LANDER_ACCOUNT/.profile-backups"
```

Backups live inside the account config directory (per-account backup bucket). Filename pattern: `<project>.sh.<timestamp>`.

### Directory layout

```
<project>/
  terraform/
    terraform.tfstate                         # current
    terraform.tfstate.backup                  # Terraform's own
    state-backups/
      terraform.tfstate.2026-04-22T14-30-22Z  # pre-apply (ours)
      terraform.tfstate.2026-04-22T16-10-05Z
      ...

~/.config/hs-lander/<account>/
  config.sh                                   # account profile (not backed up — rarely changes)
  <project>.sh                                # current project profile
  .profile-backups/
    <project>.sh.2026-04-22T14-31-08Z         # pre-post-apply (ours)
    <project>.sh.2026-04-22T16-10-45Z
    ...
```

Dotted directory (`.profile-backups/`) keeps `projects-list.sh` simple — it currently globs `*.sh` and excludes `config.sh`; the dot prefix keeps backup directories out of the results without touching that script.

### Account profile intentionally not backed up

`~/.config/hs-lander/<account>/config.sh` is created once and rarely changes (`accounts-init.sh` refuses overwrite). Backing it up would be noise. If a user needs to roll back an account profile, git-managed personal dotfiles or manual copy is the right tool.

If this proves wrong in practice, adding backup later is a one-line addition to any future `accounts-update.sh`.

### Sync-service exposure note

The `state-backups/` and `.profile-backups/` directories contain derived deployment data (HubSpot resource IDs, form metadata). This data is not directly sensitive — no credentials — but it is deployment-identifying. Users running macOS Time Machine, iCloud Drive, Dropbox, or similar on their home directory or project directory will have backups replicated off-device.

This is documented in `docs/framework.md` as a note, not as a framework concern to solve. Users who need stricter handling should relocate backups via the override env vars (below) to a location excluded from sync.

### Override env vars

For users who want backups elsewhere:

- `HS_LANDER_STATE_BACKUP_DIR` — override for Terraform state backup location (default: `<project>/terraform/state-backups`)
- `HS_LANDER_PROFILE_BACKUP_DIR` — override for project profile backup location (default: `~/.config/hs-lander/<account>/.profile-backups`)
- `HS_LANDER_BACKUP_KEEP` — max backups to retain (default: 20)

`backup-file.sh` respects these.

## Scripts

### New: `scripts/backup-file.sh`

Self-contained helper, ~30 lines of bash. Single responsibility: backup one file with timestamp, trim old backups.

Implementation sketch:

```bash
#!/usr/bin/env bash
# backup-file.sh — timestamped backup of a single file with LRU retention
set -euo pipefail

src="$1"
backup_dir="$2"
keep="${HS_LANDER_BACKUP_KEEP:-20}"

if [[ ! -f "$src" ]]; then
  echo "BACKUP=skip $src does not exist"
  exit 0
fi

mkdir -p "$backup_dir"
# ISO-8601 + nanoseconds (or seconds + PID on systems without %N)
if ts=$(date -u +%Y-%m-%dT%H-%M-%SZ.%N 2>/dev/null); then
  :
else
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ).$$"
fi

dest="$backup_dir/$(basename "$src").$ts"
cp -p "$src" "$dest" || {
  echo "BACKUP=error cp failed: $src -> $dest" >&2
  exit 1
}

# Trim to $keep most recent matching backups
pattern="$(basename "$src")."
# shellcheck disable=SC2012
ls -1t "$backup_dir" 2>/dev/null \
  | grep -F "$pattern" \
  | tail -n +$((keep + 1)) \
  | while read -r old; do
      rm -f "$backup_dir/$old"
    done

echo "BACKUP=ok $dest"
```

The `ls -1t | tail` trim is safe here because filenames are controlled (timestamp-based, no special characters). Note the `cp -p` preserves mtime so `ls -t` ordering is consistent with when the backup was made.

### Modified: `scripts/tf.sh`

Add the backup call at the top of the `apply` verb, unconditional:

```bash
apply)
  bash "$SCRIPT_DIR/backup-file.sh" \
    "${HS_LANDER_STATE_FILE:-$PROJECT_DIR/terraform/terraform.tfstate}" \
    "${HS_LANDER_STATE_BACKUP_DIR:-$PROJECT_DIR/terraform/state-backups}"
  # ... existing apply logic ...
  ;;
```

Runs before the plan-file check so backup happens even if the apply is about to fail — useful if apply fails partway through.

### Modified: `scripts/post-apply.sh`

Add the backup call at the top, before any reads or modifications:

```bash
profile="${HS_LANDER_PROFILE_FILE:-$HOME/.config/hs-lander/$HS_LANDER_ACCOUNT/$HS_LANDER_PROJECT.sh}"
bash "$SCRIPT_DIR/backup-file.sh" "$profile" \
  "${HS_LANDER_PROFILE_BACKUP_DIR:-$HOME/.config/hs-lander/$HS_LANDER_ACCOUNT/.profile-backups}"
```

### Restore procedure (documented, not scripted)

In `docs/framework.md`:

**Restore Terraform state:**

```
ls <project>/terraform/state-backups/
cp <project>/terraform/state-backups/terraform.tfstate.<timestamp> \
   <project>/terraform/terraform.tfstate
bash scripts/plan-review.sh    # verify the rollback makes sense
```

**Restore project profile:**

```
ls ~/.config/hs-lander/<account>/.profile-backups/
cp ~/.config/hs-lander/<account>/.profile-backups/<project>.sh.<timestamp> \
   ~/.config/hs-lander/<account>/<project>.sh
```

Not scripted on purpose — recovery is a considered action that should involve human judgement about which timestamp to restore. A script would invite accidental rollbacks during normal operation.

## Tests

### New: `tests/test-backup-file.sh`

- Source does not exist: exit 0 with `BACKUP=skip`; no directory created
- Fresh backup: source exists, backup dir empty; creates file with correct name pattern and content
- Second backup in same wall-clock second: distinct filenames (nanosecond or PID disambiguation)
- Backup exceeds `keep` limit: oldest backup removed, `keep` most recent retained
- Trim handles file names with dots correctly (timestamp format contains dots)
- `HS_LANDER_BACKUP_KEEP` override respected
- File permissions preserved (mtime preserved for `ls -t`)

### Modified: `tests/test-tf.sh`

- `apply` creates a state backup before running (use a fixture state file, assert backup path exists afterward)
- `apply` under `HS_LANDER_UNSAFE_APPLY=1` still creates the backup

### Modified: `tests/test-post-apply.sh`

- Running post-apply creates a profile backup before modifying the profile
- After 20+ runs, only 20 backups retained in `.profile-backups/`
- Backup directory starts with a dot (not picked up by `projects-list.sh`)

### Regression: `tests/test-projects-list.sh`

Confirm that `projects-list.sh` ignores `.profile-backups/` — the directory should not appear in `PROJECTS` output.

## Documentation

### `docs/framework.md`

New "Backups and recovery" section covering:

- What's backed up (state, profile) and what isn't (account config)
- Directory layout
- Restore procedure for each file type
- Sync-service exposure warning
- Override env vars
- Explicit note that remote Terraform backend is the proper long-term solution — this plan is interim for local-only workflows

### `CLAUDE.md`

One-line mention in the architecture section pointing to `docs/framework.md` for detail.

### `scaffold/.gitignore`

Add:

```
terraform/state-backups/
.hs-lander-plan.bin
```

(The plan file entry is from the plan-review companion plan. Including here because `.gitignore` edits are one-shot — both plans touch the same file.)

### No skill-side specification

This plan defines only the framework's backup behaviour. The skill already benefits automatically — backups happen inside `tf.sh apply` and `post-apply.sh`, which the skill calls unchanged. No skill plan required.

## Verification

1. `backup-file.sh` with non-existent source: emits `BACKUP=skip`, exits 0, creates no directories
2. First `npm run apply`: no state backup (state didn't exist yet), no error
3. Second `npm run apply`: `terraform/state-backups/terraform.tfstate.<timestamp>` exists with pre-apply content
4. `post-apply.sh` after a deploy: `~/.config/hs-lander/<account>/.profile-backups/<project>.sh.<timestamp>` exists with pre-change content
5. After 25 apply runs: exactly 20 state backups retained
6. `HS_LANDER_UNSAFE_APPLY=1 bash scripts/tf.sh apply` still creates the state backup
7. `projects-list.sh <account>` does not include `.profile-backups` in its output
8. `HS_LANDER_BACKUP_KEEP=3` retains only 3 backups
9. Scaffolded projects include `state-backups/` in `.gitignore`
10. All new and modified tests pass in CI

## Out of scope

- Remote Terraform backend (S3, HCP Terraform) — roadmap item, the durable solution
- Account config backup — documented reasoning above
- Offsite sync or cloud backup — users who want this use their own mechanisms (rsync, restic, Backblaze etc.) on the backup directories
- Backup encryption at rest — deployment IDs are not credentials; no encryption requirement
- Restore automation — deliberate
- Skill-side behaviour — none needed

## Decision notes (2026-04-22)

Gaps noted during plan review. Captured here so we don't re-think them next time.

- **Nanosecond + PID timestamp disambiguation is over-engineered for realistic usage.** One apply per minute at most; collision risk is negligible. Considered simplifying to plain ISO-8601 seconds. Decided to keep the nanosecond/PID for robustness because the cost is trivial (one `date` flag + one `$$` fallback) and the edge case — two rapid applies during CI or a scripted rerun — isn't zero. If the implementation turns ugly, fall back to seconds-only; the plan isn't hostile to that simplification.

- **Account config exclusion may age poorly.** Currently the reasoning is "account config rarely changes." That holds while account config is user-curated. It will be invalidated when R5 (subscription check + ID auto-discovery) lands, because R5 will have the framework *mutating* account config via API-discovered values. At that point, account-config backup becomes as valuable as project-profile backup. **Coordination hook:** when implementing R5, revisit this plan and add account-config backup to the `post-apply.sh` / `accounts-init.sh` wrappers. The effort is small once `backup-file.sh` exists.
