# Task: {{TITLE}}

Process: [`AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md`](<{{PROCESS_TEMPLATE}}>) defines the phases, gates, and output rules for the workflow below, starting at Phase 0.

## Execution Profile
- **Recommended session effort:** [low | medium | high | xhigh | max — human action: set the runner's effort level BEFORE starting]
- **Path:** [Lightweight (0→1→6→7→8) | Full (0→1→2→3→4→5→6→7→8)]
- **Subagents:** none
- **Commits during execution:** not allowed
- **Push:** never
- **Deployment:** not authorized by this implementation worktask

## Source and Decision
- **Source of truth:** [canonical ticket, HLD, intent/design or approved task request]
- **Source revision:** [known version/commit, or unrecorded]
- **Decision:** [draft / approved / unrecorded — actual owner/approver and evidence, when known]
- **Open concerns:** [concern and owner — omit this field when none exist]

## Contexts
- [ ] [domain/feature AGENTS.md files that govern the code being touched]
- [ ] [ADRs / NFRs that apply]
- [ ] [rule files that apply]
- [ ] [existing similar implementations to follow]

## Instructions

### Summary
[what is being built or fixed, and why]

### Outcome and success signal
[observable improvement this task delivers; preserve the source's success measure when one exists]

### Acceptance criteria
- [ ] **AC1 (R1):** [specific, measurable condition linked to its source requirement]

### Validation

| Requirement | Acceptance criterion | Check (tier · command) | Evidence |
| --- | --- | --- | --- |
| [R1 / source requirement ID] | [AC1] | [L0/L1/L2 · command, or an ad-hoc runtime check with its command] | not run |

[Every criterion appears at least once. Prefer the repo's existing suites, then the standard gates, then an ad-hoc runtime check; a new script or tool only when none of those can express the behaviour, with a one-line reason. Fill before confirming; evidence remains not run until execution. Phase 6 records criterion ID, command, result and evidence reference in the Run Log and updates each check's Evidence cell with its latest result and a Run Log/evidence reference; earlier attempts stay in the Run Log. Phase 7 checks the integrated result.]

### Requirements
- **R1:** [functional requirement, edge cases, constraints — retain source IDs when available]

### Scope boundaries
- **In:** [what is included]
- **Out:** [what is explicitly not included]

### Integration points
- [APIs, databases, services, message queues this connects to]

### Non-functional requirements
- [performance, security, compliance, scalability — only where this task puts an unusual demand on the attribute]

### Tests
- [required tiers: L0 (unit) / L1 (component) / L2 (integration), and what each must cover]

### Dependencies and references
- [work that must complete first; tickets/PRs; patterns to follow; known gotchas; migration path]

### Release and observe
[Only when deployment/operator implications exist: health/smoke checks, rollback reference, operational owner, post-release success/failure signal. This is a handoff plan, not release authorization. Delete the section when irrelevant.]

## Run Log

[Authoring guidance — delete this block when populating the scaffold so the section is empty. Execution appends criterion ID/command/result/evidence, loop-back cause/re-entry/outcome, user-only questions, approved deviations and Phase 7 findings. Phase 8's reflect step reads this.]

## Overrides

[Per-task deviations from the process template's constraints, each with a one-line reason. Delete this section if there are none.]

---

Created {{DATE}} · `{{SLUG}}`
