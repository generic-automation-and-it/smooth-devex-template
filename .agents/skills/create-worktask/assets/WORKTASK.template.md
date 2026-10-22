# Task: {{TITLE}}

Process: [`AI_WORKTASK_PROMOTE_STANDALONE_TEMPLATE.md`](<{{PROCESS_TEMPLATE}}>) defines the phases, gates, and output rules for the workflow below, starting at Phase 0.

## Execution Profile
- **Recommended session effort:** [low | medium | high | xhigh | max — human action: set the runner's effort level BEFORE starting]
- **Path:** [Lightweight (0→1→6→7→8) | Full (0→1→2→3→4→5→6→7→8)]
- **Subagents:** none
- **Commits during execution:** not allowed
- **Push:** never

## Contexts
- [ ] [domain/feature AGENTS.md files that govern the code being touched]
- [ ] [ADRs / NFRs that apply]
- [ ] [rule files that apply]
- [ ] [existing similar implementations to follow]

## Instructions

### Summary
[what is being built or fixed, and why]

### Acceptance criteria
- [ ] [specific, measurable condition]

### Validation

| Acceptance criterion | Check (tier · command) |
| --- | --- |
| [criterion above] | [L0/L1/L2 · command, or an ad-hoc runtime check with its command] |

[Every criterion appears at least once. Prefer the repo's existing suites, then the standard gates, then an ad-hoc runtime check; a new script or tool only when none of those can express the behaviour, with a one-line reason. Fill this table before confirming the worktask — Phase 3 only refines it on the full path — and Phase 7 runs it against the integrated result.]

### Requirements
- [functional requirements, edge cases, constraints]

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

## Run Log

[Authoring guidance — delete this block at scaffold time so the section is empty. Appended during execution: one line per entry — loop-back cause and re-entry phase, a question only the user could answer, a Phase 7 finding. Phase 8's reflect step reads this.]

## Overrides

[Per-task deviations from the process template's constraints, each with a one-line reason. Delete this section if there are none.]

---

Created {{DATE}} · `{{SLUG}}`
