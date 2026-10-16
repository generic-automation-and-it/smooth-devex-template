# Skills installers

One-command installers for the **agent skills** — the folders under `.agents/skills/` that Claude Code,
Codex and Copilot discover.

| Script | Platform | Interpreter |
|---|---|---|
| [`install-skills.sh`](install-skills.sh) | macOS, Linux | bash, `git`, `python3` |
| [`install-skills.ps1`](install-skills.ps1) | Windows, or anywhere `pwsh` 7 runs | PowerShell 7.0 or later, `git` |

The bash script needs `python3` only to read and write the manifest JSON; most skills shipped here use
Python or Node tooling, so it is rarely a fresh dependency. The PowerShell port has no such dependency —
`ConvertFrom-Json` and `ConvertTo-Json` are built in.

## One-liners

```bash
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h
```

```powershell
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -r -s -h
```

Or from a checkout: `scripts/install-skills.sh -r -s -h`, `./scripts/install-skills.ps1 -r -s -h`.

Category switches: `-r` rules, `-s` skills, `-h` hooks. **No switches means everything is on** —
`-r -s -h` spells the default out loud. Any switch narrows the run to exactly what was named
(`-s` installs only skills, `-r -h` rules and hooks but no skills). Switches filter the run
only; the manifest keeps no record of the selection.

Both take the same three environment overrides, so a local clone or a fork works the same way:

| Variable | Default | Purpose |
|---|---|---|
| `SKILLS_REPO` | the upstream GitHub repo | the clone source |
| `SKILLS_BRANCH` | `main` | the branch to clone |
| `SKILLS_ROOT` | *(unset — searched)* | force a skills root, skipping the search |

## What a run does

**1. Find the agent root, in this order.** `.agents` → `.claude` → `.codex`. The
first that exists is used. If none exists the run **fails and creates nothing** — a folder the operator
never asked for is not an install. The skills root is `<agent-root>/skills` (override with `SKILLS_ROOT`,
whose parent directory then counts as the agent root). If the agent root has no `skills/` directory
the run fails the same way.

In this repository `.claude` and `.codex` are symlinks to `.agents`, so all paths resolve to the
same tree and the first match is the real one.

**2. Reconcile the manifest — for the owned skills only.** The installer manages exactly six skills:
`ai-asset-sync`, `ai-template-sync`, `ai-terse`, `create-hld`, `create-worktask`, `manage-rule-system`.
The catalogue is the **owned union** of what the clone source offers and what is already on disk.
Anything else in the target tree — local coding skills, operator experiments, the seven `mimisbrunnr-*`
skills that belong to `smooth-ai-product-context-memory` and other repositories' skills — is left
untouched and never enters the manifest. Deriving the catalogue from disk alone would make a first
install into an empty folder a no-op — nothing on disk means nothing to install, and the operator's
very first run would leave them with an empty folder and a manifest listing nothing.

State lives in `<agent-root>/_smooth-devex-shared/installation.json`:

```json
{
  "updated": "2026-10-15T13:10:22Z",
  "skills": [
    { "name": "ai-terse", "installed": true },
    { "name": "create-hld", "installed": false }
  ]
}
```

The shared folder is named per-repo (`_smooth-devex-shared`) so a tree does not confuse this installer
with another one's state file.

| Skill | Result |
|---|---|
| owned, in the catalogue, new to the manifest | added as `installed: true` |
| owned, in the catalogue, already in the manifest | keeps its existing flag, `true` **or** `false` |
| in the manifest, no longer owned or on disk | removed from the manifest |
| not owned (on disk, in the source, or hand-written into the manifest) | **never** listed, **never** copied, even if the manifest is hand-edited |
| manifest will not parse | **run fails**, file left untouched |
| no manifest at all | created from the owned catalogue, every entry `installed: true` |

## Owned set

The installer is scoped to a **positive owned list**, not a deny list. The owned set lives in
`OWNED_LIST` (`install-skills.sh`) and `$script:OwnedList` (`install-skills.ps1`); the two must
match byte-for-byte (the harness holds them to each other).

| Skill | Why owned here |
|---|---|
| `ai-asset-sync` | Syncs AI assets across projects; core template mechanism |
| `ai-template-sync` | Syncs this template into consumer repos; literal purpose of the template |
| `ai-terse` | Token compression; generally useful across consumer projects |
| `create-hld` | Design workflow authoring |
| `create-worktask` | Task authoring workflow |
| `manage-rule-system` | Rule lifecycle management |

Everything else in this template's `.agents/skills/` is treated as **local** — `agile-github-*` may be
claimed by a GitHub-specific installer; `context-load-*` and `git-commit*` / `git-sync` are local
helpers; `ai-brain-dump` and `ai-understanding` are session-scoped or archival and excluded for the
same reason as the prior deny list. Skills owned by other repositories (the seven `mimisbrunnr-*`
skills plus `ai-review` from `smooth-ai-product-context-memory`) are not installed here either — install
them with that repository's own installer.

## Deny list

Session-scoped / archival skills are excluded as part of the owned set above — `ai-brain-dump` and
`ai-understanding` are deliberately not in `OWNED_LIST` for the same reason the source repo's
deny list kept them out: an operator who did not ask for a personal braindump or session-archiving
tool does not get one as a side effect of the template install.

The exclusion is enforced **three times**: the source- and disk-side getters skip unowned names; the
manifest reconciliation intersects against the owned set; and the update step refuses to copy an
unowned folder even
if the manifest was hand-edited. The harness covers the third case for every entry on the list.

**3. Update only the owned skills marked `installed: true`.** The repo is shallow-cloned once and
those folders are copied over the existing ones. A skill marked `false` is never touched, so a local
edit inside one survives every run until you set its flag back. A skill outside the owned set is
never copied even when a hand-edited manifest asks for it. Skipped entirely unless `-s` (or no
switches).

**4. Update the owned rules (`-r`).** The five `OWNED_RULES` files copy from the source's
`.github/instructions/` into `<repo>/.github/instructions/`, preserving relative paths:

| Owned rule | Why |
|---|---|
| `AGENTS.md` | rules index (shared part) |
| `code-review-standards.instructions.md` | referenced by `create-worktask` |
| `git/git-policy.instructions.md` | referenced by `ai-asset-sync`, `create-worktask` |
| `meta/knowledge-conventional-contexts-quality.instructions.md` | referenced by `create-hld` |
| `meta/rules.instructions.md` | rule lifecycle convention (`manage-rule-system`) |

Overwrite, never delete — an operator's own rules are never swept. Everything else in
`.github/instructions/` (backend/\*, skills/\*, clean-code, solid-principles, …) stays local.
The run also ensures the `<agent-root>/rules → ../.github/instructions` topology symlink when
nothing is there; a real directory is never replaced. Skipped entirely unless `-r` (or no switches).

**5. Update the owned hooks (`-h`).** The three `OWNED_HOOKS` files copy from the source's
`.agents/hooks/` into `<agent-root>/hooks/`, kept executable. A hook is owned iff an owned
skill's `SKILL.md` references it (`load-agents-context.sh`, `manage-rule-system-context.sh`,
`worktask-skill-trigger.sh`); the rest stays local. Overwrite, never delete. Hook
*registration* (`settings.json`) is deliberately out of scope — copy the wiring by hand for
the hooks you want live. Skipped entirely unless `-h` (or no switches).

**6. Refresh `_smooth-devex-shared`** (when the source ships one, and the skills category runs). That folder holds cross-cutting,
repo-owned payload — currently `setup/scripts/` (the agent setup scripts every tool selection
needs) and `templates/` (the `AGENTS.md` scaffolding and worktask templates several skills
reference) — plus the installer's own `installation.json`. It is not a skill and never appears in the
manifest, but any installed skill that calls a shared script is broken without it — so it refreshes
on every run, whatever the flags say. Its contents are reconciled rather than merged: an entry the
source no longer has is removed, except `installation.json` itself, which is this script's own state.
Every top-level payload entry is then linked back to its canonical `<agent-root>` path
(e.g. `<agent-root>/setup` → `_smooth-devex-shared/setup`), so the `.agents/setup/...` references
in `SKILL.md` files keep working. An existing real file or directory at a link path is never
replaced — the run reports it and moves on.

**7. Write the manifest last**, stamped with the current UTC time (skills category only). That ordering is deliberate — see
[Write ordering](#write-ordering-is-load-bearing).

## Turning a skill off

Edit the manifest and re-run. The flag is read, never guessed:

```bash
# one skill off
python3 - <<'EOF'
import json
p = '.agents/skills/_smooth-devex-shared/installation.json'
d = json.load(open(p))
for s in d['skills']:
    if s['name'] == 'git-sync':
        s['installed'] = False
json.dump(d, open(p, 'w'), indent=2)
EOF
scripts/install-skills.sh
```

The flag only governs **updates**. It does not remove or disable anything: a `false` skill stays on disk
and stays discoverable, it is simply never overwritten again. Delete the folder if you want it gone — the
next run drops it from the manifest.

## Write ordering is load-bearing

The manifest is written **after** the update, not before. The manifest lives inside
`_smooth-devex-shared/`, and step 4 rewrites that folder — so writing it first would have the refresh
clobber it. The update also reads the *merged* manifest, so on a first install the run that was supposed
to install the skills can see which ones it just decided to install.

Both ports are held to this by `scripts/test-install-skills.sh`, including the case where a manifest
already exists and one skill's flag is `false`.

## Overwriting local work

An `installed: true` skill is **replaced** on every run, so an edit inside one is lost on the next
install. That is the point of an updater, but it is a real hazard: either set the flag to `false` first,
or move the change somewhere the installer does not own.

A first run into an existing `.agents/skills/` **replaces every local skill folder** with the source's
version — there is no confirmation prompt. Set `installed: false` in
`_smooth-devex-shared/installation.json` for anything you want kept, before the first install, or
back the folder up first.

## Scope

The installer ships `.agents/skills/` (owned set only) plus the cross-cutting, repo-owned
`.agents/_smooth-devex-shared/` payload (currently `setup/scripts/` + `templates/`). It does **not** carry:

- `.agents/rules/` (referenced by skill `SKILL.md` frontmatter — consumer keeps its own)
- `.agents/hooks/` (referenced by some `setup/scripts/` flows)

A consumer that runs the one-liner into an empty repo gets the owned skill folders plus the shared
payload, with canonical paths (`setup/`, `templates/`) linked back to `_smooth-devex-shared/`, but
the cross-tree references inside `SKILL.md` files that point at `.agents/rules/` still need a manual
copy of those files alongside the install.

| Skill | Needs (manual copy) |
|---|---|
| `create-hld` | `.agents/rules/meta/` rules used by `hld-agents-rules.sh` |
| `manage-rule-system` | the rules themselves if you want to manage them via this skill |
| `context-load-context` / `context-load-agents-context` | `.agents/rules/` for the context files to reference |

## Layout move (2026-10): manifest and payload live at the agent root

Previously the manifest lived at `<skills-root>/_smooth-devex-shared/installation.json` and the
source shipped no shared payload. Now both live at `<agent-root>/_smooth-devex-shared/`, and the
source ships the cross-cutting payload (`setup/scripts/`, `templates/`) there. A manifest at the old location
is **ignored, not migrated** (fresh start) — the run logs a notice naming it. Delete the old
`<skills-root>/_smooth-devex-shared/` directory once you have verified the new state.

## Supported roots

The installer accepts `.agents`, `.claude`, or `.codex` as the agent root (see step 1 above);
skills live at `<agent-root>/skills`. A consumer whose skills live outside any agent directory can
point `SKILLS_ROOT` at them directly — the parent directory then counts as the agent root for state
and payload purposes.

## Testing

```bash
bash scripts/test-install-skills.sh
```

40+ cases against the bash port, no network and no container engine needed: the clone source is the
checkout itself (`SKILLS_REPO` pointed at the repo, `SKILLS_BRANCH` at the current branch), so a harness
that reached GitHub would be red for reasons unrelated to the code. Runs in the PR gate. The shared
payload, canonical links, stale-entry sweep, legacy-manifest ignore, and real-dir-at-link-path cases
all run against the source tree's real `.agents/_smooth-devex-shared/` payload.

The PowerShell port is **not exercised here.** `install-skills.ps1` is a hand-translated mirror of
`install-skills.sh` — same contract, same control flow — and its defects are the ones a careful read
catches. A two-port harness doubles the maintenance surface for a contract that exists to be read, not
to be redundantly proven on platforms the gate does not run. The PowerShell canonical-link step
uses a junction fallback (symlinks need elevation or Developer Mode on Windows); the bash port uses
plain symlinks.