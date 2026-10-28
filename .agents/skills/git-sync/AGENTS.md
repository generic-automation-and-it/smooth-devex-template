# AGENTS.md - git-sync

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — the `safe-sync.sh` sentinel contract, both modes and the resolution strategy live there.

## Non-Negotiables

- **Never add `git merge --abort` to `scripts/safe-sync.sh`.** Conflicts stay unmerged in the
  working tree on purpose: Mode 2 (`--fix`) resolves from that state, and Mode 1 hands the same
  state to the user. An abort on conflict silently disables `--fix`.
- **Commit-then-retry delegates to the git-commit skill; never commit inline, never stash.**
  A direct `git commit` bypasses logical-unit grouping and the `--autonomous` bypass; `git stash`
  hides user work where the next run cannot see it. One retry only — a second MERGE_ERROR stops.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-06-12 | Initial | #40 |
| 2026-10-15 | Mode 2: analyse commit intent on both sides before resolving | #95 |
| 2026-10-15 | Cut to HLD shape: SKILL.md pointer + non-SKILL.md traps only | — |
| 2026-10-16 | MERGE_ERROR (dirty tree): commit via git-commit skill, then retry once | — |
| 2026-10-28 | `--autonomous` documented in Arguments (already forwarded to git-commit) | — |
