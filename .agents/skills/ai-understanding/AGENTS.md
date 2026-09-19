# ai-understanding — AGENTS.md

## TL;DR

`--export` analyses a session and writes its discovered knowledge as slug-folders under the gitignored `.context/understandings/`; the store is disposable by design, so `--publish` is the only path by which knowledge leaves a workspace — never weaken the `scope` gate that governs it.

## Non-Negotiables

- **Never make the store flat.** `<slug>/UNDERSTANDING.md`, not `<slug>.md`. Understandings carry evidence files (repro, log excerpt, diagram); a flat store forces those into one shared directory where two slugs eventually claim the same filename. The folder is the namespace, and this was an explicit design correction — not an incidental layout choice.
- **Never let a write overwrite an existing slug.** Merge on matching trigger, disambiguate otherwise. An edit that adds an "overwrite" or "force" path deletes knowledge the user chose to keep.
- **Never default `--publish` to include `repo-specific` units.** That flag is the only thing preventing a local quirk from being shipped with provenance that makes it look universally verified.
- **Never add remote fetching to this skill.** Remote consumption routes through `ai-asset-sync`'s manifest. Two transport implementations means two provenance models and two merge semantics.

## Architecture Decisions

### LADR-001 — Working store is local and disposable; publish is the durability boundary

- **Date:** 2026-09-19 · **Status:** Accepted
- **Context:** Understandings could live in a tracked path (`.agents/understandings/`, syncable immediately) or in the gitignored `.context/` tree. A tracked store makes every encoded unit instantly shareable — and instantly permanent. Most of what a session produces is not worth keeping, and review pressure at encode time is exactly when the knowledge is least settled.
- **Decision:** The working store is `.context/understandings/` (local, gitignored, per-workspace) and `--export` writes the session's knowledge there. Reaching a tracked path is a separate, human-approved `--publish` step, with `.agents/understandings/` as the default destination.
- **Consequences:** Encoding stays cheap and low-stakes, so agents propose freely. Review happens once, at publish, when it is clear which knowledge held up. Trade-off: a workspace destroyed before its publish loses its memory — accepted, because the alternative pollutes shared memory with unreviewed observations. The tracked destination is created on first publish; nothing is seeded, so a repo that never publishes carries no empty scaffolding.

### LADR-002 — `scope` is a first-class field, not a judgment made at publish time

- **Date:** 2026-09-19 · **Status:** Accepted
- **Context:** Deciding portability when publishing means judging units long after the session that produced them, with none of the context that would reveal whether a behavior was general or an artifact of this repo's setup.
- **Decision:** Every Understanding declares `scope: portable | repo-specific` at export time, while the evidence is fresh. Publish filters on the field rather than re-deciding.
- **Consequences:** Publishing is mechanical and auditable. The judgment sits where the information is. Bias toward `repo-specific` when unclear: leaving knowledge behind costs one rediscovery, while publishing a false universal costs every consumer that acts on it.

### LADR-003 — `INDEX.md` is generated, and is a reference table only

- **Date:** 2026-09-19 · **Status:** Accepted
- **Context:** An index maintained by hand drifts from the units, and an index that inlines the knowledge defeats its own purpose — an agent that must read the whole index to find one applicable Understanding has already paid the tokens it was trying to save.
- **Decision:** `scripts/understanding_index.py` regenerates `INDEX.md` from frontmatter. Rows carry folder, description, trigger, scope, confidence, updated — reference data for matching, never the knowledge itself. `trigger` lives in frontmatter only, so the index cannot contradict the unit.
- **Consequences:** Importing is a two-step read: match triggers in the index, then open only matching folders. The script validates as it goes (required fields, slug/folder agreement, enum values, dangling `[[links]]`) and exits `1` on problems while still writing the index, so drift surfaces without blocking the write. There is no INDEX template — the generator is the single source.

## Key Behaviors

- **"Understanding" is a term of art, borrowed from Adrian Tchaikovsky's _Children of Time_.** In the novel an Understanding is knowledge distilled and passed to a generation that never had the experience which produced it — which is exactly the contract here: the originating session is discarded, the transferable knowledge survives. Do not "clarify" the name to `learnings`, `notes`, `lessons`, or `memories`. Those all invite session logs; this one does not, and the distinction between a log and an Understanding is the whole design.
- **Understandings are evidence; rules are orders.** The governance half of this design lives in `.github/instructions/meta/understandings.instructions.md`, not here, because importing must work at session start without anyone invoking the skill. Editing one side without the other splits the contract.
- **A session splits into several slugs.** One Understanding per trigger, each standing alone, tied together by a shared `provenance.session` and `[[slug]]` links. Merging a session's lessons into one unit to keep the count down produces a unit whose trigger matches everything and therefore nothing.
- **Consumed units land as `confidence: observed`,** whatever they claimed at the source. They were verified against a setup that may differ.
- **Promotion is the exit, not a cleanup chore.** An Understanding proven across many tasks belongs in a `*AGENTS.md` or a rule, which load without a skill invocation. Leaving it in the disposable store means re-earning it every workspace.
- **Export/import are session↔disk; publish/consume are repo↔repo.** The first naming made `--export` mean "copy to a tracked path", which reads as publishing to anyone who thinks of export as getting a session's memory out of the conversation — the switch did not do what its name promised, and the mode was invoked expecting analysis. Do not collapse the two pairs back together.
- **The frontmatter parser is deliberately minimal** (flat scalars, one nesting level, list items) because PyYAML is not available in this environment. Adding a frontmatter field with deeper structure requires extending the parser, not just the template.

## Test References

No automated tests. The generator's validation paths (missing/placeholder fields, slug-vs-folder mismatch, invalid `scope`/`confidence`, missing `UNDERSTANDING.md`, dangling links, empty store, absent store) were exercised manually against fixtures. Re-run them after touching `parse_frontmatter` — the list-under-key branch in particular is easy to break in a way that silently drops `links` instead of erroring.

## Changelog

| Date | Change | Ref |
|:-----|:-------|:----|
| 2026-09-19 | Initial version. Slug-folder store under `.context/`, generated reference index, `scope`-gated publish, consumption via `ai-asset-sync`. | |
| 2026-09-19 | Recorded the _Children of Time_ provenance of the term, to stop the name being genericized into something that invites session logs. | |
| 2026-09-19 | Renamed the switches: `--export`/`--import` now mean session↔disk (analyse the session / load it back), and the cross-repo operations became `--publish`/`--consume`. The original `--export` was invoked expecting session analysis and produced nothing. | |
