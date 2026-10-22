# AGENTS.md - create-worktask

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — the worktask contract, workflow and quality bar live there.

## Non-Negotiables

- **Cross-file sync:** Execution Profile, Validation and `## Run Log` changes span `SKILL.md`,
  `assets/WORKTASK.template.md` and both process manuals (bundled asset + `.agents/templates/`).
  **Loop Control and Reflect live in three workflow documents** — both manuals and the authoritative
  `ai-workflow-rules.instructions.md`; an edit to either must land in all three. The asset renders the
  shared manual's HTML-comment guidance visibly.
- **Scanner caveat:** SkillSpector scans this `AGENTS.md` too; moving flagged text here does not hide it.
- **Rename coupling:** `.agents/hooks/worktask-skill-trigger.sh` hard-codes this skill's `SKILL.md` path;
  update it when renaming or moving the skill.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-21 | Validation table + `## Run Log` in contract; Loop Control/Reflect sync spans three docs | — |
| 2026-10-21 | WET-copy sync coupling; removed SKILL.md restatements | — |
| 2026-09-20 | Initial; replaces the Claude-only `worktask-create.sh` hook | #74 |
| 2026-09-21 | P2 hidden-instructions rationale moved here from SKILL.md; `AGENTS.md` is scanned too | #71 |
| 2026-09-23 | Static-gate findings cleared: EA2 reworded; P6/MP2 baselined | #82 |
| 2026-09-27 | Execution Profile `Recommended session model` → `Recommended session effort` across the three files | #84 |
| 2026-09-27 | Shared Claude Code/Codex prompt router restored | #87 |
| 2026-10-15 | Cut to HLD shape: SKILL.md pointer + non-SKILL.md traps only | — |
