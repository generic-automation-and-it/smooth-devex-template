# Reuse Skills, Rules and Hooks in Another Repository

Pull the owned **skills** (`.agents/skills/`), **rules** (`.github/instructions/` subset),
and **hooks** (`.agents/hooks/` subset) from this template into an existing repository —
without copying the rest of the template. One command; per-skill opt-out via editable manifest.
Never touches the calling repo's `src/` or `tests/`.

```bash
curl -fsSL https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.sh | bash -s -- -r -s -h
```

```powershell
$script = [scriptblock]::Create((irm https://raw.githubusercontent.com/generic-automation-and-it/smooth-devex-template/main/scripts/install-skills.ps1)); & $script -r -s -h
```

`-r` rules, `-s` skills, `-h` hooks — no switches means everything is on, so `-r -s -h` spells the
default out loud. Narrow with any subset (`-s` for skills only).

> **Risk callout.** A first run into an existing `.agents/skills/` **replaces every local skill folder**
> with the source's version — there is no confirmation prompt. Set `installed: false` in
> `_smooth-devex-shared/installation.json` for anything you want kept, before the first install, or
> back the folder up first.

State lives in `<your-repo>/.agents/_smooth-devex-shared/installation.json` (UTC stamp plus a
`name` / `installed` pair per skill). Flip a skill off by setting its `installed` flag to `false`; the
installer leaves it on disk but stops overwriting it on every run. Full contract and operator
documentation: [`scripts/SKILLS_INSTALLER.md`](../../scripts/SKILLS_INSTALLER.md).

## Owned set

Ships **exactly seven** skills. Anything else in this template's `.agents/skills/` — the
`agile-github-*` pair, `context-load-*`, `git-commit*` / `git-sync`, `ai-brain-dump`,
`ai-understanding` — is **local** and never enters a consumer's manifest. Skills owned by other
repositories (the `mimisbrunnr-*` set plus `ai-review`, `git-commit-review-push`, etc., owned by
`smooth-ai-product-context-memory`) install via that repository's own installer.

| ID | Type | Does | Why important / unique |
|---|---|---|---|
| `ai-asset-sync` | skill | Dependabot-style sync of AI assets from `owner/repo@ref:path`; AI-merges, opens chore PR on diff | Only auto-update path for consumer repos |
| `ai-ralph-loop` | skill | Review → fix → verify loop until clean (cap 10); never commits | Only multi-pass quality gate; fresh-eyes each pass |
| `ai-template-sync` | skill | UPSERTs this template scaffold into existing repo | Literal purpose of template; only onboarding path |
| `ai-terse` | skill | Reformats reply: answer first, bullets/tables, TL;DR | Only token-compression / signal-only output |
| `create-hld` | skill | Authors design-only HLD (intent + spec, no code) | Only AI/human build contract before implementation |
| `create-worktask` | skill | Scaffolds self-contained worktask under `.context/work-tasks/` | Only standalone-coder handoff format |
| `manage-rule-system` | skill | Rule-file lifecycle across Claude/Copilot/Cursor/Codex | Only cross-tool rule compat convention |
| `code-review-standards.instructions.md` | rule | Review standards referenced by `create-worktask` | Required ref; worktask output broken without it |
| `git/git-policy.instructions.md` | rule | Git policy referenced by `ai-asset-sync`, `create-worktask` | Required ref for sync + worktask flows |
| `meta/knowledge-conventional-contexts-quality.instructions.md` | rule | Context quality bar referenced by `create-hld` | Required ref for HLD context files |
| `meta/rules.instructions.md` | rule | Rule lifecycle convention for `manage-rule-system` | Required ref; defines rule format itself |
| `manage-rule-system-context.sh` | hook | `UserPromptSubmit`: injects rule skill on rule-file mentions | Else skill never auto-fires |
| `worktask-skill-trigger.sh` | hook | Shared Claude/Codex router for imperative worktask requests | Only auto-trigger for worktask workflow |

## Scope

Ships owned skills, owned rules, owned hooks, and the shared payload — see
`scripts/SKILLS_INSTALLER.md` for the owned sets. Template-domain rules, local skills, and unowned
hooks stay in this repo.

A consumer that runs the one-liner into an empty repo gets the skill folders plus the
references inside `SKILL.md` files (`Bash(.agents/rules/.../SKILL.md:*)`, etc.) point at paths that
exist after a default `-r -s -h` run. Skills whose `SKILL.md` references template-domain rules
outside the owned set need a manual copy of those files alongside the install. See
`scripts/SKILLS_INSTALLER.md` for the per-category dependency list.

## Supported roots

Accepts `.agents`, `.claude`, or `.codex` as the agent root; skills live at
`<agent-root>/skills` and state plus shared payload at `<agent-root>/_smooth-devex-shared/`.
A `SKILLS_ROOT` override points at a skills directory directly — its parent then counts as the
agent root.
