# Plan: Pre-Apply Plan Review Gate

**Date:** 2026-04-22
**Status:** Pending
**Scope:** Framework. Inserts a mandatory plan-review step between `terraform plan` and `terraform apply`, with structured output that lets the skill (or a human) surface the change set before any apply executes.
**Companion plan:** `2026-04-22-backup-state-and-profiles.md` — backup before apply. These two plans together close the "skill loop could destroy/duplicate resources" exposure. They're independent and can land in either order.

## Problem

`npm run setup` currently runs `terraform apply -auto-approve` with no pre-apply inspection. Known issues this creates:

- Mastercard/restapi + Forms API v3 sometimes shows destroy+recreate on drift. Auto-approve silently destroys forms (losing submission history) and recreates them.
- A skill loop interpreting a failure as transient could retry setup, potentially creating duplicate resources if state has diverged.
- No user visibility into what apply is about to do.

## Goal

Insert a review gate between plan and apply. No apply path — including the escape hatch — proceeds without either (a) a safe plan or (b) explicit user confirmation of the specific changes.

## Design

### Two states, separate severity line

Original draft had `ok`/`warn`/`block`. Review feedback pointed out that `warn` and `block` are effectively the same operationally (both pause pending confirmation). Simplified to two operational states on `PLAN_REVIEW`, with severity as a separate metadata line:

- `PLAN_REVIEW=ok` — apply proceeds automatically
- `PLAN_REVIEW=confirm` — apply requires explicit user confirmation

On `confirm`, a separate line carries severity metadata the skill uses to choose phrasing:

- `PLAN_REVIEW_SEVERITY=info` — large number of updates (`UPDATE > update_threshold`); usually safe
- `PLAN_REVIEW_SEVERITY=caution` — large number of creates (`CREATE > create_threshold`); possible runaway
- `PLAN_REVIEW_SEVERITY=destructive` — any `DELETE > 0` or `REPLACE > 0`; resource loss likely

Multiple triggers: the severity line reports the highest (destructive > caution > info).

On `ok`, the severity line is omitted (or emits `PLAN_REVIEW_SEVERITY=none` — either works; spec the absent-line approach for a cleaner output).

Why the split: separating *what happens* (block or don't) from *how bad it is* (info / caution / destructive) is clearer in the data model and easier to test. The skill's confirmation phrasing is a presentation concern; it shouldn't change the gate's behavioural state.

### Thresholds

Use high defaults that only trip on clearly abnormal plans:

- `create_threshold` default: **50** — landing-page module v1 produces ~8 resources; account-setup adds 1; custom properties add a few more. 50 is "this plan is doing something weird" rather than "this matches expected footprint". Configurable via `HS_LANDER_MAX_CREATE` env or CLI flag.
- `update_threshold` default: **100** — updates are usually safe; only trip on clearly anomalous plans. Configurable via `HS_LANDER_MAX_UPDATE`.
- `destroy_threshold`: **0** — any destroy triggers `destructive`. Not configurable.
- `replace_threshold`: **0** — any replace triggers `destructive`. Not configurable.

Per-module expected counts are **not** used. Letting module footprints drive gate behaviour creates a version-coupling maintenance burden. The gate catches *anomalies*; the module author's responsibility is to keep the module's plan sensible.

### Plan file handling

`plan-review.sh` runs `terraform plan -out=<file>` and keeps the saved plan. Apply uses the saved plan file (`terraform apply <plan-file>`), which by Terraform's contract cannot diverge from what was reviewed. If state has drifted between review and apply, Terraform refuses to apply — that's the correct behaviour, surfaced via the existing framework error path.

No time-based staleness check. Terraform's state-match check is the real protection; a time window adds friction without adding safety.

## Scripts

### New: `scripts/plan-review.sh`

**Invocation:**

```
bash $FRAMEWORK_HOME/scripts/plan-review.sh [--plan-file PATH]
```

**Behaviour:**

1. Source config via the usual chain (same as `tf.sh`). Export `TF_VAR_*` from Keychain.
2. Run `terraform plan -out="${PLAN_FILE:-.hs-lander-plan.bin}"`.
3. Run `terraform show -json "$PLAN_FILE"`. Pipe to `jq` to tally `create`, `update`, `delete`, `replace` by counting `.resource_changes[].change.actions`.
4. Collect resource addresses for create/delete/replace (for surfacing to the user).
5. Emit structured output.

**Output contract (always 7 lines when `PLAN_REVIEW=ok`, 8 lines when `PLAN_REVIEW=confirm`, stable order):**

```
PLAN_CREATE=<count>
PLAN_UPDATE=<count>
PLAN_DELETE=<count>
PLAN_REPLACE=<count>
PLAN_RESOURCES=<json-encoded object with create/delete/replace address lists>
PLAN_FILE=<absolute path to the saved plan file>
PLAN_REVIEW=ok|confirm
PLAN_REVIEW_SEVERITY=info|caution|destructive     # present only when PLAN_REVIEW=confirm
```

Using JSON for `PLAN_RESOURCES` so addresses with commas or special characters don't break parsing. The skill uses `jq` (already a required tool) to parse.

**Exit codes:**

- `0` — always. The gate is advisory; the caller (skill or npm script chain) decides what to do with `confirm`.
- Non-zero only on infrastructure errors (plan failed to run, jq parse failed, config missing).

**Dependencies:** `terraform`, `jq` (already required by preflight).

### Modified: `scripts/tf.sh`

Add a new verb `apply`:

```
bash scripts/tf.sh apply [plan-file]
```

Behaviour:
1. Resolve plan file: argument > `$HS_LANDER_PLAN_FILE` > `.hs-lander-plan.bin`.
2. If `HS_LANDER_UNSAFE_APPLY=1` and no plan file exists, warn loudly and run plain `terraform apply`. Otherwise refuse: `APPLY=error plan-file-missing`.
3. Run `terraform apply <plan-file>`.
4. On success, delete the plan file.
5. Emit `APPLY=ok` and exit 0; or `APPLY=error <reason>` and exit 1.

Escape-hatch rationale: `HS_LANDER_UNSAFE_APPLY=1` exists for recovery scenarios (state corruption, targeted applies during debugging). Every use should be deliberate; the noisy warning and the env-var barrier ensure it never happens accidentally.

### Modified: `scaffold/package.json`

```json
{
  "scripts": {
    "plan": "bash scripts/plan-review.sh",
    "apply": "bash scripts/tf.sh apply",
    "setup": "bash scripts/build.sh && bash scripts/plan-review.sh && bash scripts/tf.sh apply"
  }
}
```

The chained `setup` will stop on any `apply` failure. If `plan-review.sh` returns `PLAN_REVIEW=confirm`, `setup` still proceeds to apply because the gate is advisory — but the skill will have read the `confirm` line and paused for user confirmation before reaching apply. For direct CLI usage (no skill), the user is expected to run `npm run plan`, inspect, then `npm run apply` separately when `confirm` appears. Document this in `docs/framework.md`.

An alternative considered: make `setup` non-chained so the user must always run plan and apply separately. Rejected for ergonomics — most plans are `ok` and the chained form is fine. The gate is set up so the skill can intercept `confirm` before `apply` runs.

## Tests

### New: `tests/test-plan-review.sh`

**Test infrastructure:** create `tests/fixtures/plan-scenarios/` containing minimal Terraform configurations that deterministically produce known plans using the `null_resource` provider (no HubSpot API calls, no credentials needed, but still produces real binary plan files that the script parses via `terraform show -json`).

Scenarios:

- `clean-6-creates/` — 6 null_resource creates → `PLAN_CREATE=6`, `PLAN_REVIEW=ok` (no severity line)
- `over-create-threshold/` — 60 null_resources → `PLAN_CREATE=60`, `PLAN_REVIEW=confirm`, `PLAN_REVIEW_SEVERITY=caution`
- `update-over-threshold/` — 110 resources with updates → `PLAN_UPDATE=110`, `PLAN_REVIEW=confirm`, `PLAN_REVIEW_SEVERITY=info`
- `one-destroy/` — state diff producing 1 delete → `PLAN_DELETE=1`, `PLAN_REVIEW=confirm`, `PLAN_REVIEW_SEVERITY=destructive`
- `one-replace/` — resource replacement → `PLAN_REPLACE=1`, `PLAN_REVIEW=confirm`, `PLAN_REVIEW_SEVERITY=destructive`
- `mixed/` — creates + 1 destroy → `PLAN_REVIEW=confirm`, `PLAN_REVIEW_SEVERITY=destructive` (highest severity wins)

Assertions per scenario: exact line-by-line match of the output contract (7 lines on `ok`, 8 lines on `confirm`), exit code 0, plan file exists at reported path.

### Modified: `tests/test-tf.sh` (new or extended)

- `apply` with no saved plan file: exits 1, `APPLY=error plan-file-missing`
- `apply` with a saved plan file: runs, emits `APPLY=ok`, deletes plan file
- `apply` with `HS_LANDER_UNSAFE_APPLY=1` and no plan file: emits warning, attempts plain apply
- `apply` with a stale plan file (state has diverged): Terraform itself refuses; we surface that verbatim

## Documentation

### `CLAUDE.md`

Add "Plan review" to the architecture section. Brief note that `npm run setup` is no longer an auto-approve apply.

### `docs/framework.md`

New "Plan review" section with the output contract, severity table, and threshold defaults. Update the `Commands` listing.

### `scaffold/.gitignore`

Add `.hs-lander-plan.bin` so saved plans never accidentally commit.

## Verification

1. `npm run plan` on a clean initial project emits `PLAN_CREATE=<8>` (or whatever the module footprint is), `PLAN_REVIEW=ok`
2. Inducing state drift (e.g. edit a form title directly in HubSpot UI) produces `PLAN_REVIEW=confirm destructive` with the specific resource in `PLAN_RESOURCES`
3. `npm run setup` respects the saved plan file — apply consumes the same plan that was reviewed
4. `HS_LANDER_UNSAFE_APPLY=1 bash scripts/tf.sh apply` works, emits the warning, and bypasses the plan-file requirement
5. All new tests pass in CI
6. Scaffolded projects have `.hs-lander-plan.bin` in `.gitignore`

## Out of scope

- State/profile backup (companion plan)
- Remote Terraform backend (roadmap item — the proper long-term solution for state durability)
- Destroy command hardening (`npm run destroy` — separate plan if pursued)
- Skill-side behaviour for `PLAN_REVIEW=confirm` output — belongs in a skill plan, not here. The framework defines the contract and stops there.
- Module-specific expected counts — the generic threshold approach is deliberate
