---
name: ai-template-sync
description: UPSERT the smooth-devex-template agentic scaffold into an existing repo. Asks which tools (Claude Code, Codex, Copilot) to configure, whether to copy .NET solutioning, and whether to overwrite existing agentic files.
models:
  claude: opus      # high-complexity; interactive multi-turn Q&A + conditional file sync across tools
  copilot: auto
  codex: gpt-5.5
---

# AI Template Sync — Skill

Sync the **smooth-devex-template** agentic scaffold into a landing repo (UPSERT — safe merge, not destructive replace).

## TL;DR

1. Ask which AI tools to configure.
2. Optionally copy .NET solutioning.
3. Detect conflicts; ask for overwrite scope.
4. Copy files per tool selection.

---

## Phase 1 — Gather Intent (ask, then stop for answers)

Ask the user all questions in **one message**:

```
1. Which AI tools to configure? (comma-separate any combo)
   a) Claude Code   b) OpenAI Codex   c) GitHub Copilot

2. Copy .NET solutioning? (only asked if the landing repo has no *.slnx / *.sln)
   Includes: Project.slnx · Directory.Build.props · Directory.Packages.props
             NuGet.Config · src/ · tests/
   [y/n]

3. Overwrite mode for agentic files?
   A) Global overwrite — replace every agentic file without further prompting
   B) Selective — show me a conflict table first; I'll pick what to overwrite
   (Dotnet files are never overwritten regardless of choice.)
```

Wait for user answers before proceeding.

---

## Phase 2 — Conflict Detection (Selective mode only)

Skip if user chose **Global overwrite**.

### Agentic file inventory

| Category | Files / paths |
|----------|--------------|
| Base scaffold | `.agents/**` (all files recursively) · `AGENTS.md` |
| Claude Code | `.claude` (symlink) · `CLAUDE.md` (symlink) · `GEMINI.md` (symlink) |
| Codex | `.codex` (symlink) |
| Copilot | `.github/copilot-instructions.md` · `.github/instructions` (symlink) |
| Setup scripts | `.agents/setup/scripts/agents-setup.sh` · `.agents/setup/scripts/agents-setup.ps1` · `.agents/setup/scripts/agents-terminals.sh` · `.agents/setup/scripts/agents-terminals.ps1` |

Check each file/path against the landing repo. Build a conflict table for every item that **already exists**:

| # | Name | Purpose | Action |
|---|------|---------|--------|
| 1 | `.agents/hooks/load-agents-context.sh` | PostToolUse hook — emits AGENTS.md context | skip |
| … | … | … | … |

Print the table, then ask:

```
Enter IDs to overwrite (e.g. "1 3 5"), "all", or "none":
```

Collect the response before moving to Phase 3.

---

## Phase 3 — Execute Sync

Apply overwrite decisions from Phase 1–2, then execute each section that applies.

> **Never touch dotnet files** (`.slnx`, `.sln`, `Directory.*.props`, `NuGet.Config`, `src/`, `tests/`) during agentic sync, even if the user requests it here.

### Section A — .agents Base Folder

Copy the entire `.agents/` tree to the landing repo root.
- Skip individual files the user chose NOT to overwrite (Selective mode).
- Overwrite files the user approved or when Global mode is active.
- Preserve existing landing-repo-only files (i.e., do not delete files absent from the template).

```bash
# From the TEMPLATE repo root
rsync -av --no-delete \
  --exclude='*.py' \        # skip repo-specific hooks unless user confirmed
  .agents/ <LANDING_REPO>/.agents/
```

> Adjust excludes based on user answers. Run without `--dry-run` only after confirmation.

### Section B — Claude Code (if selected)

Create symlinks in the landing repo:

```bash
cd <LANDING_REPO>

# Directory symlinks
ln -sf .agents .claude
ln -sf .agents .cursor          # optional; add if Cursor is used

# File symlinks
ln -sf AGENTS.md CLAUDE.md
ln -sf AGENTS.md GEMINI.md

# Enable git symlink support
git config core.symlinks true
```

Windows (PowerShell, requires Developer Mode or admin):

```powershell
cd <LANDING_REPO>
New-Item -ItemType SymbolicLink -Name .claude   -Target .agents -Force
New-Item -ItemType SymbolicLink -Name CLAUDE.md -Target AGENTS.md -Force
New-Item -ItemType SymbolicLink -Name GEMINI.md -Target AGENTS.md -Force
git config core.symlinks true
```

### Section C — OpenAI Codex (if selected)

```bash
cd <LANDING_REPO>
ln -sf .agents .codex
git config core.symlinks true
```

Windows:

```powershell
cd <LANDING_REPO>
New-Item -ItemType SymbolicLink -Name .codex -Target .agents -Force
git config core.symlinks true
```

Codex discovers skills, rules, and hooks through `.codex/` → `.agents/`. No additional files needed beyond the base scaffold (Section A).

### Section D — GitHub Copilot (if selected)

```bash
cd <LANDING_REPO>

# Symlink rules folder for Copilot instructions
mkdir -p .github
ln -sf ../.agents/rules .github/instructions
```

Copy `copilot-instructions.md` (overwrite only if approved or Global mode):

```bash
cp <TEMPLATE>/.github/copilot-instructions.md <LANDING_REPO>/.github/copilot-instructions.md
```

Windows:

```powershell
cd <LANDING_REPO>
New-Item -ItemType Directory -Path .github -Force
New-Item -ItemType SymbolicLink -Name .github\instructions -Target ..\agents\rules -Force
Copy-Item <TEMPLATE>\.github\copilot-instructions.md .github\copilot-instructions.md -Force
```

### Section E — .NET Solutioning (if opted in)

Only execute if the user answered **y** to question 2 AND no `.slnx`/`.sln` was detected.

Copy these files/folders from the template root to the landing repo root:

| Item | Notes |
|------|-------|
| `Project.slnx` | Rename to match landing project name |
| `Directory.Build.props` | MSBuild shared props |
| `Directory.Packages.props` | Central package management |
| `NuGet.Config` | Feed config |
| `src/` | All source projects — rename `Project.*` namespaces |
| `tests/` | All test projects — rename `Project.*` namespaces |

> After copying, rename every occurrence of `Project` → `<ActualProjectName>` in file names, folder names, and file contents.

---

## Phase 4 — Post-Sync Checklist

After all copies/symlinks are done, report:

```
✅ Sync complete. Next steps for the landing repo:

□ Run the setup script once:
    bash .agents/setup/scripts/agents-setup.sh   # Mac/Linux
    pwsh .agents/setup/scripts/agents-setup.ps1  # Windows

□ Update AGENTS.md — replace template placeholder content with real project context.

□ [Claude Code] Verify `.claude/` symlink resolves:  ls -la .claude

□ [Codex] Verify `.codex/` symlink resolves:  ls -la .codex

□ [Copilot] Verify `.github/instructions/` symlink resolves:  ls -la .github/instructions

□ [.NET] Rename Project.* → <ActualProjectName> everywhere (if .NET was copied).

□ Commit the agentic scaffold with:  git add -A && git commit -m "chore: add smooth-devex agentic scaffold"
```

---

## Guardrails

- **Never overwrite dotnet files** (`.slnx`, `.sln`, `Directory.*.props`, `NuGet.Config`, `src/`, `tests/`) during agentic sync.
- **Never delete** landing-repo files absent from the template.
- **Always confirm** before executing file writes/copies; show the plan first.
- In Selective mode, skip any file not explicitly approved by the user.
- Symlinks require `git config core.symlinks true`; remind the user if the repo was cloned with symlinks off.
