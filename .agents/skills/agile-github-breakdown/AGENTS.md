# AGENTS.md - agile-github-breakdown

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — workflow, write gates, script contracts and exit codes live there.

## Non-Negotiables

- **Script changes run the L0 tests by hand — no workflow runs them.** `scripts/test_skill_scripts.py`
  covers parse/validate and the write script's pure helpers; nothing in it reaches `gh`. Add a case for
  any defect found, and keep `gh` calls out of tests.

## Architecture Decisions

### LADR-001 — Dry-run default; GitHub links fail soft

- **Status:** Accepted · **Date:** 2026-09-13
- **Decision:** No write without `--apply`. `link_sub_issue()` and `add_blocked_by()` return `False` and
  print a manual-link note instead of raising — some tokens cannot use those APIs.
- **Consequence:** Never make them hard-fail: an abort mid-run leaves created Tasks with no Feature
  parent and no report of what was created.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-09-13 | Ported from `epic-breakdown` onto vanilla GitHub Projects (Feature/Task; no Epic type); LADR-001 | — |
| 2026-10-15 | Cut to HLD shape: SKILL.md pointer + non-SKILL.md traps only | — |
| 2026-10-23 | FR table gains Priority, Release (optional) (synced from `epic-breakdown`); parser input stays ID + Requirement only — extra cells parse into the text at exit 0 | — |
