# AGENTS.md

This file provides guidance for AI coding agents working in the builder-catalogue repository.

## Project Overview

builder-catalogue is an AI-spec-driven, AI-agnostic development catalogue. It documents reusable patterns, blueprints, and component specifications that guide automated and AI-assisted software delivery.

**Tech stack:** .NET 10 · ASP.NET Core · Clean Architecture (Domain / Application / Infrastructure / Host) · EF Core + PostgreSQL · Mediator (source-gen CQRS) · xunit.v3

## AI Context Files

Keep `*_AGENTS.md` files synchronised with code and documentation changes. Functional `*_AGENTS.md` files in feature folders are auto-loaded by the `load-agents-context` PostToolUse hook on the first Read/Edit in their directory tree — no manual registration required.

### Required Maintenance

- Every PR should create or update at least one `*_AGENTS.md` file.
- Update the closest context file to the code you change. Prefer local context over adding more content to this root file.
- When domain model or structural shape changes, also update the relevant implementation or architecture context.

### Placement Rules

- Functional feature context belongs close to the feature code.
- Cross-cutting concerns belong under `.docs/hlds/02-nfrs/` or the nearest `*_AGENTS.md`.
- Avoid creating duplicate context files that restate the same plan at multiple levels without adding new information.

## Implementation Docs

All planned work is tracked as worktasks under `.context/work-tasks/` (gitignored — local only). Use `/create worktask` to scaffold a new one from the template.

## Repository Layout (Navigation)

| Layer | Path | Purpose |
|---|---|---|
| Domain | `src/BuilderCatalogue.Domain/` | Core entities, value objects — no external deps |
| Application | `src/BuilderCatalogue.Application/` | Vertical-slice use cases via Mediator — `Features/<Name>/`, shared code in `Common/` |
| Infrastructure | `src/BuilderCatalogue.Infrastructure/` | EF Core + PostgreSQL (`Persistence/`), HTTP clients (`Clients/`) |
| Host | `src/BuilderCatalogue.Host/` | ASP.NET Core Web API, Serilog, Scalar OpenAPI |
| ChatHost | `src/BuilderCatalogue.ChatHost/` | Standalone LLM microservice — owns Anthropic SDK; talks to Host via HTTP only |

Detailed backend coding rules are maintained in `.agents/rules-scoped/backend/` and injected only when a backend file is opened (see Rules section).

## Rules

Project-wide rules live in `.agents/rules/` as `*.instructions.md` files and are auto-loaded every session by Claude Code, Cursor, Copilot, and Codex via the symlinks/path-references documented in `.agents/AI_DEVELOPMENT_AGENTS.md`. Scope-conditional rules live in `.agents/rules-scoped/<scope>/` and are injected by the `load-agents-context` PostToolUse hook only when an in-scope file is opened (`*.cs`, `*.csproj`, `*.sln(x)`, or files under `src/BuilderCatalogue.*/` and `tests/BuilderCatalogue.*/`). Out-of-scope sessions (e.g., editing `.github/workflows/`, `.docs/`, `.agents/` infra) see only the always-loaded set. See `.agents/rules/meta/rules.instructions.md` for the file convention and `.agents/skills/manage-rule-system/SKILL.md` for the directory contract.

### Scoped Rules Inventory

The AI does not auto-load scoped rules out-of-scope. Read on demand from this list when reasoning across scopes:

| Scope | File | What it covers |
|-------|------|----------------|
| backend | `.agents/rules-scoped/backend/api-mediator-validation.instructions.md` | Minimal API + Mediator + FluentValidation fail-fast |
| backend | `.agents/rules-scoped/backend/architecture-slices.instructions.md` | Clean-architecture boundaries; vertical-slice Features |
| backend | `.agents/rules-scoped/backend/backend-logging-conventions.instructions.md` | Default Information vs Debug log levels |
| backend | `.agents/rules-scoped/backend/external-api-clients.instructions.md` | Refit list vs singular client split; HybridCache adapter pattern |
| backend | `.agents/rules-scoped/backend/migrations.instructions.md` | `[ExcludeFromCodeCoverage]` requirement on migration classes |
| backend | `.agents/rules-scoped/backend/wiremock-stubbing.instructions.md` | TestFramework.Aspire single-source-of-truth stub helper |

## Build / Lint / Test Commands

```bash
# Build
dotnet build BuilderCatalogue.slnx

# Run all tests
dotnet test BuilderCatalogue.slnx

# Run the dev Aspire AppHost from the repo root
dotnet run --project src/BuilderCatalogue.AppHost

# Run by level — target projects directly (no Trait annotations required)
dotnet test tests/BuilderCatalogue.Domain.UnitTest
dotnet test tests/BuilderCatalogue.Application.UnitTest
dotnet test tests/BuilderCatalogue.Infrastructure.UnitTest
dotnet test tests/BuilderCatalogue.Host.UnitTest
dotnet test tests/BuilderCatalogue.Application.ComponentTest
dotnet test tests/BuilderCatalogue.Infrastructure.ComponentTest
dotnet test tests/BuilderCatalogue.Host.IntegrationTest
dotnet test tests/BuilderCatalogue.ChatHost.UnitTest
dotnet test tests/BuilderCatalogue.ChatHost.IntegrationTest

# Run ChatHost standalone (separate process from the API Host)
dotnet run --project src/BuilderCatalogue.ChatHost
```

The dev Aspire AppHost dashboard is exposed on `http://localhost:15278` by this repository's checked-in launch settings. If started from a terminal, use the printed `/login?t=...` URL for the first browser visit.

## Test Framework

| Concern | Tool |
|---|---|
| Framework | xunit.v3 |
| Assertions | Shouldly |
| Fake / fixture data | Bogus |
| DB cleanup | Respawn |
| L0 (unit) | `*.UnitTest` — no I/O, all in-process |
| L1 (component) | `Application.ComponentTest` — in-memory EF Core; `Infrastructure.ComponentTest` — real isolated DB + Respawn |
| L2 (integration) | `*.IntegrationTest` — full stack, real PostgreSQL |

Shared L0-L2 fixtures live in `tests/BuilderCatalogue.TestFramework/`; the Aspire dependency host lives in `tests/BuilderCatalogue.TestFramework.Aspire/`. Aspire-managed test dependencies use PostgreSQL and WireMock containers.

## Style and Dependencies

Authoritative stack and coding conventions for AI coders are in `.agents/rules/project-overview.instructions.md` and backend-specific rules under `.agents/rules-scoped/backend/` (injected on demand by `load-agents-context`).

## Architecture Decisions (NFRs)

Human-facing reviewer documentation lives in `.docs/wiki/`. Detailed high-level designs, non-functional requirements, and lightweight architecture decision records live under `.docs/hlds/`.

## CI/CD

| Stage | Workflow | Trigger |
|---|---|---|
| PR Gate | `.github/workflows/pr-gate.yml` | `pull_request` → `main` (includes PR branch updates), `push` → `main`, `workflow_dispatch` |

### PR Gate steps

1. **Checkout** — `actions/checkout@v4`
2. **Install .NET SDK** — `actions/setup-dotnet@v4` (version from `DOTNET_VERSION` env, currently `10.0.x`)
3. **Restore** — `dotnet restore BuilderCatalogue.slnx`
4. **Build** — `dotnet build … --no-restore --configuration Release`
5. **Aspire test with coverage** — local action `.github/actions/aspire-test-with-coverage`
   - Starts `tests/BuilderCatalogue.TestFramework.Aspire`, keeps its PID inside the action script, and waits for PostgreSQL (`127.0.0.1:15432`), Redis (`127.0.0.1:16379`), and WireMock (`http://127.0.0.1:19091/__admin/health`)
   - Restores .NET tools (`dotnet tool restore`) after dependency pre-warm, matching the proven CI timing before tests start
   - Prepares `artifacts/testresults/` and `artifacts/coverage/`
   - Runs test projects in order: Host integration, Application/Infrastructure component, then Domain/Application/Infrastructure/Host unit tests
   - Generates coverage reports with `dotnet tool run reportgenerator`
   - Stops the Aspire host from the action script's teardown trap after tests and coverage generation have finished or failed
6. **Publish coverage summary** (`if: always()`) — appends `artifacts/coverage/SummaryGithub.md` to the GitHub step summary
7. **Upload coverage artifacts** (`if: always()`) — uploads `artifacts/coverage/` as `coverage-report`

### .NET local tools

`.config/dotnet-tools.json` declares the local tool manifest. Currently registered:

| Tool | Version | Command |
|---|---|---|
| `dotnet-reportgenerator-globaltool` | `5.4.4` | `reportgenerator` |

## Git Constraints

This repository is hosted on **GitHub** at `https://github.com/generic-automation-and-it/builder-catalogue`.

- **CLI tool:** Use `gh` (GitHub CLI) for PR and repository operations.
- **PR template:** `.github/pull_request_template.md`
- **Code owners:** `.github/CODEOWNERS` — all files owned by `@generic-automation-and-it/builder-catalogue`

## Glossary

<!-- TODO: Add domain-specific terms and abbreviations as the project evolves. -->

| Term | Description |
|---|---|
| Blueprint | A reusable, parameterised specification for a component or service |
| Catalogue | The collection of all blueprints and templates in this repository |
| Spec-driven | Development approach where machine-readable specifications are the source of truth |
