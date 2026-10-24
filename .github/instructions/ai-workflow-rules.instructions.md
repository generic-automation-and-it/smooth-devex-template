---
description: 'AI-assisted coding workflow phases (Odin→Bragi) — mandatory execution order for all coding tasks'
globs: "**"
paths:
  - "**"
applyTo: '**'
alwaysApply: true
---
# AI-Assisted Coding Workflow

Standard execution workflow for all coding tasks. Authoritative for the workflow; `AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md` carries a FALLBACK copy that must be kept in sync with this file. Updated: 2026-10-22

## Phase 0: Context Load (MANDATORY BLOCKING)

**A functional `*AGENTS.md` file MUST be loaded into the conversation before ANY execution or planning.**

`AGENTS.md` and `*AGENTS.md` are first-class AI-coder context documents — read them like `CLAUDE.md`, not as optional reference. They carry the functional requirements and intent behind the code (the "why", constraints, boundaries, non-obvious behaviors) that source alone cannot convey. Context is layered — **domain → sub-domain → feature → technology** — so read every level that governs the code you touch; specific overrides general, and the nearest `*AGENTS.md` is most authoritative.

Root AGENTS.md / NFR files alone are NOT sufficient. Domain-specific context is required.

| Working in | Apply |
|------------|-------|
| Backend code (.NET, C#, server-side) | `.agents/rules/backend/*` rules (scoped to `**/*.cs` via frontmatter; attach when a C# file is opened) |

All rules under `.agents/rules/` are auto-loaded every session, organized into category subfolders (`backend/`, `git/`, `meta/`); applicability is scoped per-file via frontmatter (`paths`/`globs`/`applyTo`). For functional `*AGENTS.md` context: use the `context-load-context` skill with `[domain]` or manually request the relevant files. Root `AGENTS.md` lists the rule category folders; per-rule coverage lives in the rule files themselves.

If no context loaded: **BLOCK** → offer: Load / Search / Create / BYPASS.

Then **import prior Understandings** before asking anything. Check `.context/understandings/INDEX.md`; when `mimisbrunnr-kvasir-understanding` is among your available skills, query the store with `import --query WORD` (read-only). Otherwise use `ai-understanding --import` on the local Understanding files. Skip silently when neither exists.

## Phase 1: Odin (Clarify) — GATE

Ask clarifying questions about requirements, constraints, business logic (not technical implementation details — decide those autonomously).

- **Never assume** — when unsure about anything, ask
- **Answer from the code before asking** — for each open question, search the repo and its context first; surface only what the code cannot answer
- **Every question carries a recommended answer** so the user can confirm in one word
- If requirements are already clear from the task description, state your understanding and proceed without waiting
- Otherwise, **wait for user response before proceeding**

## Phase 2: Thoth (Analyze)

Analyze tech stack and existing patterns relevant to the task.

- **Verify, don't trust** — subagent and document claims about versions, API support, or where a behavior originates are leads, not facts. Confirm cheaply with the real tool (build it, grep for the actual producer, read the vendor's docs) before building on them.

Skip for: single-line fixes, obvious bugs, config changes.

## Phase 3: Forseti (Specify)

Create technical specification with architectural decisions.

**Define validation with the specification — before any code exists.** Every acceptance criterion maps to a check, and each check names the criterion it proves. Prefer, in order: the repo's existing L0/L1/L2 suites; the standard build/lint/type gates; an ad-hoc runtime check; a purpose-built script or tool as a last resort, with a one-line reason the earlier options could not express the behavior. A green check that does not trace to a criterion is not evidence.

Skip for: simple tasks where implementation is obvious.

## Phase 4: Tyr (Plan) — GATE

**Prerequisites:** Phase 1 complete. If Phases 2/3 were not skipped, their output informs this plan.

Present implementation plan, including the Phase 3 validation table (or, when Phase 3 was skipped, each acceptance criterion mapped to the check that proves it). **Wait for user approval before proceeding.**

Use for: 3+ files, architectural decisions, complex logic, cross-cutting concerns, new features.
Skip for: single-line fixes, obvious bugs, config changes.

## Phase 5: Frigg (Document)

Update project documentation with approved plan (e.g., AGENTS.md under `## Requirements`).

Skip when: no documentation convention exists or changes are trivial.

## Phase 6: Thor (Execute) — YOLO MODE

Implement autonomously. No permission asks. Complete implementations (no TODOs). Fix forward.

**On failure:** Attempt to fix forward within the failing change. If 2 attempts have not resolved it, triage by [Loop Control](#loop-control) instead of continuing to retry.

### Parallelism

Batch independent tool calls in a single message: reads of different files, greps, and builds or tests of projects that do not depend on each other. Sequence only when one call's output feeds the next. Never run two write operations against the same file, and never run concurrent `dotnet build` / `dotnet test` over the same solution. Parallel writers require worktree isolation plus an explicit merge step — otherwise implement sequentially.

## Phase 7: Heimdall (Review)

Quality gate — spec/implementation sync check.

**Checklist:** Code quality | Tests | Pattern consistency | Security | Spec/implementation sync | Changelog

**Review the whole picture, not the diff alone.** Judge the diff against the Phase 3 specification and its validation checks, and against the worktask's `## Run Log`. A diff-only review cannot tell whether the acceptance criteria are actually proven.

**Sync check:** Compare specification (Phase 3) or task instructions (if Phase 3 was skipped) vs implementation. A mismatch is a finding: triage it by [Loop Control](#loop-control). Escalate to the user only when the fix would change the specification or a requirement — then offer: update spec / update logic / manual review.

**Findings that require change:** triage by [Loop Control](#loop-control), and record each in the worktask's `## Run Log` when the run has one.

**→ After review, proceed to Phase 8 (Bragi). Do not stop here.**

## Phase 8: Bragi (Record) — 🛑 MANDATORY

**Do not skip this phase.** Document what was **actually implemented** (not just planned):

- Update the context document loaded in Phase 0 with real implementation details
- Finalize LADRs with actual outcomes
- Review whether any `docs/adr/` or HLD NFRs (`docs/hlds/*/nfrs/`) need updating — if the implementation changes behavior covered by an existing ADR or NFR, update it; if a new architectural decision was made, create a new ADR
- Update changelog with comprehensive entry

**If a context document was loaded in Phase 0, it MUST be updated in Phase 8.** Loading a context document creates a mandatory update obligation — this is not optional regardless of path (lightweight or full).

**If no context document existed:** Create from `TEMPLATE_AGENTS.md`, add to root AGENTS.md.

**Why this is mandatory:** The Gemini code review gate requires `*AGENTS.md` changes on FULL reviews. Skipping Phase 8 will block PRs. This phase also ensures AI-generated changes are documented for future conversations.

### Reflect (mandatory, after the recording above)

Turn this run's friction into something that makes the next run lighter. Read the worktask's `## Run Log` when the run has one — otherwise the session's own phase output — and ask:

- Which Phase 1 question could the code or context have answered — would a `*AGENTS.md` line, an acceptance criterion, or a check have removed it?
- Which Phase 7 finding, or loop-back cause, could an existing gate have caught first?

For each, propose the smallest fix that prevents the repeat: a validation check in the worktask template, an L0/L1/L2 test, a rule entry, or a line in the nearest `*AGENTS.md`. Put the proposals in this turn's output; apply only the ones inside this change's scope.

**Capture what outlives this task.** When the run produced knowledge that no code file, `*AGENTS.md`, or Understanding already holds, capture it — in this order:

1. **Locate the skill.** If `mimisbrunnr-kvasir-understanding` is among your available skills, use it. Otherwise use the first directory that contains `SKILL.md`:
   - `**/skills/mimisbrunnr-kvasir-understanding/SKILL.md` anywhere in the repo (vendored or installed copy)
   - `$HOME/.claude/skills/mimisbrunnr-kvasir-understanding/SKILL.md`
   - `$HOME/.codex/skills/mimisbrunnr-kvasir-understanding/SKILL.md`
   - `$HOME/.config/opencode/skills/mimisbrunnr-kvasir-understanding/SKILL.md`
2. **Run its client by absolute path, with the repo root as the working directory** — `<skill-dir>/scripts/understanding_client.py`, where `<skill-dir>` is the directory holding the matched `SKILL.md`; use the four locations above when the skill came from your available-skills list. Do not follow Kvasir's own repo-relative path — it does not hold for a global install. The client anchors its dump folder on `git rev-parse --show-toplevel` and falls back to the working directory, so running it after stepping into the skill directory writes the dump outside the repo.
3. **Capture locally:** run `dump --currentsession --from -` with this run's durable claims on stdin, one per list item. It writes a folder under `.context/mimisbrunnr-understandings/` at the repo root and touches no shared or remote state.
4. **Propose an `export` of that folder** and say so in the output. The store is written only on an explicit request — a proposal is not authorization.
5. **If no Kvasir install resolves,** use `ai-understanding --export` when it is available. **If neither is installed,** list the durable claims in this turn's output and report capture as unavailable — that completes the step. State which route ran.

## Loop Control

A failed check or a review finding routes back to the phase that can actually fix it — never to a blind re-run of the whole pipeline.

| Failure | Re-enter at |
|---|---|
| Local defect — lint, type error, typo, an obvious mistake confined to one file or unit | Phase 6 |
| Systemic — wrong approach, a missed requirement, a break that crosses files or concerns | Phase 2 |
| A genuinely new question only the user can answer | Phase 1, and only then |

- **Re-entry overrides the chosen path.** A lightweight-path run that re-enters Phase 2 is now on the
  full path; do not skip a phase because it was not originally selected.
- **Caps: 5 loop-backs in one run, or 3 tracing to the same root cause.** On either cap, stop and escalate with what was tried and why it keeps failing; a fresh diagnosis each time still counts against the total.
- **Record every loop-back** as one line in the worktask's `## Run Log` when the run has one: cause, re-entry phase, outcome. Phase 8's reflect step reads it.

## Output Requirements

**MANDATORY for every conversation — no exceptions:**

1. **Label every phase** — Output `## Phase N: Name` as a visible header before executing each phase
2. **Label every skip** — If skipping a phase, output: `## Phase N: Name — Skipped: [one-line reason]`
3. **Sequential execution** — Phases MUST execute in declared order. Never reorder, combine, or nest phases (e.g., doing Phase 5 work inside Phase 6 is a violation)
4. **No silent phases** — Every phase in your chosen path (lightweight or full) MUST appear in output. If the user can't see it, it didn't happen

**Why this matters:** Without visible phase labels, skipped phases are invisible to the user. This makes it impossible to verify workflow compliance or catch when phases are silently dropped.

## Enforcement

| Phase | Name | Gate? | Level |
|-------|------|-------|-------|
| 0 | Context Load | 🛑 MANDATORY | No context = no execution |
| 1 | Odin (Clarify) | 🛑 GATE | State understanding if clear, otherwise wait for response |
| 2 | Thoth (Analyze) | | Skippable — MUST output skip reason |
| 3 | Forseti (Specify) | | Skippable — MUST output skip reason |
| 4 | Tyr (Plan) | 🛑 GATE | Wait for user approval before proceeding |
| 5 | Frigg (Document) | | Skippable — MUST output skip reason |
| 6 | Thor (Execute) | | 🔨 YOLO MODE — implement autonomously |
| 7 | Heimdall (Review) | | Mandatory sync check — MUST proceed to Phase 8 |
| 8 | Bragi (Record) | 🛑 MANDATORY | Update context doc, review ADRs/NFRs, update changelog; then **Reflect** (proposals + Understanding capture) |

### Path Selection

**Lightweight path**: Phase 0 → 1 → 6 → 7 → 8
Use when: single file, no architectural decisions, clear requirements.

**Full path**: Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
Use when: 3+ files, new patterns, cross-cutting concerns, or ambiguous scope.

**Phase 8 is on BOTH paths.** If a context document was loaded in Phase 0, Phase 8 is mandatory regardless of which path was chosen. The only exception is if no context document was loaded AND the change is truly trivial (e.g., single-line typo fix).

**Path selection is NOT a way to avoid Phase 8.** Changing 30 config files is not "lightweight" even if each change is simple. The path determines which middle phases (2–5) to run, not whether to document.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-05-30 | Initial version. |
| 2026-06-17 | Phase 0: state that AGENTS.md/`*AGENTS.md` are first-class context (read like CLAUDE.md) and layered domain→sub-domain→feature→technology. Pattern notation `*_AGENTS.md`→`*AGENTS.md` (underscore no longer required). |
| 2026-09-20 | Phase 6: added a **Parallelism** subsection (batch independent tool calls; no concurrent writes to one file; no concurrent `dotnet build`/`dotnet test` over one solution; parallel writers need worktree isolation + merge). Phase 0: `load-context`→`context-load-context` (the former resolves to nothing). Header now states this file is authoritative and the worktask template's copy is a FALLBACK to keep in sync; stale `Updated:` date refreshed. |
| 2026-10-21 | Phase 0 imports prior Understandings (Kvasir `import` when installed, else `ai-understanding --import`). Phase 1 answers from the code first and every question carries a recommended answer. Phase 2 verifies subagent/document claims. Phase 3 defines validation from the acceptance criteria, in preference order. Phase 6 no longer gives up after 2 attempts — it triages. Phase 7 reviews against the spec and validation, not the diff alone. New **Loop Control** section (local → Phase 6, systemic → Phase 2, new-user-question → Phase 1; 5 loop-backs / 3 per root cause). Phase 8 adds the mandatory **Reflect** sub-step: proposals plus Understanding capture through Kvasir's `dump --currentsession` when the skill resolves at any of four locations, else `ai-understanding --export`. |
| 2026-10-22 | Phase 8 Reflect step 5: when neither Kvasir nor `ai-understanding` is installed — the skill installer ships neither — list the durable claims in the output and report capture as unavailable, instead of invoking a missing skill. |
