# Reuse Skills, Rules and Hooks in Another Repository

Pull the owned **skills** (`.agents/skills/`), **rules** (`.github/instructions/` tree),
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

Missing category folders are created beneath an existing agent root; no root means an error without
creating one. Rules land in `<agent-root>/rules/`, writing through an operator's existing rules symlink.
Copied skills omit tests and owner `AGENTS.md` files. Links to files/directories inside the template
clone become real content in both per-repo and global installs. PowerShell requires 7.2+.

> **Risk callout.** A first run into an existing `.agents/skills/` **replaces every local skill folder**
> with the source's version — there is no confirmation prompt. Set `installed: false` in
> `_smooth-devex-shared/installation.json` for anything you want kept, before the first install, or
> back the folder up first.

State lives in `<your-repo>/.agents/_smooth-devex-shared/installation.json` (UTC stamp plus a
`name` / `installed` pair per skill). Flip a skill off by setting its `installed` flag to `false`; the
installer leaves it on disk but stops overwriting it on every run. Full contract and operator
documentation: [`scripts/SKILLS_INSTALLER.md`](../../scripts/SKILLS_INSTALLER.md).

## Owned set

Ships **exactly sixteen** skills. Anything else in this template's `.agents/skills/` — `ai-brain-dump`
and `ai-understanding` — is **local** and never enters a consumer's manifest. Skills owned by other
repositories (the `mimisbrunnr-*` set plus `ai-review`, `git-commit-review-push`, etc., owned by
`smooth-ai-product-context-memory`) install via that repository's own installer.

| ID | Type | Does | Why important / unique |
|---|---|---|---|
| `ai-asset-sync` | skill | Dependabot-style sync of AI assets from `owner/repo@ref:path`; AI-merges, opens chore PR on diff | Only auto-update path for consumer repos |
| `ai-execute-pipeline` | skill | Delivers one worktask end to end: worktask-sourced sub-ticket, draft PR first, implement, Ralph loop, ready, SHA-matched AI-review fix loop; `--initialize` stacks later runs with `gh stack`, `--stack <branch>` joins an existing stack | Only zero-touch worktask → reviewed-PR path |
| `ai-ralph-loop` | skill | Review → fix → verify loop until clean (cap 10) over the branch diff, or over a plan via `--plan`; never commits | Only multi-pass quality gate; fresh-eyes each pass |
| `ai-template-sync` | skill | UPSERTs this template scaffold into existing repo | Literal purpose of template; only onboarding path |
| `ai-terse` | skill | Reformats reply: answer first, bullets/tables, TL;DR | Only token-compression / signal-only output |
| `create-hld` | skill | Authors design-only HLD (intent + spec, no code) | Only AI/human build contract before implementation |
| `create-worktask` | skill | Scaffolds self-contained worktask under `.context/work-tasks/` | Only standalone-coder handoff format |
| `manage-rule-system` | skill | Rule-file lifecycle across Claude/Copilot/Cursor/Codex | Only cross-tool rule compat convention |
| `agile-github-breakdown` | skill | Turns a braindump or Feature into GitHub Feature + Task issues, dry-run first | Only braindump-to-backlog path |
| `agile-github-task-from-diff` | skill | Creates a horizontally sliced GitHub Task from the branch diff and links it to its Feature | Only diff-to-task path |
| `context-load-agents-context` | skill | Loads ancestor `AGENTS.md` context for a target file, once per session | Only per-file context loader; used by `ai-ralph-loop` |
| `context-load-context` | skill | Loads or creates functional `AGENTS.md` context before implementation work | Gate for the context-first workflow |
| `git-commit` | skill | Conventional commits, split into logical units | Enforces `git/git-policy` at commit time |
| `git-commit-push` | skill | Commit and push to the remote | Same policy, one step further |
| `git-commit-push-pr` | skill | Commit, push, create or update the PR with the repo template | Only policy-checked PR path |
| `git-sync` | skill | Sync with `origin/main`, optionally resolving conflicts | Safe-sync wrapper around merge |
| `code-review-standards.instructions.md` | rule | Review standards referenced by `create-worktask` | Required ref; worktask output broken without it |
| `git/git-policy.instructions.md` | rule | Git policy referenced by `ai-asset-sync`, `create-worktask` | Required ref for sync + worktask flows |
| `meta/knowledge-conventional-contexts-quality.instructions.md` | rule | Context quality bar referenced by `create-hld` | Required ref for HLD context files |
| `meta/rules.instructions.md` | rule | Rule lifecycle convention for `manage-rule-system` | Required ref; defines rule format itself |
| `manage-rule-system-context.sh` | hook | `UserPromptSubmit`: injects rule skill on rule-file mentions | Else skill never auto-fires |
| `worktask-skill-trigger.sh` | hook | Shared Claude/Codex router for imperative worktask requests | Only auto-trigger for worktask workflow |

## Scope

Ships owned skills, owned rules, owned hooks, and the shared payload — see
`scripts/SKILLS_INSTALLER.md` for the owned sets. Local skills and unowned
hooks stay in this repo.

A consumer that creates an agent root and runs the default `-r -s -h` command gets owned skill
folders, rules, hooks, and shared helpers. Source symlink dependencies within the template are copied
into the installed payload; arbitrary text references inside `SKILL.md` are not rewritten. See
`scripts/SKILLS_INSTALLER.md` for remaining per-category dependencies.

## Supported roots

Accepts `.agents`, `.claude`, or `.codex` as the agent root; skills live at
`<agent-root>/skills` and state plus shared payload at `<agent-root>/_smooth-devex-shared/`.
A `SKILLS_ROOT` override points at a skills directory directly — its parent then counts as the
agent root.
