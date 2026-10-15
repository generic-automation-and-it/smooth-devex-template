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
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1 | iex
```

Or from a checkout: `scripts/install-skills.sh`, `./scripts/install-skills.ps1`.

Both take the same three environment overrides, so a local clone or a fork works the same way:

| Variable | Default | Purpose |
|---|---|---|
| `SKILLS_REPO` | the upstream GitHub repo | the clone source |
| `SKILLS_BRANCH` | `main` | the branch to clone |
| `SKILLS_ROOT` | *(unset — searched)* | force a skills root, skipping the search |

## What a run does

**1. Find the skills root, in this order.** `.agents/skills` → `.claude/skills` → `.codex/skills`. The
first that exists is used. If none exists the run **fails and creates nothing** — a folder the operator
never asked for is not an install. Set `SKILLS_ROOT` to install somewhere else.

In this repository `.claude/skills` and `.codex/skills` are symlinks to `.agents/skills`, so all three
paths resolve to the same tree and the first match is the real one.

**2. Reconcile the manifest.** The catalogue is the **union** of the skills the clone source offers and
the skills already on disk. Deriving it from disk alone would make a first install into an empty folder a
no-op — nothing on disk means nothing to install, and the operator's very first run would leave them with
an empty folder and a manifest listing nothing.

State lives in `<root>/_smooth-devex-shared/installation.json`:

```json
{
  "updated": "2026-10-15T13:10:22Z",
  "skills": [
    { "name": "ai-terse", "installed": true },
    { "name": "git-sync", "installed": false }
  ]
}
```

The shared folder is named per-repo (`_smooth-devex-shared`) so a tree does not confuse this installer
with another one's state file.

| Skill | Result |
|---|---|
| in the catalogue, new to the manifest | added as `installed: true` |
| in the catalogue, already in the manifest | keeps its existing flag, `true` **or** `false` |
| in the manifest, in neither the source nor disk | removed from the manifest |
| in the deny list (see below) | **never** in the catalogue, **never** copied, even if the manifest is hand-edited |
| manifest will not parse | **run fails**, file left untouched |
| no manifest at all | created from the catalogue, every entry `installed: true` |

## Deny list

A small built-in list of skills the installer will **not** carry across, even when present in source.
Interactive / session-scoped skills do not fit the implicit "ship in a template" install contract — an
operator who did not ask for a personal braindump tool should not get one as a side effect.

The list is hardcoded inside each installer (`DENY_LIST` in `install-skills.sh`,
`$script:DenyList` in `install-skills.ps1`):

| Skill | Why |
|---|---|
| `ai-brain-dump` | Starts a listen-first session that captures in-conversation content. Installing it implicitly on every consumer repo would surprise the operator. Opt-in via manual copy. |
| `ai-understanding` | Exports session-derived state into per-repo `.context/` folders. It is the consumer's own archival pipeline, not a skill the installer should silently plant alongside the read-only ones. |

The exclusion is enforced **three times**: the source- and disk-side getters skip denied names; the
manifest reconciliation refuses to add them; and the update step refuses to copy a denied folder even
if the manifest was hand-edited. The harness covers the third case for every entry on the list.

**3. Update only the `installed: true` skills.** The repo is shallow-cloned once and those folders are
copied over the existing ones. A skill marked `false` is never touched, so a local edit inside one
survives every run until you set its flag back.

**4. Refresh `_smooth-devex-shared`** (when the source ships one). That folder is not a skill and never
appears in the manifest, but any installed skill that calls a shared script is broken without it — so
it refreshes on every run, whatever the flags say. Its contents are reconciled rather than merged: an
entry the source no longer has is removed, except `installation.json` itself, which is this script's own
state.

**5. Write the manifest last**, stamped with the current UTC time. That ordering is deliberate — see
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

## Testing

```bash
bash scripts/test-install-skills.sh
```

19 cases against the bash port, no network and no container engine needed: the clone source is the
checkout itself (`SKILLS_REPO` pointed at the repo, `SKILLS_BRANCH` at the current branch), so a harness
that reached GitHub would be red for reasons unrelated to the code. Runs in the PR gate.

The PowerShell port is **not exercised here.** `install-skills.ps1` is a hand-translated mirror of
`install-skills.sh` — same contract, same control flow — and its defects are the ones a careful read
catches. A two-port harness doubles the maintenance surface for a contract that exists to be read, not
to be redundantly proven on platforms the gate does not run.

The harness also does not cover the shared-folder refresh path because this repository does not ship a
`_smooth-devex-shared/` folder in source; the code path runs only when the source has one to copy, and
is otherwise a no-op. See `scripts/AGENTS.md` for what that gap does and does not cover.