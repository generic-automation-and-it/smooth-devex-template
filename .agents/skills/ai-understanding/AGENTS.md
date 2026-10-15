# AGENTS.md - ai-understanding

## TL;DR

Read [`SKILL.md`](./SKILL.md) first — switches, store layout, the reconcile/export/import/publish/consume procedures and guardrails live there.

## Non-Negotiables

- **Task-start import is wired outside this skill.** The trigger is the host repo's root `AGENTS.md`
  `## Understandings` section; the governance rule attaches only on `**/*understanding.md` (LADR-013),
  which `INDEX.md` does not match. Nothing checks the root section — a port without it installs a store
  nothing reads. Add it first when porting.
- **SKILL.md's contract is restated in three files that drift.** `agents/openai.yaml` `default_prompt`
  (the Codex export contract), `references/publish-consume.md`, and
  `.agents/rules/meta/understandings.instructions.md` (import precedence). A change to outcomes, fields,
  paths or precedence sweeps all three; a missed sweep has shipped before (stale Codex index command).
- **The generator's parser is hand-rolled stdlib and has no automated tests.** It is line-based, so
  every template placeholder must open `<` and close `>` on one line — a wrapped one fails
  `placeholder()` and is accepted as filled in. Verify generator changes by hand against a temporary
  store; `parse_frontmatter`'s list-under-key branch breaks silently (drops `links`).

## Architecture Decisions

### LADR-001 — Working store is local and disposable; publish is the durability boundary

- **Status:** Accepted — destination superseded by LADR-008 · **Date:** 2026-09-19
- **Decision:** The store is the gitignored `.context/understandings/`; leaving the workspace is a
  separate `--publish`. No mode writes to a tracked path.
- **Consequence:** a tracked store (e.g. `.agents/understandings/`) turns unreviewed session
  observations into shared repo memory.

### LADR-006 — Publish defaults to every unit; `--portable-only` filters for cross-repo

- **Status:** Accepted · **Date:** 2026-09-19
- **Decision:** `--publish` archives all units; `--portable-only` restricts to `scope: portable`.
- **Consequence:** do not flip the default to portable-only "for safety" — the common case is a
  same-repo handoff, and that default cut a real 8-unit store to 1, dropping the build/CI knowledge.

### LADR-007 — Subject folder is stamped when created

- **Status:** Accepted — uniqueness and folder-reuse clauses superseded by LADR-010 · **Date:** 2026-09-19
- **Decision:** `<subject>-<yyyyMMdd-HHmm>`, 24-hour UTC, set once; `_unfiled` exempt; publish never re-stamps.
- **Consequence:** only the stamp rules stand; "reuse the existing stamped folder" is void.

### LADR-008 — Publish is a zip under `.context/`; the store is never shared through the repository

- **Status:** Accepted — agent procedure, no script · **Date:** 2026-09-19
- **Decision:** `--publish` writes `understandings-<YYYYMMDD-HHMMSS>.zip` to
  `.context/understandings-publish/`; `--consume` takes a local zip path only. `ai-asset-sync` does
  not transport Understandings.
- **Consequence:** adding remote fetch or a transport here creates a second provenance and merge model
  beside `ai-asset-sync`'s.

### LADR-009 — A specified destination is the approval

- **Status:** Accepted · **Date:** 2026-09-19
- **Decision:** `--path` is the one target override for `--export`/`--publish`/`--consume`, never a
  source. Writing to a default or `--path` location asks nothing; every write is reported. Only promote
  and a consume that would make an incoming copy current still ask.
- **Consequence:** the generator's `[store-dir]` stays positional, not `--path` — aligning it breaks
  every command already written against it.

### LADR-010 — An export run is a stamped folder; a slug is a version key

- **Status:** Accepted — supersedes LADR-007's uniqueness and folder reuse · **Date:** 2026-09-19
- **Decision:** Each run writes a new folder holding only its new/improved units; an improved unit is
  re-written in full with `provenance.supersedes`; old copies are never edited or deleted; the index
  shows the newest copy per slug. Rejected: merge-in-place (rewrites history, loses revision depth).
- **Consequence:** never restore a store-wide duplicate-slug check — it disables versioning. A typo'd
  slug colliding with unrelated knowledge is now uncaught by design; only the reconcile step guards it.

### LADR-011 — `--all` widens the qualifying bar, not only the ask

- **Status:** Accepted · **Date:** 2026-09-20
- **Decision:** `--all` waives the user's cut and loosens the agent's bar; exclusions report as
  `has another home`, naming the file.
- **Consequence:** rejected — `--all` bypassing the qualifying test entirely; it would admit toolchain
  and already-homed knowledge.

### LADR-012 — Durability and redaction are write-time; the body carries no paths

- **Status:** Accepted · **Date:** 2026-09-21
- **Decision:** A path that is the knowledge goes in `agents_context`, which the generator
  existence-checks; redaction happens at write, the pre-publish check is the second net.
- **Consequence:** do not add a path-shaped-string check on the body — prose legitimately names files
  (`Project.slnx`), so it fires on correct units and trains agents to ignore the problem list.

### LADR-013 — A unit file carries a `.understanding.md` postfix

- **Status:** Accepted · **Date:** 2026-09-22
- **Decision:** `<slug>.understanding.md`, mirroring `.instructions.md`; the governance rule is scoped
  `**/*understanding.md`. `INDEX.md` and `<slug>.assets/` keep their names. Rejected:
  `<slug>-understanding.md` — a hyphen reads as part of the slug.
- **Consequence:** the rule no longer always-applies — see the task-start Non-Negotiable.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-09-19 | Initial: `.context/` store, generated index, scope-gated publish (LADR-001) | #68 |
| 2026-09-19 | `--export`/`--import` session↔disk; `--publish`/`--consume` cross-workspace | #68 |
| 2026-09-19 | Unit is a question/answer pair (`trigger`→`question`); product knowledge only; outcomes admitted | #68 |
| 2026-09-19 | LADR-006: publish defaults to every unit; `--portable-only` | #68 |
| 2026-09-19 | LADR-007: UTC creation stamp on subject folders | #68 |
| 2026-09-19 | LADR-008: publish is a zip under `.context/`; tracked destination retired | #68 |
| 2026-09-19 | LADR-009: `--path` target override; named destination is the approval | #68 |
| 2026-09-19 | LADR-010: slug is a version key; history immutable, exempt from validation | #68 |
| 2026-09-19 | Generator: generic reference walk, flow-sequence and quoted-reference detection, `--review` | #68 |
| 2026-09-20 | LADR-011: `--all` widens the bar; `has another home` outcome | #70 |
| 2026-09-21 | LADR-012: path-free body, write-time redaction; `recheck`, `skills` fields | #76 |
| 2026-09-22 | LADR-013: `.understanding.md` postfix; rule scoped `**/*understanding.md` | #78 |
| 2026-09-22 | Placeholder in `provenance.inherited` rejected and skipped; template placeholders single-line | #80 |
| 2026-10-15 | Cut to HLD shape: SKILL.md pointer + non-SKILL.md traps only | — |
