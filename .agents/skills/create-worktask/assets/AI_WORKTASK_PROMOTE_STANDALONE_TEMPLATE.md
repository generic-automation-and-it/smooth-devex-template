# Task: [one-liner task description]

## Execution Profile
- **Recommended session effort:** [low | medium | high | xhigh | max] — human action: set the runner's effort level BEFORE starting; raise it at a gate if a later phase needs more reasoning
- **Path:** Lightweight (0→1→6→7→8) | Full (0→1→2→3→4→5→6→7→8)
- **Subagents:** none | Explore (read-only fan-out) | worktree-isolated writers
- **Commits during execution:** not allowed | allowed via the git-commit skill
- **Push:** never
- **Deployment:** not authorized by this implementation worktask

## Source and Decision
- **Source of truth:** [canonical ticket, HLD, intent/design or approved task request]
- **Source revision:** [known version/commit, or unrecorded]
- **Decision:** [draft / approved / unrecorded — actual owner/approver and evidence, when known]
- **Open concerns:** [concern and owner — omit when none exist]

## Contexts
- [ ] list relevant context documents, domain files, or knowledge sources
- [ ] if needed context is missing, include creation only for lasting guidance that passes the AGENTS quality rule

## Instructions
- [ ] link source requirement IDs to acceptance criteria and validation commands; evidence starts as not run
- [ ] state scope, outcome/success signal and dependencies; include release/observe handoff only when relevant

## SDLC Stages and Scope

The Software Development Lifecycle (SDLC) has six non-linear stages. These development steps support that lifecycle; they do not implement deployment or production maintenance.

| SDLC stage | Development steps / boundary |
| --- | --- |
| Plan | Phase 1 clarifies product intent, outcome and constraints |
| Design | Phases 2–3 analyze constraints and specify requirements/design |
| Build | Phase 4 plans implementation; Phase 6 implements it |
| Test | Validation is defined before code, run during Phase 6, and checked against the integrated result in Phase 7 |
| Deploy | Phase 7 supplies pre-release review evidence; release authorization, deployment, health checks and rollback are separate |
| Maintain | Phase 8 records development lessons; operational metrics, incident triggers and remediation are separate |

Context loading and artifact/knowledge maintenance are cross-cutting. Keep the phase order within an execution pass; failed checks re-enter by **Loop Control**, not by restarting the lifecycle.

Use the existing ticket, HLD, intent/design record or approved task request as the source of truth. Link its identity/revision and known decision owner/status; do not fabricate approvals or require separate `intent.md`, `spec.md` and `plan.md` files for every task. Trace requirement IDs through acceptance criteria, checks and actual evidence. Keep local worktasks and their Run Log gitignored; put shared accepted decisions in the canonical record.

These gates are workflow instructions, not technical enforcement. Required action/release approvals need the project's actual hooks or external controls; creating or approving an implementation worktask does not itself authorize deployment.

## Constraints

### Load Context (Phase 0 — MANDATORY FIRST)
- **Load domain/feature context BEFORE asking clarifying questions** — you cannot ask intelligent questions without understanding existing patterns
- Use the `context-load-context` skill with `[domain]` to find/create functional context, or rely on the `load-agents-context` PostToolUse hook which auto-injects ancestor `*AGENTS.md` on first Read/Edit
- **Import prior Understandings** next: check `.context/understandings/INDEX.md`; when `mimisbrunnr-kvasir-understanding` is among your available skills, query the store with `import --query WORD` (read-only). Otherwise use `ai-understanding --import` on the local Understanding files. Skip silently when neither exists

### Git Behavior

`git-policy.instructions.md` is authoritative. Nothing in this template overrides it.

- **Commits** are governed by the **Commits during execution** field in the Execution Profile above. Default: **not allowed** — report the change set and stop; the user commits.
- When the field allows commits, make them by **invoking the `git-commit` skill**, never by composing a message inline — the skill runs conventional-format validation and logical-unit grouping.
- **Push: never.** Manual review is required before any push.

### Phase Output Rules (MANDATORY — no exceptions)

1. **Label every phase** — Output `## Phase N: Name` as a visible header before executing each phase
2. **Label every skip** — If skipping a phase, output: `## Phase N: Name — Skipped: [one-line reason]`
3. **Sequential execution** — Phases MUST execute in declared order. Never reorder, combine, or nest (e.g., doing Phase 5 work inside Phase 6 is a violation)
4. **No silent phases** — Every phase in your chosen path MUST appear in output. If the user can't see it, it didn't happen

> **FALLBACK copy.** `ai-workflow-rules.instructions.md` is authoritative. This copy exists for runners that do not auto-load `.agents/rules/` (e.g. Codex) and MUST be kept in sync with the rule on every workflow change.

### Execution Phases

Follow in order. **Do not skip phases without outputting the skip reason. Do not proceed without explicit user confirmation at gates.**

| Phase | Name | Gate? | Purpose | Who |
|-------|------|-------|---------|-----|
| 0 | Load Context | 🛑 MANDATORY | Read documents from **Contexts** section above | session |
| 1 | Clarify Intent (Odin) | 🛑 GATE | Consolidate domain/technical/test clarifications | session (PO → Architect → QA lenses, in sequence) |
| 2 | Analyze Constraints (Thoth) | | Analyze tech stack, determine tech requirements, identify patterns | session (read-only fan-out allowed) |
| 3 | Specify Requirements & Design (Forseti) | | Create requirements/design spec with source IDs, owned concerns and the **Validation** table | session |
| 4 | Plan Implementation (Tyr) | 🛑 GATE | Present implementation plan + module breakdown | session (per-stack lenses, in sequence) |
| 5 | Baseline Approved Artifacts (Frigg) | | Record the approved plan/decision in its canonical home; link source requirements | session |
| 6 | Implement & Verify (Thor) | | Bounded autonomous execution + actual check evidence | session (parallel writers only when worktree-isolated) |
| 7 | Validate & Review (Heimdall) | | Quality gate — review skill + Validation table + spec/implementation sync check | session + review skill |
| 8 | Record & Learn (Bragi) | 🛑 MANDATORY | Review context, record actual outcomes; then **Reflect**; obey the commit profile | session |

### Path Selection

Choose by risk and complexity first, file count second. This rubric is authoritative for worktask authoring and execution.

**Lightweight path**: Phase 0 → 1 → 6 → 7 → 8
Use for a clear, contained, low-risk fix or mechanical change following established patterns, with no architectural decision, new feature/pattern, complex logic or cross-cutting concern.

**Full path**: Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
Use for new features/patterns, architectural decisions, complex logic, cross-cutting concerns or ambiguous scope regardless of file count. Default to full for 3+ files; a purely mechanical change may use lightweight with a stated low-risk rationale. If unsure, choose full.

**Phase 8 is on BOTH paths.** Context review and recording remain mandatory; whether a context edit is warranted is decided by the quality rule, not the path.

**Path selection is NOT a way to avoid Phase 8.** Even a purely mechanical change across many config files must complete Phase 8. The path determines which middle phases (2–5) to run, not whether to document.

### Subagents

**Default: none.** Every subagent starts cold, re-derives context this session already holds, and returns only text. Spawn one only in these three shapes:

1. **Read-only fan-out** (Phase 2) — a broad sweep across many files or naming conventions where only the conclusion is needed, not the file dumps. `Explore` in Claude Code; the runner's read-only search agent elsewhere.
2. **Worktree-isolated parallel writers** (Phase 6) — each writer in its own git worktree, with an explicit merge step owned by the session. Without worktree isolation and a merge step, implement sequentially.
3. **Independent review** (Phase 7) — the runner's existing review skill, not ad-hoc reviewer agents.

**Parallelism means batching tool calls, not spawning agents.** Issue N independent reads, greps, or builds of unrelated projects in a single message. Sequence only when one call's output feeds the next. Never run two write operations against the same file, and never run concurrent `dotnet build` / `dotnet test` over the same solution.

Where a phase does spawn a subagent, carry an `effort:` hint on the same `low` → `medium` → `high` → `xhigh` → `max` scale as skill frontmatter — never a per-runner model. The subagent runs on the session's model. The *session* effort is not set by this file; it is a human action (the runner's effort setting), recorded in the Execution Profile.

### Loop Control

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

---

## Phase 1: Clarify Intent (Odin)

**No subagents.** One session applies three lenses in sequence over the context loaded in Phase 0, then consolidates them into a single question list. The deliverable is that list — three cold agents plus a merge produces less, later.

**Answer from the code before asking.** For each open question, search the repo and its context files first; surface only what the code cannot answer. Carry a recommended answer with every question so the user can confirm in one word.

### PO lens
- Business intent and value proposition
- Acceptance criteria and success metrics
- User stories and edge cases
- Scope boundaries (what's IN, what's OUT)
- Related business context or dependencies

### Architect lens
- Technical feasibility and constraints
- System integration points and dependencies
- Performance, scalability, or security implications
- Trade-offs between proposed approaches
- Impact on existing architecture

### QA lens
- Testing scope and coverage expectations
- Acceptance criteria validation (are they testable?)
- Test tiers required: L0 (unit), L1 (component), L2 (integration)
- Known edge cases or failure scenarios to cover
- Regression test impact

### Consolidation & Gate

```markdown
## Phase 1: Clarify Intent (Odin) — Consolidated Findings

### Business Clarifications
- [finding and question/recommendation]

### Technical Clarifications
- [finding and question/recommendation]

### Test Scope Clarifications
- [finding and question/recommendation]

### Assumptions validated
- [what was already clear, no question needed]

---

**Gate Question:**
Does this consolidated understanding capture your intent?
Reply 'approved' to proceed to Phase 2, or provide corrections.
```

**If requirements are already clear from the task description, state your understanding and proceed without waiting. Otherwise, wait for the user's response before proceeding.**

---

## Phase 2: Analyze Constraints (Thoth)

**Prerequisite:** Phase 1 clarifications resolved.

**Responsibilities:**

1. **Determine technology stack requirements** — this output selects the per-stack work in Phase 4:
   - Backend required? (Database changes, API endpoints, server-side logic, service integrations, message queues)
   - Frontend required? (User-facing UI changes, in whatever frontend stack this repo uses)
   - Infrastructure/DevOps required? (Deployment, configuration, CI/CD, security)
   - **Output**: Clear YES/NO for each, with justification

2. **Analyze existing patterns and conventions**:
   - Similar features already implemented — what patterns do they follow?
   - Existing architecture decisions (ADRs) that apply to this task
   - Code organization, naming conventions, testing patterns
   - Technology stack baseline (what's already in use)

3. **Identify architectural constraints and dependencies**:
   - How does this task integrate with existing systems?
   - Breaking changes or migration paths needed?
   - Performance or scalability constraints
   - Security/compliance considerations

4. **Verify, don't trust.** Subagent and document claims about versions, API support, or where a behavior originates are leads, not facts. Confirm cheaply with the real tool — build it, grep for the actual producer, read the vendor's docs — before building on them.

**Optional read-only fan-out.** This is the one phase where a subagent is routinely justified: if locating the relevant patterns means sweeping many directories or naming conventions, dispatch a read-only search agent and take its conclusion. Effort hint at that spawn point:

```yaml
effort: medium
```

**Output format:**

```markdown
## Phase 2: Analyze Constraints (Thoth)

### Technology Stack Requirements
- **Backend**: YES — [justification: DB changes, API endpoints, etc.]
- **Frontend**: NO — [justification: no UI changes]
- **Infrastructure**: NO — [justification: no deployment changes]

### Existing Patterns & Conventions
- Similar features: [list and reference]
- Relevant ADRs: [which decisions from code-review-standards.instructions.md apply]
- Code organization: [where should new code go]
- Testing patterns: [what test structure to follow]

### Architectural Constraints
- Integration points: [where this connects]
- Performance considerations: [if any]
- Security implications: [if any]
- Migration/breaking changes: [if any]

**Ready for Phase 3.**
```

**Exit check**: proceed to Phase 3 only if tech stack requirements are clear. (Self-check, not a user stop.)

---

## Phase 3: Specify Requirements & Design (Forseti)

**Prerequisite:** Phase 2 analysis complete (tech stack determined).

Carry forward unresolved concerns with their owners and show how each source constraint is met.

**Define validation with the specification — before any code exists.** Every acceptance criterion maps to a check, and each check names the criterion it proves. Prefer, in order: the repo's existing L0/L1/L2 suites; the standard build/lint/type gates; an ad-hoc runtime check; a purpose-built script or tool as a last resort, with a one-line reason the earlier options could not express the behavior. A green check that does not trace to a criterion is not evidence. This table is what Phase 6 executes and Phase 7 reviews against.

**Responsibilities:**

1. **Create technical specification** with architectural decisions:
   - Architecture diagram or data model changes (if applicable)
   - API contracts, database schema changes (if backend)
   - UI/component structure (if frontend)
   - Error handling and logging strategy (following backend-logging-conventions.instructions.md)

2. **Document architectural decisions** — Use LADR format:
   - Decision title
   - Context (why this decision is needed)
   - Decision (what was chosen)
   - Consequences (what changes as a result)
   - Reference to code-review-standards.instructions.md ADRs if applicable

3. **Define testing approach**:
   - Test tiers and coverage expectations
   - Edge cases and failure scenarios
   - Integration test requirements (if applicable)

4. **Specify constraints and non-functional requirements**:
   - Performance targets
   - Security requirements
   - Scalability considerations
   - Compliance/audit trail needs

**Output format:**

```markdown
## Phase 3: Specify Requirements & Design (Forseti)

### Technical Specification

[Include architecture diagrams, data model, API contracts, etc.]

### Architectural Decisions

**LADR-XXX: [Decision Title]**
- Context: [why this decision]
- Decision: [what was chosen]
- Consequences: [what changes]
- Related ADRs: [links to code-review-standards.instructions.md decisions]

[Additional LADRs if needed]

### Testing Approach
- Test tiers: [L0 (unit) / L1 (component) / L2 (integration) requirements]
- Coverage targets: [e.g., >80% for critical paths]
- Edge cases: [high-risk scenarios identified in Odin]

### Validation

| Requirement | Acceptance criterion | Check (tier · command) | Evidence |
| --- | --- | --- | --- |
| [source requirement ID / R1] | [AC1 from Phase 1] | [L0/L1/L2 · command, or an ad-hoc runtime check with its command] | not run |

[Every criterion appears at least once. A custom script appears only with its one-line justification.]

### Non-Functional Requirements
- Performance: [targets or constraints]
- Security: [requirements from clarifications]
- Scalability: [expectations for growth]

**Ready for Phase 4.**
```

**Exit check**: proceed to Phase 4 only if the specification is complete and aligns with Phase 1 clarifications. (Self-check, not a user stop.)

---

## Phase 4: Plan Implementation (Tyr) — 🛑 GATE

**Prerequisite:** Phase 3 specification complete.

**Sequence (one session, no subagents):**

1. **Create the overall implementation plan**:
   - Ordered list of implementation steps
   - Module/component breakdown
   - File-level changes and dependencies
   - Risk mitigation strategies
   - Estimated scope (files touched, effort)

2. **Apply a per-stack engineer lens for each stack answered YES in Phase 2**, in sequence — same session, same context:
   - Input: Phase 3 spec + overall plan
   - Output: a stack-specific plan — units to add or change, data/contract changes, tests, dependencies

3. **Reconcile the per-stack plans**:
   - Check integration points and conflicts between stacks
   - Adjudicate conflicts before presenting
   - Present the consolidated plan to the user

**Output format:**

```markdown
## Phase 4: Plan Implementation (Tyr)

### Overall Implementation Strategy
- Step 1: [implementation step] (File: X)
- Step 2: [implementation step] (File: Y)
- Dependencies: [what must complete before what]
- Risks: [identified risks and mitigation]

### Per-Stack Plans (one block per stack answered YES in Phase 2)

**[Stack]**
- Modules/units: [new or modified]
- Data & contract changes: [schema, API, message shapes, persisted state]
- Tests: [tier and location for each new behavior]
- Dependencies: [what this stack depends on, and what depends on it]

### Integration Points
- [How the stacks interact]
- [Conflict resolution if any]

**Gate Question:**
Does this plan look correct? Reply 'approved' to proceed, or provide feedback.
```

**Gate**: wait for user approval before proceeding to Phase 5.

---

## Phase 5: Baseline Approved Artifacts (Frigg)

**Prerequisite:** Phase 4 plan approved by user.

**Responsibilities:**

1. Record the approved plan, decision owner/status and source requirement references in the existing plan artifact or canonical tracker. Link that record from the worktask; do not duplicate it in `*AGENTS.md`.
2. Carry forward unresolved concerns with their owners; do not invent an approval or mark a draft accepted.
3. Keep architectural decisions in their existing HLD/LADR/ADR home. Update or create a decision record only when the design needs it.
4. Put only lasting, non-duplicated local constraints in `*AGENTS.md` under `meta/knowledge-conventional-contexts-quality.instructions.md`; temporary plans and adjacent design summaries do not belong there.

**Output format:**

```markdown
## Phase 5: Baseline Approved Artifacts (Frigg)

### Approved Artifacts
- Plan: [canonical location/revision and known approval]
- Source requirements: [IDs and design/intent reference]
- Open concerns: [owner and disposition, or none]

### Lasting Context Changes
- [Context file and changed guidance, or reviewed — no context changes needed]

**Ready for Phase 6.**
```

---

## Phase 6: Implement & Verify (Thor)

**Prerequisite:** Phase 5 documentation complete (or skipped with a reason).

**Bounded autonomous execution; sequential by default.** One writer works within the approved scope and action limits. Implement completely — no TODOs, no stubs. Batch independent *reads* freely; keep *writes* sequential. A new requirement or action outside those limits re-enters the appropriate gate. On failure, fix forward within the failing change; if 2 attempts have not resolved it, triage by **Loop Control** above instead of continuing to retry.

Run targeted checks as affected units become runnable, then run the applicable Validation table against the integrated result. Record criterion ID, command, result and evidence reference in the worktask's `## Run Log` (or phase output when no worktask exists); never turn an unrun check into a passing claim. Update each check's Validation table Evidence cell with its latest observed result and a Run Log/evidence reference; keep earlier attempts in the Run Log and unrun checks marked `not run`. For bug fixes, reproduce the failure before fixing when a regression test or runtime check can express it. UI changes need visual evidence when appearance is an acceptance criterion. Do not weaken a valid check to pass; justify any legitimate test correction against the requirement.

**Parallel writers are allowed only with worktree isolation plus an explicit merge step:**

- Each writer gets its own git worktree. **Never two writes to the same file**, within a worktree or across worktrees.
- **Never run concurrent `dotnet build` / `dotnet test` over the same solution.** Build and test once, in the session, after the merge.
- The session owns the merge step and the post-merge build + test run.
- **Weigh the cost first:** a .NET worktree pays a fresh `dotnet restore` per agent, and EF Core migration ordering still collides at merge — for most tasks sequential is faster end to end.
- Effort hint at that spawn point:

```yaml
effort: medium
```

**Output format:**

```markdown
## Phase 6: Implement & Verify (Thor)

### Implementation Complete
- [File 1]: [what was implemented]
- [File 2]: [what was implemented]
- Validation: [criterion ID · command · observed result · evidence reference]

**Ready for Phase 7 (Review).**
```

**No user gate** — and no commits either, unless the Execution Profile allows them.

---

## Phase 7: Validate & Review (Heimdall)

**Prerequisite:** Phase 6 execution complete.

**Invoke the runner's existing review skill on the diff** rather than spawning ad-hoc reviewer agents — `/code-review` in Claude Code, the equivalent review skill elsewhere. It already covers code quality, pattern consistency, security and test adequacy, and it reviews what was actually written.

Then apply the three checks a diff review does not cover:

1. **Specification sync** — does the implementation match the Phase 3 spec (or the task Instructions, if Phase 3 was skipped)? Are the LADR decisions honored? Any design issue introduced during execution?
2. **Validation** — run the Phase 3 **Validation** table against the integrated result. A criterion with no passing check is unmet, whatever the code looks like.
3. **Acceptance criteria** — is every criterion from Phase 1 demonstrably met, with tests at the right tier (L0 unit / L1 component / L2 integration)?

**Consolidation & Decision:**

- If all pass: proceed to Phase 8
- If issues found: triage by **Loop Control** above — local defects re-enter Phase 6, systemic ones Phase 2 — and append each finding to the worktask's `## Run Log`. Where triage does not settle it, present to the user with options:
  - **Option A**: Fix issues in a follow-up execution (re-run Phase 6 with feedback)
  - **Option B**: Accept known issues in the canonical decision record; update context only when guidance changes
  - **Option C**: Block and ask for clarification/requirements change

**Output format:**

```markdown
## Phase 7: Validate & Review (Heimdall)

### Review Skill Findings
- [finding + remediation, or "none"]

### Specification Sync
- ✅ Implementation matches Phase 3 spec
- ✅ Architectural decisions honored
- Issues (if any): [list with remediation]

### Validation
- [criterion]: ✅ [check + evidence] | ❌ [what failed, and its loop-control triage]

### Acceptance Criteria & Test Coverage
- Acceptance criteria: ✅ covered
- Edge cases: ✅ covered
- Test tiers: [L0/L1/L2 added or updated]
- Coverage %: [X%]

### Gate Decision
- ✅ Ready for Phase 8 (record)
- OR ⚠️ Issues found — [ask user for remediation approach]
```

---

## Phase 8: Record & Learn (Bragi) — 🛑 MANDATORY

**Prerequisite:** Phase 7 passed (or user approved known issues).

**Mandatory to perform — and it stops before committing.** Context review and recording are never skipped; committing happens only if the Execution Profile allows it.

1. **Review relevant context documents loaded in Phase 0**:
   - Update guidance made untrue by the change and add only newly necessary, non-duplicated constraints.
   - Follow `meta/knowledge-conventional-contexts-quality.instructions.md`; reading a file alone is not a reason to edit it.
   - If no guidance needs changing, record “reviewed — no context changes needed.”
   - If needed context did not exist, create it from `TEMPLATE_AGENTS.md` only when lasting local guidance passes the quality rule, and link it from the nearest governing context.

2. **Finalize decision records and artifact links**:
   - Confirm that LADRs/ADRs/NFRs reflect actual outcomes; update decisions changed by implementation in their existing home.
   - Record approved plan deviations, source revisions and validation evidence in the canonical record where applicable; do not fabricate an approval.

3. **Record actual implementation outcomes**:
   - Update the project's changelog with the implemented change, breaking changes or migration guidance when applicable.
   - Context-document changelog rows describe changes in guidance, not a duplicate implementation summary.
   - Report requirement/criterion coverage, commands and observed evidence from the worktask's Validation table and Run Log.

### Reflect (mandatory, after steps 1–3 and before the commit step)

Turn this run's friction into something that makes the next run lighter. Read the worktask's `## Run Log` when the run has one — otherwise the session's own phase output — and ask:

- Which Phase 1 question could the code or context have answered — would a `*AGENTS.md` line, an acceptance criterion, or a check have removed it?
- Which Phase 7 finding, or loop-back cause, could an existing gate have caught first?

For each, propose the smallest fix that prevents the repeat: a validation check in the worktask template, an L0/L1/L2 test, a rule entry, or a line in the nearest `*AGENTS.md`. Put the proposals in this turn's output; apply only the ones inside this change's scope. An applied proposal is a new change: run it through the Validation table, and **Loop Control** above on a failure, before the commit step.

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

### Commit or stop (last)

Per the Execution Profile's Commits field:

- **Not allowed (default):** report the change set — files touched, what changed, and a suggested commit grouping — then **stop**. The user commits.
- **Allowed:** commit by **invoking the `git-commit` skill** so conventional-format validation and logical-unit grouping run. Never compose commit messages inline. One logical unit per commit; include the worktask/ticket reference.
- **Push: never.**

**Output format:**

```markdown
## Phase 8: Record & Learn (Bragi)

### Context and Decisions Reviewed
- Context: [changed guidance, or reviewed — no context changes needed]
- Decision records: [actual outcomes and approved deviations, when applicable]
- Validation evidence: [criterion coverage and Run Log references]

### Changelog Entry
[Comprehensive entry for release notes]

### Change Set
- [File]: [what changed]
- Suggested commit grouping: [logical units]

### Reflection
- Prevention proposals: [each friction → the smallest fix that prevents it]
- Understanding capture: [route used (Kvasir at <path> | ai-understanding | unavailable — claims listed above), or "nothing durable"]
- Proposed store export: [folder + yes/no, or "n/a"]

### Commits
- Commits not allowed by this worktask — change set reported above, awaiting the user
- OR: [conventional message per commit, created via the git-commit skill]

### Task Complete ✅
[Change set ready for review | Commits created on [branch]; push not performed.]
```

---

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this template.

| Date | Task | Changes |
|------|------|---------|
| 2026-10-24 | SDLC development alignment | Descriptive phase labels; lifecycle boundaries and current Evidence cells; shared risk-based paths with mechanical exception; plans outside AGENTS; bounded execution and value-gated context edits. |
| 2026-05-30 | | Initial version. |
| 2026-09-20 | Worktask template & hook remediation | Removed the git-policy override and the autonomous-commit instructions — commits are now a per-task Execution Profile field routed through the `git-commit` skill, push never. Added `## Execution Profile`, replacing the 17-row phase/model table and the fabricated cost/quality metric; model hints now bind only at spawn points, in the per-runner `claude:`/`copilot:`/`codex:` form. `Agent Fleet Autonomy` → `Subagents` (default none, three justified shapes; parallelism means batched tool calls). Phases 1/4/7 no longer spawn specialist rosters; Phase 6 is sequential unless worktree-isolated with a merge step; Phase 7 delegates to the runner's review skill. Genericized the frontend/stack specifics. `load-context` → `context-load-context`; test tiers corrected to L0 unit / L1 component / L2 integration. Self-check "Gate"s renamed to "Exit check". Added the FALLBACK banner naming `ai-workflow-rules.instructions.md` authoritative, plus this `## Changelog` heading. |
| 2026-09-27 | Model → effort | The Execution Profile recommends a session **effort** (`low` → `max`, set via the runner's effort setting) instead of a model, and the Phase 2/6 spawn-point hints are `effort: medium` instead of a per-runner `claude:`/`copilot:`/`codex:` model block. Subagents run on the session's model. |
| 2026-10-21 | Validation, loop control, reflect | Phase 0 imports prior Understandings. Phase 1 answers from the code first and carries a recommended answer per question. Phase 2 verifies subagent/document claims. Phase 3 defines the **Validation** table (criterion → check, in preference order) before any code. New **Loop Control** section (local → Phase 6, systemic → Phase 2, new-user-question → Phase 1; caps 5 / 3 per root cause; each recorded in `## Run Log`). Phase 6 triages instead of stopping after 2 attempts. Phase 7 runs the Validation table and reviews against the spec, not the diff alone. Phase 8 adds the mandatory **Reflect** sub-step (prevention proposals + Understanding capture via Kvasir's `dump --currentsession` when the skill resolves at any of four locations, else `ai-understanding --export`). |
| 2026-10-22 | PR 133 review | Phase 8 runs **Reflect** after recording steps 1–3 and before the commit step, which is now the last subsection (*Commit or stop*). Before, Reflect followed the default profile's "then stop" and never ran, or ran after the commit when commits were allowed. An applied proposal goes through the Validation table before committing. The output block lists Reflection before Commits. |
| 2026-10-22 | PR 133 review | Reflect step 5 no longer assumes `ai-understanding` exists — the installer ships neither provider. When neither Kvasir nor `ai-understanding` is installed, the run lists its durable claims in the output and reports capture as unavailable. |
