# AGENTS.md - Operational Scripts

## TL;DR

`scripts/` houses **operator-facing utilities**. Skills live under `.agents/skills/`; the installers here
are the only supported way to pull a fresh checkout of them into another repository. Anything in this
directory must be safe to `curl | bash` against a clean tree, and must never edit the calling
repository's source outside its declared contract.

## Non-Negotiables

- **Read-only by default.** Scripts write only into the paths their contract declares: the
  installer writes the resolved skills root, `<agent-root>/_smooth-devex-shared/`, the owned
  `<agent-root>/hooks/` files, the owned `.github/instructions/` subset, and canonical symlinks —
  or, when force-pinned via `SKILLS_ROOT`, into exactly that path and its siblings. The `-g`
  global mode is the explicit exception: it writes `$HOME/.smooth-ai-devex/` (its store + manifest)
  and wires into Codex's `$HOME/.codex/` (skills symlinks, an `AGENTS.md` import, `hooks.json`), plus
  Claude's `$HOME/.claude/skills` and OpenCode's `$HOME/.config/opencode/commands`.
  Anything else that wants to touch the calling repo's `src/`, `tests/`, `.github/` or other
  top-level directories belongs elsewhere — most likely as a workflow under `.github/workflows/` or an
  action under `.github/actions/`.
- **Idempotent runs.** Re-running a script with the same inputs must converge on the same state — that
  is the contract the [test harness](test-install-skills.sh) verifies, and the property that makes a
  `curl | bash` one-liner safe to put in onboarding docs.
- **No silent skips on hard errors.** A missing skills directory, an unparseable manifest, or a failed
  clone are all non-zero exits with a one-line reason on stderr. A green exit followed by an empty
  tree is the failure mode the first-install case in the harness exists to catch.
- **Dependency floor is declared at the top of the file.** If a script needs `python3`, `pwsh`, or any
  other interpreter, the dependency line is the first line the operator sees.

## Skills Installer

Two ports, one contract — see [SKILLS_INSTALLER.md](SKILLS_INSTALLER.md) for the operator-facing
documentation.

| File | Role |
| --- | --- |
| `install-skills.sh` | bash port. macOS / Linux. Needs `bash`, `git`, `python3`. |
| `install-skills.ps1` | PowerShell 7 port. Windows or anywhere `pwsh` runs. Needs `pwsh`, `git`. |
| `test-install-skills.sh` | Harness. 70 cases, bash port only (the ps1 port is read, not run). |

The installer pulls a flat list of folders from `.agents/skills/` in this repository into a consumer
repository, controlled by a per-skill `installed` flag in
`<consumer-root>/_smooth-devex-shared/installation.json`. Skills owned by **other** repositories
(such as `smooth-ai-product-context-memory`'s `mimisbrunnr-*` set) are not touched, and the shared-folder
name is deliberately per-repo so a single tree cannot confuse two installers' state files.

A skill's own `AGENTS.md` is **never copied** — it documents the owner repo's local-dev context and
improvements, not the runnable payload a consumer should inherit. The installer strips `AGENTS.md`
files from every skill folder it copies (per-repo and `-g` global), leaving `SKILL.md`, scripts and
references intact.

A small hardcoded **owned set** (`OWNED_LIST` in `install-skills.sh`, `$script:OwnedList` in
`install-skills.ps1`) scopes the installer to seven template-purpose skills: `ai-asset-sync`,
`ai-ralph-loop`, `ai-template-sync`, `ai-terse`, `create-hld`, `create-worktask`, `manage-rule-system`. Everything
else in `.agents/skills/` is treated as local and never enters a consumer's manifest, even when a
hand-edited manifest names it `installed: true` — the update loop refuses unowned names as well as
the manifest builder. This is the same shape `smooth-ai-product-context-memory` PR #245 introduced;
the unscoped installer pulled a target repo's local-only skills into its manifest as `installed: true`,
and the owned-set gate stops that here.

`SKILLS_TEST_OWNED_EXTRA` is a test-only env var the harness sets to extend the owned list with
synthetic names (`alpha beta gamma delta epsilon`) so the harness can exercise add/drop cases
without planting real source-owned names. Production installers never set it.

**`-g` is a separate global mode.** Instead of scoping to `<agent-root>` in the repo you are in, it
installs the same owned set once, machine-wide, into `~/.smooth-ai-devex/` and wires it into Codex's
`~/.codex/`: owned skills are symlinked into `~/.codex/skills/` (coexisting with Codex's `.system/`),
and made vendorable into any agent tree; the skills' own `SKILL.md` files reference a repo-local
`.agents/...` tree (own scripts, rules, `.context/`), so a globally-installed skill is *discoverable*
but its scripts only run when the consumer has that tree (a per-repo install, or this template).
the full template rules tree is copied into the store and imported through a generated
`~/.smooth-ai-devex/AGENTS.md` that `~/.codex/AGENTS.md` pulls in with one marker-guarded `@`-line
(never written into `~/.codex/rules/`, a Starlark `prefix_rule` namespace), symlinked into
`~/.claude/rules/` when Claude is installed, and added to `opencode.json` `instructions` when OpenCode
is installed — unlike the per-repo install, which ships only the 4 `OWNED_RULES`. And the owned hooks
are JSON-merged into `~/.codex/hooks.json`
under `UserPromptSubmit` only, with absolute store commands. When Claude is installed, owned skills
are also symlinked into `~/.claude/skills/`. When OpenCode is installed, each owned skill is
referenced from `~/.config/opencode/commands` (a folder symlink to the store's `opencode-commands/`,
whose `<name>.md` links point at the skill's `SKILL.md`), and the store's rules are added to the
operator's `opencode.json` `instructions` (with a backup). State
is `~/.smooth-ai-devex/installation.json` (a `links[]` record of what
was installed); `-g --uninstall` removes exactly that — never `.system/`, an operator's `gk` hooks, or
their `RTK.md` `@`-import line. Every pre-existing config file the installer appends to
(`~/.codex/AGENTS.md`, `~/.codex/hooks.json`, and the shell profile when decision env vars are written)
is snapshotted once as `<file>.smooth-devex-<UTC datetime>` before modification, and `--uninstall`
restores it; the symlinks the installer creates (Codex skills, OpenCode commands) are removed, and a
`-g -d` profile edit is restored too. `-g` refuses to be combined with `SKILLS_ROOT`, and `--uninstall`
without `-g` is refused.

## Test References

The harness is wired into `.github/workflows/pr-gate.yml` (`Test skills installer`). It deliberately
exercises the manifest reconciliation, the agent-root search, and the shared-payload refresh; the clone/copy path is exercised against the
checkout itself (`SKILLS_REPO` pointed at this repo, `SKILLS_BRANCH` at the current branch), so no
network is involved and a red run is about the code under test, not GitHub availability.

Two known gaps:

- **The PowerShell port is not exercised.** `install-skills.ps1` is a hand-translated mirror of
  `install-skills.sh` — same contract, same control flow — and the contract exists to be read, not
  to be redundantly proven on a platform the gate does not run. Reading the two scripts side by
  side is the test.
- **The `_smooth-devex-shared/` payload is scoped, not comprehensive.** Only cross-cutting,
  repo-owned items live there (`setup/scripts/`, `templates/`). Skills have their own category;
  rules and hooks each have an owned allowlist (`OWNED_RULES`, `OWNED_HOOKS`) — template-domain
  files stay local by default.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-15 | Initial: `install-skills.{sh,ps1}` + harness + docs | — |
| 2026-10-16 | Agent-root layout: manifest + cross-cutting payload at `<agent-root>/_smooth-devex-shared/` (ships `setup/scripts/`, `templates/`), canonical symlinks, legacy-manifest fresh start; harness covers refresh/sweep/links/legacy | — |
| 2026-10-16 | Category switches `-r -s -h` (default all-on): `OWNED_RULES` (4 files) + rules topology link, `OWNED_HOOKS` (2 files, exec bit); harness covers categories, unowned, real-dir, bad flag; README one-liners spell the default | — |
| 2026-10-16 | Symlink support: temp clone forces `-c core.symlinks=true`, consumer repo marked best-effort; ps1 junction fallback documented as degraded | — |
| 2026-10-16 | `ai-ralph-loop` added to the owned set (seven skills) | #104 |
| 2026-10-16 | README owned-set table before Tech Stack (7 skills, 4 rules, 2 hooks); matches `OWNED_LIST`/`OWNED_RULES`/`OWNED_HOOKS` | — |
| 2026-10-16 | README top install section shows both Mac/Linux `curl` and Windows `irm` one-liners; full details stay in `docs/wiki/reuse.md` | — |
| 2026-10-17 | Installer decision prompt reads `/dev/tty`/console so it is asked even on piped `curl \| bash` / `irm \| iex`; falls back to disabled with no terminal | — |
| 2026-10-17 | `-d` switch: opt into decision validation without prompting (writes env vars, sets `decisions_enabled: true`) | — |
| 2026-10-17 | Decision prompt probes `/dev/tty` by opening it (`-r` passes on CI runners with no controlling terminal, then `read` died under `set -e`); harness adds a no-controlling-terminal case | — |
| 2026-10-17 | `-g` global mode: `~/.smooth-ai-devex/{skills,rules,hooks}` store + manifest with `links[]`; Codex wiring — skills symlinks, marker-guarded `~/.codex/AGENTS.md` import, UserPromptSubmit `hooks.json` merge; snaps pre-existing appended files as `<file>.smooth-devex-<datetime>` and restores on `-g --uninstall`; harness adds 8 `-g` cases | — |
| 2026-10-18 | Review fixes: `-g --uninstall` removes an installer-created `AGENTS.md` from nothing (exact inverse, no leftover), `symlink_global_skill` guards a failed `ln -s` instead of aborting the run, `-g` usage string reworded; harness adds case 8i (60 total) | — |
| 2026-10-18 | Skill `AGENTS.md` files are no longer copied over (owner local-dev context; stripped from per-repo and `-g` skill copies); harness case 8j | — |
| 2026-10-18 | `-g` wires OpenCode: owned skills referenced as `~/.config/opencode/commands/<name>.md` (command, not skills-folder copy); `-g -d` profile edit tracked and restored on uninstall; harness cases 8k/8l | — |
| 2026-10-18 | Harness global cases pin `SMOOTH_DEVEX_HOME`/`OPENCODE_CONFIG` and clear inherited `SKILLS_ROOT` (operator env vars cannot leak into an isolated `-g` run) | — |
| 2026-10-18 | `-g` review fixes: uninstall restores from a snapshot and **retires** it (so install→uninstall→reinstall snapshots fresh, never data-loss); global store copy/symlink honor `installed:false` (preserve edits, keep discoverable); harness cases 8m/8n | — |
| 2026-10-18 | `-g --uninstall` snapshots each content file's current (post-install) state as `*.smooth-devex-uninstall-<stamp>` before restoring/removing it, so operator edits made after install are not lost; symlinks are safe (target content stays in the store); harness case 8o | — |
| 2026-10-18 | `-g` wires Claude Code: owned skills symlinked into `~/.claude/skills` when Claude is installed (removed on `--uninstall`); harness case 8p | — |
| 2026-10-18 | `-g` OpenCode: owned skills symlinked into OpenCode's skills dir, and the store's rules added to `opencode.json` `instructions` with a backup; harness cases 8k/8q | — |
| 2026-10-18 | `-g` Claude rules: owned rules symlinked into `~/.claude/rules` so Claude Code loads them across sessions; harness case 8r | — |
| 2026-10-18 | `-g` global rules ship the **full** template rules tree (incl. `backend/`, `skills/`, clean-code, solid-principles), not just the 4 `OWNED_RULES` a consumer gets — for Codex `@`-import, Claude `~/.claude/rules`, OpenCode `opencode.json` | — |
