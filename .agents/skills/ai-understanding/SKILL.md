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

An **Understanding** is a **question and its answer** — a distilled, self-contained unit of hard-won knowledge, written so a future agent with zero context from this session can act on it as if it had learned it firsthand. The question is what a reader has in their head at the moment the knowledge applies; the answer is what to do about it. Pairing them is what makes a unit retrievable and keeps it honest: one question has one answer, so a unit that needs two is two units.

An Understanding is **not** a session log, not a summary of what we did, and not documentation of the code. It is the transferable skill that remains after the experience is discarded.

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

### What qualifies: the system, not the toolchain

An Understanding carries **functional and non-functional knowledge about the system being built** — how a
domain actually behaves, a constraint the data imposes, an integration that misbehaves under load, a
security boundary that is not where it looks. The kind of thing that would still be true, and still
matter, if the work had been done by hand.

It does **not** carry knowledge about the tools used to do the work. How a skill's script computes a diff,
which Python version a scanner needs, how a CI workflow's path filters combine, how the agent harness
shares a checkout — all true, all occasionally useful, none of it an Understanding. That is knowledge
about the *vehicle*, and the store is for the *cargo*.

The tell: **the skill you used is never the subject.** Running a braindump session is not an
Understanding; the requirements that came out of it, split by question and given slugs, are. Running a
task-from-diff is not an Understanding; a constraint you discovered about the feature you were slicing is.

### Outcomes count, narratives do not

A session's **outcome** is knowledge in its own right, and it has no other home. The requirements a
braindump distilled out of three meetings; the issues and PRs a piece of work produced and what state it
left them in; what was decided, what was specified but not built, and who is carrying it. None of that
belongs in an `*AGENTS.md` — which documents what the code does, not what is still owed — and all of it is
what a next session needs first.

The line against session logs still holds, and it is about **shape**, not subject matter:

| Not this | This |
|---|---|
| "We discussed the export format, then I refactored the parser, then tests passed" | "Issue #67 tracks the skill; PR #68 is open as a draft; publish is specified in a worktask but unbuilt" |
| A narrative of the work, in order, from the agent's point of view | The durable artifacts, their identifiers, and their state |

Outcome units go stale faster than anything else in the store, so say so: give the date in `Boundaries`
and name the command that re-checks the claim. A ticket number is a fact; a ticket's status is a snapshot.

Two questions that settle it:

- Would this still be true and worth knowing for someone who never used these tools?
- Is it about the product, or about the process that produced the product?
- If neither — is it the **outcome** of the work, the artifacts and their state? Then it qualifies on its own terms, and the questions above do not apply.

Tooling knowledge is not worthless — it is just filed elsewhere. It belongs in the nearest `*AGENTS.md`
(the skill's own, the workflow's own), in a rule if it is a decision, or in setup documentation. Put it
there and leave the store alone.

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
| `confidence` | `observed` (seen once), `verified` (reproduced or confirmed), `contested` (evidence conflicts) |
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

The reverse of export: knowledge comes **off disk and back into the session**. This is also what the
always-loaded rule asks for at the start of a task, with or without the switch.

Read `.context/understandings/INDEX.md` and load every Understanding whose **question** matches one you are about to ask. Read the index first and the units second — that is what the index is for.

Treat loaded Understandings as prior knowledge. If one contradicts what the code actually does, say so: they go stale, and a stale one is worse than none. Lower its `confidence` to `contested` and tell the user.

**Keep track of what you actually used.** Anything loaded here that goes on to shape the work is recorded as `provenance.inherited` on whatever the session exports later. Loading an Understanding and then ignoring it is not inheritance — only record the ones that changed what you did.

Rules always win a conflict with an Understanding. Flag the conflict rather than resolving it silently.

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
| 2026-09-19 | Outcomes named as a first-class kind of Understanding: requirements distilled from meetings, and the issues/PRs/worktasks a piece of work produced and their state — none of which has an `*AGENTS.md` home. | |
| 2026-09-19 | A unit is now an explicit question/answer pair: frontmatter `trigger` became `question`, body `## Knowledge` became `## Answer`. | |
| 2026-09-19 | Scope narrowed to functional/non-functional knowledge about the system; knowledge about the agent toolchain is explicitly out and belongs in `*AGENTS.md` or setup docs. | |
| 2026-09-19 | Store gained a subject tier. Unit is `<subject>/<slug>.md`; artifacts, when any, go in `<slug>.assets/`. | |
| 2026-09-19 | `--publish` defaults to every unit; `--portable-only` replaces `--all` as the cross-repo scope filter (`--all` stays `--export`-only). | |
