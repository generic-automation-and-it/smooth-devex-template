# Publish / Consume Contract

Export writes a session's knowledge to the working store; **publish** carries it out of the workspace
altogether, and **consume** brings another workspace's published set in. The working store
(`.context/understandings/`) is gitignored and dies with the workspace, so publishing is how knowledge
survives and consuming is how a fresh workspace starts with knowledge it did not earn.

## Two tiers

| Tier | Path | Tracked | Lifetime | Purpose |
|------|------|---------|----------|---------|
| Working memory | `.context/understandings/` | No | This workspace | Where export lands; accrues cheaply, most of it is never worth keeping |
| Published memory | `.agents/understandings/` (default publish destination) | Yes | The repository | Reviewed, portable knowledge that other workspaces and repos consume |

Nothing is published implicitly. An Understanding reaches the tracked tier only when a human
approves the publish, which is the review step that keeps published memory small and true.

## What travels

| `scope` | Published by default | Meaning |
|---------|---------------------|---------|
| `portable` | Yes | True of the stack, tooling, or language anywhere it is used |
| `repo-specific` | No (needs `--all`) | True only of this repository's setup, data, or conventions |

Getting this wrong in the permissive direction is the expensive failure: a `repo-specific`
Understanding published and then consumed elsewhere is a local quirk presented to a future agent as
firsthand universal knowledge, with provenance that makes it look trustworthy.

When the distinction is genuinely unclear, mark it `repo-specific`. The cost of leaving knowledge
behind is one rediscovery. The cost of shipping a false universal is every consumer acting on it.

## Publish

1. Read the working store's index; select `portable` units (or all, with `--all`).
2. Show the user the slug list and the destination. Wait for approval — this writes to a tracked path.
3. Copy each `<subject>/<slug>/` folder whole, including supporting artifacts. Filter per Understanding, never per subject — one subject routinely mixes scopes.
4. On each published copy, record the origin under `provenance` and leave the working copy untouched.
5. Regenerate the destination's `INDEX.md` with the index script, pointed at the destination:

   ```bash
   python3 .agents/skills/ai-understanding/scripts/understanding_index.py .agents/understandings
   ```

6. Leave the change uncommitted. Committing and opening a PR is the user's call, via the `git-*` skills.

### Pre-publish check

Understandings are written during debugging, when a literal value is the fastest thing to type. Before
anything reaches a tracked path, confirm no unit carries a credential, token, connection string, or
internal hostname. Record the shape of the problem, not the value. See
`.github/instructions/skills/skill-secret-handling.instructions.md`.

## Consume

Sources are a local published directory or a repository path in `owner/repo@ref:path` form.

**This skill does not fetch remote content.** For a remote source, add an entry to the `ai-asset-sync`
manifest and let that skill perform the fetch — it already owns cloning, lockfile provenance, AI-merge,
and the resulting PR. One transport implementation, not two.

```yaml
# .github/assets/ai-sync.yml
version: 1
entries:
  - source: generic-automation-and-it/smooth-devex-template@main:.agents/understandings
```

Once the content is present locally, reconcile it into the working store:

| Incoming slug | Action |
|---------------|--------|
| Absent locally | Copy the folder in; set `provenance.consumed_from`; set `confidence: observed` |
| Present, same trigger | Merge as a collision. **Local wins on any conflict**; report the difference to the user |
| Present, different trigger | Bring it in under a slug disambiguated by what distinguishes it |

Two rules make consuming safe to run without reading every incoming file first:

- **Local belief is never silently overwritten.** Consuming can add knowledge and can surface a
  disagreement, but it cannot quietly replace what this workspace already observed.
- **Incoming knowledge arrives unverified.** It was `verified` somewhere else, against a setup that may
  differ. It becomes `verified` here only when something here confirms it.

After reconciling, regenerate the working index.

## Cross-repo lifecycle

```
session → .context/understandings/<subject>/<slug>/   (--export, local, disposable)
        → .agents/understandings/<subject>/<slug>/    (--publish, tracked, reviewed, per-unit scope filter)
        → ai-asset-sync manifest entry                (transport to another repo)
        → .context/understandings/<subject>/<slug>/   (--consume, into that repo's working memory)
        → session                                     (--import, matched by trigger)
        → *AGENTS.md  or  .github/instructions/       (--promote, when it stops being an observation)
```

Promotion is the exit from this loop. An Understanding that has been consumed, confirmed, and applied
across many tasks is no longer discovered knowledge in flight — it belongs in a context file or a rule,
where it loads without anyone invoking a skill.
