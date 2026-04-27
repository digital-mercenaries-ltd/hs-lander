# Plans Index and Dependency Graph

This directory holds implementation plans for the hs-lander framework. Each plan has a lifecycle (Pending → In-flight → Complete | Superseded) tracked in its frontmatter. This index gives a view of:

1. What's pending and what's done
2. How plans depend on each other
3. Where to go for the current active work

For roadmap items that haven't yet become plans, see `../roadmap.md`. Roadmap items (R-namespace) map to specific plans (date-named files) when they become actionable.

Shipped plans live in `archive/`. The Complete table below points at the archived files for cross-reference.

## Current status

### In-flight

| Plan | Notes |
|---|---|
| (none) | |

### Pending

Plans written and reviewed; implementation not yet started.

| Plan | Depends on | Likely target release |
|---|---|---|
| 2026-04-27-welcome-email-published-state-handling.md (B3) | v1.8.1 shipped; needs probe before prescriptive sections | v1.8.2 or v1.9.0 (folded if convenient) |
| 2026-04-22-plan-review-gate.md | v1.8.1 shipped | v1.9.0 (paired with backup-state-and-profiles) |
| 2026-04-22-backup-state-and-profiles.md | v1.8.1 shipped | v1.9.0 (paired with plan-review-gate) |

### Pending — to be written

Concrete work scoped but no plan file yet. Listed here so plan authors know what's queued without re-inventing scope.

| Plan | Likely target release | Notes |
|---|---|---|
| v1.9.0 lib + preflight refactor | v1.9.0 | `scripts/lib/` consolidation (Keychain reader with xtrace, sed portability, var extractor, validator extension), `preflight.sh` decomposition. Bundles with the safety pair above. |
| v1.9.1 ergonomics (R9 sub-items 2 + 3, scaffold-to-plan test, VERSION.compat) | v1.9.1 | Operator ergonomics + test pyramid widening. |
| v2.0 breaking changes (R5 main + scope auto-discovery, output-contract normalisation, migration consolidation) | v2.0 | Major-version cut; multiple breaking-candidate items already noted in roadmap. |

### Complete (archived)

Plans that have shipped and are reflected in the framework source. Files moved to `archive/` during the v1.8.1 plan-archive sweep.

| Plan | Status | Ships in |
|---|---|---|
| `archive/2026-04-10-hs-lander-framework.md` | Complete | v1.0.0 |
| `archive/2026-04-20-account-config-hierarchy.md` | Complete | v1.1.x |
| `archive/2026-04-21-preflight-cli-tools.md` | Complete | v1.2.x |
| `archive/2026-04-21-preflight-richer-output.md` | Complete | v1.2.x |
| `archive/2026-04-22-config-mutation-commands.md` | Complete | v1.3.x |
| `archive/2026-04-22-preflight-fix-and-prescaffold-commands.md` | Complete | v1.3.x |
| `archive/2026-04-22-v1.4.0-api-drift-fixes.md` (partial — fixes 1 + 2) | Complete | v1.4.0 |
| `archive/2026-04-22-hosting-modes-landing-slug.md` | Complete (retroactive — bookkeeping caught up in v1.8.1) | v1.5.0 |
| `archive/2026-04-22-v1.6.0-heard-apply-drift-fixes.md` | Complete (retroactive) | v1.6.0 |
| `archive/2026-04-22-v1.6.1-provider-version-bump.md` | Complete | v1.6.1 |
| `archive/2026-04-23-v1.6.2-heard-apply-round-2.md` | Complete | v1.6.2 |
| `archive/2026-04-23-v1.6.3-forms-privacy-text.md` | Complete | v1.6.3 |
| `archive/2026-04-23-v1.6.4-forms-field-group-cap.md` | Complete | v1.6.4 |
| `archive/2026-04-23-v1.6.5-email-publish-and-upload-endpoint.md` | Complete | v1.6.5 |
| `archive/2026-04-26-v1.6.6-upload-multipart.md` | Complete | v1.6.6 |
| `archive/2026-04-26-v1.6.7-email-rendering-and-form-hide.md` | Complete | v1.6.7 |
| `archive/2026-04-26-v1.7.0-scaffold-hubl-and-tier-aware-preflight.md` | Complete | v1.7.0 |
| `archive/2026-04-27-v1.7.1-bugfixes-and-script-refresh.md` | Complete | v1.7.1 |
| `archive/2026-04-27-v1.8.0-survey-schema-and-email-dns.md` | Complete | v1.8.0 |
| `archive/2026-04-27-v1.8.1-codex-review-fixes.md` | Complete | v1.8.1 |

### Superseded (archived)

Plans whose substantive design has been overtaken by later releases. Kept for historical reference of the original design rationale.

| Plan | Status | Reason |
|---|---|---|
| `archive/2026-04-22-preflight-domain-hubspot-check.md` (R8) | Superseded | Most of the design shipped in v1.7.0 as `PREFLIGHT_DOMAIN_CONNECTED`. Two residual pieces (a `scripts/lib/hosting-mode.sh` helper + mode-aware skipping) are partly obsolete because `HOSTING_MODE_HINT` was removed in v1.7.0. If wanted, fold the helper into v1.9.0's `scripts/lib/` consolidation; otherwise close R8 in the roadmap. |

## Dependency graph (current pending work)

```
v1.8.0 (shipped) ──────── ?
                          │
v1.8.1 (codex-review-fixes — to be written)
                          │
v1.9.0 ─── plan-review-gate ──── safety pair ──┐
       ─── backup-state-and-profiles ──────────┤
       ─── scripts/lib/ consolidation          │
       ─── preflight.sh decomposition          │
                                                │
v1.9.1 ─── R9.2 migrate-project.sh             ├── (next live deploy)
       ─── R9.3 projects-describe.sh           │
       ─── scaffold-to-plan test               │
       ─── VERSION.compat maintenance          │
                                                │
v2.0   ─── R5 main + scope auto-discovery ─────┤
       ─── output-contract normalisation       │
       ─── migration consolidation doc         │
       ─── plans archive cull (R3, R8 close)   │
```

## Plan authoring conventions

- **Filename**: `YYYY-MM-DD-<topic>.md` where the date is the plan's initial draft date, not implementation date. Renaming on implementation is discouraged; a "Status" field tracks lifecycle instead.
- **Frontmatter**: `Date`, `Status` (Pending / In-flight / Complete / Superseded), `Scope`, `Target release` (where known), `Dependency` (other plans).
- **Scope discipline**: one plan per independent change unit. Bundling unrelated changes tends to produce plans that are harder to review and that block each other during implementation.
- **Investigation subtasks**: when a plan depends on empirical evidence (API shape, UI behaviour), list the probe commands in the plan and run them before writing the prescriptive sections. Retrofit the results back into the plan; don't ship speculation.
- **Status updates**: when a plan ships (or is superseded), update its frontmatter Status field in the same PR that ships the work. The v1.8.1 archive sweep caught up two plans whose statuses had drifted (`hosting-modes-landing-slug` shipped silently in v1.5.0; `preflight-domain-hubspot-check` was overtaken by v1.7.0).

## Roadmap vs plans — when to promote

Roadmap items (R1 through R19 in `../roadmap.md`) are captured ideas with loose sizing. A roadmap item becomes a plan when:

1. It's the next thing we expect to work on (i.e. moves from "deferred" to "on deck")
2. Design questions that block implementation are answered (often by a live probe or a discussion thread)
3. Dependencies on earlier work are resolved

Before becoming a plan, items can evolve freely on the roadmap. Once a plan exists, it's the source of truth for that piece of work; the roadmap entry gets a `Plan written: <filename>` reference.

## Archive

`archive/` contains plans whose substantive design has shipped or been superseded. Plans live there for cross-reference and historical context — the index above points to them by relative path. Future archive sweeps happen at major-version cuts (planned for v2.0); plans don't move during patch or minor releases unless their status changes.
