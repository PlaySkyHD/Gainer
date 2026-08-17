---
description: 'Code review instructions for spec driven development with OpenSpec.'
applyTo: 'openspec/**'
excludeAgent: ["coding-agent"]
---

# OpenSpec Code Review Instructions

Spec-driven review guidelines for changes that touch `openspec/**`. These instructions supplement the generic code review file with checks tailored to the OpenSpec workflow, artifact structure, and lifecycle conventions verified in our repository. The authoritative schema and drafting rules live in `openspec/config.yaml`; treat it as the source of truth when this file is silent.

## Precedence

These code review instructions take precedence over the generic review file when reviewing OpenSpec artifacts. When a change touches both `openspec/**` and source code, apply this file to the artifacts and the language-specific review files to the code, then reconcile: the specs and the implementation must agree.

## OpenSpec Layout

When performing a code review, orient against the expected layout:

- `openspec/specs/<capability>/spec.md` — the current, deployed truth. Updated only by syncing a change.
- `openspec/changes/<change-id>/` — one in-flight change: `proposal.md`, `tasks.md`, optional `design.md`, and spec deltas under `specs/<capability>/spec.md`.
- `openspec/changes/archive/<change-id>/` — completed changes, moved here after deployment.
- `openspec/config.yaml` — schema, drafting rules, tier model, and per-artifact rules.

## Lifecycle And Archiving

When performing a code review, verify the change is in the correct lifecycle state:

- A pull request **should** carry exactly one OpenSpec change. Flag a PR that adds or archives multiple changes at once; it makes archiving non-atomic and the review harder to reason about. Split it unless the changes are tightly coupled and must ship together.
- A change whose `tasks.md` is fully checked and whose implementation is merged **must** be archived: moved to `openspec/changes/archive/<change-id>/` and its deltas folded into `openspec/specs/`. Flag an implemented-but-unarchived change as a finding.
- After archiving, `openspec/changes/<change-id>/` **must not** still exist as an active change. Flag a change that lives in both active and archive locations.
- Do not archive a change with unchecked tasks or unmerged implementation. Flag premature archiving.
- Prefer `openspec archive <change-id>` to perform the move; verify the result rather than trusting a manual copy.

## Spec Synchronization

When performing a code review, verify the specs reflect reality after archiving:

- Every delta in the archived change (ADDED, MODIFIED, REMOVED requirements) **must** be applied to `openspec/specs/<capability>/spec.md`. Flag any delta that was not merged (spec drift).
- REMOVED requirements **must** be deleted from the target spec, not left orphaned.
- MODIFIED requirements **must** replace the prior text, not duplicate it.
- Delta headers **must** reference a real capability and requirement. Flag deltas that target a non-existent or renamed requirement.
- The final spec **must not** contain leftover delta markers (`## ADDED`, `## MODIFIED`, `## REMOVED`) — those belong only in change folders.
- The implementation **must** match what the spec now claims. Flag specs that describe behavior the merged code does not deliver, and code behavior the spec does not cover.

## Artifact Coherence

When performing a code review, verify proposal, specs, design, and tasks tell one consistent story:

- **Proposal ↔ Specs**: every capability the proposal promises has a matching spec delta; no spec delta introduces scope the proposal never mentioned.
- **Specs ↔ Tasks**: every requirement has at least one task that implements it and a task that tests it; no task implements behavior that is absent from the specs.
- **Design ↔ Specs/Tasks**: when a `design.md` exists, its chosen approach, migrations, and diagrams match the requirements and the task breakdown. Flag a design that contradicts the specs.
- **Tier consistency**: the tier recorded in each artifact (per `config.yaml`) matches. A `high` or `very high` change **must** include a `design.md` with rollout and rollback plans; flag its absence. A `low` change may omit design.
- **Scenarios**: every requirement has at least one Given/When/Then scenario, including failure and edge paths appropriate to the tier.
- **Non-goals**: implementation and specs stay within the proposal's stated non-goals and out-of-scope items. Flag scope creep.
- **Breaking changes**: a breaking change flagged in the proposal is reflected in the specs (migration/compat notes) and in tasks (migration + doc steps), and vice versa.

## Artifact Quality

When performing a code review, check each artifact against `config.yaml` rules:

- **Proposal**: states security-posture impact (even "none"), explicit non-goals, Impact (services, public APIs, data schemas, tenant-facing behavior), ADR note when applicable, and up-front breaking-change flags.
- **Specs**: one feature-sized capability per spec, testable and unambiguous requirements, failure modes and tenant boundaries covered, backwards compatibility preserved or migration documented, required logging/metrics/traces specified.
- **Design**: rejected alternatives with reasons, OWASP-relevant risks addressed, new dependencies justified against the existing stack, resilience for remote calls (timeouts, retries, idempotency, bounded concurrency), forward/backward migration defined for schema or data changes.
- **Tasks**: every behavior paired with its verifying test, doc and config wiring included, small independently committable units following Conventional Commits, ordered so the build and tests stay green after each task, integration tests preferred over unit tests.

## Hygiene

When performing a code review, verify basic artifact hygiene:

- Change IDs are descriptive, kebab-case, and verb-led (e.g., `add-tenant-rate-limit`).
- Artifacts are in English, short declarative sentences, one idea per sentence.
- No real secrets, connection strings, or customer data — placeholders only. Treat any real secret as a Critical finding.
- No invented APIs, files, or config keys; every claim is grounded in the codebase.
- No abandoned or empty change folders left behind.

## Severity Mapping For OpenSpec Findings

When performing a code review, map OpenSpec issues onto the generic severity model:

- **Critical**: spec drift that misrepresents deployed behavior, real secrets in artifacts, a REMOVED requirement still enforced by code (or vice versa), or a breaking change neither documented nor migrated.
- **Important**: unarchived completed change, missing `design.md` for a high-tier change, a requirement with no implementing or testing task, tier inconsistency across artifacts, or proposal/spec scope mismatch.
- **Suggestion**: naming, phrasing, scenario clarity, or splitting an oversized spec, where no correctness or drift risk exists.

## Comment Template

Use the generic review comment shape, pointing at the specific artifact and line:

```markdown
**[Severity] | [Category] | openspec/path/to/artifact.md:line**

Short statement of the issue.

Why it matters: explain the drift, lifecycle, or coherence risk.

Suggested fix: describe the smallest safe correction, aligned with config.yaml and the OpenSpec workflow.
```

### Example Comments

#### Critical Finding

```markdown
**Critical | Spec Drift | openspec/specs/rate-limiting/spec.md:1**

The change `add-tenant-rate-limit` was archived, but its MODIFIED requirement was not applied to the spec.

Why it matters: the spec now misrepresents deployed behavior, so future changes will build on a false baseline.

Suggested fix: fold the archived delta into the spec (or re-run `openspec archive`) so the requirement text matches what shipped.
```

#### Important Finding

```markdown
**Important | Lifecycle | openspec/changes/add-tenant-rate-limit/tasks.md:1**

All tasks are checked and the implementation is merged, but the change still lives under `changes/`.

Why it matters: an unarchived completed change hides the true spec state and blocks the next change from a clean baseline.

Suggested fix: run `openspec archive add-tenant-rate-limit` to move it to `changes/archive/` and update `specs/`.
```

#### Suggestion Finding

```markdown
**Suggestion | Coherence | openspec/changes/add-tenant-rate-limit/specs/rate-limiting/spec.md:24**

The requirement has no failure-path scenario.

Why it matters: reviewers and implementers cannot verify behavior when the limit is exceeded.

Suggested fix: add a Given/When/Then scenario for the over-limit case.
```

## Review Checklist

When performing a code review, systematically verify:

### Lifecycle

- [ ] The PR carries exactly one OpenSpec change (unless tightly coupled).
- [ ] Completed change (tasks checked + implementation merged) is archived.
- [ ] Archived change no longer exists as an active change.
- [ ] No change was archived prematurely (unchecked tasks / unmerged code).

### Spec Synchronization

- [ ] Every ADDED/MODIFIED/REMOVED delta is folded into `openspec/specs/`.
- [ ] No leftover delta markers remain in the target specs.
- [ ] Delta headers reference real capabilities and requirements.
- [ ] Specs and merged implementation describe the same behavior.

### Artifact Coherence

- [ ] Proposal, specs, design, and tasks agree on scope and tier.
- [ ] Every requirement has an implementing task and a testing task.
- [ ] `design.md` exists for high / very high tier and includes rollout + rollback.
- [ ] Every requirement has at least one Given/When/Then scenario.
- [ ] Non-goals are respected; no scope creep.
- [ ] Breaking changes are flagged, documented, and migrated consistently.

### Hygiene

- [ ] Change ID is descriptive, kebab-case, verb-led.
- [ ] No real secrets or customer data in any artifact.
- [ ] No invented APIs, files, or config keys.
- [ ] No abandoned or empty change folders.

