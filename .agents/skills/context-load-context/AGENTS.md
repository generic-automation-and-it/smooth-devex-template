# AGENTS.md - context-load-context

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — discovery, the BLOCK prompt and creation steps live there.

## Non-Negotiables

- **The `*AGENTS.md` naming and template path are shared, not owned here.** The same pattern drives the
  `context-load-agents-context` hook's `find` and the knowledge rule's glob; `.agents/templates/TEMPLATE_AGENTS.md`
  is also hard-coded in `.agents/hooks/agentmd-create-update.sh`. Changing either here alone splits
  interactive and automatic loading.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-06-12 | Initial | #40 |
| 2026-06-17 | Pattern `*_AGENTS.md` → `*AGENTS.md` | #46 |
| 2026-10-15 | Cut to HLD shape: SKILL.md pointer + non-SKILL.md traps only | — |
