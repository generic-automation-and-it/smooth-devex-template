---
name: ai-understanding
description: Export this session's hard-won knowledge into Understandings under .context/understandings/<subject>/<slug>.md (one file per unit, grouped into a subject folder), import matching ones back at task start, and publish/consume them across repos. Trigger on "export the understandings", "make an Understanding of this", "encode this", "what did we learn", "/ai-understanding", or when a session resolved something that cost real effort and would cost the same again. Not a session log and not code documentation.
allowed-tools:
  - Bash(python3 .agents/skills/ai-understanding/scripts/understanding_index.py:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
models:
  claude: opus        # high-complexity; multi-turn judgment on what qualifies, merge/promotion decisions
  copilot: auto
  codex: gpt-5.5
---

# Understanding — Skill

An **Understanding** is the **input and outcome of a session's memory**, kept so another agent can act on
it: reusable, terse, structured, and holding what no code file or knowledge document already holds.

The last clause is the whole test, and the rest follows from the purpose — it is written for an agent to
act on, not for a human to read or an archive to keep:

- **terse**, because it competes for a context budget it does not control
- **structured**, because it must be matched before it is read
- **no narrative**, because an agent cannot act on a story
- **evidence, not orders**, because the agent must be able to override it when the system disagrees

Two kinds qualify. **Input** — what went into the work: requirements distilled from meetings, a braindump's
findings, a constraint someone stated once. **Outcome** — what came out: the issues and PRs a piece of work
produced and their state, what was decided, what was specified but left unbuilt, and anything learned in
passing that the work did not set out to learn.

The working store is **local and disposable** (`.context/` is gitignored). That is deliberate: memory accrues cheaply per workspace, and only what earns it gets published. Anything you want to survive this workspace must be published.

## TL;DR

1. Working store: `.context/understandings/<subject>/<slug>.md` — a subject folder groups a session's lessons, one file per Understanding inside it.
2. `.context/understandings/INDEX.md` is a generated table of **unit + description + question** — the only file an agent reads to decide what to load.
3. One session may yield **several** Understandings; each is its own slug folder, each stands alone, and they share a `provenance.session` value.
4. Never overwrite an existing slug. Same question → merge. Different question → distinct slug.
5. Export writes the session's knowledge to disk; import reads it back. Publish/consume move it between repositories.

## Store layout

```
.context/understandings/
  INDEX.md                  # generated — grouped by subject, one row per Understanding
  <subject>/                # the topic or session the lessons came out of
    <slug>.md               # one Understanding (frontmatter + body)
    <slug>.assets/          # only when a unit carries artifacts — repro, log excerpt, diagram
```

**One folder, one file per Understanding.** The subject keeps a session's lessons browsable together, so the work that produced them stays legible months later; use `_unfiled/` for an Understanding belonging to no particular topic. Almost every unit is a single file — evidence normally belongs inline, quoted in the body, where a reader sees it without opening anything.

A unit that genuinely needs artifacts gets a sibling `<slug>.assets/` directory. Naming it after the slug is what prevents the collisions a shared directory would cause, and it is paid for only by the rare unit that needs it.

The subject is **not** how knowledge is found. Retrieval is by **question** — a future agent has a question in mind, not a subject, so the index lists every unit regardless of which subject produced it.

## Switches

Export and import are about **this session's memory**: export writes what the session learned to disk, import loads it back. Publish and consume are the separate, rarer cross-repository operations.

| Switch | Effect |
|--------|--------|
| `--export` _(default)_ | **Analyse this session** and write each durable lesson to `.context/understandings/<subject>/<slug>.md`. Proposes the split first |
| `--export --all` | Same, but write every qualifying candidate without pausing for the user to cut the list |
| `--import` | Load Understandings whose question matches one the task will make you ask |
| `--publish [--portable-only]` | Copy every unit to a tracked destination (default `.agents/understandings/`); `--portable-only` restricts to `scope: portable` units |
| `--consume <source>` | Hydrate the working store from a published set or another repo |
| `--promote <slug>` | Escalate an Understanding to a `*AGENTS.md` context file or a rule |
| `--index` | Regenerate `INDEX.md` from the slug folders |
| `--review` | Advisory decay report — what is contested, never inherited, or overdue a re-check |

`--all` applies only to `--export`, where it means "skip the cut". `--publish`'s scope filter is a
separate switch, `--portable-only` — the two are unrelated despite the old design overloading `--all`
for both.

Single-dash spellings of the long switches (`-all`, `-export`) are accepted as typed — they are
unambiguous here, and rejecting them would fail a run for a keystroke. An unrecognised switch is not
guessed at: say what was passed and ask.

## Export (default mode)

Exporting is the act of getting knowledge **out of the session and onto disk**, where it outlives the
conversation. Invoked bare, or with `--export`, this is what the skill does.

Read the whole session before writing anything. What qualifies is not "what we did" — it is what a
future agent would otherwise have to rediscover.

### What qualifies: nothing with another home

Work down this list. The store is the residue after the other homes have taken what is theirs.

| If it is… | It goes… |
|---|---|
| Visible in the code | nowhere — read the code |
| Functional intent about a code area | the nearest `*AGENTS.md` |
| A decision the user made | a rule |
| A design decision with trade-offs | an LADR in the nearest `*AGENTS.md` |
| **Reusable, and none of the above has a claim on it** | **here** |

"Not written down yet" is not the same as "no other home". If something belongs in an `*AGENTS.md` and
nobody has written it, write it there — otherwise the store becomes the place for anything unfiled.

This is what excludes the toolchain. How a skill's script computes a diff, which Python version a scanner
needs, how a workflow's path filters combine — all true, all expensive to learn, all with a home beside the
tool they describe. The skill you used is never the subject: running a braindump is not an Understanding,
the requirements that came out of it are.

Outcomes are the one kind with no fallback. An `*AGENTS.md` records what the code does, not what is still
owed, so the state of a piece of work — its issues, its open decisions, its unbuilt specifications — lands
here or nowhere. Those units go stale fastest: give the date and the command that re-checks them.

### When to propose one unprompted

After resolving something about **the system** that cost real effort and would cost the same again: a non-obvious root cause in the domain, a constraint the data or an integration imposes, a convention not visible in the code, a rejected design and why it was rejected. Effort alone does not qualify it — a toolchain quirk can cost a whole afternoon and still belong in an `*AGENTS.md` rather than here.

**Propose it. Ask before writing.** The user decides what becomes memory.

### Splitting a session

A single session frequently contains more than one durable lesson. Split it — do not cram unrelated knowledge into one slug to keep the count down, and do not split one lesson into fragments that only make sense read together.

- One Understanding per **question**. If two pieces of knowledge answer different questions, they are two Understandings — and if one question needs two unrelated answers, it was really two questions.
- Each must stand alone. No "as established above", no reference to the conversation that produced it.
- Related slugs from the same session cross-link with `[[other-slug]]` and share one `provenance.session`.

When proposing a split, list the candidate slugs with their questions and let the user cut or merge before anything is written. **With `--all`, skip the cut** — write every candidate that qualifies and report what was written, so the user prunes afterwards instead of beforehand.

### Writing one

Copy `assets/UNDERSTANDING.template.md` to `.context/understandings/<subject>/<slug>.md` and fill it.

Subject: kebab-case, names the topic or piece of work the session was about — reuse an existing subject folder when the knowledge came out of the same work. `_unfiled` is the home for a one-off that belongs to no topic. The subject is derived from the parent folder, so it is never written into frontmatter and cannot drift.

Slug: kebab-case, names the **knowledge**, not the incident. `npgsql-enum-mapping-needs-datasource` — not `tuesday-db-bug`.

Frontmatter fields:

| Field | Meaning |
|-------|---------|
| `slug` | Must equal the file name without `.md`. Unique across the whole store, since `[[slug]]` links and merges address it from any subject |
| `description` | One line — what this knowledge is. Appears in `INDEX.md` |
| `question` | **Optional.** The question a reader has at the moment this applies, when there is a natural one — one question, one answer. Omit it on an outcome record, where `description` is the match. Appears in `INDEX.md` |
| `scope` | `portable` (true of the stack/tooling anywhere) or `repo-specific` (true only here). Governs export |
| `confidence` | `observed` (seen once), `verified` (reproduced, or confirmed against source), `contested` (the system disagreed). It records how the knowledge was obtained, **not that it is correct** |
| `links` | `[[slug]]` references to related Understandings |
| `agents_context` | Path to the nearest `*AGENTS.md` this bears on, when it concerns a specific code area |
| `provenance.learned` | Date, absolute |
| `provenance.session` | Shared by all slugs encoded from one session |
| `provenance.source` | What produced it — a failure, a doc, an experiment |
| `provenance.inherited` | `[[slug]]` list of the Understandings this session loaded **and acted on**. Omit when none |
| `updated` | Date of last change |

Body sections: **Answer** (direct operational guidance, answering the frontmatter question and nothing wider), **Why** (the reasoning or failure behind it — enough to judge an edge case the Answer does not cover), **Boundaries** (where it stops applying). The question lives in frontmatter only, so `INDEX.md` never drifts from the unit.

**Write it terse.** Every line earns its place or comes out. Cut what the reader already knows, what the code shows, and anything said once already. Prefer a table to a paragraph and a command to a description of a command. There is no length to fill and none to stay under — but a unit that does not fit on one screen is usually two units, or one unit padded. Density is the point: a reader who skips half of it has been failed twice, once by the noise and once by the signal they missed in it.

Keeping the answer inside the question's scope is what stops a unit over-reaching: an answer that outgrows its question means the question was too narrow, and a question no answer covers means it was too broad. Both are visible on one screen.

Record the lineage: list under `provenance.inherited` the Understandings this session imported and acted on. That is the store's only evidence of which knowledge is earning its place — a unit nothing ever inherits is either badly triggered or dead weight, and without the record you cannot tell those apart from knowledge that simply has not come up yet. It also gives the blast radius when a unit later turns out to be wrong.

A bracketed `[[slug]]` must resolve. When an ancestor is pruned or promoted away, drop the brackets rather than deleting the entry — the lineage is a historical fact and stays readable, without pinning the store to knowledge it no longer holds.

### Confidence moves

The field is worthless if it only ever gets set once.

| From | To | When |
|---|---|---|
| `observed` | `verified` | You used it and it held — confirming a unit you were relying on anyway is the cheapest verification there is, so take it |
| any | `contested` | The system disagreed. Record what you saw in the body; do not delete the unit |
| `contested` | `verified` | Someone re-checked and it holds — say what changed, in the changelog |

Raising confidence is a normal part of using the store, not a maintenance task. Lowering it is urgent: a
confidently wrong unit is the one failure mode worse than an empty store.

Note what it does **not** mean. `verified` says the claim was checked once, by someone, against something.
Two independent agents reading the source have found a false claim in a unit marked `verified`. Treat it as
provenance, not warranty — which is why the import protocol says verify rather than defer.

### Language

Understandings are **evidence, never orders**. Write them as "X behaves like Y; do Z" — an answer to the stated question, not an instruction issued in the abstract.

If it needs must/never language, it is not an Understanding — propose it as a rule instead (see `.github/instructions/meta/understandings.instructions.md`). Never encode a user preference, convention, or instruction as an Understanding; those are rules.

### Slug collisions

The store must never lose knowledge to a name clash.

| Situation | Action |
|-----------|--------|
| File absent | Create it under the relevant subject |
| File exists, **same question** | Merge into the existing unit, wherever its subject: reconcile the Answer, union `links`, raise `confidence` if now reproduced, bump `updated`, add a changelog row |
| File exists, **different question** | Write a new slug, disambiguated by what distinguishes it (`…-on-linux`, `…-under-aspire`) — never a numeric suffix. Putting it under a different subject does not make the slug reusable |

Overwriting an existing unit wholesale is not an available outcome. When a merge would drop something, ask.

After any write, regenerate the index:

```bash
python3 .agents/skills/ai-understanding/scripts/understanding_index.py
```

## Import (`--import`)

The reverse of export, and where the value is actually realised. This is also what the always-loaded rule
asks for at the start of a task, with or without the switch.

Read `INDEX.md` first and units second. Match on the **question** — or on `description` where a unit
carries none — against what the work at hand will make you ask.

**How many.** As many as genuinely match, which is usually none or one. Loading a unit costs context you
cannot spend twice, so a match has to be a match: the same question, not the same subject area. If three
match, read all three — but three matches on a store this size usually means the questions are too broad,
which is what `--review` is for.

**When nothing matches, say so.** One line, once. Silence is indistinguishable from not having looked, and
the next person cannot tell whether the store was consulted or ignored.

**When one contradicts the system.** The system wins, always. Say which unit, what it claims, and what you
observed. Set its `confidence: contested` — do not delete it, and do not quietly work around it. A unit that
was true and stopped being true is more informative than a missing one.

**Record what you used.** Any unit that changed what you did goes in `provenance.inherited` on whatever the
session exports later. Loading is not inheriting: only what shaped the work counts. This is the store's
only evidence of which units earn their place, and `--review` reads it back — a unit nothing ever inherits
is either badly asked or dead weight.

Rules always win a conflict with an Understanding. Flag the conflict rather than resolving it silently.

## Review (`--review`)

A store that only grows stops being readable. Nothing else notices, so this does:

```bash
python3 .agents/skills/ai-understanding/scripts/understanding_index.py --review
```

| Flag | What to do |
|---|---|
| `contested` | Confirm it against the system and raise it back to `verified`, or retire it |
| `never inherited` | The question probably does not match what anyone asks. Re-word it, or accept the unit was never needed and prune it |
| overdue re-check | Read it against the current system. Outcome units are flagged after 30 days, knowledge after 90 |

Advisory only — it never changes the exit code, because none of it is wrong, it is just decaying. Act on it
when you are already in the store; do not make a project of it.

Pruning is a legitimate outcome. The store earns its retrieval cost or it does not.

## Publish (`--publish`)

Export puts knowledge on disk; publishing carries it **out of this workspace entirely**. `.context/` is
gitignored, so a published copy is the only form that survives the workspace being destroyed.

- Default destination `.agents/understandings/` — tracked, shared across Claude/Copilot/Codex via the `.agents` symlinks, and a valid `ai-asset-sync` source path. Created on first publish; nothing is seeded before then.
- Publishing filters **per Understanding, not per subject** — a subject folder routinely mixes scopes. By default every unit publishes; pass `--portable-only` to restrict the archive to `scope: portable` units, for the cross-repo case. Never let `--portable-only` publish a `repo-specific` unit — that filter is the only thing preventing a local quirk from being shipped to another repo with provenance that makes it look universally verified.
- The destination keeps the same `<subject>/<slug>.md` layout and gets its own generated `INDEX.md`.
- Each published unit records where it came from; the working copy is left in place.
- Publishing into a tracked path changes the repository — show the user the list of slugs and the destination, and get approval before writing.

Full contract, including the `ai-asset-sync` manifest recipe for consuming repos: `references/publish-consume.md`.

## Consume (`--consume <source>`)

The reverse of publish: another workspace's published knowledge becomes available here.

Sources: a local published directory, or a repo path in `owner/repo@ref:path` form.

For a remote source, add it to the `ai-asset-sync` manifest (`.github/assets/ai-sync.yml`) and let that skill perform the fetch — it already owns transport, provenance, and the merge PR. This skill does not fetch remote content itself.

Reconciliation, per incoming slug:

| Situation | Action |
|-----------|--------|
| Slug absent locally | Copy it in, set `provenance.consumed_from`, set `confidence: observed` |
| Slug present, same question | Merge as a normal collision; **the local unit wins on any conflict** and the difference is reported |
| Slug present, different question | Bring it in under a disambiguated slug |

Consuming never silently changes what this workspace already believes. Incoming knowledge was verified somewhere else, against a setup that may differ, so it arrives as `observed` until something here confirms it.

## Promote (`--promote <slug>`)

An Understanding that keeps proving true has outgrown the disposable store:

- Concerns a specific code area → fold into the nearest `*AGENTS.md`, following `.github/instructions/meta/knowledge-conventional-contexts-quality.instructions.md`.
- Applies to nearly every task, or has become a decision rather than an observation → propose a rule under `.github/instructions/`, following `manage-rule-system`.

Propose the promotion; the user decides. Once promoted, the Understanding records where it went so the two do not drift into competing copies.

## Guardrails

- Ask before merging, publishing, or promoting — every time. These change durable state.
- On `--export`, propose the split and let the user cut it before writing. `--all` is the user's own instruction to skip that step, and waives it for the local store only; it never waives approval for writing to a tracked path.
- Never delete a slug folder to resolve a conflict.
- Never write an Understanding in must/never language.
- Never let an Understanding contradict a rule without flagging it.
- No secrets, tokens, or credential values in an Understanding — they are exportable by design. Record the shape of the problem, not the value.

## Changelog

| Date | Change | Ref |
|:-----|:-------|:----|
| 2026-09-19 | Initial version. | |
| 2026-09-19 | `--export`/`--import` are session↔disk; cross-repo moves became `--publish`/`--consume`. | |
| 2026-09-19 | Definition restated from its purpose — input and outcome of a session's memory, for another agent to act on — with a single "no other home" test replacing two separate qualifying rules. | |
| 2026-09-19 | Outcomes named as a first-class kind of Understanding: requirements distilled from meetings, and the issues/PRs/worktasks a piece of work produced and their state — none of which has an `*AGENTS.md` home. | |
| 2026-09-19 | A unit is now an explicit question/answer pair: frontmatter `trigger` became `question`, body `## Knowledge` became `## Answer`. | |
| 2026-09-19 | Scope narrowed to functional/non-functional knowledge about the system; knowledge about the agent toolchain is explicitly out and belongs in `*AGENTS.md` or setup docs. | |
| 2026-09-19 | Store gained a subject tier. Unit is `<subject>/<slug>.md`; artifacts, when any, go in `<slug>.assets/`. | |
| 2026-09-19 | `--publish` defaults to every unit; `--portable-only` replaces `--all` as the cross-repo scope filter (`--all` stays `--export`-only). | |
