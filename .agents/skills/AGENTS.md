# AGENTS.md - .agents/skills

## TL;DR

Read [`README.md`](./README.md) first — skill index, switches, effort levels and frontmatter shape live there.

## Non-Negotiables

- **Never silence a SkillSpector finding by removing a skill's capability.** If the flagged behavior is
  the skill's job (shell out to `gh`, swap a symlink, refresh a template dir), keep it and baseline it
  per [skillspector-pre-pr](../../.github/instructions/skills/skillspector-pre-pr.instructions.md). A green
  gate bought by gutting a skill is a failure.

## Architecture Decisions

### LADR-001 — Gate on the deterministic static scan; LLM semantic stage is advisory

- **Status:** Accepted · **Date:** 2026-06-21
- **Decision:** The gate runs `--no-llm` against `.github/skillspector-baseline.yml`; the LLM scan runs
  separately, non-blocking, and never affects the decision. Gating on it re-breaks the gate on every
  model/prompt drift with no skill change.
- **Consequence:** a semantic-only dangerous pattern surfaces in the advisory summary for human review,
  not as a block. Hard-blocking on it means baselining LLM findings and re-triaging on drift.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-06-21 | Initial; SkillSpector baseline gate; secret-handling guardrail | #52 |
| 2026-06-21 | LADR-001: static gate, LLM advisory (policy A) | #52 |
| 2026-07-31 | SARIF omits baselined findings instead of `suppressions` | #57 |
| 2026-09-13 | `ai-asset-sync`: first secret consumer, env-only | #66 |
| 2026-09-19 | `ai-understanding` added; store gitignored under `.context/` | #68 |
| 2026-09-22 | `create-worktask` added; its `assets/` is HTML-comment-free (no `P2` baseline entry) | #74 |
| 2026-09-27 | `effort` replaces `models`; no `model:` in `agents/openai.yaml` | #83 |
| 2026-09-27 | Secret-handling audit: model processes isolated from credentials | #85 |
| 2026-10-15 | Cut to README pointer + LADR-001; skill-specific facts moved to each skill's AGENTS.md | — |
