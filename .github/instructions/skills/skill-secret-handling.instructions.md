---
description: 'How AI agent skills must handle secrets — read from the runtime environment via a script, never embed secret values in model-visible or committed text.'
globs: ".agents/skills/**"
paths:
  - ".agents/skills/**"
applyTo: '.agents/skills/**'
alwaysApply: false
---

# Skill Secret Handling

How any skill under `.agents/skills/` must handle a secret (API key, token, password, connection string). Updated: 2026-09-27

## The Rule

A skill that needs a secret **MUST delegate to a script that reads the secret from the runtime environment** (an environment variable injected at execution time) and uses it there. The secret **value** must never appear in any model-visible or committed text.

| Allowed | Forbidden |
|---------|-----------|
| `SKILL.md` instructs the agent to run a script that reads `$MY_API_KEY` from the env | A real key, token, or password written literally in `SKILL.md`, a prompt, agent YAML, README, reference doc, or any committed file |
| A bash/python script reads the secret via `os.environ` / `"$VAR"` and passes it to the tool | Echoing/printing the secret, putting it in a URL query string, or passing it as a logged CLI argument |
| Documenting the env var **name** the script expects (e.g. `MY_API_KEY`) | Documenting the env var **value** |

The secret value flows: **runtime environment → script → tool**. It is never typed into a file an agent reads, generates, or commits.

## Reference Pattern

`.github/workflows/skill-scan.yml` is the canonical example: the SkillSpector LLM key lives in `secrets.SKILLSPECTOR_OPENAI_API_KEY`, is injected as the `OPENAI_API_KEY` env var on the scan step, and is consumed only by the scan process. No file in the repo contains the value. Mirror this shape for any skill that needs a secret: declare the env var name, read it in a script, never persist it.

## Checklist

Run this when **authoring or reviewing** a skill that touches a secret or launches a model/agent with tools. Every box is a yes/no question about the diff; a "no" is a finding, not a style note.

**Where the value lives**
- [ ] No secret value in `SKILL.md`, prompts, agent YAML, README, references, templates, tests or fixtures — only env var **names**.
- [ ] Knowledge artefacts the skill writes (Understandings, worktasks, PR bodies, run summaries) redact to `<REDACTED>`.
- [ ] Custom config ships placeholders (`{env:VAR}`), never values.

**How the script uses it**
- [ ] Read from the environment inside a script (`"${VAR:-}"`, `os.environ`); presence checked without printing (`[ -n "${VAR:-}" ]`).
- [ ] Never a CLI argument, URL userinfo (`https://token@host`) or query string. Use env-auth tools (`gh` reads `GH_TOKEN`), stdin, or a one-shot credential helper (`git -c 'credential.helper=!gh auth git-credential' push`).
- [ ] A user-supplied URL is **rejected** when it embeds credentials, before it is echoed or cloned.
- [ ] No `set -x`, `env`/`printenv`, or unredacted stderr from tools that echo URLs or headers around the secret.

**What a model process can reach**
- [ ] The model subprocess gets only the key its provider needs, via an **allowlist** (a deny-list misses tokens nobody listed, such as a developer shell's other keys): in a subshell, `unset` every variable not on the list, then `exec` the model CLI. A GitHub, OIDC or cloud token never reaches it. Never pass `NAME=value` to `env -i`: the value shows in the process list.
- [ ] Tool sandbox: no shell, no web fetch, no paths outside the repo; `read` and `edit` deny `.git/**` (persisted credentials, hooks) and `.env*`. Check **how** each tool's permission is matched: a content-search tool whose rule matches the query, not the file path (opencode `grep`), cannot be fenced by path and must be denied outright. Agent-level `read: "allow"` replaces the tool's default `.env` deny, so restate the denies.
- [ ] Nothing on disk inside the model's readable root holds a credential while the model runs. In Actions: `actions/checkout` with `persist-credentials: false`. If one may still be there, the script moves it outside the root for the model phase and restores it (or fails closed when it cannot safely move it).
- [ ] **Every** git command the script runs is hook-proof, set once for the whole script (`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n=core.hooksPath`/`GIT_CONFIG_VALUE_n=/dev/null`), not per command: the model may have written a hook, hooks inherit the token, and `checkout`, `commit`, `push` and any ref update each fire one.
- [ ] Untrusted input the model reads (upstream repos, issues, diffs) is treated as a prompt-injection source. The script, not the model, decides what gets committed or pushed.

**CI wiring**
- [ ] Secrets mapped on the **step** that needs them, not job-level `env`.
- [ ] Only the needed secrets are mapped; `secrets: inherit` is documented as a same-org shortcut, not the default.

**Before the PR**
- [ ] SkillSpector static scan run or predicted, and baseline updated in the same PR ([`skillspector-pre-pr`](skillspector-pre-pr.instructions.md)).
- [ ] The skill's `AGENTS.md` names every env var it reads, and which process receives it.

## Current Status

**One skill handles real secrets today:** `ai-asset-sync` (env-only — `OPENCODE_<PROVIDER>_API_KEY` via opencode `{env:…}` placeholders, `GITHUB_TOKEN` via `gh` env auth; no value ever appears in committed text or prompts). It is the reference for the checklist's model-process items: the opencode child gets only the selected key, its `sync` agent cannot read or edit `.git/**`/`.env*`, a persisted checkout credential is set aside for the model phase and restored before push, and every git command runs hook-free and the push uses a one-shot `gh` credential helper. `ai-template-sync` reads no secret but refuses a `--template-url` with embedded credentials. The only SkillSpector "data exfiltration / context leakage" signal ever raised on this tree was a false positive on a natural-language prompt phrase (no secret value, no external send), since reworded. This rule is a **standing guardrail** so that if a future skill needs a secret, it is added the safe way — and so the SkillSpector gate's exfiltration detection stays meaningful rather than being trained to ignore real leaks.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-09-27 | Added the authoring/review **Checklist** (value location, script usage, model-process reach, CI wiring, pre-PR). Current Status records the `ai-asset-sync` hardening and the `ai-template-sync` credential-URL refusal. |
| 2026-09-13 | Moved into the new `skills/` rule category (with `skillspector-pre-pr`); cross-references updated. |
| 2026-06-21 | Initial version — env-via-script secret handling for skills; mirrors the skill-scan workflow's key handling. |
