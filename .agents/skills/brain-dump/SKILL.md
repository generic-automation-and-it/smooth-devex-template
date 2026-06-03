---
name: brain-dump
description: Start and run a listen-first braindump session for tickets, issues, ADRs, worktasks, PR descriptions, requirements, designs, or implementation plans. Use when the user says they want to braindump, think out loud, capture rough requirements, or provide context incrementally before asking the agent to synthesize, update a ticket, create docs, or perform implementation work.
---

# Brain Dump

## Core Posture

Run a low-friction capture session. The user is thinking out loud; do not prematurely organize, debate, or act.

Default behavior:

- Acknowledge that the session is active.
- State that you will listen and hold context until explicitly asked to synthesize or update an artifact.
- Do not modify tickets, files, docs, code, or remote systems during the listening phase.
- Keep responses short while the user is dumping context.
- Preserve rough phrasing, intent, trade-offs, decisions, open questions, and contradictions.
- Treat later user corrections as authoritative.

## Session Phases

### 1. Initialize

When the user starts a braindump, reply briefly:

```text
Absolutely. Braindump away.

I’ll listen and hold the context for [target if known]; I won’t update anything until you explicitly ask me to.
```

If the target artifact is ambiguous, still start listening. Do not block the session unless acting later would be impossible without clarification.

### 2. Listen

For each braindump message:

- Confirm capture in one or two sentences.
- Summarize only the newly added information or the evolving theme.
- Do not produce a full requirements spec unless asked.
- Do not ask clarifying questions by default.
- Do not browse, inspect code, or use external tools unless the user asks you to compare against current reality, validate feasibility, or prepare for synthesis.

Good listening response:

```text
Captured. Adding that the pre-pipeline should fetch the diff with patch data, detect `configuration.json`, and continue normally unless deeper analysis is requested later.
```

### 3. Compare Or Clarify

If the user asks whether there are questions, whether the dump matches the current solution, or whether anything is unclear:

- Inspect the relevant local code/docs or remote issue only as needed.
- Ask targeted questions grounded in discovered reality.
- Keep questions concrete and numbered.
- Separate true blockers from wording improvements.
- Do not update artifacts yet unless explicitly asked.

Question style:

```text
Yes, a few clarifying questions before we finalize the dump:

1. Should the old flag be removed entirely or kept as a compatibility alias?
2. When detection succeeds, should this ticket only log and continue, or should it suppress dispatch?
```

### 4. Synthesize On Request

Only when the user asks to update/create/synthesize an artifact:

- Confirm the target if multiple were mentioned.
- Use the accumulated context and any final decisions.
- Produce the requested artifact directly: issue description, ADR, worktask, PR body, implementation checklist, acceptance criteria, etc.
- Preserve decisions and non-goals explicitly.
- Include open questions only when still unresolved.

If the user asks to update a live ticket or file, perform the update with the appropriate tool and report the exact target changed.

## Capture Model

Maintain a mental running capture with these buckets:

- Target artifact or ticket
- Problem statement
- Desired behavior
- Defaults and configuration
- Current-system references
- Implementation shape
- Tests and documentation
- Decisions made during clarification
- Open questions
- Explicit non-goals

Do not expose the whole capture every turn. Surface it when the user asks to finalize, review, or synthesize.

## Guardrails

- Do not treat a braindump as permission to implement.
- Do not clean up the user's rough wording during the listening phase except in tiny confirmations.
- Do not over-question early; braindumps often become clear after several messages.
- Do not lose changed targets. If the user later names a different issue or file, use the latest explicit target and mention the switch.
- If the user asks you to "just listen," obey that even when you notice likely issues.
- If the user asks you to compare against code, tools are allowed, but final output should still be questions or observations unless they ask for edits.

## Finalization Output

When finalizing requirements, prefer this shape unless the requested artifact has its own format:

- Requirement Specification
- Functional Requirements
- Implementation Notes
- Documentation Updates
- Acceptance Criteria
- Non-Goals
- Open Questions, only if any remain

Keep the final artifact specific enough for another engineer or agent to execute without needing the whole conversation.
