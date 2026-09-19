# ai-understanding — AGENTS.md

## TL;DR

`--export` analyses a session and writes its discovered knowledge to `<subject>/<slug>/` folders under the gitignored `.context/understandings/`; the store is disposable by design, so `--publish` is the only path by which knowledge leaves a workspace — never weaken the `scope` gate that governs it.

## Non-Negotiables

- **Never flatten either tier.** `<subject>/<slug>/UNDERSTANDING.md`. Dropping the leaf folder puts evidence files (repro, log excerpt, diagram) from different units in one directory, where they eventually claim the same filename. Dropping the subject folder loses the session's coherence. Both tiers were explicit design corrections from the user — not incidental layout choices.
- **Never make the index subject-first for retrieval.** The index groups by subject for browsing, but lists every leaf with its trigger, because an agent hitting a tooling quirk has no reason to open the subject folder that produced it. An edit that makes a reader open a subject before seeing triggers files knowledge under the one label nobody searches by.
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
- **Consequences:** Importing is a two-step read: match triggers in the index, then open only matching folders. The script validates as it goes (required fields, slug/folder agreement, enum values, store-wide slug uniqueness, dangling `[[links]]`, and units left at the old single-level depth) and exits `1` on problems while still writing the index, so drift surfaces without blocking the write. There is no INDEX template — the generator is the single source.

### LADR-004 — Subject tier groups; the trigger still retrieves

- **Date:** 2026-09-19 · **Status:** Accepted
- **Context:** A session usually has one main subject, and splitting its lessons into sibling top-level folders loses that — the work reads as five unrelated facts a month later. The obvious fix, making the subject the addressable unit with several Understandings inside it, breaks two things: retrieval (most of what a session teaches applies to work that has nothing to do with the session's subject) and publish granularity (one subject folder routinely mixes `portable` and `repo-specific` units, so it cannot be moved wholesale).
- **Decision:** Two levels — `<subject>/<slug>/UNDERSTANDING.md`. The subject groups for browsing; the leaf stays the addressable unit for retrieval, merging, `[[links]]`, scope filtering, and confidence. The generated index groups by subject but lists every leaf with its trigger. Leaf slugs are unique store-wide, so a link or a merge never needs to name the subject.
- **Consequences:** A session stays legible as a unit without knowledge becoming findable only through its origin. Cost: paths are deeper, every Understanding needs a subject (`_unfiled/` absorbs the ones with no topic), and the generator walks two levels. Units left at the old single-level depth are reported as a problem naming the fix rather than silently skipped.

### LADR-005 — Record inherited lineage, not the session's reasoning

- **Date:** 2026-09-19 · **Status:** Accepted
- **Context:** Import wrote nothing back, so the store had no evidence of which knowledge was ever used — a unit nothing inherits is indistinguishable from one that simply has not come up, which makes pruning guesswork and leaves no blast radius when a unit turns out wrong. A proposed alternative modelled the export on the novel's generational framing with four dimensions per unit: inherited knowledge, the conflict encountered, the cost-benefit reasoning behind the agent's adaptation, and the resulting lesson.
- **Decision:** Take the lineage only. `provenance.inherited` lists the `[[slug]]`s a session loaded **and acted on**. The other three dimensions are rejected: "the conflict encountered" and "the reasoning behind the adaptation" are agent-centric — they record what the agent did and why it adapted, which is a session log with better vocabulary — and "the resulting lesson" is the Understanding itself under another name.
- **Consequences:** One optional list buys a usage signal, a lineage graph, and the ability to find what depended on a unit later found wrong. The store stays knowledge-centric: what is true and when it applies, never the journey that produced it. A bracketed entry must resolve; unbracketing records an ancestor that has since been pruned or promoted, so removing a unit does not either break the index permanently or force rewriting history. Not adopted: machine-validating the *quality* of recorded reasoning — a checker can only confirm a field is non-empty, which teaches agents to write filler into a required box.

## Key Behaviors

- **"Understanding" is a term of art, borrowed from Adrian Tchaikovsky's _Children of Time_.** In the novel an Understanding is knowledge distilled and passed to a generation that never had the experience which produced it — which is exactly the contract here: the originating session is discarded, the transferable knowledge survives. Do not "clarify" the name to `learnings`, `notes`, `lessons`, or `memories`. Those all invite session logs; this one does not, and the distinction between a log and an Understanding is the whole design.
- **Understandings are evidence; rules are orders.** The governance half of this design lives in `.github/instructions/meta/understandings.instructions.md`, not here, because importing must work at session start without anyone invoking the skill. Editing one side without the other splits the contract.
- **A session splits into several slugs inside one subject.** One Understanding per trigger, each standing alone, grouped under the subject it came out of. Merging a session's lessons into one unit to keep the count down produces a unit whose trigger matches everything and therefore nothing — the subject folder is what keeps them together, not a shared file.
- **Consumed units land as `confidence: observed`,** whatever they claimed at the source. They were verified against a setup that may differ.
- **Promoted knowledge does not stay in the store.** Once an Understanding is folded into a `*AGENTS.md` or a rule, the store copy is a competing copy that will drift. The naming-vocabulary lesson recorded above in Key Behaviors was exported as a unit first and then removed for exactly this reason.
- **Promotion is the exit, not a cleanup chore.** An Understanding proven across many tasks belongs in a `*AGENTS.md` or a rule, which load without a skill invocation. Leaving it in the disposable store means re-earning it every workspace.
- **Export/import are session↔disk; publish/consume are repo↔repo.** The first naming made `--export` mean "copy to a tracked path", which reads as publishing to anyone who thinks of export as getting a session's memory out of the conversation — the switch did not do what its name promised, and the mode was invoked expecting analysis. Do not collapse the two pairs back together.
- **The frontmatter parser is hand-rolled** because PyYAML is not available in this environment. It handles flat scalars, top-level lists, a nested map, and a list inside that map (`provenance.inherited`) — and nothing deeper. Adding a frontmatter field with more structure means extending `parse_frontmatter`, not just the template; the `inherited` list was exactly that case and the naive version silently clobbered the whole `provenance` map into a list.

## Test References

No automated tests. The generator's validation paths (missing/placeholder `description`/`trigger`/`scope`/`confidence`/`updated`/`provenance.*`, slug-vs-folder mismatch, invalid `scope`/`confidence`, a non-existent `agents_context` path, missing `UNDERSTANDING.md`, duplicate slugs across subjects, a unit left at the old single-level depth, an empty subject folder, dangling links, empty store, absent store) its lineage validation (resolving, dangling, and deliberately unbracketed `provenance.inherited` entries), and its argument handling (`--help`, unknown flag, surplus argument) were exercised manually against fixtures. `parse_frontmatter` additionally has direct assertions for the nested-list case, same-indent list items, a scalar following a list, and absent frontmatter. Re-run them after touching `parse_frontmatter` — the list-under-key branch in particular is easy to break in a way that silently drops `links` instead of erroring.

## Changelog

| Date | Change | Ref |
|:-----|:-------|:----|
| 2026-09-19 | Initial version. Slug-folder store under `.context/`, generated reference index, `scope`-gated publish, consumption via `ai-asset-sync`. | |
| 2026-09-19 | Recorded the _Children of Time_ provenance of the term, to stop the name being genericized into something that invites session logs. | |
| 2026-09-19 | LADR-005: `provenance.inherited` added; parser extended to handle a list nested inside a map. | |
| 2026-09-19 | Review sweep: corrected a false claim (an empty diff aborts task-from-diff rather than creating an empty issue) and a wrong mechanism (fixed layer precedence, not sort order); removed a store unit that duplicated an already-promoted Key Behavior; extended generator validation to `updated`, `provenance.*` and `agents_context`. | |
| 2026-09-19 | LADR-004: added the subject tier (`<subject>/<slug>/`) after a single-subject session produced five sibling top-level folders and lost its coherence. | |
| 2026-09-19 | Renamed the switches: `--export`/`--import` now mean session↔disk (analyse the session / load it back), and the cross-repo operations became `--publish`/`--consume`. The original `--export` was invoked expecting session analysis and produced nothing. | |
