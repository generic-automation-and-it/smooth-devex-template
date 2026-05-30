# AGENTS.md - AI Development Experience

🤖 AI Context: Unified AI development folder structure and best practices. Updated: 2026-04-03 Maintainer: Engineering Team

## 🎯 TL;DR

The `.agents` folder provides a tool-agnostic structure for AI-assisted development, with symbolic links (`.claude`, `.cursor`, `.codex`) ensuring compatibility across multiple AI coding tools without duplication or vendor lock-in.

## 📋 Overview

This is a unified AI development experience folder that centralizes skills, prompts, and configuration for AI-assisted coding tools.

**Scope:**
- In: Skill definitions, prompt templates, tool permissions, AI workflow orchestration
- Out: Tool-specific internal state (handled by individual tools), model weights, API credentials
- Depends: Git (for version control), bash/shell (for scripts), symbolic link support (Unix-like systems)

## 🏗️ Architecture

### Folder Structure

| Path | Purpose |
| :---- | :---- |
| `.agents/` | Root folder for all AI development tooling |
| `.agents/prompts/` | Reusable prompt templates (code review, architecture analysis) |
| `.agents/roles/` | Multi-agent role instructions (PO, Architect, QA, Backend/Frontend Engineer, Heimdall Reviewer) |
| `.agents/rules/` | Enforced AI development rules (workflow rules, coding standards) |
| `.agents/settings.json` | Tool permissions, compile/test commands |
| `.agents/skills/` | Executable skills (multi-file workflows) |
| `.agents/skills/load-context/` | Load or create functional `*_AGENTS.md` context files |
| `.agents/skills/ai-review/` | Analyze and execute AI PR review decisions |
| `.agents/skills/git-commit/` | Commit with conventional format |
| `.agents/skills/git-commit-push/` | Commit and push to remote |
| `.agents/skills/git-commit-push-pr/` | Commit, push, and create/update PRs |
| `.agents/skills/git-sync/` | Sync with main (stop on conflicts) |
| `.agents/skills/github-task-from-diff/` | Create a GitHub Task (sub-issue) from the current git diff vs main |
| `.agents/templates/` | Document templates (AGENTS.md, README.md, work task promote templates) |
| `.claude` → `.agents` | Symbolic link for Claude Code compatibility |
| `.codex` → `.agents` | Symbolic link for OpenAI Codex compatibility |
| `.cursor` → `.agents` | Symbolic link for Cursor AI compatibility |
| `CLAUDE.md` → `AGENTS.md` | Symbolic link alias for Claude-compatible root context discovery |
| `GEMINI.md` → `AGENTS.md` | Symbolic link alias for Gemini-compatible root context discovery |
| `.github/instructions` | GitHub Copilot path reference file pointing to `../.agents/rules` |
| `.github/skills` | GitHub Copilot path reference file pointing to `../.agents/skills` |

### Tool Compatibility Matrix

| Tool | Access Method | Status |
| :---- | :---- | :---- |
| **Claude Code** | Via `.claude` symlink | ✅ Active |
| **GitHub Copilot** | Via `.github/instructions` and `.github/skills` path reference files | ✅ Active |
| **Cursor AI** | Via `.cursor` symlink | ✅ Active |
| **OpenAI Codex** | Via `.codex` symlink | ✅ Active |
| **Gemini** | Via `GEMINI.md` symlink | ✅ Compatible |
| **Aider** | Direct `.agents` access (CLI) | ✅ Compatible |

## 📐 Architecture Decisions (Lightweight ADRs)

### LADR-001: Agnostic .agents Folder Structure

- **Date**: 2026-02-12
- **Status**: Accepted
- **Context**: Project was using `.claude` folder, but team wanted to support multiple AI coding tools without duplicating configuration or creating vendor lock-in
- **Decision**: Create tool-agnostic `.agents` folder as single source of truth, with symbolic links for tool-specific compatibility
- **Consequences**:
  - Single configuration folder to maintain
  - Easy to add support for new AI tools (just create symlink)
  - Backward compatible with existing `.claude` references
  - Requires symbolic link support (standard on Unix/Linux/macOS)

### LADR-002: Symbolic Link Strategy for Backward Compatibility

- **Date**: 2026-02-12
- **Status**: Accepted
- **Context**: Existing scripts, documentation, and workflows reference `.claude` paths explicitly
- **Decision**: Use symbolic links (`.claude` → `.agents`, `.cursor` → `.agents`, `.codex` → `.agents`) to maintain backward compatibility while migrating to agnostic structure
- **Consequences**:
  - Zero-downtime migration (existing references continue working)
  - Tools automatically access unified configuration
  - Symbolic links are committed to git

### LADR-003: Git Ignore Strategy

- **Date**: 2026-02-12
- **Status**: Accepted
- **Context**: Some AI tools generate local state files that should not be committed
- **Decision**:
  - Commit `.agents` folder structure and configuration to git
  - Commit symlinks to git for zero-setup developer experience
  - Ignore tool-specific local state: `.agents/settings.local.json`
- **Consequences**:
  - Clean git history without local state pollution
  - Symlinks available immediately after clone

## 📊 Setup Instructions

**Symlinks (`.claude`, `.codex`, `.cursor`, `CLAUDE.md`, `GEMINI.md`) are committed to git and available immediately after clone. GitHub Copilot uses committed path reference files in `.github/`, so no setup script is required for those mappings.**

```bash
# Verify links are present after clone
ls -la | grep -E '(\.claude|\.codex|\.cursor)'
# Expected output:
# lrwxr-xr-x ... .claude -> .agents
# lrwxr-xr-x ... .codex -> .agents
# lrwxr-xr-x ... .cursor -> .agents
```

**Optional: Run setup script to recreate symlink aliases if needed:**
```bash
# Mac/Linux
./.agents/setup/scripts/agents-setup.sh

# Windows (Administrator)
./.agents/setup/scripts/agents-setup.ps1
```

## 📝 Changelog

| Date | Change | Reason |
| :---- | :---- | :---- |
| 2026-05-08 | Converted `.github/instructions` and `.github/skills` from symlinks to committed path reference files; added `GEMINI.md` alias | Improve GitHub Copilot and Gemini compatibility |
| 2026-04-03 | Added `.codex` and GitHub Copilot path mappings | Support GitHub Copilot and OpenAI Codex |
| 2026-02-12 | Created `.agents` folder structure, migrated from `.claude` | Unified AI development experience across multiple tools |
