---
name: create-worktask
description: 'Author an execution-ready implementation worktask for the AI-native Software Development Lifecycle (SDLC), translating clarified intent and design into scope, measurable acceptance criteria, validation checks, dependencies, and an execution profile under `.context/work-tasks/`. Trigger on "create worktask", "create a work task", "make a work-task", "promote this to a worktask", or "create an SDLC worktask"; also /create-worktask (Claude Code) or $create-worktask (Codex). Does not execute the worktask or trigger on questions about worktasks or SDLC.'
allowed-tools:
  - Bash(.agents/skills/create-worktask/scripts/scaffold-worktask.sh:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: xhigh  # investigation + requirement authoring the whole 9-phase workflow runs on
---

# Create Worktask — SDLC Implementation Planning

## TL;DR

Produce `.context/work-tasks/<slug>.md` carrying **Title, Execution Profile, Source and Decision, Contexts, Instructions**
and (only when needed) **Overrides**. The worktask *links* the bundled process manual,
[`assets/AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md`](assets/AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md) — it never copies it.

The worktask prepares the **Build and Test** work in the AI-native SDLC development workflow
(Odin→Bragi). It links clarified intent/design from the existing ticket, HLD or task request rather
than replacing them. Everything downstream inherits its gaps, so populate it from **real investigation**, not placeholders.

The process manual is a bundled **WET asset** so installing this skill does not depend on repo-level
templates. Generated worktasks still link it rather than embedding the manual.

## Non-Negotiables

- **Link the process manual, never copy it.** The template carries the phases, gates, output rules and
  Constraints block. Copying them into the worktask creates a second copy that drifts.
- **Contexts must be real, verified paths.** Open each one before listing it. A listed file that does
  not exist is worse than an omitted one — the executing session will hunt for it.
- **Acceptance criteria are testable and measurable.** "Works correctly" is not a criterion.
- **One source of truth per artifact.** Link canonical intent/design/plan records and known revisions,
  owners and decisions. Do not invent approvals or require three new documents for a small task.
- **Deployment is separate.** Creating or approving an implementation worktask does not authorize
  release actions. The Execution Profile records that boundary; release authorization belongs in its
  separate canonical record.
- **Commit permission is per-task and defaults to not allowed.** The Execution Profile's
  `Commits during execution` field is the only thing that grants it; `Push` is always `never`. Nothing
  in a worktask overrides `git-policy.instructions.md`.
- **The session effort is a human action.** Recommend a level (`low` → `max`); never claim to set it,
  and never recommend a model. The user sets the runner's effort level before starting and can raise
  it at a gate.
- **No HTML comments in `assets/`.** Authoring guidance for the asset lives in
  this skill's `AGENTS.md` instead. See that file for why.
- **Do not execute the worktask in the same turn that creates it.** Creating and executing are separate
  invocations; the user chooses the effort and path in between.

## Invocation

Use `/create-worktask <kebab-slug>` in Claude Code or `$create-worktask <kebab-slug>` in Codex —
or describe the work in natural language and follow the workflow.

## Output structure (the contract)

```
.context/work-tasks/<kebab-slug>.md
├── # Task: <one-liner>
├── Process: link to AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md
├── ## Execution Profile   # effort, path, subagents, commits, push, deployment boundary
├── ## Source and Decision # canonical source/revision, known decision/owner, open concerns
├── ## Contexts            # verified paths only
├── ## Instructions        # summary, acceptance criteria, validation table, requirements,
│                          # scope, integration points, NFRs, tests, dependencies
├── ## Run Log             # empty at scaffold time; appended during execution
└── ## Overrides           # omit entirely when there are none
```

`.context/` is gitignored — worktasks are local, per-workspace, never committed.

## Workflow

1. **Understand the task** — parse the request and the conversation. If the intent is ambiguous in a way
   that changes what gets built, ask before scaffolding; do not invent requirements.

2. **Investigate before writing.** Batch the independent reads and greps in one message: candidate
   `*AGENTS.md` files, similar existing implementations, the rules and ADRs that apply, schema or API
   surfaces the change touches. Then recall what earlier sessions established: check
   `.context/understandings/INDEX.md`, query the Mímisbrunnr store when `mimisbrunnr-kvasir-understanding`
   is among your available skills, otherwise run `ai-understanding --import` when it is available, and
   skip the recall when neither is installed. Record the exact build, test and lint commands the repo
   already uses — they seed the Validation table in step 6.

3. **Scaffold** — run:
   ```bash
   .agents/skills/create-worktask/scripts/scaffold-worktask.sh <slug> [--title "One-liner"] [--force]
   ```
   It prints JSON of the created path. The slug is kebab-case and describes the task
   (`add-vessel-eta-validation`, `fix-claims-filter-bug`).

4. **Fill the Execution Profile:**
   - **Recommended session effort + Path** — from the complexity read in step 7
   - **Subagents** — `none` unless the task genuinely needs read-only fan-out or worktree-isolated writers
   - **Commits during execution** — `not allowed` unless the user explicitly grants it for this task
   - **Push** — `never`
   - **Deployment** — `not authorized by this implementation worktask`; link separate release
     authorization if it already exists, without granting it through this field

   Fill **Source and Decision** with the originating ticket/HLD/intent or approved task request, its
   canonical location and known revision, and the actual decision/owner/status. If no shared record
   exists, name the user request as the source and say revision/approval evidence is unrecorded rather
   than inventing it. Carry open concerns with their owners, deleting the field when none exist.

5. **Fill Contexts** — every resource a standalone coder needs, each one verified in step 2:
   - Domain/feature `*AGENTS.md` files governing the code being touched
   - ADRs and NFRs that apply (`docs/hlds/`, `code-review-standards.instructions.md`)
   - Rule files that apply (logging conventions, git policy, workflow rules)
   - Root `AGENTS.md` for system context; existing similar features to follow
   - Schema / API surfaces where the change touches them
   - If no feature `*AGENTS.md` exists, say so; add creation to Instructions only when lasting local
     guidance is needed and passes the AGENTS quality rule

6. **Fill Instructions** — the phases downstream consume these:
   - **Summary + outcome/success signal + acceptance criteria + requirements + scope boundaries**
     (Phase 1 clarifies against these). Preserve source requirement IDs, or assign local IDs when the
     source has none; link them to criterion IDs instead of losing traceability.
   - **Validation** — one row per acceptance criterion: source requirement ID, criterion ID, then the check that proves it as
     tier + command (L0/L1/L2, or an ad-hoc runtime check). Prefer the repo's existing suites, then the
     standard build/lint/type gates, then an ad-hoc check; a new script or tool only when none of those
     can express the behaviour, with a one-line reason in the row. Fill this table before confirming
     the worktask — Phase 3 only refines it on the full path. Evidence starts as `not run`; Phase 6 runs
     targeted checks during implementation and records actual command/result/evidence in the Run Log.
     Update each check's Evidence cell with its latest result and a Run Log/evidence reference; keep
     earlier attempts in the Run Log and unrun checks marked `not run`. Phase 7 reviews the integrated
     result. A criterion with no passing check is unmet.
   - **Integration points, performance, security, compliance** (Phase 2 analyses these)
   - **Data model, API contracts, UI structure** where the change implies them (Phase 3 specifies these)
   - **Tests** — required tiers: L0 (unit) / L1 (component) / L2 (integration), and what each must cover
   - **Dependencies and references** — prior work, tickets/PRs, patterns to follow, known gotchas,
     migration path for breaking changes
   - **Release and observe** — only when the change has deployment/operator implications: health or
     smoke checks, a rollback reference, operational owner, and post-release success/failure signal.
     This plans the handoff; it does not authorize deployment. Omit the section when irrelevant.

7. **Recommend the session effort and path** — a human action, reported to the user and recorded in the
   Execution Profile:
   - Choose the path using **Path Selection** in the loaded `ai-workflow-rules.instructions.md`
     (authoritative), or the linked bundled manual when the rule is unavailable. Do not maintain a
     second file-count threshold in this skill.
   - **Lightweight path (0→1→6→7→8)** — recommend `low`/`medium` effort.
   - **Full path (0→1→2→3→4→5→6→7→8)** — recommend `high`/`xhigh`/`max` effort.
   - One-line rationale. Remind the user to set the runner's effort level before starting execution.

8. **Delete what does not apply** — remove unused placeholder bullets and drop `## Overrides` entirely
   when there are none. A worktask full of unfilled brackets reads as noise and hides the real content.

9. **Confirm** — show the file path, key acceptance criteria, files/domains affected, estimated
   complexity, and the recommended effort + path.

## Quality bar before confirming

- [ ] Would a new AI coder execute this with only the worktask and its linked contexts?
- [ ] Does every listed context path exist? (Opened, not guessed.)
- [ ] Is every acceptance criterion testable and measurable?
- [ ] Does every acceptance criterion appear in the Validation table with a runnable check?
- [ ] Are source requirement IDs linked to criteria, with evidence honestly marked `not run`?
- [ ] Is the source of truth identified, with known revision/decision/owner and no invented approval?
- [ ] Are scope boundaries explicit — what is OUT as well as what is IN?
- [ ] Are the required test tiers named (L0/L1/L2) with what each must cover?
- [ ] Are dependencies and integration points concrete?
- [ ] Is the Execution Profile filled in — effort, path, subagents, commits, push, deployment boundary?
- [ ] Are all unfilled placeholder brackets gone?
- [ ] Does the worktask link the process template rather than restating its phases?
- [ ] Is `## Run Log` present and empty (the executing session appends to it)?

## Agent-agnostic notes

- The script is `bash` + coreutils only and finds the repo root via `git rev-parse` — Codex, Copilot
  and Cursor run it identically. It must stay executable (`chmod +x`).
- The original worktask-writing hook was removed in 2026-09. A shared `UserPromptSubmit` router
  now detects imperative requests in Claude Code and Codex and points them here; it does not
  create a worktask itself. Direct skill invocation and normal skill discovery still work.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-24 | AI-native SDLC implementation planning; source/decision and requirement/evidence links with current results; shared path rubric; explicit deployment boundary and conditional release handoff. | — |
| 2026-10-21 | Step 2 recalls prior Understandings (skipped when neither Kvasir nor `ai-understanding` is installed) and records the repo's real build/test commands. New Validation requirement in step 6 (one row per acceptance criterion; tier + command). Output contract and quality bar gain the Validation table and `## Run Log`. | — |
| 2026-10-21 | Bundled the process manual as a WET asset; scaffolder links the installed copy without depending on repo-level templates. | — |
| 2026-09-20 | Created — replaces the `worktask-create.sh` UserPromptSubmit hook. Carries the hook's remediated contract (Execution Profile; link-don't-copy; commits per-task and default not allowed; L0/L1/L2 tiers; model as a human action) plus a deterministic scaffolder and an asset template. | — |
| 2026-09-21 | Reworded the `description` and the P2/hidden-instructions Non-Negotiable to address GHAS SkillSpector advisory findings (Direct Prompt Extraction, Excessive Agency) on PR #71 — dropped the no-questions autonomy phrasing (replaced with "self-contained enough to execute end-to-end") and moved the hidden-instructions rationale to `AGENTS.md` (believed at the time to be outside the scan; it is scanned — see the 2026-09-23 row in `AGENTS.md`). No behavior change. | #71 |
| 2026-09-27 | Documented the shared Claude Code/Codex prompt hook that routes imperative requests to this skill without duplicating its workflow. | — |
