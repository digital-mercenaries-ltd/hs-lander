# Framework / skill compatibility — `VERSION.compat`

The `VERSION.compat` file at the repo root declares the **range of framework versions the consuming skill knows how to talk to**. The skill reads it via `check-framework-compat.sh` (in the skill repo) and refuses to run against a framework outside the range.

## Format

A single-line semver range expression on the first line of `VERSION.compat`. Example:

```
>=1.7.0,<2.0.0
```

This declares that framework versions from `1.7.0` (inclusive) up to but not including `2.0.0` are skill-compatible. The lower bound is the minimum-required-by-skill version; the upper bound is the next major where breaking changes are explicitly anticipated.

The grammar follows standard semver-range conventions:

- `>=X.Y.Z` — at least version X.Y.Z
- `<X.Y.Z` — strictly less than version X.Y.Z
- Combinations comma-separated mean AND
- One-version pin: `=X.Y.Z` (rare; useful only during a known-broken interim)

Whitespace in the value is tolerated. Trailing newline required.

## When to bump `VERSION.compat`

A bump is required when **any** of the following change in a way the skill needs to know about:

### Lower-bound bumps (`>=` value moves forward)

The skill starts requiring a feature added in a specific framework version. Examples that would have triggered a lower-bound bump:

- v1.7.0's introduction of `PREFLIGHT_TIER` — the skill's tier-aware coaching depends on it
- v1.8.0's introduction of `PREFLIGHT_EMAIL_DNS` — the skill's email-deliverability flow depends on it
- v1.9.0's introduction of `PREFLIGHT_EMAIL_REPLY_TO` — the skill uses it to decide between explicit and fallback reply-to behaviour

**The skill author bumps the lower bound when the skill stops being able to operate against an older framework.** Lower bound only ever moves forward.

### Upper-bound tightening (`<` value pulled in)

A framework version inside the range turns out to break compatibility — e.g. a patch release introduces a contract change that bypasses the bump rule (see below). This is rare and represents a process failure; preferred fix is to bump the framework patch instead. Tightening the upper bound is the emergency response.

### Upper-bound widening (`<` value pushed out)

A new major version ships and the skill knows how to talk to it. E.g. when v2.0 ships and the skill catches up, `<2.0.0` becomes `<3.0.0`.

## What counts as a contract surface change (must bump)

Any of these in a framework change requires a `VERSION.compat` bump (or a documented justification for not bumping):

- A `PREFLIGHT_*` line's name, presence in the contract, or set of valid output state values
- A pre-scaffold or config-mutation script's prefix or state values: `SCAFFOLD=`, `INIT_POINTER=`, `ACCOUNT_STATUS=`, `SET_FIELD=`, `ACCOUNTS_INIT=`, `PROJECTS=`, `BACKUP=`, `PLAN_REVIEW=`, `APPLY=`, `PROJECT_STATUS=`, `MIGRATE=`
- A module input variable's name or required-vs-optional status
- The build-token list in `build.sh`
- A scaffold root variable's name, default, or required-vs-optional status
- The `set-project-field.sh` `ALLOWED_KEYS` array

Each of these is a surface the skill talks to. Changing one without bumping `VERSION.compat` means an old skill against a new framework (or vice versa) silently misbehaves.

## What does NOT need a bump

Internal refactors that don't change the contract surface. Examples:

- v1.9.0's `scripts/lib/` consolidation — internal helpers, not skill-facing
- v1.9.0's `preflight.sh` decomposition — output contract preserved verbatim
- Implementation changes to existing scripts that preserve their stdout/stderr/exit-code contract

The CI guard (see below) flags PRs that touch the contract surface; the operator decides whether to bump or document an exemption.

## CI guard

`.github/workflows/ci.yml` runs a `version-compat-check` job on every PR. It:

1. Diffs the changed files against `main`.
2. If any of these contract-surface paths changed, AND `VERSION.compat` did NOT change in the same PR, fails with a structured message pointing the operator at this document.
3. Soft override: include `[skip-compat-check]` in the PR description to acknowledge the contract surface changed but the bump isn't needed (e.g. internal-only refactor that happens to touch a contract-surface file).

Watched paths:

```
scripts/preflight.sh
scripts/preflight.d/*.sh
scripts/*.sh                 (the framework's operator-facing scripts)
scaffold/terraform/main.tf   (root variables)
scripts/build.sh             (build-token list — captured in scripts/*.sh above too)
terraform/modules/landing-page/variables.tf
terraform/modules/account-setup/variables.tf
```

The diff is a heuristic — a contract-changing edit can hide in any of these files, but a non-contract edit in the same file is also legal. The override token is the safety valve.

## How to bump

Single-line edit to `VERSION.compat`. Always raise the version, never lower (lower bound is monotonic). Document the reason in the same commit's body.

Example bump for v1.9.0's `PREFLIGHT_EMAIL_REPLY_TO` introduction (illustrative — v1.9.0 didn't actually bump because the skill hadn't added a dependency on the line yet):

```
- >=1.7.0,<2.0.0
+ >=1.9.0,<2.0.0
```

with commit message:

> Bump VERSION.compat lower bound to 1.9.0
>
> The skill's email-coaching flow now reads PREFLIGHT_EMAIL_REPLY_TO and
> coaches based on its set/fallback state. Skill running against framework
> <1.9.0 sees the line absent and either crashes (strict mode) or silently
> misses the coaching (lenient mode). Either failure mode is worse than
> refusing to run.

## Provenance

Introduced in v1.9.1 per the v1.9.1 plan, Fix 5. Tracks R20 (interface normalisation, deferred to v2.0); the `VERSION.compat` mechanism is a stopgap that gives skill+framework version pairing a structured contract while the bigger normalisation work is pending.
