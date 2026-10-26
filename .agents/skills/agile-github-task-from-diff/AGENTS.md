# AGENTS.md - agile-github-task-from-diff

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — flags, workflow, branch rename and gotchas live there.

## Non-Negotiables

- **Backend detection is hard-coded to this template's layout.** The `src/`/`Project` prefix check
  appears twice in the script — `classify_horizontal_slice()` and the acceptance-criteria checklist.
  A repo rename or ported layout updates both, or backend diffs lose the `backend` layer: no `feat`
  branch suggestion and no build-check criterion.
- **Script changes run the L0 tests by hand — no workflow runs them.** Tests patch the module's
  `run`/`run_json` and never reach `gh`/`git`; keep new tests that way.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-06-12 | Initial; branch-rename derivation moved into the script (`suggest_branch_name`) | — |
| 2026-09-23 | Sub-issue link by database `id`; missing label soft-fails; L0 tests | #81 |
| 2026-09-27 | `--noparentid`; `build_parser()`/`parse_args(argv)`; `effort` replaces `models` | #83 |
| 2026-10-15 | Cut to HLD shape: SKILL.md pointer + non-SKILL.md traps only | — |
| 2026-10-26 | `--body-file`: file-sourced task, diff not read | — |
