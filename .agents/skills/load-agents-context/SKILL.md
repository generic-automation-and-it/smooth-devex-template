---
name: load-agents-context
description: Load ancestor AGENTS.md context for a target file. Use when Codex, Claude, Copilot, or another agent needs local domain context before reading or editing source files.
allowed-tools:
  - Bash(.agents/skills/load-agents-context/scripts/load-agents-context.sh:*)
---

# Load AGENTS Context — Skill

## TL;DR

Agent-agnostic skill that emits `*AGENTS.md` context files from ancestor directories for a target source file; each file loads at most once per conversation session. Claude Code runs the script automatically as a `PostToolUse` hook. Codex, Copilot, and other agents invoke the same skill script explicitly.

## Non-Negotiables

- **Never load from auto-loaded dirs** — skip `.agents/rules/`, `.ai/rules/`, `.claude/rules/`, `.cursor/rules/`, `.github/instructions/`. Those are already in context via the AI tool's built-in loading mechanism.
- **Exit 0 always** — the hook must never return a non-zero exit code; it must not block the triggering tool. File-operation failures (tracker write, content read) are silently tolerated.
- **Read/Edit/Write or explicit skill invocation only** — skip unrelated hook tools (`Grep`, `Glob`, `Bash`). Trigger on actual file access for context, or on an explicit skill request.
- **Session dedup** — each `*AGENTS.md` file must be emitted at most once per conversation session. Paths are canonicalised (physical path) so symlinked access (`.claude/...` vs `.agents/...`) is treated as the same file.

## System Context

```mermaid
sequenceDiagram
    participant AI as AI Agent
    participant Hook as load-agents-context.sh
    participant FS as Repo File System
    participant Ctx as Conversation Context

    AI->>Hook: PostToolUse (tool: Read|Edit, file_path)
    Hook->>Hook: Check tool name — exit 0 if not Read|Edit|Write
    Hook->>Hook: Resolve absolute path, detect git repo root
    Hook->>FS: Walk dir(file) → repo root, find *AGENTS.md per level
    FS-->>Hook: Candidate AGENTS.md paths (sorted, maxdepth 1 per dir)
    Hook->>Hook: Filter: skip auto-loaded dirs + session-tracker hits
    Hook->>Hook: Detect scope from path (backend / out-of-scope)
    Hook->>FS: If in-scope, list .agents/rules-scoped/<scope>/*.instructions.md
    Hook->>Hook: Skill-on-path: rule file ⇒ manage-rule-system; *AGENTS.md ⇒ knowledge-conventional-contexts
    Hook->>FS: Read each new file (AGENTS.md + scoped rules + skill SKILL.md)
    Hook->>Ctx: Emit <context-auto-loaded> block via stdout
    Hook->>Hook: Append loaded paths to session tracker file
```

## Architecture Decisions

### LADR-001: PostToolUse over UserPromptSubmit
**Date:** 2026-05-14 | **Status:** Accepted

**Context:** `UserPromptSubmit` fires on every user message regardless of which files are in scope. `PostToolUse` fires only after a specific tool executes, so context is loaded only when the AI actually opens a file.

**Decision:** Use `PostToolUse` with `matcher: "Read|Edit"`.

**Consequences:** Context is injected *after* the first read of a file in a new directory. The AI has context before acting on the content, just not before the initial read call. Acceptable trade-off for targeted loading.

### LADR-002: Session file for deduplication
**Date:** 2026-05-14 | **Status:** Accepted

**Context:** Without dedup, the same `*AGENTS.md` is injected on every subsequent `Read`/`Edit` or explicit command call in that directory, bloating context linearly.

**Decision:** Write loaded absolute paths to `/tmp/.agents_ctx_${SESSION_ID}`. Explicit `--session-id` always wins. Otherwise, Codex CLI mode uses `CODEX_SESSION_ID` then `CODEX_THREAD_ID`; Copilot CLI mode uses `COPILOT_SESSION_ID` then `GITHUB_COPILOT_SESSION_ID`; Claude hook mode uses `CLAUDE_SESSION_ID`. All modes fall back to `$PPID`.

**Consequences:** Temp files accumulate in `/tmp/` but are trivially small and cleaned by the OS on reboot. If a session crashes and restarts with the same ID, the tracker prevents reloading — this is the desired behaviour.

### LADR-003: Walk to git root, not filesystem root
**Date:** 2026-05-14 | **Status:** Accepted

**Context:** Walking to `/` picks up unrelated `*AGENTS.md` files from parent repositories or home directories.

**Decision:** Use `git rev-parse --show-toplevel` from the file's directory (not CWD) to stop at the repo boundary. Fall back to a max-depth of 20 if `git` is unavailable.

**Consequences:** Requires `git` in `$PATH` for the boundary guard to work (standard assumption in development environments). Monorepos are handled correctly because the root is detected from the file's own location.

### LADR-004: Skill-resident script — thin hook wrapper
**Date:** 2026-05-14 | **Status:** Accepted

**Context:** Scripts could live entirely in `.agents/hooks/` or inside the skill folder. Either is workable.

**Decision:** Authoritative script lives at `.agents/skills/load-agents-context/scripts/load-agents-context.sh`. A one-line `exec` wrapper at `.agents/hooks/load-agents-context.sh` lets `settings.json` reference the conventional `.agents/hooks/` path.

**Consequences:** Transferring to another repo requires copying the skill folder, copying the hook wrapper, and adding one entry to `settings.json`. Single source of truth for the implementation; agent-agnostic invocation lives in one place.

### LADR-005: Scope-conditional rule injection — no default scope
**Date:** 2026-05-14 | **Status:** Accepted

**Context:** Always-loading every backend rule for every session means CI/docs/`.agents/` infra edits drag the full backend rule set into context unnecessarily. Bunker-procurement PR #5206 demonstrated 5,500–12,500 token savings per session by moving backend/frontend rules to `rules-scoped/` and injecting them only when an in-scope file is touched.

**Decision:** The hook detects scope from the touched file's absolute path: backend (`*.cs`, `*.csproj`, `*.sln(x)`, or files under `src/BuilderCatalogue.*/` and `tests/BuilderCatalogue.*/`). Anything else is **out-of-scope and injects zero scoped rules** — no catch-all default. Files outside any known scope (CI YAML, docs, `.agents/` infra) save the most tokens because they bypass the scoped set entirely. A Scoped Rules Inventory table in root `AGENTS.md` lists every scoped rule so the AI can Read-on-demand when reasoning out-of-scope.

**Consequences:** An AI session that never touches a backend file does not see backend rules — by design. If the agent needs them for cross-cutting reasoning, it must Read them explicitly using the inventory table. Adding a new scope (e.g., `infra/` later) requires a new `case` arm in the script and a new section in the inventory. Estimated savings on this backend-only repo: ~2,500–4,000 tokens per non-backend session (smaller than bunker-procurement because there is only one scope here).

### LADR-006: Skill-on-path injection (rule files, AGENTS.md)
**Date:** 2026-05-14 | **Status:** Accepted

**Context:** Some guidance is only relevant when a specific kind of file is being edited — e.g., the `manage-rule-system` skill is useful when the agent edits `.agents/rules*/` content, and `knowledge-conventional-contexts-quality.instructions.md` is most useful when editing `*AGENTS.md`. Always-loading both bloats every session; loading neither means the agent reasons without the guidance when it most needs it.

**Decision:** The hook injects targeted SKILL.md / rule files based on the touched file's location or basename: editing under `.agents/rules*/` injects `manage-rule-system/SKILL.md`; editing `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` / `*_AGENTS.md` injects the knowledge-conventional-contexts rule. Each is dedup-tracked per session.

**Consequences:** Modest token cost (one file per trigger, gated by dedup); large quality win because the guidance arrives precisely when needed. If a file qualifies for multiple triggers, all matching contexts inject (the cap is one per session per file).

## Key Behaviors

1. **Trigger filter**: In hook mode, exits 0 immediately for any tool that is not `Read` or `Edit`. In explicit skill mode, accepts `--file PATH` or a positional path.
2. **Path resolution**: Uses `cd "$(dirname ...)" && pwd` pattern to resolve relative paths correctly regardless of the AI agent's working directory.
3. **Repo root detection**: `git rev-parse --show-toplevel` is called from the file's directory, not the process CWD — handles nested repos and monorepos correctly.
4. **File pattern**: Matches `AGENTS.md` and `*_AGENTS.md` at `maxdepth 1` per directory. Does not recurse, so only the immediate directory's context is loaded at each level.
5. **Auto-loaded dir skip**: Paths matching `.agents/rules/`, `.ai/rules/`, `.claude/rules/`, `.cursor/rules/`, `.github/instructions/` are silently skipped.
6. **Session tracker**: `/tmp/.agents_ctx_${SESSION_ID}` — one absolute path per line, checked via `grep -qxF` (exact full-line match, no partial hits).
7. **Output envelope**: All emitted content is wrapped in `<context-auto-loaded>` tags for traceability. Each file is prefixed with `## Context: <relative-path>`.
8. **Tool agnostic**: Plain bash with `jq` as the only external dependency. Claude Code uses hook mode. Codex and Copilot use explicit skill invocation and session identifiers (`CODEX_THREAD_ID`/`CODEX_SESSION_ID`, `COPILOT_SESSION_ID`/`GITHUB_COPILOT_SESSION_ID`) for stable deduplication.
9. **Scope-conditional rule injection**: After the AGENTS.md walk, the hook detects scope from the touched file's path. Backend (`*.cs`/`*.csproj`/`*.sln(x)` or `src/BuilderCatalogue.*/`, `tests/BuilderCatalogue.*/`) → list and inject every `*.instructions.md` under `.agents/rules-scoped/backend/`. Out-of-scope (no match) → inject **zero** scoped rules. There is intentionally no default/catch-all scope.
10. **Skill-on-path injection**: After scope detection, touching a file under `.agents/rules*/` / `.claude/rules/` / `.cursor/rules/` / `.github/instructions/` injects `.agents/skills/manage-rule-system/SKILL.md`. Touching `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` / `*_AGENTS.md` injects `.agents/rules/knowledge-conventional-contexts-quality.instructions.md`. Each is dedup-tracked per session.

## Hook Registration

Add to `.agents/settings.json` (equivalently `.claude/settings.json` via symlink) under `hooks`:

```json
"PostToolUse": [
  {
    "matcher": "Read|Edit|Write",
    "hooks": [
      {
        "type": "command",
        "command": ".agents/hooks/load-agents-context.sh"
      }
    ]
  }
]
```

## Invocation

Use the skill as `/load-agents-context <path>` or run the script directly:

```bash
.agents/skills/load-agents-context/scripts/load-agents-context.sh --file path/to/source-file
```

Codex can pass its thread identifier for stable deduplication:

```bash
CODEX_SESSION_ID="${CODEX_SESSION_ID:-${CODEX_THREAD_ID:-codex-manual}}" \
  .agents/skills/load-agents-context/scripts/load-agents-context.sh --tool Codex --file path/to/source-file
```

Copilot can pass a stable prompt/session identifier:

```bash
.agents/skills/load-agents-context/scripts/load-agents-context.sh \
  --tool Copilot \
  --session-id copilot-vscode-session \
  --file path/to/source-file
```

## Transferring to Another Repo

1. Copy `.agents/skills/load-agents-context/` to the target repo's skills folder (adjust path prefix if the repo uses `.ai/` instead of `.agents/`)
2. Copy `.agents/hooks/load-agents-context.sh` wrapper (adjust the path it `exec`s if needed)
3. Add the hook registration above to the target repo's `settings.json`
4. Ensure `jq` and `git` are available in the environment
5. Optionally: remove any central context-index file or `Current Context File Map` table from the root AGENTS.md/CLAUDE.md

## Changelog

| Date | Change | Ref |
|:-----|:-------|:----|
| 2026-05-14 | Added LADR-005 (scope-conditional rule injection, no default scope) and LADR-006 (skill-on-path injection). Hook now detects backend scope and injects `.agents/rules-scoped/backend/*` on `.cs`/`.csproj`/`.sln(x)` / `src/BuilderCatalogue.*/` / `tests/BuilderCatalogue.*/` access; injects `manage-rule-system/SKILL.md` on rule-file access; injects `knowledge-conventional-contexts-quality.instructions.md` on `*AGENTS.md` access. Inventory table added to root `AGENTS.md`. | hamburg-v3 — port of bunker-procurement #5206 + token-reduction playbook |
| 2026-05-14 | Hardening from upstream Gemini review: wrapper guards `exec` with `[ -x ]` check, matcher widened to `Read\|Edit\|Write`, `cd -P`/`pwd -P` for symlink-safe canonical paths, `\|\| true` guards on tracker append and content read. | denpasar |
| 2026-05-14 | Ported from bunker-procurement: agent-agnostic lazy AGENTS.md context loading via PostToolUse hook; skip list extended with `.agents/rules/` for this repo's symlink layout. | denpasar |
