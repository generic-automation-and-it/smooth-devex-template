---
name: context-load-context
description: Load or create functional AGENTS.md context files before implementation work. Use when starting frontend/backend/devops code changes, when a task references a domain or feature, or when required context is missing and must be discovered or created.
effort: low  # file discovery and loading, minimal reasoning
---

# Load Context — Phase 0 of AI Coding Workflow

**MANDATORY PHASE** — load functional `*AGENTS.md` context BEFORE clarifying requirements or executing code changes. Without it you cannot ask intelligent clarifying questions or follow existing patterns, architecture, and domain constraints.

## Workflow Steps

### 1. Detect Domain/Feature

Use the argument if provided; otherwise infer the domain from file paths, feature names, or the task description in the conversation.

### 2. Search for Relevant AGENTS.md Files

Glob `**/*{DOMAIN}*AGENTS.md`. Prioritize: exact domain match (e.g. `auth` → `AUTH_AGENTS.md`) > parent feature match > related domains (e.g. `orders` → `ORDER_PROCESSING_AGENTS.md`, `INVENTORY_AGENTS.md`).

### 3. Load Context Files

**If files found:** read them, report what was loaded with a TL;DR summary, proceed to Phase 1 (Clarify) or execution.

**If NO files found — BLOCK immediately:**

```
⚠️ CONTEXT REQUIRED - No functional context found for [domain]

Options:
A) Author new [DOMAIN]_AGENTS.md if useful local guidance warrants it
B) Search codebase more broadly for relevant AGENTS.md files
C) Provide file path(s) manually to load
D) BYPASS - Proceed without context (not recommended)

Respond with A, B, C, D, or type file paths directly
```

### 4. Context Creation (If Requested)

Read and follow the shared [AGENTS.md authoring workflow](references/agentmd/authoring.md), also used
by `agentmd-create-update`. It owns evidence loading, template selection, the quality rule and
creation/update checks. Do not create an empty scaffold merely to unblock this phase.

Load the authored file and proceed to Phase 1. If the authoring Value Gate finds no useful local
delta, report that result and return to the remaining context-loading options.

The reference directory is a link into `.agents/_smooth-devex-shared/agentmd/` in this repository.
Both installers bundle its contents, rule and template in this skill; resolve the link relative to
this `SKILL.md`, so creation does not require a sibling skill or repository-local `.agents/` tree.

### 5. Report Context Status

Always report: files loaded / file created / bypass warning, and the next phase ("Ready for Phase 1: Clarify Requirements" or "Ready to execute").

## Arguments

Optional domain/feature name (e.g. `auth`, `orders`, `dashboard`, `dotnet`, `api`); auto-detected from conversation context when omitted.

```
/context-load-context auth
/context-load-context
```

## Context Loading Rules

**Mandatory for:** frontend/backend/devops code changes; feature implementation, bug fixes, refactoring.
**Optional for:** pure research, documentation-only tasks, non-functional requirement changes.
