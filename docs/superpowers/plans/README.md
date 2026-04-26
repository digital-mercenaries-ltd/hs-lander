# Plans Index and Dependency Graph

This directory holds implementation plans for the hs-lander framework. Each plan has a lifecycle (Pending → In-flight → Complete) tracked in its frontmatter. This index gives a view of:

1. What's pending and what's done
2. How plans depend on each other
3. Where to go for the current active work

For roadmap items that haven't yet become plans, see `../roadmap.md`. Roadmap items (R-namespace) map to specific plans (date-named files) when they become actionable.

## Current status

### Complete

Plans that have been implemented and are reflected in the framework source.

| Plan | Status | Ships in |
|---|---|---|
| 2026-04-10-hs-lander-framework.md | Complete | v1.0.0 |
| 2026-04-20-account-config-hierarchy.md | Complete | v1.1.x |
| 2026-04-21-preflight-cli-tools.md | Complete | v1.2.x |
| 2026-04-21-preflight-richer-output.md | Complete | v1.2.x |
| 2026-04-22-config-mutation-commands.md | Complete | v1.3.x |
| 2026-04-22-preflight-fix-and-prescaffold-commands.md | Complete | v1.3.x |
| 2026-04-22-v1.4.0-api-drift-fixes.md (partial — fixes 1 + 2) | Complete | v1.4.0 |
| 2026-04-22-v1.6.0-heard-apply-drift-fixes.md | Complete (retroactive) | v1.6.0 |
| 2026-04-22-v1.6.1-provider-version-bump.md | Complete | v1.6.1 |
| 2026-04-23-v1.6.2-heard-apply-round-2.md | Complete | v1.6.2 |
| 2026-04-23-v1.6.3-forms-privacy-text.md | Complete | v1.6.3 |
| 2026-04-23-v1.6.4-forms-field-group-cap.md | Complete | v1.6.4 |
| 2026-04-23-v1.6.5-email-publish-and-upload-endpoint.md | Complete | v1.6.5 |
| 2026-04-26-v1.6.6-upload-multipart.md | Complete | v1.6.6 |

### In-flight

| Plan | Status | Notes |
|---|---|---|
(none)

### Pending

Plans written and reviewed; implementation not yet started.

| Plan | Depends on | Blocks |
|---|---|---|
| 2026-04-22-preflight-domain-hubspot-check.md (R8) | v1.5.0 merged | Revises skill hosting-modes plan |
| 2026-04-22-plan-review-gate.md | — | Plan-review skill coaching plan (future) |
| 2026-04-22-backup-state-and-profiles.md | — | — |

## Dependency graph

```
v1.0.0 framework ──┐
                   │
v1.1.x ────────────┼── account-config-hierarchy ──┐
                   │                              │
v1.2.x ────────────┼── preflight-cli-tools ───────┤
                   │                              │
                   └── preflight-richer-output ───┤
                                                  │
v1.3.x ──── config-mutation-commands ─────────────┤
                   │                              │
                   └── preflight-fix-and-prescaffold
                                                  │
v1.4.0 ──── v1.4.0-api-drift-fixes (fixes 1+2) ───┤
                                                  │
v1.5.0 ──── v1.4.0-api-drift-fixes (fixes 3+4) ───┤
            + hosting-modes-landing-slug          │
                                                  │
            ┌─── preflight-domain-hubspot-check (R8) ──┐
            │                                          │
            ├─── plan-review-gate                      ├── (next live deploy)
            │                                          │
            └─── backup-state-and-profiles ────────────┘

Skill plans (separate repo, separate lifecycle):
  skills/hs-lander/plans/2026-04-22-skill-hosting-modes.md
    ↳ depends on: hosting-modes-landing-slug (framework) + R8 preflight check
  skills/hs-lander/plans/2026-04-22-skill-drop-write-exceptions.md
    ↳ depends on: config-mutation-commands (already complete)
  skills/hs-lander/plans/2026-04-22-skill-api-drift-warning.md
    ↳ depends on: R6 framework API contract monitoring (plan pending)
```

## Plan authoring conventions

- **Filename**: `YYYY-MM-DD-<topic>.md` where the date is the plan's initial draft date, not implementation date. Renaming on implementation is discouraged; a "Status" field tracks lifecycle instead.
- **Frontmatter**: `Date`, `Status` (Pending / In-flight / Complete / Superseded), `Scope`, `Target release` (where known), `Dependency` (other plans).
- **Scope discipline**: one plan per independent change unit. Bundling unrelated changes tends to produce plans that are harder to review and that block each other during implementation.
- **Investigation subtasks**: when a plan depends on empirical evidence (API shape, UI behaviour), list the probe commands in the plan and run them before writing the prescriptive sections. Retrofit the results back into the plan; don't ship speculation.

## Roadmap vs plans — when to promote

Roadmap items (R1 through R15 in `../roadmap.md`) are captured ideas with loose sizing. A roadmap item becomes a plan when:

1. It's the next thing we expect to work on (i.e. moves from "deferred" to "on deck")
2. Design questions that block implementation are answered (often by a live probe or a discussion thread)
3. Dependencies on earlier work are resolved

Before becoming a plan, items can evolve freely on the roadmap. Once a plan exists, it's the source of truth for that piece of work; the roadmap entry gets a `Plan written: <filename>` reference.
