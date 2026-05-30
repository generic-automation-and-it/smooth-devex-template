---
description: 'Builder Catalogue backend tech stack, architecture, and commands for AI coding tasks'
globs: "**"
paths:
  - "**"
applyTo: '**'
alwaysApply: true
---
# Project Overview

Updated: 2026-05-09

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | ASP.NET Core (.NET 10) |
| Architecture | Clean Architecture (`Domain` / `Application` / `Infrastructure` / `Host`) |
| API style | Minimal API endpoints in `src/BuilderCatalogue.Host` |
| Mediator | [`martinothamar/Mediator`](https://github.com/martinothamar/Mediator) (in-process request/response dispatch with pipeline support) |
| Messaging durability options | Message Queue / Message Streaming can be introduced when durability, retries, or asynchronous decoupling are required |
| Validation | FluentValidation in Mediator pipeline (fail fast) |
| Persistence | EF Core + PostgreSQL (`Npgsql.EntityFrameworkCore.PostgreSQL`) |
| Logging/Observability | Serilog + OpenTelemetry |
| Testing | xunit.v3 + Shouldly + Bogus + Respawn |

## Commands

```bash
dotnet build BuilderCatalogue.slnx
dotnet test BuilderCatalogue.slnx

# Targeted test projects
dotnet test tests/BuilderCatalogue.Domain.UnitTest
dotnet test tests/BuilderCatalogue.Application.UnitTest
dotnet test tests/BuilderCatalogue.Infrastructure.UnitTest
dotnet test tests/BuilderCatalogue.Host.UnitTest
dotnet test tests/BuilderCatalogue.Application.ComponentTest
dotnet test tests/BuilderCatalogue.Infrastructure.ComponentTest
dotnet test tests/BuilderCatalogue.Host.IntegrationTest
```

## Project Structure

```
src/
  BuilderCatalogue.Domain/          # Entities, value objects, invariants
  BuilderCatalogue.Application/     # Feature slices + Mediator handlers/pipelines
  BuilderCatalogue.Infrastructure/  # EF Core persistence + external integrations
  BuilderCatalogue.Host/            # Minimal API composition, middleware, observability

tests/
  BuilderCatalogue.*.UnitTest/
  BuilderCatalogue.*.ComponentTest/
  BuilderCatalogue.*.IntegrationTest/
  BuilderCatalogue.TestFramework/
```

## AI Coder Rules (Summary)

- Keep business logic out of `Host`; route requests into Application via Mediator.
- In Application, organize by `Features/<FeatureName>/` (no global `Commands/` or `Queries/` folders).
- Use `Mediator` (martinothamar) — not `MediatR`.
- Add a FluentValidation validator for each request model and enforce validation in a fail-fast Mediator pipeline.
- If a use case suggests durable/asynchronous processing, explicitly prompt whether to introduce Message Queue or Message Streaming before generating that integration.
- Update the closest `*_AGENTS.md` context file in each PR.

## Changelog

> AI loading note: Skip this section during routine task execution. Use it only when updating this rule file.

| Date | Change |
|:-----|:-------|
| 2026-05-09 | Replaced template content with repository-specific stack, commands, structure, and AI-coder rules |
| 2026-05-09 | Corrected Mediator description and added messaging durability prompt guidance (queue/streaming) |
| 2026-03-07 | Reset to generic template — remove project-specific content |
