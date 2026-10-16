# AGENTS.md - Operational Scripts

## TL;DR

`scripts/` houses **operator-facing utilities**. Skills live under `.agents/skills/`; the installers here
are the only supported way to pull a fresh checkout of them into another repository. Anything in this
directory must be safe to `curl | bash` against a clean tree, and must never edit the calling
repository's source outside its declared contract.

## Non-Negotiables

- **Read-only by default.** Scripts write only into the skills root they resolved (or, when the
  installer is force-pinned via `SKILLS_ROOT`, into exactly that path). Anything that wants to touch
  the calling repo's `src/`, `tests/`, `.github/` or other top-level directories belongs elsewhere —
  most likely as a workflow under `.github/workflows/` or an action under `.github/actions/`.
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
| `test-install-skills.sh` | Harness. 30+ cases over both ports when `pwsh` is present. |

The installer pulls a flat list of folders from `.agents/skills/` in this repository into a consumer
repository, controlled by a per-skill `installed` flag in
`<consumer-root>/_smooth-devex-shared/installation.json`. Skills owned by **other** repositories
(such as `smooth-ai-product-context-memory`'s `mimisbrunnr-*` set) are not touched, and the shared-folder
name is deliberately per-repo so a single tree cannot confuse two installers' state files.

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

## Test References

The harness is wired into `.github/workflows/pr-gate.yml` (`Test skills installer`). It deliberately
exercises the manifest reconciliation and the root search; the clone/copy path is exercised against the
checkout itself (`SKILLS_REPO` pointed at this repo, `SKILLS_BRANCH` at the current branch), so no
network is involved and a red run is about the code under test, not GitHub availability.

Two known gaps:

- **The PowerShell port is not exercised.** `install-skills.ps1` is a hand-translated mirror of
  `install-skills.sh` — same contract, same control flow — and the contract exists to be read, not
  to be redundantly proven on a platform the gate does not run. Reading the two scripts side by
  side is the test.
- **The shared-folder refresh path is not exercised** — this repository does not ship a
  `_smooth-devex-shared/` folder in `.agents/skills/`, so the source-side copy is a no-op. The code
  is symmetric with the bash port, but a green harness does not prove the shared-folder copy works
  end-to-end on this tree. Add a `_smooth-devex-shared/` folder to source and a refresh-folder case
  back to the harness if a shared payload ever needs to ship.

## Changelog

| Date | Change | Ref |
| :---- | :---- | :---- |
| 2026-10-15 | Initial: `install-skills.{sh,ps1}` + harness + docs | — |
| 2026-10-16 | `ai-ralph-loop` added to the owned set (seven skills) | #104 |
