# Skills installers

One-command installers for the **agent skills** — the folders under `.agents/skills/` that Claude Code,
Codex and Copilot discover.

| Script | Platform | Interpreter |
|---|---|---|
| [`install-skills.sh`](install-skills.sh) | macOS, Linux | bash, `git`, `python3` |
| [`install-skills.ps1`](install-skills.ps1) | Windows, or anywhere `pwsh` 7.2+ runs | PowerShell 7.2 or later (.NET 6 link resolution), `git` |

The bash script needs `python3` for manifest JSON and canonical path resolution; most skills shipped here use
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
whose parent directory then counts as the agent root). Once an agent root is found, missing category
directories are created only for the categories that run. A rules-only or hooks-only run creates no
`skills/` directory. An explicit `SKILLS_ROOT` must already exist.

In this repository `.claude` and `.codex` are symlinks to `.agents`, so all paths resolve to the
same tree and the first match is the real one.

**2. Reconcile the manifest — for the owned skills only.** The installer manages exactly fifteen skills:
`agile-github-breakdown`, `agile-github-task-from-diff`, `ai-asset-sync`, `ai-ralph-loop`, `ai-template-sync`,
`ai-terse`, `context-load-agents-context`, `context-load-context`, `create-hld`, `create-worktask`,
`git-commit`, `git-commit-push`, `git-commit-push-pr`, `git-sync`, `manage-rule-system`.
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
| `agile-github-breakdown` | Turns a braindump or Feature into GitHub Feature + Task issues; generally useful across consumer projects |
| `agile-github-task-from-diff` | Creates a GitHub Task from the branch diff; generally useful across consumer projects |
| `ai-asset-sync` | Syncs AI assets across projects; core template mechanism |
| `ai-template-sync` | Syncs this template into consumer repos; literal purpose of the template |
| `ai-ralph-loop` | Review → fix → verify loop over a branch diff, or over a plan with `--plan`; generally useful across consumer projects |
| `ai-terse` | Token compression; generally useful across consumer projects |
| `context-load-agents-context` | Loads ancestor `AGENTS.md` context for a file; `ai-ralph-loop` and `manage-rule-system` use it |
| `context-load-context` | Loads or creates functional `AGENTS.md` context before implementation work |
| `create-hld` | Design workflow authoring |
| `create-worktask` | AI-native SDLC implementation task authoring; source/decision and validation links |
| `git-commit` | Conventional-commit workflow; follows the shipped `git/git-policy` rule |
| `git-commit-push` | Commit and push; follows the shipped `git/git-policy` rule |
| `git-commit-push-pr` | Commit, push and open or update a PR; follows the shipped `git/git-policy` rule |
| `git-sync` | Sync the branch with `origin/main`, optionally resolving conflicts |
| `manage-rule-system` | Rule lifecycle management |

Everything else in this template's `.agents/skills/` is treated as **local** — `ai-brain-dump` and
`ai-understanding` are session-scoped or archival and excluded for the same reason as the prior deny
list. Skills owned by other repositories (the seven `mimisbrunnr-*` skills plus `ai-review` from
`smooth-ai-product-context-memory`) are not installed here either — install them with that
repository's own installer.

`load-agents-context.sh`, the `PostToolUse` hook that runs `context-load-agents-context` automatically
in Claude Code, is not in `OWNED_HOOKS`: `-g` registers hooks under `UserPromptSubmit` only, so shipping it
would fire it on the wrong event. Without the hook the skill still works; agents invoke its script explicitly.

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
those folders are copied over the existing ones. A skill's own `AGENTS.md` is stripped from every copy —
it documents the owner repo's local-dev context and improvements, not the runnable payload a consumer
should inherit. Tests are also pruned from skills and the shared payload: folders named `test/`,
`tests/`, or `__tests__/`, and files matching `test_*`, `*_test.*`, `*.test.*`, or `*.Tests.ps1`.
The same pruning applies to global skill-store copies. A skill marked `false` is never touched, so a local
edit inside one survives every run until you set its flag back. A skill outside the owned set is
never copied even when a hand-edited manifest asks for it. Skipped entirely unless `-s` (or no
switches).

**4. Update the owned rules (`-r`).** Every rule in this template is owned, so all of the
`.instructions.md` files copy from the source's `.github/instructions/` into `<agent-root>/rules/`,
preserving relative paths. An operator's `rules` symlink (for example, `rules → ../.github/instructions`)
is written through, including creation of a dangling target. Otherwise `rules/` is a real directory;
the installer no longer creates the topology symlink itself. Examples of shipped rules:

| Owned rule | Why |
|---|---|
| `code-review-standards.instructions.md` | referenced by `create-worktask` |
| `git/git-policy.instructions.md` | referenced by `ai-asset-sync`, `create-worktask` |
| `meta/knowledge-conventional-contexts-quality.instructions.md` | referenced by `create-hld` |
| `meta/rules.instructions.md` | rule lifecycle convention (`manage-rule-system`) |

The template's own `AGENTS.md` index is **never copied** — it would clobber an existing consumer index. Instead the run
writes a generated subset index: missing index → created; installer-generated index → refreshed;
an existing operator index → the subset section is appended once, never rewritten. Overwrite,
never delete — an operator's own rules are never swept. Skipped entirely unless `-r` (or no
switches).

**5. Update the owned hooks (`-h`).** The two `OWNED_HOOKS` files copy from the source's
`.agents/hooks/` into `<agent-root>/hooks/`, kept executable (exec bit preserved per owned file,
never a wildcard over the directory). A hook is owned iff an owned skill's `SKILL.md` references
it *and* its implementation ships with it (`manage-rule-system-context.sh`,
`worktask-skill-trigger.sh`); `load-agents-context.sh` stays local because it requires a different
registration event (`PostToolUse` rather than `UserPromptSubmit`).
Overwrite, never delete. Hook *registration* (`settings.json`) is deliberately out of scope —
copy the wiring by hand for the hooks you want live. Skipped entirely unless `-h` (or no
switches).

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

**WET copies.** Both per-repo and global installs materialize source symlinks whose resolved targets
remain inside the temporary clone. File and directory links become real content; external, dangling,
and cyclic links remain links. Installed skill references therefore survive deletion of the temporary
clone. These copy rules apply to skills, rules, hooks, and the per-repo shared payload. The canonical
`setup/` and `templates/` links created by the installer are separate and remain links. On Windows
without symlink privilege, a link that must be preserved is warned about and skipped.

The manifest-bearing shared-payload root must remain a real directory. Its source may be an
in-clone link that can be materialized, but external, dangling, and ancestor-pointing shared roots
are rejected before replacing the destination. A linked shared destination is also rejected;
cleanup never traverses retained payload-root links.

**Symlink support.** The temp clone forces `-c core.symlinks=true` so committed symlinks in the
source check out as links even under a Windows-default git (otherwise the payload copy would copy
file-blobs instead of directories). The run also sets `core.symlinks=true` in the consumer repo
(best-effort, silently skipped outside a git work tree) so created links record as links on the
next commit — same as `.agents/setup/scripts` does.

**7. Write the manifest last**, stamped with the current UTC time (skills category only). That ordering is deliberate — see
[Write ordering](#write-ordering-is-load-bearing).

## Turning a skill off

Edit the manifest and re-run. The flag is read, never guessed:

```bash
# one skill off
python3 - <<'EOF'
import json
p = '.agents/_smooth-devex-shared/installation.json'
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

## Global install (`-g`)

`-g` installs the same owned set **once, machine-wide**, into `~/.smooth-ai-devex/`, then wires it into
Codex's own config dir (`~/.codex`, or `$CODEX_HOME`). It is a separate mode from the per-repo install
above — the two never mix, and `-g` refuses to be combined with `SKILLS_ROOT`. It composes with the same
category switches (`-g -s -r -h`), so you can install just skills, just rules, or just hooks globally.

| Layer | Where it lands |
|---|---|
| Skills | copied into `~/.smooth-ai-devex/skills/` (tests and owner `AGENTS.md` stripped), then symlinked into `~/.codex/skills/<name>` — coexisting with Codex's own `.system/`, which is never touched. When Claude is installed, each is also symlinked into `~/.claude/skills/<name>`; when OpenCode is installed, each is symlinked into `~/.config/opencode/skills/<name>` and the store's rules are added to `opencode.json` `instructions` |
| Rules | the **full** template rules tree is copied into `~/.smooth-ai-devex/rules/`. Codex gets a compact **index** of the enabled rules (absolute path, scope, one-line description, ~5 KiB) in a delimited block of `~/.codex/AGENTS.md` — see [Codex](#codex-rules-index-and-command-policy). When Claude is installed the rules are also symlinked into `~/.claude/rules/`; when OpenCode is installed each rule is added to `opencode.json` `instructions` as its own absolute path (never a `rules/**` glob, which could not exclude one rule). The per-repo install ships the same owned rules |
| Hooks | copied into `~/.smooth-ai-devex/hooks/` and JSON-merged into `~/.codex/hooks.json` under `UserPromptSubmit` only, with absolute store commands (relative `.agents/...` commands would break outside the repo), deduped by command match, preserving the `gk` and `code-review-graph` entries already there |

State is `~/.smooth-ai-devex/installation.json` — `decisions_enabled` and `skills[]` as in the per-repo
manifest, plus `rules[]` and `hooks[]` (below) and a `links[]` array recording every symlink and config
edit, so `-g --uninstall` removes exactly what was installed.

### Switching one rule or hook off

Every owned rule and hook has the same `{ "name", "installed" }` entry a skill has:

```json
{
  "skills": [ { "name": "ai-terse", "installed": true } ],
  "rules":  [ { "name": "clean-code.instructions.md", "installed": false },
              { "name": "git/git-policy.instructions.md", "installed": true } ],
  "hooks":  [ { "name": "worktask-skill-trigger.sh", "installed": false } ]
}
```

Rule names are paths relative to `.github/instructions/`; hook names are file names. They reconcile on
every run exactly as skills do: a name the manifest has not seen joins as `installed: true`, a name no
longer owned is dropped, and the flag you set — `false` included — is kept. Edit the flag, re-run
`install-skills -g`.

`installed: false` switches the item **off**, not just out of the update loop:

| Item | Not copied or refreshed | Removed from |
|---|---|---|
| rule | the store copy (an edit you made there survives) | the Codex `AGENTS.md` index and the store `AGENTS.md`, its `~/.claude/rules/` symlink, its `opencode.json` `instructions` entry |
| hook | the store copy | its command in `~/.codex/hooks.json` (a group left empty goes with it; the `gk` entries and the other owned hook stay) |

Flip it back to `true` and the next run copies a fresh version and rewires it. A skill set to
`installed: false` differs on purpose: it keeps its existing symlinks and stays discoverable, it is only
never refreshed.

A category-only run (`-g -r`, `-g -h`, `-g -s`) reconciles just its own list and carries the others
forward unchanged; `hooks[]` does not appear until a run that covers hooks. `-g -r` now also updates
`opencode.json` — that step used to run only with skills — and rewrites the `rules/*.instructions.md` and
`rules/**/*.instructions.md` glob pair an earlier install wrote into per-file entries. The per-repo
install has no per-item rules/hooks flags: it ships its fixed owned subset.

### Codex: rules index and command policy

Codex has two things called "rules", and neither is an `@`-import:

- **Instructions** reach Codex through `~/.codex/AGENTS.md`, which Codex reads as plain text: global file
  first, then each `AGENTS.md` from the repo root down, joined and capped at `project_doc_max_bytes`
  (32 KiB by default). It does **not** resolve `@path` imports, and the 20 rule files total ~84 KB, so the
  installer cannot import or inline them. Instead the block holds an index — "read these at the start of
  every task", "read these when editing files matching `<scope>`" — and the model opens the files it needs.
  The block is replaced in place on every run, so it follows each rule's `installed` flag; an `@RTK.md`
  line or any other text of yours outside it is never touched. This relies on the model following the
  index; it is not enforced.
- **Codex `.rules` files** (`~/.codex/rules/*.rules`) are a Starlark command-approval policy
  (`prefix_rule()` with `allow` / `prompt` / `forbidden`), not instructions. The installer writes one,
  `~/.codex/rules/smooth-devex.rules`, while `git/git-policy` is enabled: ordinary `git commit` and
  `git push` commands are unmatched, and a push whose first flag is `--force`, `-f` or
  `--force-with-lease` is forbidden. Explicit-user-request authorization stays in the Git policy
  instructions; command rules cannot inspect conversation consent. Unconditional `prompt` rules
  would block even authorized operations with `approval_policy = "never"`. It is a separate
  file because Codex appends your permanent approvals to `default.rules`, which the installer never
  touches. Matching is by command prefix only, so `git push origin x --force` is not caught — a guard
  rail, not complete enforcement. Re-running the fixed global installer replaces legacy commit/push
  prompt blocks in its own generated file; files without its ownership header are left untouched. The
  file exists only while `codex` is on and `git/git-policy` is `installed: true`, is removed otherwise
  (only if it still carries its header), and Codex reads it at startup, so start a new Codex session
  after a change. Updating repository instructions alone does not repair an already-installed policy.

### Switching a whole harness off

`harnesses` turns an entire tool on or off for this machine:

```json
{
  "harnesses": { "claude-code": true, "codex": false, "opencode": true }
}
```

A harness the manifest has not seen is added as `true` (the object always lists exactly these three, in
this order; any other key is dropped). `true` installs into it as usual. `false` installs nothing into it
**and** removes whatever this installer already put there, on every run:

| Harness | Wired when `true`; removed when `false` |
|---|---|
| `claude-code` | symlinks in `~/.claude/skills/` and `~/.claude/rules/` |
| `codex` | symlinks in `~/.codex/skills/`, the rules block in `~/.codex/AGENTS.md` (the lines around it stay), `~/.codex/rules/smooth-devex.rules`, the store commands in `~/.codex/hooks.json` (other hooks stay) |
| `opencode` | symlinks in `~/.config/opencode/skills/`, the store entries in `opencode.json` `instructions` (your own entries stay) |

Removal is found **on disk**, not only in `links[]`: any symlink in those folders that points into the
store goes, including one whose record was lost; a real file or a link to anywhere else is never touched.
The store (`~/.smooth-ai-devex/{skills,rules,hooks}` and its `AGENTS.md`) is shared by all three and stays
filled. Like the category switches, a narrowed run only cleans what it covers — `-g -r` removes a `false`
harness's rule wiring but not its skill links.

Every symlink record in `links[]` (`skill-link`, `claude-skill`, `opencode-skill`, `claude-rule`) carries an
`enabled` field:

```json
{
  "type": "claude-rule",
  "path": "/Users/me/.claude/rules/backend/solid-principles.instructions.md",
  "detail": "/Users/me/.smooth-ai-devex/rules/backend/solid-principles.instructions.md",
  "enabled": true
}
```

`enabled` is a **status the installer writes**, not a control: it is `true` while the symlink is on disk
and points at `detail`, and `false` once the link has been removed because its rule or its harness was
switched off. The record stays so a re-enable and `--uninstall` still know about it. Editing it by hand
does nothing — the next run recomputes it; use `installed` and `harnesses` to steer. The config-edit records
(`agents-import`, `hooks-merge`, `opencode-config`, `profile-edit`) have no `enabled`.

`--uninstall` ignores `harnesses` and `enabled`: it removes whatever its records point at that is present,
and restores the files it edited byte-for-byte, however the flags were toggled before.

Before appending to any pre-existing file it does not own, the
installer snapshots it **once** as `<file>.smooth-devex-<UTC datetime>` — `~/.codex/hooks.json` and
`~/.codex/AGENTS.md`, plus the shell profile when decision env vars are written. `--uninstall` restores
those snapshots (so the operator's earlier content comes back byte-for-byte), removes the `AGENTS.md`
rules block and `~/.codex/rules/smooth-devex.rules`, and deletes the skill symlinks — leaving Codex's
`.system/`, an operator's `gk` hooks, and their `RTK.md` `@`-import line untouched. The store directory itself is left in place
(`rm -rf ~/.smooth-ai-devex` to reclaim it).

`$SMOOTH_DEVEX_HOME` overrides the store location and `$CODEX_HOME` overrides Codex's config dir — both
are how a test harness isolates a run from a real `~/.codex`.

```bash
scripts/install-skills.sh -g                  # all layers
scripts/install-skills.sh -g -s               # skills only
scripts/install-skills.sh -g --uninstall      # remove the global install
```

Windows (PowerShell 7.2+) mirrors the contract: `./scripts/install-skills.ps1 -g`. Symlinks need Developer
Mode or elevation; on a machine without either the ps1 port falls back to a junction — degraded, because
git records a junction's target contents as real files, so prefer symlinks.

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

The installer ships `.agents/skills/` (owned set only), the owned `.github/instructions/` rule
tree (into `<agent-root>/rules/`), the owned `.agents/hooks/` subset, plus the cross-cutting, repo-owned
`.agents/_smooth-devex-shared/` payload (currently `setup/scripts/` + `templates/`). It does **not**
carry anything else: local skills and unowned hooks stay in this repo.

A consumer that runs the one-liner into an empty repo gets the owned skills, rules, and hooks plus
the shared payload, with canonical paths (`setup/`, `templates/`) linked back to
`_smooth-devex-shared/`. Cross-tree references inside `SKILL.md` files that point at rules outside
the owned set still need a manual copy of those files alongside the install.

| Skill | Needs (manual copy) |
|---|---|
| `ai-ralph-loop` | Optional — `context-load-agents-context` script (falls back to an ancestor walk), `.agents/rules/AGENTS.md` index, an `ai-understanding` store under `.context/understandings/` |
| `create-hld` | `.agents/rules/meta/` rules used by `hld-agents-rules.sh` |
| `manage-rule-system` | the rules themselves if you want to manage them via this skill |
| `context-load-context` / `context-load-agents-context` | `.agents/rules/` for the context files to reference |
| `git-commit` / `git-commit-push` / `git-commit-push-pr` | the `git/git-policy` rule (ships); `git-commit-push-pr` also needs `gh` and reads the repo's `.github/pull_request_template.md` |
| `agile-github-breakdown` / `agile-github-task-from-diff` | `gh` authenticated against the target repo; task-from-diff links into a GitHub Project unless run with `--noparentid` |

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

The Bash harness needs no container engine: the clone source is the
checkout itself (`SKILLS_REPO` pointed at the repo, `SKILLS_BRANCH` at the current branch), so a harness
that reached GitHub would be red for reasons unrelated to the code. Runs in the PR gate. The shared
payload, canonical links, stale-entry sweep, legacy-manifest ignore, and real-dir-at-link-path cases
all run against the source tree's real `.agents/_smooth-devex-shared/` payload.

The harness also runs `test-installer-payload.py` against Bash. It uses a temporary local Git fixture to
cover test pruning, in-clone file/directory links, external/dangling/cyclic links, missing category
folders, rules through dangling operator links, shared-payload refresh, disabled skills, and global
copy parity. Run the same payload tests against both ports locally (requires `pwsh` 7.2+):

```bash
python3 scripts/test-installer-payload.py --port all -v
```

The rest of the Bash harness does not exercise PowerShell at runtime. The PowerShell canonical-link step
uses a junction fallback (symlinks need elevation or Developer Mode on Windows); the bash port uses
plain symlinks. A junction is *not* a symlink — git would commit its target's contents as real
files, so prefer Developer Mode/elevation and treat junctions as a degraded install.
