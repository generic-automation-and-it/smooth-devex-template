# AGENTS.md

> **⚠️ TEMPLATE NOTICE — read before working.**
> This repository is currently a **template**. `Project` is a placeholder name used throughout the `.agents` tree, root `AGENTS.md`, rule files, skill docs, and the solution/project layout (`Project.slnx`, `src/Project.*`, `tests/Project.*`).
>
> **As soon as the project is given a real name, you MUST:**
> 1. Replace every occurrence of `Project` / `project` (PascalCase namespaces/paths and lowercase prose) across all `.agents` files, root `AGENTS.md`, rule files, skill docs, `Project.slnx`, and the GitHub URL/slug with the chosen name.
> 2. Update the glossary and the Project Overview description below to describe the real project.
> 3. **Remove this entire TEMPLATE NOTICE block** — including this instruction — once the rename is complete.

## Project Overview

Project is an AI-spec-driven, AI-agnostic development project. _(Placeholder description — update once the project is named; see Template Notice above.)_

**Tech stack:** .NET 10 · ASP.NET Core · Clean Architecture (Domain / Application / Infrastructure / Host) · EF Core + PostgreSQL · Mediator (source-gen CQRS) · xunit.v3

## AI Context Files

Before changing code, read every `AGENTS.md` / `*AGENTS.md` in scope — they carry the "why" source code cannot convey. Specific overrides general; the nearest file is most authoritative.

- Every PR creates or updates at least one `*AGENTS.md`. Update the closest context file to the code you change; prefer local context over adding to this root file.
- Quality bar and value gate for all `*AGENTS.md` edits: `.agents/rules/meta/knowledge-conventional-contexts-quality.instructions.md`.

## Understandings

Understandings are discovered behavior notes under `.context/understandings/` (gitignored, per-workspace). Check `.context/understandings/INDEX.md` at task start; apply one when its question matches yours. On conflict, the rule wins. Mechanics: `ai-understanding` skill.

## Implementation Docs

Planned work is tracked as worktasks under `.context/work-tasks/` (gitignored, local only). Scaffold with the `create-worktask` skill.

## Repository Layout (Navigation)

| Layer | Path | Purpose |
|---|---|---|
| Domain | `src/Project.Domain/` | Core entities, value objects — no external deps |
| Application | `src/Project.Application/` | Vertical-slice use cases via Mediator — `Features/<Name>/`, shared code in `Common/` |
| Infrastructure | `src/Project.Infrastructure/` | EF Core + PostgreSQL (`Persistence/`), HTTP clients (`Clients/`) |
| Host | `src/Project.Host/` | ASP.NET Core Web API, Serilog, Scalar OpenAPI |
| ChatHost | `src/Project.ChatHost/` | Standalone LLM microservice — owns Anthropic SDK; talks to Host via HTTP only |

## Rules

All rules live under `.agents/rules/` and auto-load every session; per-file applicability is scoped via frontmatter. Categories: flat (cross-cutting), `git/`, `meta/`, `skills/`, `backend/` (`**/*.cs`). Exception: Claude defers prompt-scoped rules via `UserPromptSubmit` hook — see `.agents/rules/meta/rules.instructions.md`.

## Build / Test Commands

```bash
dotnet build Project.slnx                     # build
dotnet test  Project.slnx                     # run all tests
dotnet run --project src/Project.AppHost      # dev Aspire AppHost
dotnet run --project src/Project.ChatHost     # ChatHost standalone (separate process from the API Host)
```

Target a single test project when possible (e.g. `dotnet test tests/Project.Domain.UnitTest`). **Gotcha:** the dev Aspire dashboard runs at `http://localhost:15278`; on first browser visit use the printed `/login?t=...` URL.

## Test Framework

xunit.v3 · Shouldly · Bogus · Respawn. Three tiers (drives where a test belongs):

- **L0** `*.UnitTest` — no I/O, all in-process.
- **L1** component — `Application.ComponentTest` uses in-memory EF Core; `Infrastructure.ComponentTest` uses a real isolated DB + Respawn.
- **L2** `*.IntegrationTest` — full stack, real PostgreSQL.

Shared fixtures: `tests/Project.TestFramework/`; Aspire dependency host (PostgreSQL + WireMock): `tests/Project.TestFramework.Aspire/`. Details: `.docs/wiki/testing.md`.

## Architecture Decisions (NFRs)

Reviewer docs: `.docs/wiki/`. Designs, NFRs and LADRs: `.docs/hlds/`.

## CI/CD

- PR gate (`.github/workflows/pr-gate.yml`): restore → build (Release) → Aspire-backed test with coverage. Details: `.docs/wiki/ci.md`.
- Skill gate (`.github/workflows/skill-scan.yml`): only relevant when touching `.agents/skills/**`. Baseline-aware — new non-baselined findings fail; details live in the workflow and `.agents/skills/AGENTS.md` (LADR-001).
